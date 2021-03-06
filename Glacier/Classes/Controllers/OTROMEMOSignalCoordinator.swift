//
//  OTROMEMOSignalCoordinator.swift
//  ChatSecure
//
//  Created by David Chiles on 8/4/16.
//  Copyright © 2016 Chris Ballinger. All rights reserved.
//

import UIKit
import XMPPFramework
import YapDatabase
import CocoaLumberjack
import SignalProtocolObjC
import MapboxStatic

/** 
 * This is the glue between XMPP/OMEMO and Signal
 */
@objc open class OTROMEMOSignalCoordinator: NSObject {

    @objc public static let DeviceListUpdateNotificationName = Notification.Name(rawValue: "DeviceListUpdateNotification")
    
    public let signalEncryptionManager:OTRAccountSignalEncryptionManager
    public let omemoStorageManager:OTROMEMOStorageManager
    @objc public let accountYapKey:String
    @objc public let databaseConnection:YapDatabaseConnection
    @objc open weak var omemoModule:OMEMOModule?
    @objc open weak var omemoModuleQueue:DispatchQueue?
    @objc open var callbackQueue:DispatchQueue
    @objc public let workQueue:DispatchQueue
    @objc public let messageStorage: MessageStorage
    @objc public let roomManager: OTRXMPPRoomManager
    
    private var roomStorage: RoomStorage {
        return roomManager.roomStorage
    }

    fileprivate var myJID:XMPPJID? {
        get {
            return omemoModule?.xmppStream?.myJID
        }
    }
    let preKeyCount:UInt = 100
    fileprivate var outstandingXMPPStanzaResponseBlocks:[String: (Bool) -> Void]
    /// callbacks for when fetching device Id list
    private var deviceIdFetchCallbacks:[XMPPJID: (Bool) -> Void] = [:]
    
    private var lekList:[UInt32] = []
    
    /**
     Create a OTROMEMOSignalCoordinator for an account. 
     
     - parameter accountYapKey: The accounts unique yap key
     - parameter databaseConnection: A yap database connection on which all operations will be completed on
 `  */
    @objc public required init(accountYapKey:String,
                               databaseConnection:YapDatabaseConnection,
                               messageStorage: MessageStorage,
                               roomManager: OTRXMPPRoomManager) throws {
        try self.signalEncryptionManager = OTRAccountSignalEncryptionManager(accountKey: accountYapKey,databaseConnection: databaseConnection)
        self.omemoStorageManager = OTROMEMOStorageManager(accountKey: accountYapKey, accountCollection: OTRAccount.collection, databaseConnection: databaseConnection)
        self.accountYapKey = accountYapKey
        self.databaseConnection = databaseConnection
        self.outstandingXMPPStanzaResponseBlocks = [:]
        self.callbackQueue = DispatchQueue(label: "OTROMEMOSignalCoordinator-callback", attributes: [])
        self.workQueue = DispatchQueue(label: "OTROMEMOSignalCoordinator-work", attributes: [])
        self.messageStorage = messageStorage
        self.roomManager = roomManager
    }
    
    /**
     Checks that a jid matches our own JID using XMPPJIDCompareBare
     */
    fileprivate func isOurJID(_ jid:XMPPJID) -> Bool {
        guard let ourJID = self.myJID else {
            return false;
        }
        
        return jid.isEqual(to: ourJID, options: .bare)
    }
    
    /** Always call on internal work queue */
    fileprivate func callAndRemoveOutstandingBundleBlock(_ elementId:String,success:Bool) {
        
        guard let outstandingBlock = self.outstandingXMPPStanzaResponseBlocks[elementId] else {
            return
        }
        outstandingBlock(success)
        self.outstandingXMPPStanzaResponseBlocks.removeValue(forKey: elementId)
    }
    
    /** Always call on internal work queue */
    fileprivate func callAndRemoveOutstandingDeviceIdFetch(_ jid:XMPPJID,success:Bool) {
        guard let outstandingBlock = self.deviceIdFetchCallbacks[jid] else {
            return
        }
        outstandingBlock(success)
        self.deviceIdFetchCallbacks.removeValue(forKey: jid)
    }
    
    /** 
     This must be called before sending every message. It ensures that for every device there is a session and if not the bundles are fetched.
     
     - parameter buddyYapKey: The yap key for the buddy to check
     - parameter completion: The completion closure called on callbackQueue. If it successfully was able to fetch all the bundles or if it wasn't necessary. If there were no devices for this buddy it will also return flase
     */
    open func prepareSessionForBuddy(_ buddyYapKey:String, completion:@escaping (Bool) -> Void) {
        self.prepareSession(buddyYapKey, yapCollection: OTRBuddy.collection, completion: completion)
    }
    
    /**
     This must be called before sending every message. It ensures that for every device there is a session and if not the bundles are fetched.
     
     - parameter yapKey: The yap key for the buddy or account to check
     - parameter yapCollection: The yap key for the buddy or account to check
     - parameter completion: The completion closure called on callbackQueue. If it successfully was able to fetch all the bundles or if it wasn't necessary. If there were no devices for this buddy it will also return flase
     */
    open func prepareSession(_ yapKey:String, yapCollection:String, completion:@escaping (Bool) -> Void) {
        var devices:[OMEMODevice] = []
        var user:String? = nil
        
        //Get all the devices ID's for this buddy as well as their username for use with signal and XMPPFramework.
        self.databaseConnection.read { (transaction) in
            devices = OMEMODevice.allDevices(forParentKey: yapKey, collection: yapCollection, transaction: transaction)
            user = self.fetchUsername(yapKey, yapCollection: yapCollection, transaction: transaction)
        }
        
        guard let username = user,
            let jid = XMPPJID(string:username) else {
            self.callbackQueue.async(execute: {
                completion(false)
            })
            return
        }
        
        let bundleFetch = { [weak self] in
            guard let strongself = self else {
                return
            }
            var finalSuccess = true
            
            let group = DispatchGroup()
            
            //For each device Check if we have a session. If not then we need to fetch it from their XMPP server.
            for device in devices where device.deviceId.uint32Value != self?.signalEncryptionManager.registrationId {
                if !strongself.signalEncryptionManager.sessionRecordExistsForUsername(username, deviceId: device.deviceId.int32Value) || device.publicIdentityKeyData == nil {
                    //No session for this buddy and device combo. We need to fetch the bundle.
                    //No public idenitty key data. We don't have enough information (for the user and UI) to encrypt this message.
                    
                    let elementId = UUID().uuidString
                    
                    group.enter()
                    // Hold on to a closure so that when we get the call back from OMEMOModule we can call this closure.
                    strongself.outstandingXMPPStanzaResponseBlocks[elementId] = { success in
                        if (!success) {
                            finalSuccess = false
                        }
                        
                        group.leave()
                    }
                    //Fetch the bundle
                    strongself.omemoModule?.fetchBundle(forDeviceId: device.deviceId.uint32Value, jid: jid, elementId: elementId)
                }
            }
            
            if let cQueue = self?.callbackQueue {
                group.notify(queue: cQueue) {
                    completion(finalSuccess)
                }
            }
        }
        
        let deviceFetch = { [weak self] in
            guard let sself = self else {
                return
            }
            var deviceFetchSuccess = true
            let group = DispatchGroup()
            let elementId = UUID().uuidString
            
            group.enter()
            // Hold on to a closure so that when we get the call back from OMEMOModule we can call this closure.
            self?.deviceIdFetchCallbacks[jid] = { success in
                if (!success) {
                    deviceFetchSuccess = false
                }
                group.leave()
            }
            //Fetch the bundle
            self?.omemoModule?.fetchDeviceIds(for: jid, elementId: elementId)
            
            group.notify(queue: sself.workQueue) {
                devices = self?.databaseConnection.fetch {
                    OMEMODevice.allDevices(forParentKey: yapKey, collection: yapCollection, transaction: $0)
                } ?? []
                if deviceFetchSuccess == false {
                    DDLogWarn("Could not fetch devices for \(jid)")
                }
                if devices.count > 0 {
                    DDLogVerbose("Fetched \(devices.count) devices on the fly while sending message for \(jid)")
                    bundleFetch()
                } else {
                    self?.callbackQueue.async {
                        completion(false)
                    }
                }
            }
        }
        
        self.workQueue.async {
            // We are trying to send to someone but haven't fetched any devices
            // this might happen if we aren't subscribed to someone's presence in a group chat
            if devices.count == 0 {
                deviceFetch()
            } else {
                bundleFetch()
            }
        }
    }
    
    fileprivate func fetchUsername(_ yapKey:String, yapCollection:String, transaction:YapDatabaseReadTransaction) -> String? {
        if let object = transaction.object(forKey: yapKey, inCollection: yapCollection) {
            if let account = object as? OTRAccount {
                return account.username
            } else if let buddy = object as? OTRBuddy {
                return buddy.username
            }
        }
        return nil
    }
    
    /**
     Check if we have valid sessions with our other devices and if not fetch their bundles and start sessions.
     */
    func prepareSessionWithOurDevices(_ completion:@escaping (_ success:Bool) -> Void) {
        self.prepareSession(self.accountYapKey, yapCollection: OTRAccount.collection, completion: completion)
    }
    
    fileprivate func encryptPayloadWithSignalForDevice(_ device:OMEMODevice, payload:Data) throws -> OMEMOKeyData? {
        var user:String? = nil
        self.databaseConnection.read({ (transaction) in
            user = self.fetchUsername(device.parentKey, yapCollection: device.parentCollection, transaction: transaction)
        })
        if let username = user {
            let encryptedKeyData = try self.signalEncryptionManager.encryptToAddress(payload, name: username, deviceId: device.deviceId.uint32Value)
            var isPreKey = false
            if (encryptedKeyData.type == .preKeyMessage) {
                isPreKey = true
            }
            return OMEMOKeyData(deviceId: device.deviceId.uint32Value, data: encryptedKeyData.data, isPreKey: isPreKey)
        }
        return nil
    }
    
    /**
     Gathers necessary information to encrypt a message to the buddy and all this accounts devices that are trusted. Then sends the payload via OMEMOModule
     
     - parameter messageBody: The boddy of the message
     - parameter buddyYapKey: The unique buddy yap key. Used for looking up the username and devices 
     - parameter messageId: The preffered XMPP element Id to be used.
     - parameter completion: The completion block is called after all the necessary omemo preperation has completed and sendKeyData:iv:toJID:payload:elementId:expiration is invoked
     */
    open func encryptAndSendMessage(_ message: OTRMessageProtocol, completion:@escaping (_ success: Bool, _ error: Error?) -> Void) {
        // Gather bundles for buddy and account here
        let group = DispatchGroup()
        
        let prepareCompletion = { (success:Bool) in
            group.leave()
        }
        
        // destinationJID is either the XMPPRoom JID or OTRXMPPBuddy JID
        var _destinationJID: XMPPJID?
        var buddyKeys: [String] = []
        if let roomMessage = message as? OTRXMPPRoomMessage {
            databaseConnection.read({ (transaction) in
                buddyKeys = roomMessage.allBuddyKeysForOutgoingMessage(transaction)
                _destinationJID = roomMessage.room(transaction)?.roomJID
            })
        } else if let directMessage = message as? OTROutgoingMessage {
            buddyKeys = [message.threadId]
            databaseConnection.read({ (transaction) in
                _destinationJID = directMessage.buddy(with: transaction)?.bareJID
            })
        }
        guard buddyKeys.count > 0, let destinationJID = _destinationJID else {
            completion(false, NSError.chatSecureError(OTROMEMOError.noDevicesForBuddy, userInfo: nil))
            return
        }
        buddyKeys.forEach { (key) in
            group.enter()
            self.prepareSessionForBuddy(key, completion: prepareCompletion)
        }
        group.enter()
        self.prepareSessionWithOurDevices(prepareCompletion)
        //Even if something went wrong fetching bundles we should push ahead. We may have sessions that can be used.
        
        group.notify(queue: self.workQueue) {
            //Strong self work here
            var buddies: [OTRXMPPBuddy] = []
            self.databaseConnection.read { (transaction) in
                buddies = buddyKeys.compactMap({ key in
                    OTRXMPPBuddy.fetchObject(withUniqueID: key, transaction: transaction)
                })
            }
            guard buddies.count > 0 else {
                completion(false, NSError.chatSecureError(OTROMEMOError.noDevicesForBuddy, userInfo: nil))
                return
            }
            
            guard let messageBody = message.messageText,
                let ivData = OTRSignalEncryptionHelper.generateIV(), let keyData = OTRSignalEncryptionHelper.generateSymmetricKey(), let messageBodyData = messageBody.data(using: String.Encoding.utf8) else {
                
                let error = NSError.chatSecureError(OTROMEMOError.unknownError, userInfo: nil)
                completion(false,error)
                
                return
            }
            do {
                //Create the encrypted payload
                let gcmData = try OTRSignalEncryptionHelper.encryptData(messageBodyData, key: keyData, iv: ivData)
                
                // this does the signal encryption. If we fail it doesn't matter here. We end up trying the next device and fail later if no devices worked.
                let encryptClosure:(OMEMODevice) -> (OMEMOKeyData?) = { device in
                    do {
                        // new OMEMO format puts auth tag inside omemo session
                        // see https://github.com/siacs/Conversations/commit/f0c3b31a42ac6269a0ca299f2fa470586f6120be#diff-e9eacf512943e1ab4c1fbc21394b4450R170
                        let payload = keyData + gcmData.authTag
                        return try self.encryptPayloadWithSignalForDevice(device, payload: payload)
                    } catch {
                        return nil
                    }
                }
                
                /**
                 1. Get all devices for this buddy.
                 2. Filter only devices that are trusted.
                 3. encrypt to those devices.
                 4. Remove optional values
                */
                let buddyKeyDataArray = buddyKeys.flatMap({ key in
                    self.omemoStorageManager.getDevicesForParentYapKey(key, yapCollection: OTRXMPPBuddy.collection, trustedOnly: true).map(encryptClosure).compactMap{ $0 }
                })
                
                // Stop here if we were not able to encrypt to any of the buddies
                if (buddyKeyDataArray.count == 0) {
                    self.callbackQueue.async(execute: {
                        let error = NSError.chatSecureError(OTROMEMOError.noDevicesForBuddy, userInfo: nil)
                        completion(false,error)
                    })
                    return
                }
                
                /**
                 1. Get all devices for this this account.
                 2. Filter only devices that are trusted and not ourselves.
                 3. encrypt to those devices.
                 4. Remove optional values
                 */
                let ourDevicesKeyData = self.omemoStorageManager.getDevicesForOurAccount(trustedOnly: true).filter({ (device) -> Bool in
                    return device.deviceId.uint32Value != self.signalEncryptionManager.registrationId
                }).map(encryptClosure).compactMap{ $0 }
                
                // Combine teh two arrays for all key data
                let keyDataArray = ourDevicesKeyData + buddyKeyDataArray
                
                //Make sure we have encrypted the symetric key to someone
                if (keyDataArray.count > 0) {
                    // new OMEMO format puts auth tag inside omemo session
                    let finalPayload = gcmData.data
                    
                    if message is OTRXMPPRoomMessage,
                        let groupMessage = self.omemoModule?.message(forKeyData: keyDataArray, iv: ivData, to: destinationJID, payload: finalPayload, elementId: message.remoteMessageId)
                        {
                        groupMessage.addAttribute(withName: "type", stringValue: "groupchat")
                        groupMessage.addReceiptRequest()
                        groupMessage.addBody("Sent encrypted message, need to re-sync keys")
                        self.omemoModule?.xmppStream?.send(groupMessage)
                    } else if message is OTROutgoingMessage {
                        self.omemoModule?.sendKeyData(keyDataArray, iv: ivData, to: destinationJID, payload: finalPayload, elementId: message.remoteMessageId, expiration: message.messageExpires)
                    }
                    
                    self.callbackQueue.async(execute: {
                        completion(true,nil)
                    })
                    return
                } else {
                    self.callbackQueue.async(execute: {
                        let error = NSError.chatSecureError(OTROMEMOError.noDevices, userInfo: nil)
                        completion(false,error)
                    })
                    return
                }
            } catch let err {
                //This should only happen if we had an error encrypting the payload
                self.callbackQueue.async(execute: {
                    completion(false,err)
                })
                return
            }
            
        }
    }
    
    /**
     Remove a device from the yap store and from the XMPP server.
     
     - parameter deviceId: The OMEMO device id
    */
    @objc open func removeDevice(_ devices:[OMEMODevice], completion:@escaping ((Bool) -> Void)) {
        
        self.workQueue.async { [weak self] in
            
            guard let accountKey = self?.accountYapKey else {
                completion(false)
                return
            }
            //Array with tuple of username and the device
            //Needed to avoid nesting yap transactions
            var usernameDeviceArray = [(String,OMEMODevice)]()
            self?.databaseConnection.readWrite({ (transaction) in
                devices.forEach({ (device) in
                    
                    // Get the username if buddy or account. Could possibly be extracted into a extension or protocol
                    let extractUsername:(AnyObject?) -> String? = { object in
                        switch object {
                        case let buddy as OTRBuddy:
                            return buddy.username
                        case let account as OTRAccount:
                            return account.username
                        default: return nil
                        }
                    }
                    
                    //Need the parent object to get the username
                    let buddyOrAccount = transaction.object(forKey: device.parentKey, inCollection: device.parentCollection)
                    
                    
                    if let username = extractUsername(buddyOrAccount as AnyObject?) {
                        usernameDeviceArray.append((username,device))
                    }
                    device.remove(with: transaction)
                })
            })
            
            //For each username device pair remove the underlying signal session
            usernameDeviceArray.forEach({ (username,device) in
                _ = self?.signalEncryptionManager.removeSessionRecordForUsername(username, deviceId: device.deviceId.int32Value)
            })
            
            
            let remoteDevicesToRemove = devices.filter({ (device) -> Bool in
                // Can only remove devices that belong to this account from the remote server.
                return device.parentKey == accountKey && device.parentCollection == OTRAccount.collection
            })
            
            if( remoteDevicesToRemove.count > 0 ) {
                let elementId = UUID().uuidString
                let deviceIds = remoteDevicesToRemove.map({ (device) -> NSNumber in
                    return device.deviceId
                })
                self?.outstandingXMPPStanzaResponseBlocks[elementId] = { success in
                    completion(success)
                }
                self?.omemoModule?.removeDeviceIds(deviceIds, elementId: elementId)
            } else {
                completion(true)
            }
        }
    }
    
    /// transforms incoming group message into JID matching a 1:1 Buddy
    private func extractAddressFromGroupMessage(_ message: XMPPMessage) -> XMPPJID? {
        if let fromJID = message.from {
            let roomJID = fromJID.bareJID
            // This formula is defined in XMPPRoom.roomYapKey
            let accountId = accountYapKey
            var _occupant: OTRXMPPRoomOccupant? = nil
            var _buddy: OTRXMPPBuddy? = nil
            self.databaseConnection.read({ (transaction) in
                _occupant = OTRXMPPRoomOccupant.occupant(jid: fromJID, realJID: nil, roomJID: roomJID, accountId: accountId, createIfNeeded: false, transaction: transaction)
                _buddy = _occupant?.buddy(with: transaction)
            })
            // we've found the existing 1:1 buddy!
            if let buddy = _buddy {
                return buddy.bareJID
            } else {
                if let user = fromJID.resource {
                    if let userjid = handleNoBuddy(message, fromname: user) {
                        return userjid
                    }
                }
                
                if let occupant = _occupant,
                    let user = occupant.jid?.resource {
                    return XMPPJID(string: user)
                }
                
                return nil
            }
        }
        return nil
    }
    
    func handleNoBuddy(_ message: XMPPMessage, fromname: String) -> XMPPJID? {
        var budjid: XMPPJID? = nil
        self.databaseConnection.read({ (transaction) in
            if let object = transaction.object(forKey: self.accountYapKey, inCollection: OTRAccount.collection) {
                if let account = object as? OTRAccount {
                    account.allBuddies(with: transaction).forEach { (buddy) in
                        let tempjid = XMPPJID(string: buddy.username)
                        if (fromname == buddy.displayName || fromname == tempjid?.user) {
                            budjid = tempjid
                            return
                        }
                    }
                    
                    let fromJID = message.from
                    if (account.displayName == fromJID?.resource) {
                        budjid = XMPPJID(string: account.username)
                    }
                }
            }
        })
        
        return budjid
    }
    
    open func processKeyData(_ keyData: [OMEMOKeyData], iv: Data, senderDeviceId: UInt32, forJID: XMPPJID, payload: Data?, delayed: Date?, forwarded: Bool, isIncoming: Bool, message: XMPPMessage, originalMessage: XMPPMessage) {
        var incoming = isIncoming
        //let aesGcmBlockLength = 16
        guard let encryptedPayload = payload, encryptedPayload.count > 0, let myJID = self.myJID else {
            return
        }
        var _addressJID: XMPPJID? = nil
        // handle incoming group chat messages slightly differently
        if message.isGroupChatMessage {
            if let groupAddressJID = extractAddressFromGroupMessage(message) {
                _addressJID = groupAddressJID
                if groupAddressJID.isEqual(to: myJID, options: .bare) {
                    incoming = false
                } else {
                    incoming = true
                }
            } else {
                DDLogWarn("Found Incoming OMEMO group message, but corresponding Buddy could not be found!")
                return
            }
        } else {
            if !incoming {
                _addressJID = myJID.bareJID
            } else {
                _addressJID = forJID.bareJID
            }
            
        }
        guard let addressJID = _addressJID else {
            return
        }

        let rid = self.signalEncryptionManager.registrationId
        
        //Could have multiple matching device id. This is extremely rare but possible that the sender has another device that collides with our device id.
        var unencryptedKeyData: Data?
        for key in keyData where key.deviceId == rid {
            let keydata = key.data
            do {
                unencryptedKeyData = try self.signalEncryptionManager.decryptFromAddress(keydata, name: addressJID.bare, deviceId: senderDeviceId)
                // have successfully decripted the AES key. We should break and use it to decrypt the payload
                break
            } catch let error {
                DDLogError("Error decrypting OMEMO message for \(addressJID): \(error) \(message)")
                let nsError = error as NSError
                if nsError.domain == SignalErrorDomain, nsError.code == SignalError.duplicateMessage.rawValue {
                    // duplicate messages are benign and can be ignored
                    DDLogInfo("Ignoring duplicate OMEMO message: \(message)")
                    return
                }
                
                let buddyAddress = SignalAddress(name: addressJID.bare, deviceId: Int32(senderDeviceId))
                
                // retry after create session
                let prepareCompletion = { (success:Bool) in
                    if (success) { 
                        do {
                            let unencryptedKeyData2 = try self.signalEncryptionManager.decryptFromAddress(keydata, name: addressJID.bare, deviceId: senderDeviceId)
                            self.handleUnencryptedKeyData(unencryptedKeyData: unencryptedKeyData2, iv: iv, senderDeviceId: senderDeviceId, forJID: forJID, encryptedPayload: encryptedPayload, delayed: delayed, forwarded: forwarded, isIncoming: incoming, message: message, originalMessage: originalMessage)
                        } catch {
                            DDLogError("Error decrypting OMEMO after re-creating session")
                            if (incoming) {
                                self.handleMissingKeys(message: message, forwarded: forwarded, delayed: delayed)
                                if (!message.isGroupChatMessage) {
                                    self.doGlacierbotAlert(addressJID: addressJID)
                                }
                            }
                        }
                    } else {
                        if (incoming) {
                            self.handleMissingKeys(message: message, forwarded: forwarded, delayed: delayed)
                            if (!message.isGroupChatMessage) {
                                self.doGlacierbotAlert(addressJID: addressJID)
                            }
                        }
                    }
                }
                
                if self.signalEncryptionManager.storage.sessionRecordExists(for: buddyAddress) {
                    // Session is corrupted
                    let _ = self.signalEncryptionManager.storage.deleteSessionRecord(for: buddyAddress)
                    DDLogError("Session exists and is possibly corrupted."); // Deleting...")
                    createSession(jid: addressJID, completion: prepareCompletion)
                } else if nsError.domain == SignalErrorDomain, nsError.code == SignalError.noSession.rawValue{
                    
                    // create session and then retry
                    let group = DispatchGroup()
                    let prepareCompletion = { (success:Bool) in
                        group.leave()
                    }
                    
                    group.enter()
                    createSession(jid: addressJID, completion: prepareCompletion)
                    group.enter()
                    self.prepareSessionWithOurDevices(prepareCompletion)
                    
                    group.notify(queue: self.workQueue) {
                        do {
                            let unencryptedKeyData2 = try self.signalEncryptionManager.decryptFromAddress(keydata, name: addressJID.bare, deviceId: senderDeviceId)
                            self.handleUnencryptedKeyData(unencryptedKeyData: unencryptedKeyData2, iv: iv, senderDeviceId: senderDeviceId, forJID: forJID, encryptedPayload: encryptedPayload, delayed: delayed, forwarded: forwarded, isIncoming: incoming, message: message, originalMessage: originalMessage)
                        } catch {
                            DDLogError("Error decrypting OMEMO after creating session")
                            if (incoming) {
                                self.handleMissingKeys(message: message, forwarded: forwarded, delayed: delayed)
                                if (!message.isGroupChatMessage) {
                                    self.doGlacierbotAlert(addressJID: addressJID)
                                }
                            }
                        }
                    }
                    
                    return
                }
                
                return
            }
        }
        
        handleUnencryptedKeyData (unencryptedKeyData: unencryptedKeyData, iv: iv, senderDeviceId: senderDeviceId, forJID: forJID, encryptedPayload: encryptedPayload, delayed: delayed, forwarded: forwarded, isIncoming: incoming, message: message, originalMessage: originalMessage)
    }
    
    func doGlacierbotAlert(addressJID: XMPPJID) {
        let lekMessage = OTROutgoingMessage()!
        var lekName = ""
        if let jname  = self.myJID?.user {
            lekName = jname
        }
        
        var foundbud = false
        self.databaseConnection.read { (transaction) in
            if let buddy = OTRXMPPBuddy.fetchBuddy(jid: addressJID, accountUniqueId: self.accountYapKey, transaction: transaction) {
                lekMessage.buddyUniqueId = buddy.uniqueId
                foundbud = true
            }
        }
        
        lekMessage.text = "Glacierbot 🤖: We had a problem delivering your last message to " + lekName + ". We've attempted to reset the secure connection. Please try to send your message again and if the problem continues contact Glacier Support."
        
        if (foundbud) {
            self.encryptAndSendMessage(lekMessage) { (success, nil) in
                if (success == false) {
                    OTRProtocolManager.sharedInstance().send(lekMessage)
                }
            }
        }
    }
    
    func handleUnencryptedKeyData(unencryptedKeyData: Data?, iv: Data, senderDeviceId: UInt32, forJID: XMPPJID, encryptedPayload: Data, delayed: Date?, forwarded: Bool, isIncoming: Bool, message: XMPPMessage, originalMessage: XMPPMessage) {
        let aesGcmBlockLength = 16
        
        guard var aesKey = unencryptedKeyData else {
            handleMissingKeys(message: message, forwarded: forwarded, delayed: delayed)
            return
        }
        var authTag: Data?
        
        // Treat >=32 bytes OMEMO 'keys' as containing the auth tag.
        // https://github.com/ChatSecure/ChatSecure-iOS/issues/647
        if (aesKey.count >= aesGcmBlockLength * 2) {
            
            authTag = aesKey.subdata(in: aesGcmBlockLength..<aesKey.count)
            aesKey = aesKey.subdata(in: 0..<aesGcmBlockLength)
        }
        
        var tmpBody: Data?
        // If there's already an auth tag, that means the payload
        // doesn't contain the auth tag.
        if authTag != nil { // omemo namespace
            tmpBody = encryptedPayload
        } else { // 'siacs' namespace fallback
            
            tmpBody = encryptedPayload.subdata(in: 0..<encryptedPayload.count - aesGcmBlockLength)
            authTag = encryptedPayload.subdata(in: encryptedPayload.count - aesGcmBlockLength..<encryptedPayload.count)
        }
        guard let tag = authTag, let encryptedBody = tmpBody else {
            return
        }
        
        do {
            guard let messageBody = try OTRSignalEncryptionHelper.decryptData(encryptedBody, key: aesKey, iv: iv, authTag: tag),
            var messageString = String(data: messageBody, encoding: String.Encoding.utf8),
            messageString.count > 0 else {
                return
            }
            
            // for sending location
            let messageCopy = String(data: messageBody, encoding: String.Encoding.utf8)
            if (messageString.hasPrefix("geo:")) {
                let newMsg = messageString
                let geoless = newMsg.replacingOccurrences(of: "geo:", with: "", options: .regularExpression)
                if geoless.contains(",") {
                    let latlon = geoless.components(separatedBy: ",")
                    let latd = (latlon.first! as NSString).doubleValue
                    let lond = (latlon.last! as NSString).doubleValue
                    
                    let defaultAccessToken = Bundle.main.object(forInfoDictionaryKey: "MGLMapboxAccessToken") as? String
                    
                    let camera = SnapshotCamera(
                        lookingAtCenter: CLLocationCoordinate2D(latitude: latd, longitude: lond),
                        zoomLevel: 12)
                    let options = SnapshotOptions(
                        styleURL: URL(string: "mapbox://styles/mapbox/dark-v9")!,
                        camera: camera,
                        size: CGSize(width: 667, height: 667))
                    let snapshot = Snapshot(
                        options: options,
                        accessToken: defaultAccessToken)
                    
                    let imageURL = snapshot.url.absoluteString
                    if imageURL.range(of:"https") != nil {
                        messageString = imageURL.replacingOccurrences(of: "https", with: "aesgcm")
                    }
                }
            }
            
            let preSave: MessageStorage.PreSave = { message, transaction in
                guard let buddy = message.buddy(with: transaction) else {
                    return
                }

                let deviceNumber = NSNumber(value: senderDeviceId as UInt32)
                let deviceYapKey = OMEMODevice.yapKey(withDeviceId: deviceNumber, parentKey: buddy.uniqueId, parentCollection: OTRBuddy.collection)
                message.messageSecurityInfo = OTRMessageEncryptionInfo.init(omemoDevice: deviceYapKey, collection: OMEMODevice.collection)
                
                message.save(with: transaction)
                
                if let threadOwner = message.threadOwner(with: transaction)?.copyAsSelf() {
                    // new messages of conversations in Archive page move back to Inbox
                    if threadOwner.isArchived {
                        threadOwner.isArchived = false
                        transaction.setObject(threadOwner, forKey:threadOwner.threadIdentifier, inCollection:threadOwner.threadCollection)
                    }
                    
                    threadOwner.lastMessageIdentifier = message.uniqueId
                    threadOwner.save(with: transaction)
                }
                
                //Update device last received message
                guard let device = OMEMODevice.fetchObject(withUniqueID: deviceYapKey, transaction: transaction)?.copyAsSelf() else {
                    return
                }
                device.lastSeenDate = Date()
                device.save(with: transaction)
            }
            
            if message.isGroupChatMessage {
                if let roomJID = message.from?.bareJID,
                    let room = self.roomManager.room(for: roomJID) {
                    self.roomManager.roomStorage.insertIncoming(message, body: messageString, original: messageCopy, delayed: delayed, into: room, preSave: preSave)
                }
            } else {
                if forwarded {
                    var isOutgoingFromOtherDevice = false
                    if let origto = originalMessage.to, let forwardedfrom = message.from {
                        if (origto.bare == forwardedfrom.bare && origto.resource != forwardedfrom.resource) {
                            isOutgoingFromOtherDevice = true
                            if (messageCopy?.hasPrefix("geo:") ?? false) {
                                messageString = messageCopy ?? messageString
                            }
                        }
                    }
                    
                    self.messageStorage.handleForwardedMessage(message, forJID: forJID, body: messageString, original: messageCopy, accountId: self.accountYapKey, delayed: delayed, isIncoming: isIncoming, isOutgoingFromOtherDevice: isOutgoingFromOtherDevice, preSave: preSave)
                } else {
                    self.messageStorage.handleDirectMessage(message, body: messageString, original: messageCopy, accountId: self.accountYapKey, preSave: preSave)
                }
            }
            
        } catch let error {
            DDLogError("Message decryption error: \(error)")
            return
        }
    }
    
    func createSession(jid: XMPPJID, completion:@escaping (Bool) -> Void) {
        var keyForSession: String?
        self.databaseConnection.read { (transaction) in
            if let buddy = OTRXMPPBuddy.fetchBuddy(jid: jid, accountUniqueId: self.accountYapKey, transaction: transaction) {
                    keyForSession = buddy.uniqueId
            }
        }
    
        if let key = keyForSession {
            self.prepareSessionForBuddy(key, completion: completion)
        }
    }
    
    private var publishingMyDevice:Bool = false
    private var missingKeysSet = Set<String>()
    func handleMissingKeys(message: XMPPMessage, forwarded: Bool, delayed: Date?) {
        // 1 - store unencrypted notice of failed message
        // 2 - call for key exchange
        if let messageString = message.body,
            messageString.count > 0,
            messageString.contains("encrypted message"){
            
            //this is a self-sent message, not sure why its getting here
            //if (messageString.contains("Sent encrypted message")) {
            //    return
            //}
            
            if message.isGroupChatMessage {
                if let roomJID = message.from?.bareJID,
                    let room = self.roomManager.room(for: roomJID) {
                    
                    guard let myRoomJID = room.myRoomJID,
                        let messageJID = message.from else {
                            //DDLogError("Discarding invalid MUC message \(message)")
                            return
                    }
                    if myRoomJID.isEqual(to: messageJID),
                        !message.wasDelayed {
                        // DDLogVerbose("Discarding duplicate outgoing MUC message \(message)")
                        return
                    }
                    
                    // this can be delayed/stamped from me if it was a share.
                    // Will it cause big problems to ignore anything from my roomjid?
                    if myRoomJID.isEqual(to: messageJID) {
                        // DDLogVerbose("Discarding duplicate outgoing MUC message \(message)")
                        return
                    }
                    
                    let missingFrom = roomJID.bare
                    if (!missingKeysSet.contains(missingFrom)) {
                        // check if appDelegate ready to handle undecryptable
                        if (self.isBeforeMyTime(message: message, delayed: delayed)) {
                            return
                        }
                        
                        self.missingKeysSet.insert(missingFrom)
                        self.roomManager.roomStorage.handleFailedIncomingMessage(message, room: room)
                        
                        //put this on a timer. if just published, don't immediately do it again
                        //in case we opened and logged in to multiple messages we cant decrypt
                        if let myid = self.myJID, !self.publishingMyDevice {
                            self.publishingMyDevice = true
                            let devices = self.fetchDeviceIds(for: myid)
                            self.omemoModule?.publishDeviceIds(devices, elementId: nil)
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
                                self.missingKeysSet.removeAll()
                                self.publishingMyDevice = false
                            }
                        }
                    }
                }
            } else {
                if forwarded {
                    if let from = message.from?.bareJID.bare, let test = self.myJID?.bare, from == test {
                        //this might be due to MAM...
                        return
                    }
                 } 
                
                if let missingFrom = message.fromStr,
                    !missingKeysSet.contains(missingFrom) {
                    
                    // check if appDelegate ready to handle undecryptable
                    if (self.isBeforeMyTime(message: message, delayed: delayed)) {
                        return
                    }
                    
                    self.missingKeysSet.insert(missingFrom)
                    self.messageStorage.handleDirectMessage(message, body: "Message cannot be decrypted - tap here to reset session.", original: nil, accountId: self.accountYapKey) 
                    
                    //put this on a timer. if just published, don't immediately do it again
                    //in case we opened and logged in to multiple messages we cant decrypt
                    if let myid = self.myJID, !self.publishingMyDevice {
                        self.publishingMyDevice = true
                        let devices = self.fetchDeviceIds(for: myid)
                        self.omemoModule?.publishDeviceIds(devices, elementId: nil)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
                            self.missingKeysSet.removeAll()
                            self.publishingMyDevice = false
                        }
                    }
                }
            }
        }
    }
    
    func isBeforeMyTime(message: XMPPMessage, delayed: Date?) -> Bool {
        
        var msgtime = Date.distantFuture
        if let delayedtime = delayed {
            msgtime = delayedtime
        } else if let delaydate = message.delayedDeliveryDate {
            msgtime = delaydate
        } else {
            return false
        }
        
        var acctTime = Date.distantPast
        self.databaseConnection.readWrite({ (transaction) in
            if let object = transaction.object(forKey: self.accountYapKey, inCollection: OTRAccount.collection) {
                if let account = object as? OTRAccount {
                    if let loginDate = account.loginDate {
                        acctTime = loginDate
                    } else {
                        let cur = Date()
                        account.loginDate = cur
                        acctTime = cur
                        account.save(with: transaction)
                    }
                }
            }
        })
        
        if (acctTime > msgtime) {
            return true
        }

        return false
    }
}

// MARK: - OMEMOModuleDelegate
extension OTROMEMOSignalCoordinator: OMEMOModuleDelegate {
    
    public func omemo(_ omemo: OMEMOModule, publishedDeviceIds deviceIds: [NSNumber], responseIq: XMPPIQ, outgoingIq: XMPPIQ) {
        //DDLogVerbose("publishedDeviceIds: \(responseIq)")

    }
    
    public func omemo(_ omemo: OMEMOModule, failedToPublishDeviceIds deviceIds: [NSNumber], errorIq: XMPPIQ?, outgoingIq: XMPPIQ) {
        DDLogWarn("failedToPublishDeviceIds: \(String(describing: errorIq))")
    }
    
    public func omemo(_ omemo: OMEMOModule, deviceListUpdate deviceIds: [NSNumber], from fromJID: XMPPJID, incomingElement: XMPPElement) {
        //DDLogVerbose("deviceListUpdate: \(fromJID) \(deviceIds)")
        self.workQueue.async { [weak self] in
            if let eid = incomingElement.elementID {
                self?.callAndRemoveOutstandingBundleBlock(eid, success: true)
            }
        }
    }
    
    public func omemo(_ omemo: OMEMOModule, failedToFetchDeviceIdsFor fromJID: XMPPJID, errorIq: XMPPIQ?, outgoingIq: XMPPIQ) {
        DDLogWarn("failedToFetchDeviceIdsFor \(fromJID)")
        self.workQueue.async { [weak self] in
            self?.callAndRemoveOutstandingDeviceIdFetch(fromJID, success: false)
            if let eid = outgoingIq.elementID {
                self?.callAndRemoveOutstandingBundleBlock(eid, success: false)
            }
        }
    }
    
    public func omemo(_ omemo: OMEMOModule, publishedBundle bundle: OMEMOBundle, responseIq: XMPPIQ, outgoingIq: XMPPIQ) {
        //DDLogVerbose("publishedBundle: \(responseIq) \(outgoingIq)")
    }
    
    public func omemo(_ omemo: OMEMOModule, failedToPublishBundle bundle: OMEMOBundle, errorIq: XMPPIQ?, outgoingIq: XMPPIQ) {
        DDLogWarn("failedToPublishBundle: \(String(describing: errorIq)) \(outgoingIq)")
    }
    
    public func omemo(_ omemo: OMEMOModule, fetchedBundle bundle: OMEMOBundle, from fromJID: XMPPJID, responseIq: XMPPIQ, outgoingIq: XMPPIQ) {
        //DDLogVerbose("fetchedBundle: \(responseIq) \(outgoingIq)")

        if (self.isOurJID(fromJID) && bundle.deviceId == self.signalEncryptionManager.registrationId) {
            //DDLogVerbose("fetchedOurOwnBundle: \(responseIq) \(outgoingIq)")

            //We fetched our own bundle
            if let ourDatabaseBundle = self.fetchMyBundle() {
                //This bundle doesn't have the correct identity key. Something has gone wrong and we should republish
                if ourDatabaseBundle.identityKey != bundle.identityKey {
                    //DDLogError("Bundle identityKeys do not match! \(ourDatabaseBundle.identityKey) vs \(bundle.identityKey)")
                    omemo.publishBundle(ourDatabaseBundle, elementId: nil)
                }
            }
            return;
        }
        
        self.workQueue.async { [weak self] in
            let elementId = outgoingIq.elementID
            if (bundle.preKeys.count == 0) {
                self?.callAndRemoveOutstandingBundleBlock(elementId!, success: false)
                return
            }
            var result = false
            //Consume the incoming bundle. This goes through signal and should hit the storage delegate. So we don't need to store ourselves here.
            do {
                try self?.signalEncryptionManager.consumeIncomingBundle(fromJID.bare, bundle: bundle)
                result = true
            } catch let err {
                DDLogWarn("Error consuming incoming bundle: \(err) \(responseIq.prettyXMLString())")
            }
            self?.callAndRemoveOutstandingBundleBlock(elementId!, success: result)
        }
        
    }
    public func omemo(_ omemo: OMEMOModule, failedToFetchBundleForDeviceId deviceId: UInt32, from fromJID: XMPPJID, errorIq: XMPPIQ?, outgoingIq: XMPPIQ) {
        
        self.workQueue.async { [weak self] in
            let elementId = outgoingIq.elementID
            self?.callAndRemoveOutstandingBundleBlock(elementId!, success: false)
        }
    }
    
    public func omemo(_ omemo: OMEMOModule, removedBundleId bundleId: UInt32, responseIq: XMPPIQ, outgoingIq: XMPPIQ) {
        
    }
    
    public func omemo(_ omemo: OMEMOModule, failedToRemoveBundleId bundleId: UInt32, errorIq: XMPPIQ?, outgoingIq: XMPPIQ) {
        DDLogWarn("Error removing bundle: \(String(describing: errorIq))")
    }
    
    public func omemo(_ omemo: OMEMOModule, failedToRemoveDeviceIds deviceIds: [NSNumber], errorIq: XMPPIQ?, elementId: String?) {
        self.workQueue.async { [weak self] in
            if let eid = elementId {
                self?.callAndRemoveOutstandingBundleBlock(eid, success: false)
            }
        }
    }
    
    public func omemo(_ omemo: OMEMOModule, receivedKeyData keyData: [OMEMOKeyData], iv: Data, senderDeviceId: UInt32, from fromJID: XMPPJID, payload: Data?, message: XMPPMessage) {
        self.processKeyData(keyData, iv: iv, senderDeviceId: senderDeviceId, forJID: fromJID, payload: payload, delayed: nil, forwarded: false, isIncoming: true, message: message, originalMessage: message)
    }
    
    public func omemo(_ omemo: OMEMOModule, receivedForwardedKeyData keyData: [OMEMOKeyData], iv: Data, senderDeviceId: UInt32, for forJID: XMPPJID, payload: Data?, isIncoming: Bool, delayed: Date?, forwardedMessage: XMPPMessage, originalMessage: XMPPMessage) {
        self.processKeyData(keyData, iv: iv, senderDeviceId: senderDeviceId, forJID: forJID, payload: payload, delayed: delayed, forwarded: true, isIncoming: isIncoming, message: forwardedMessage, originalMessage: originalMessage) 
    }
}

// MARK: - OMEMOStorageDelegate
extension OTROMEMOSignalCoordinator:OMEMOStorageDelegate {
    
    public func configure(withParent aParent: OMEMOModule, queue: DispatchQueue) -> Bool {
        self.omemoModule = aParent
        self.omemoModuleQueue = queue
        return true
    }
    
    public func storeDeviceIds(_ deviceIds: [NSNumber], for jid: XMPPJID) {
        
        let isOurDeviceList = self.isOurJID(jid)
        
        
        if (isOurDeviceList) {
            self.omemoStorageManager.storeOurDevices(deviceIds)
        } else {
            self.omemoStorageManager.storeBuddyDevices(deviceIds, buddyUsername: jid.bare, completion: {() -> Void in

                //Devices updated for buddy
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: OTROMEMOSignalCoordinator.DeviceListUpdateNotificationName, object: self, userInfo: ["jid":jid])
                }
            })
        }
        callAndRemoveOutstandingDeviceIdFetch(jid, success: true)
    }
    
    public func fetchDeviceIds(for jid: XMPPJID) -> [NSNumber] {
        var devices:[OMEMODevice]?
        if self.isOurJID(jid) {
            devices = self.omemoStorageManager.getDevicesForOurAccount(trustedOnly: false)
        } else {
            devices = self.omemoStorageManager.getDevicesForBuddy(jid.bare, trustedOnly:false)
        }
        //Convert from devices array to NSNumber array.
        return (devices?.map({ (device) -> NSNumber in
            return device.deviceId
        })) ?? [NSNumber]()
        
    }

    //Always returns most complete bundle with correct count of prekeys
    public func fetchMyBundle() -> OMEMOBundle? {
        var _bundle: OMEMOBundle? = nil
        
        do {
            _bundle = try signalEncryptionManager.storage.fetchOurExistingBundle()
            
        } catch let omemoError as OMEMOBundleError {
            switch omemoError {
            case .invalid:
                DDLogError("Found invalid stored bundle!")
                // delete???
                break
            default:
                break
            }
        } catch let error {
            DDLogError("Other error fetching bundle! \(error)")
        }
        let maxTries = 50
        var tries = 0
        while _bundle == nil && tries < maxTries {
            tries = tries + 1
            do {
                _bundle = try self.signalEncryptionManager.generateOutgoingBundle(self.preKeyCount)
            } catch let error {
                DDLogError("Error generating bundle! Try #\(tries)/\(maxTries) \(error)")
            }
        }
        guard let bundle = _bundle else {
            DDLogError("Could not fetch or generate valid bundle!")
            return nil
        }
        
        var preKeys = bundle.preKeys
        
        let keysToGenerate = Int(self.preKeyCount) - preKeys.count
        
        //Check if we don't have all the prekeys we need
        if (keysToGenerate > 0) {
            var start:UInt = 0
            if let maxId = self.signalEncryptionManager.storage.currentMaxPreKeyId() {
                start = UInt(maxId) + 1
            }
            
            if let newPreKeys = self.signalEncryptionManager.generatePreKeys(start, count: UInt(keysToGenerate)) {
                let omemoKeys = OMEMOPreKey.preKeysFromSignal(newPreKeys)
                preKeys.append(contentsOf: omemoKeys)
            }
        }
        
        let newBundle = bundle.copyBundle(newPreKeys: preKeys)
        return newBundle
    }

    public func isSessionValid(_ jid: XMPPJID, deviceId: UInt32) -> Bool {
        return self.signalEncryptionManager.sessionRecordExistsForUsername(jid.bare, deviceId: Int32(deviceId))
    }
}
