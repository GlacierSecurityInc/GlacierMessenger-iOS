//
//  NotificationOMEMOSignalCoordinator.swift
//  GlacierNotifications
//
//  Created by Andy Friedman on 9/23/20.
//  Copyright © 2020 Glacier. All rights reserved.
//

import UIKit
import XMPPFramework
import YapDatabase
import CocoaLumberjack
import SignalProtocolObjC

@objc public protocol NotificationMessageDelegate: NSObjectProtocol {
    func decryptedMessage(_ message:NotificationMessage)
    func failedToDecryptMessage(_ message:NotificationMessage)
}

/**
 * This is the glue between XMPP/OMEMO and Signal
 */
@objc open class NotificationOMEMOSignalCoordinator: NSObject {
    
    public let signalEncryptionManager:OTRAccountSignalEncryptionManager
    public let omemoStorageManager:OTROMEMOStorageManager
    @objc public let accountYapKey:String
    @objc public let databaseConnection:YapDatabaseConnection
    @objc open weak var omemoModule:OMEMOModule?
    @objc open weak var omemoModuleQueue:DispatchQueue?
    @objc open var callbackQueue:DispatchQueue
    @objc public let workQueue:DispatchQueue
    
    @objc open weak var delegate:NotificationMessageDelegate?

    fileprivate var myJID:XMPPJID? {
        get {
            return omemoModule?.xmppStream?.myJID
        }
    }
    let preKeyCount:UInt = 100
    fileprivate var outstandingXMPPStanzaResponseBlocks:[String: (Bool) -> Void]
    /// callbacks for when fetching device Id list
    private var deviceIdFetchCallbacks:[XMPPJID: (Bool) -> Void] = [:]
    
    /**
     Create a NotificationOMEMOSignalCoordinator for an account.
     
     - parameter accountYapKey: The accounts unique yap key
     - parameter databaseConnection: A yap database connection on which all operations will be completed on
 `  */
    @objc public required init(accountYapKey:String,
                               databaseConnection:YapDatabaseConnection, notificationDelegate:NotificationMessageDelegate) throws {
        try self.signalEncryptionManager = OTRAccountSignalEncryptionManager(accountKey: accountYapKey,databaseConnection: databaseConnection)
        self.omemoStorageManager = OTROMEMOStorageManager(accountKey: accountYapKey, accountCollection: "OTRAccount", databaseConnection: databaseConnection)
        self.accountYapKey = accountYapKey
        self.databaseConnection = databaseConnection
        self.delegate = notificationDelegate
        self.outstandingXMPPStanzaResponseBlocks = [:]
        self.callbackQueue = DispatchQueue(label: "NotificationOMEMOSignalCoordinator-callback", attributes: [])
        self.workQueue = DispatchQueue(label: "NotificationOMEMOSignalCoordinator-work", attributes: [])
        
        NSKeyedUnarchiver.setClass(OTRGroupDownloadMessage.self, forClassName: "Glacier.OTRGroupDownloadMessage")
        NSKeyedUnarchiver.setClass(OTRXMPPRoomMessage.self, forClassName: "Glacier.OTRXMPPRoomMessage")
        NSKeyedUnarchiver.setClass(OTRXMPPRoomOccupant.self, forClassName: "Glacier.OTRXMPPRoomOccupant")
        NSKeyedUnarchiver.setClass(OTRXMPPRoom.self, forClassName: "Glacier.OTRXMPPRoom")
        
        NSKeyedArchiver.setClassName("Glacier.OTRGroupDownloadMessage", for: OTRGroupDownloadMessage.self)
        NSKeyedArchiver.setClassName("Glacier.OTRXMPPRoomMessage", for: OTRXMPPRoomMessage.self)
        NSKeyedArchiver.setClassName("Glacier.OTRXMPPRoomOccupant", for: OTRXMPPRoomOccupant.self)
        NSKeyedArchiver.setClassName("Glacier.OTRXMPPRoom", for: OTRXMPPRoom.self)
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
            if let object = transaction.object(forKey: self.accountYapKey, inCollection: "OTRAccount") {
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
    
    @objc public func processUnencryptedData(_ isIncoming: Bool, message: XMPPMessage, forJID: XMPPJID) {
        let decryptedMsg = NotificationMessage()
        guard let myJID = self.myJID else {
            delegate?.failedToDecryptMessage(decryptedMsg)
            return
        }
        var _addressJID: XMPPJID? = nil
        var isIncoming = isIncoming
        
        // handle incoming group chat messages slightly differently
        if message.isGroupChatMessage {
            if let groupAddressJID = extractAddressFromGroupMessage(message) {
                _addressJID = groupAddressJID
                if groupAddressJID.isEqual(to: myJID, options: .bare) {
                    isIncoming = false
                } else {
                    isIncoming = true
                }
            } else {
                DDLogWarn("Found Incoming OMEMO group message, but corresponding Buddy could not be found!")
                delegate?.failedToDecryptMessage(decryptedMsg)
                return
            }
        } else {
            if !isIncoming {
                delegate?.failedToDecryptMessage(decryptedMsg)
                return
            } else {
                _addressJID = forJID.bareJID
            }
            
        }
        guard let addressJID = _addressJID else {
            delegate?.failedToDecryptMessage(decryptedMsg)
            return
        }
        
        let displayName = getDisplayName(message, from: addressJID)
        if message.isGroupChatMessage {
            if let fromJID = message.from {
                let roomJID = fromJID.bareJID
                
                let accountId = accountYapKey
                let roomUniqueId = OTRXMPPRoom.createUniqueId(accountId, jid: roomJID.bare)
                self.databaseConnection.read({ (transaction) in
                    if let object = transaction.object(forKey: roomUniqueId, inCollection: "Glacier.OTRXMPPRoom"), let xroom = object as? OTRXMPPRoom {
                        decryptedMsg.from = "#" + xroom.threadName
                    } else {
                        let namecomponents = roomJID.bare.components(separatedBy: "@")
                        if (namecomponents.count == 2 && namecomponents[0].count > 0) {
                            decryptedMsg.from = "#" + namecomponents[0]
                        }
                    }
                })
            }
        } else {
            decryptedMsg.from = displayName
        }
        
        guard var messageString = message.body, messageString.count > 0 else {
            if (displayName != nil && message.isGroupChatMessage) {
                decryptedMsg.message = "From: " + displayName!
            }
            delegate?.failedToDecryptMessage(decryptedMsg)
            return
        }
        
        if (messageString.hasPrefix("geo:")) {
            messageString = "Location Received"
        }
        
        messageString = getMediaString(messageString)
        
        if (displayName != nil && message.isGroupChatMessage) {
            decryptedMsg.message = displayName! + ": " + messageString
        } else {
            decryptedMsg.message = messageString
        }
        
        delegate?.decryptedMessage(decryptedMsg)
    }
    
    @objc public func processKeyData(_ keyData: [OMEMOKeyData], iv: Data, senderDeviceId: UInt32, forJID: XMPPJID, payload: Data?, delayed: Date?, forwarded: Bool, isIncoming: Bool, message: XMPPMessage, originalMessage: XMPPMessage) {
        var isIncoming = isIncoming
        let aesGcmBlockLength = 16
        let decryptedMsg = NotificationMessage()
        guard let encryptedPayload = payload, encryptedPayload.count > 0, let myJID = self.myJID else {
            delegate?.failedToDecryptMessage(decryptedMsg)
            return
        }
        var _addressJID: XMPPJID? = nil
        // handle incoming group chat messages slightly differently
        if message.isGroupChatMessage {
            if let groupAddressJID = extractAddressFromGroupMessage(message) {
                _addressJID = groupAddressJID
                if groupAddressJID.isEqual(to: myJID, options: .bare) {
                    isIncoming = false
                } else {
                    isIncoming = true
                }
            } else {
                DDLogWarn("Found Incoming OMEMO group message, but corresponding Buddy could not be found!")
                delegate?.failedToDecryptMessage(decryptedMsg)
                return
            }
        } else {
            if !isIncoming {
                delegate?.failedToDecryptMessage(decryptedMsg)
                return
            } else {
                _addressJID = forJID.bareJID
            }
            
        }
        guard let addressJID = _addressJID else {
            delegate?.failedToDecryptMessage(decryptedMsg)
            return
        }
        
        let displayName = getDisplayName(message, from: addressJID)
        if message.isGroupChatMessage {
            if let fromJID = message.from {
                let roomJID = fromJID.bareJID
                
                let accountId = accountYapKey
                let roomUniqueId = OTRXMPPRoom.createUniqueId(accountId, jid: roomJID.bare)
                self.databaseConnection.read({ (transaction) in
                    if let object = transaction.object(forKey: roomUniqueId, inCollection: "Glacier.OTRXMPPRoom"), let xroom = object as? OTRXMPPRoom {
                        decryptedMsg.from = "#" + xroom.threadName
                    } else {
                        let namecomponents = roomJID.bare.components(separatedBy: "@")
                        if (namecomponents.count == 2 && namecomponents[0].count > 0) {
                            decryptedMsg.from = "#" + namecomponents[0]
                        }
                    }
                })
            }
        } else {
            decryptedMsg.from = displayName
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
                if (displayName != nil && message.isGroupChatMessage) {
                    decryptedMsg.message = "From: " + displayName!
                }
                delegate?.failedToDecryptMessage(decryptedMsg)
                return
            }
        }
        
        guard var aesKey = unencryptedKeyData else {
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
            if (displayName != nil && message.isGroupChatMessage) {
                decryptedMsg.message = "From: " + displayName!
            }
            delegate?.failedToDecryptMessage(decryptedMsg)
            return
        }
        
        do {
            guard let messageBody = try OTRSignalEncryptionHelper.decryptData(encryptedBody, key: aesKey, iv: iv, authTag: tag),
            var messageString = String(data: messageBody, encoding: String.Encoding.utf8),
            messageString.count > 0 else {
                if (displayName != nil && message.isGroupChatMessage) {
                    decryptedMsg.message = "From: " + displayName!
                }
                delegate?.failedToDecryptMessage(decryptedMsg)
                return
            }
            
            if (messageString.hasPrefix("geo:")) {
                messageString = "Location Received"
            }
            
            messageString = getMediaString(messageString)
            
            if (displayName != nil && message.isGroupChatMessage) {
                decryptedMsg.message = displayName! + ": " + messageString
            } else {
                decryptedMsg.message = messageString
            }
            
            delegate?.decryptedMessage(decryptedMsg)
            
        } catch let error {
            if (displayName != nil && message.isGroupChatMessage) {
                decryptedMsg.message = "From: " + displayName!
            }
            delegate?.failedToDecryptMessage(decryptedMsg)
            DDLogError("Message decryption error: \(error)")
            return
        }
    }
    
    fileprivate func getDisplayName(_ message:XMPPMessage, from: XMPPJID) -> String? {
        var displayName = from.user
        self.databaseConnection.read({ (transaction) in
            if let object = transaction.object(forKey: self.accountYapKey, inCollection: OTRAccount.collection) {
                if let account = object as? OTRAccount {
                    account.allBuddies(with: transaction).forEach { (buddy) in
                        let tempjid = XMPPJID(string: buddy.username)
                        if (from.user == tempjid?.user) {
                            displayName = buddy.displayName
                        }
                    }
                }
            }
        })
        return displayName
    }
    
    fileprivate func getMediaString (_ messageString:String) -> String {
        if messageString.count == 0 || messageString.downloadableURLs.count == 0 {
            return messageString
        }
        var mediaString = messageString
        
        if let fileurl = mediaString.downloadableURLs.first {
            if (fileurl.lastPathComponent.hasSuffix(".null")) {
                let fullPathComponent = fileurl.lastPathComponent
                let end = fullPathComponent.index(fullPathComponent.endIndex, offsetBy: -5)
                let range = fullPathComponent.startIndex..<end
                mediaString = String(fullPathComponent[range])
            }
            
            if (mediaString.contains("#")) {
                let components = mediaString.components(separatedBy: "#")
                mediaString = components[0]
            }
            mediaString = mediaString.lowercased()
            
            if mediaString.hasSuffix(".m4a") || mediaString.hasSuffix(".wav") {
                mediaString = "Audio received"
            } else if mediaString.hasSuffix(".jpg") || mediaString.hasSuffix(".png") || mediaString.hasSuffix(".jpeg") || mediaString.hasSuffix(".gif") {
                mediaString = "Image received"
            } else if mediaString.hasSuffix(".mov") || mediaString.hasSuffix(".qt") || mediaString.hasSuffix(".mp4") {
                mediaString = "Video received"
            } else if mediaString.hasSuffix(".pdf") || mediaString.hasSuffix(".doc") || mediaString.hasSuffix(".docx") {
                mediaString = "File received"
            } else {
                mediaString = "Media received"
            }
        }
        
        return mediaString
    }
}

// MARK: - OMEMOModuleDelegate
extension NotificationOMEMOSignalCoordinator: OMEMOModuleDelegate {
    
    public func omemo(_ omemo: OMEMOModule, publishedDeviceIds deviceIds: [NSNumber], responseIq: XMPPIQ, outgoingIq: XMPPIQ) {
        //DDLogVerbose("publishedDeviceIds: \(responseIq)")

    }
    
    public func omemo(_ omemo: OMEMOModule, failedToPublishDeviceIds deviceIds: [NSNumber], errorIq: XMPPIQ?, outgoingIq: XMPPIQ) {
        DDLogWarn("failedToPublishDeviceIds: \(String(describing: errorIq))")
    }
    
    public func omemo(_ omemo: OMEMOModule, deviceListUpdate deviceIds: [NSNumber], from fromJID: XMPPJID, incomingElement: XMPPElement) {
        //
    }
    
    public func omemo(_ omemo: OMEMOModule, failedToFetchDeviceIdsFor fromJID: XMPPJID, errorIq: XMPPIQ?, outgoingIq: XMPPIQ) {
        //
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
        //
    }
    
    public func omemo(_ omemo: OMEMOModule, removedBundleId bundleId: UInt32, responseIq: XMPPIQ, outgoingIq: XMPPIQ) {
        
    }
    
    public func omemo(_ omemo: OMEMOModule, failedToRemoveBundleId bundleId: UInt32, errorIq: XMPPIQ?, outgoingIq: XMPPIQ) {
        DDLogWarn("Error removing bundle: \(String(describing: errorIq))")
    }
    
    public func omemo(_ omemo: OMEMOModule, failedToRemoveDeviceIds deviceIds: [NSNumber], errorIq: XMPPIQ?, elementId: String?) {
        //
    }
    
    public func omemo(_ omemo: OMEMOModule, receivedKeyData keyData: [OMEMOKeyData], iv: Data, senderDeviceId: UInt32, from fromJID: XMPPJID, payload: Data?, message: XMPPMessage) {
        self.processKeyData(keyData, iv: iv, senderDeviceId: senderDeviceId, forJID: fromJID, payload: payload, delayed: nil, forwarded: false, isIncoming: true, message: message, originalMessage: message)
    }
    
    public func omemo(_ omemo: OMEMOModule, receivedForwardedKeyData keyData: [OMEMOKeyData], iv: Data, senderDeviceId: UInt32, for forJID: XMPPJID, payload: Data?, isIncoming: Bool, delayed: Date?, forwardedMessage: XMPPMessage, originalMessage: XMPPMessage) {
        self.processKeyData(keyData, iv: iv, senderDeviceId: senderDeviceId, forJID: forJID, payload: payload, delayed: delayed, forwarded: true, isIncoming: isIncoming, message: forwardedMessage, originalMessage: originalMessage)
    }
}

// MARK: - OMEMOStorageDelegate
extension NotificationOMEMOSignalCoordinator:OMEMOStorageDelegate {
    
    public func configure(withParent aParent: OMEMOModule, queue: DispatchQueue) -> Bool {
        self.omemoModule = aParent
        self.omemoModuleQueue = queue
        return true
    }
    
    public func storeDeviceIds(_ deviceIds: [NSNumber], for jid: XMPPJID) {
        
        /*let isOurDeviceList = self.isOurJID(jid)
        
        
        if (isOurDeviceList) {
            self.omemoStorageManager.storeOurDevices(deviceIds)
        } else {
            self.omemoStorageManager.storeBuddyDevices(deviceIds, buddyUsername: jid.bare, completion: {() -> Void in
            })
        }*/
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

@objc public class NotificationMessage:NSObject {
    @objc public var from:String?
    @objc public var message:String?
}

extension OTRDownloadMessage {
    /// Turn aesgcm links into https links
    var downloadableURL: URL? {
        guard var downloadableURL = url else { return nil }
        if downloadableURL.isAesGcm, var components = URLComponents(url: downloadableURL, resolvingAgainstBaseURL: true) {
            components.scheme = URLScheme.https.rawValue
            if let rawURL = components.url {
                downloadableURL = rawURL
            }
        }
        return downloadableURL
    }
}

public extension OTRMessageProtocol {
    var downloadableURLs: [URL] {
        return self.messageText?.downloadableURLs ?? []
    }
}

public extension OTRBaseMessage {
    @objc var downloadableNSURLs: [NSURL] {
        return self.downloadableURLs as [NSURL]
    }
}

public extension OTRXMPPRoomMessage {
    @objc var downloadableNSURLs: [NSURL] {
        return self.downloadableURLs as [NSURL]
    }
}

// expand to http?
enum URLScheme: String {
    case https = "https"
    case aesgcm = "aesgcm"
    static let downloadableSchemes: [URLScheme] = [.https, .aesgcm]
}

extension URL {
    
    /** URL scheme matches aesgcm:// */
    var isAesGcm: Bool {
        return scheme == URLScheme.aesgcm.rawValue
    }
    
}

public extension NSString {
    var isSingleURLOnly: Bool {
        return (self as String).isSingleURLOnly
    }
}

public extension String {
    
    private var urlRanges: ([URL], [NSRange]) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return ([], [])
        }
        var urls: [URL] = []
        var ranges: [NSRange] = []
        
        let matches = detector.matches(in: self, options: NSRegularExpression.MatchingOptions(rawValue: 0), range: NSRange(location: 0, length: self.utf16.count))
        
        for match in matches where match.resultType == .link {
            if let url = match.url {
                urls.append(url)
                ranges.append(match.range)
            }
        }
        return (urls, ranges)
    }
    
    /** Grab any URLs from a string */
    var urls: [URL] {
        let (urls, _) = urlRanges
        return urls
    }
    
    /** Returns true if the message is ONLY a single URL */
    var isSingleURLOnly: Bool {
        let (_, ranges) = urlRanges
        guard ranges.count == 1,
            let range = ranges.first,
            range.length == self.count else {
            return false
        }
        return true
    }
    
    /** Use this for extracting potentially downloadable URLs from a message. Currently checks for https:// and aesgcm:// */
    var downloadableURLs: [URL] {
        
        return urlsMatchingSchemes(URLScheme.downloadableSchemes)
    }
    
    fileprivate func urlsMatchingSchemes(_ schemes: [URLScheme]) -> [URL] {
        let urls = self.urls.filter {
            guard let scheme = $0.scheme?.lowercased() else { return false }
            for inScheme in schemes where inScheme.rawValue == scheme {
                return true
            }
            return false
        }
        return urls
    }
}
