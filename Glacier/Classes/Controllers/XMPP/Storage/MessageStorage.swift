//
//  MessageStorage.swift
//  ChatSecureCore
//
//  Created by Chris Ballinger on 11/21/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

import Foundation
import XMPPFramework
import CocoaLumberjack
import MapboxStatic


@objc public class MessageStorage: XMPPModule {
    /// This gets called before a message is saved, if additional processing needs to be done elsewhere
    public typealias PreSave = (_ message: OTRMessageProtocol, _ transaction: YapDatabaseReadWriteTransaction) -> Void

    // MARK: Properties
    private let connection: YapDatabaseConnection
    /// Only access this within moduleQueue
    private var mamCatchupInProgress: Bool = false
    
    /// Capabilities must be activated elsewhere
    @objc public let capabilities: XMPPCapabilities
    @objc public let archiving: XMPPMessageArchiveManagement
    @objc public let roomStorage: RoomStorage
    @objc public let roomManager: OTRXMPPRoomManager
    private let carbons: XMPPMessageCarbons
    private let fileTransfer: FileTransferManager

    // MARK: Init
    deinit {
        self.carbons.removeDelegate(self)
        self.archiving.removeDelegate(self)
    }
    
    /// Capabilities must be activated elsewhere
    @objc public init(connection: YapDatabaseConnection,
                      capabilities: XMPPCapabilities,
                      fileTransfer: FileTransferManager,
                      roomStorage: RoomStorage,
                      dispatchQueue: DispatchQueue? = nil) {
        self.connection = connection
        self.capabilities = capabilities
        self.carbons = XMPPMessageCarbons(dispatchQueue: dispatchQueue)
        let archiving = XMPPMessageArchiveManagement(dispatchQueue: dispatchQueue)
        self.archiving = archiving
        self.archiving.resultAutomaticPagingPageSize = NSNotFound
        self.fileTransfer = fileTransfer
        self.roomStorage = roomStorage
        self.roomManager = OTRXMPPRoomManager(databaseConnection: connection, roomStorage: roomStorage, archiving: archiving, dispatchQueue: dispatchQueue)
        super.init(dispatchQueue: dispatchQueue)
        self.carbons.addDelegate(self, delegateQueue: self.moduleQueue)
        self.archiving.addDelegate(self, delegateQueue: self.moduleQueue)
    }
    
    // MARK: XMPPModule overrides
    
    @discardableResult override public func activate(_ xmppStream: XMPPStream) -> Bool {
        guard super.activate(xmppStream),
            carbons.activate(xmppStream),
            archiving.activate(xmppStream),
            roomManager.activate(xmppStream)
            else {
            return false
        }
        return true
    }
    
    public override func deactivate() {
        carbons.deactivate()
        archiving.deactivate()
        roomManager.deactivate()
        super.deactivate()
    }
    
    // MARK: Private
    
    /// only if the new date is newer than the old date it will save
    private func updateLastFetch(account: OTRXMPPAccount, date: Date, transaction: YapDatabaseReadWriteTransaction) {
        // Don't update fetch date from realtime messages if we're currently fetching
        var fetching = false
        performBlock {
            fetching = self.mamCatchupInProgress
        }
        if fetching {
            return
        }
        if let lastFetch = account.lastHistoryFetchDate,
            date > lastFetch,
            let account = account.copyAsSelf() {
            account.lastHistoryFetchDate = date
            account.save(with: transaction)
        }
    }
    
    /// Updates chat state for buddy
    private func handleChatState(message: XMPPMessage, buddy: OTRXMPPBuddy) {
        let chatState = OTRChatState.chatState(from: message.chatState)
        OTRBuddyCache.shared.setChatState(chatState, for: buddy)
    }
    
    /// Marks a previously sent outgoing message as delivered.
    private func handleDeliveryResponse(message: XMPPMessage, transaction: YapDatabaseReadWriteTransaction) {
        guard message.hasReceiptResponse,
            !message.isErrorMessage,
            let responseId = message.receiptResponseID else {
                return
        }
        var _deliveredMessage: OTROutgoingMessage? = nil
        transaction.enumerateMessages(elementId: responseId, originId: responseId, stanzaId: nil) { (message, stop) in
            if let message = message as? OTROutgoingMessage {
                _deliveredMessage = message
                stop = true
            }
        }
        if _deliveredMessage == nil {
            DDLogWarn("Outgoing message not found for receipt: \(message)")
            // This can happen with MAM + OMEMO where the decryption
            // for the OMEMO message makes it come in after the receipt
            // To solve this, we need to make a placeholder message...
            
            // TODO.......
        }
        guard let deliveredMessage = _deliveredMessage,
            deliveredMessage.isDelivered == false,
            deliveredMessage.dateDelivered == nil else {
            return
        }
        if let deliveredMessage = deliveredMessage.copyAsSelf() {
            deliveredMessage.isDelivered = true
            deliveredMessage.dateDelivered = Date()
            deliveredMessage.save(with: transaction)
        }        
    }
    
    /// Marks a previously sent outgoing message as read.
    private func handleDisplayedResponse(message: XMPPMessage, transaction: YapDatabaseReadWriteTransaction) {
        guard message.hasDisplayedChatMarker,
            !message.isErrorMessage,
            let responseId = message.chatMarkerID else {
                return
        }
        var _displayedMessage: OTROutgoingMessage? = nil
        transaction.enumerateMessages(elementId: responseId, originId: responseId, stanzaId: nil) { (message, stop) in
            if let message = message as? OTROutgoingMessage {
                _displayedMessage = message
                stop = true
            }
        }
        guard let displayedMessage = _displayedMessage,
            displayedMessage.isDisplayed == false else {
            return
        }
        if let displayedMessage = displayedMessage.copyAsSelf() {
            displayedMessage.isDisplayed = true
            displayedMessage.save(with: transaction)
        }
    }
    
    /// It is a violation of the XMPP spec to discard messages with duplicate stanza elementIds. We must use XEP-0359 stanza-id only.
    private func isDuplicate(message: OTRBaseMessage, transaction: YapDatabaseReadTransaction) -> Bool {
        var result = false
        let buddyUniqueId = message.buddyUniqueId
        let oid = message.originId
        let sid = message.stanzaId
        if oid == nil, sid == nil {
            return false
        }
        transaction.enumerateMessages(elementId: oid, originId: oid, stanzaId: sid) { (foundMessage, stop) in
            if foundMessage.threadId == buddyUniqueId {
                result = true
                stop = true
            }
        }
        return result
    }
    
    /// Handles both MAM and Carbons
    public func handleForwardedMessage(_ xmppMessage: XMPPMessage,
                                        forJID: XMPPJID,
                                        body: String?,
                                        original: String?,
                                        accountId: String,
                                        delayed: Date?,
                                        isIncoming: Bool,
                                        isOutgoingFromOtherDevice: Bool,
                                        preSave: PreSave? = nil ) {
        guard !xmppMessage.isErrorMessage else {
            DDLogWarn("Discarding forwarded error message: \(xmppMessage)")
            return
        }
        // Inject MAM messages into group chat storage
        if xmppMessage.containsGroupChatElements {
            DDLogVerbose("Injecting forwarded MAM message into room: \(xmppMessage)")
            if let roomJID = xmppMessage.from?.bareJID {
                if let room = roomManager.room(for: roomJID) {
                    roomStorage.insertIncoming(xmppMessage, body: body, original: original, delayed: delayed, into: room)
                } else {
                    if xmppMessage.element(forName: "x", xmlns: XMPPMUCUserNamespace)?.element(forName:"invite") != nil {
                        roomManager.xmppMUC(nil, roomJID: roomJID, didReceiveInvitation: xmppMessage)
                    }
                }
            }
            return
        }
        // Ignore OTR text
        if let messageBody = xmppMessage.body, messageBody.isOtrText {
            return
        }

        connection.asyncReadWrite { (transaction) in
            guard let account = OTRXMPPAccount.fetchObject(withUniqueID: accountId, transaction: transaction),
                let buddy = OTRXMPPBuddy.fetchBuddy(jid: forJID, accountUniqueId: accountId, transaction: transaction) else {
                    return
            }
            var _message: OTRBaseMessage? = nil
            
            if isIncoming {
                self.handleDeliveryResponse(message: xmppMessage, transaction: transaction)
                self.handleChatState(message: xmppMessage, buddy: buddy)
                self.handleDisplayedResponse(message: xmppMessage, transaction: transaction)
                
                // If this is a receipt, we are done
                if xmppMessage.hasReceiptResponse || xmppMessage.hasDisplayedChatMarker {
                    return
                }
                
                let incomingMessage = OTRIncomingMessage(xmppMessage: xmppMessage, body: body, account: account, buddy: buddy, capabilities: self.capabilities)
                // mark message as read if this is a MAM catchup
                if delayed != nil {
                    //
                }
                
                if xmppMessage.hasMarkableChatMarker {
                    incomingMessage.markable = true
                }
                
                _message = incomingMessage
            } else {
                let outgoing = OTROutgoingMessage(xmppMessage: xmppMessage, body: body, account: account, buddy: buddy, capabilities: self.capabilities)
                outgoing.dateSent = delayed ?? Date()
                outgoing.readDate = Date()
                outgoing.isOutgoingFromDifferentDevice = isOutgoingFromOtherDevice
                _message = outgoing
            }
            guard let message = _message else {
                DDLogWarn("Discarding empty message: \(xmppMessage)")
                return
            }
            
            // Bail out if we receive duplicate messages identified by XEP-0359
            if self.isDuplicate(message: message, transaction: transaction) {
                DDLogWarn("Duplicate forwarded message received: \(xmppMessage)")
                return
            }
            
            if let expiretime = xmppMessage.element(forName: "x", xmlns: "jabber:x:msgexpire") {
                message.expires = expiretime.attributeStringValue(forName:"seconds")
            }
            message.originalText = original;
            
            if xmppMessage.element(forName: "x", xmlns: "jabber:x:systemupdate") != nil {
                message.systemUpdate = true
            }
            
            if let delayed = delayed {
                message.date = delayed
            }
            preSave?(message, transaction)
            message.save(with: transaction)
            if let incoming = message as? OTRIncomingMessage {
                // We only want to send receipts and show notifications for "real time" messages
                // undelivered messages still go through the "handleDirectMessage" path,
                // so MAM messages have been delivered to another device
                self.finishHandlingIncomingMessage(incoming, account: account, showNotification:(delayed == nil), from: forJID.bare, transaction: transaction)
            } else if let outgoing = message as? OTROutgoingMessage {
                if (outgoing.isOutgoingFromDifferentDevice) {
                    self.fileTransfer.createAndDownloadItemsIfNeeded(message: message, force: false, transaction: transaction)
                    /// mark as read if on screen
                    MessageStorage.markAsReadIfVisible(message: message, account: account)
                }
            }
            // let's count carbon messages as realtime
            if delayed == nil {
                self.updateLastFetch(account: account, date: Date(), transaction: transaction)
            }
        }
    }
    
    /// Inserts direct message into database
    public func handleDirectMessage(_ message: XMPPMessage,
                                    body: String?,
                                    original: String?,
                                    accountId: String,
                                    preSave: PreSave? = nil) {
        //var incomingMessage: OTRIncomingMessage? = nil
        connection.asyncReadWrite({ (transaction) in
            guard let account = OTRXMPPAccount.fetchObject(withUniqueID: accountId, transaction: transaction),
                let fromJID = message.from,
                let buddy = OTRXMPPBuddy.fetchBuddy(jid: fromJID, accountUniqueId: accountId, transaction: transaction)
                else {
                    return
            }

            // Update ChatState
            self.handleChatState(message: message, buddy: buddy)
            
            // Handle Delivery Receipts
            self.handleDeliveryResponse(message: message, transaction: transaction)
            self.handleDisplayedResponse(message: message, transaction: transaction)
            
            // Update lastSeenDate
            // If we receive a message from an online buddy that counts as them interacting with us
            let status = OTRBuddyCache.shared.threadStatus(for: buddy)
            if status != .offline,
                !message.hasReceiptResponse,
                !message.hasDisplayedChatMarker, 
                !message.isErrorMessage {
                OTRBuddyCache.shared.setLastSeenDate(Date(), for: buddy)
            }
            
            // Handle errors
            guard !message.isErrorMessage else {
                if let elementId = message.elementID,
                    let existingMessage = OTROutgoingMessage.message(forMessageId: elementId, transaction: transaction) {
                    if let outgoing = existingMessage as? OTROutgoingMessage {
                        outgoing.error = OTRXMPPError.error(for: message)
                        outgoing.save(with: transaction)
                    } else if existingMessage is OTRIncomingMessage,
                        let errorText = message.element(forName: "error")?.element(forName: "text")?.stringValue,
                        errorText.contains("OTR Error")
                    {
                        // automatically renegotiate a new session when there's an error
                        OTRProtocolManager.encryptionManager.otrKit.initiateEncryption(withUsername: fromJID.bare, accountName: account.username, protocol: account.protocolTypeString())
                        
                    }
                }
                return
            }
            
            let incoming = OTRIncomingMessage(xmppMessage: message, body: body, account: account, buddy: buddy, capabilities: self.capabilities)
            
            // Check for duplicates
            if self.isDuplicate(message: incoming, transaction: transaction) {
                DDLogWarn("Duplicate message received: \(message)")
                return
            }
            guard let text = incoming.text, text.count > 0 else {
                // discard empty message text
                return
            }
            
            // check message expiration
            if let expiretime = message.element(forName: "x", xmlns: "jabber:x:msgexpire") {
                incoming.expires = expiretime.attributeStringValue(forName:"seconds")
            }
            incoming.originalText = original;
            
            if message.element(forName: "x", xmlns: "jabber:x:systemupdate") != nil {
                incoming.systemUpdate = true
            }
            
            if message.hasMarkableChatMarker {
                incoming.markable = true
            }
            
            if text.isOtrText {
                OTRProtocolManager.encryptionManager.otrKit.decodeMessage(text, username: buddy.username, accountName: account.username, protocol: kOTRProtocolTypeXMPP, tag: incoming)
            } else {
                preSave?(incoming, transaction)
                incoming.save(with: transaction)
                
                self.finishHandlingIncomingMessage(incoming, account: account, showNotification:true, from: fromJID.bare, transaction: transaction)
            }
            self.updateLastFetch(account: account, date: incoming.messageDate, transaction: transaction)
        })
    }
    
    private func finishHandlingIncomingMessage(_ message: OTRIncomingMessage, account: OTRXMPPAccount, showNotification:Bool, from:String, transaction: YapDatabaseReadWriteTransaction) {
        guard let xmpp = OTRProtocolManager.shared.protocol(for: account) as? XMPPManager else {
            return
        }
        xmpp.sendDeliveryReceipt(for: message)
        
        self.fileTransfer.createAndDownloadItemsIfNeeded(message: message, force: false, transaction: transaction)
        if showNotification {
            Application.shared.showLocalNotification(message, transaction: transaction)
        } else {
            DispatchQueue.main.async {
                OTRAppDelegate.appDelegate.setResortIfNeeded()
            }
        }
        
        /// mark as read if on screen
        MessageStorage.markAsReadIfVisible(message: message, account: account)
    }
}

// MARK: - Extensions

extension MessageStorage: XMPPCapabilitiesDelegate {
    public func xmppCapabilities(_ sender: XMPPCapabilities, didDiscoverCapabilities caps: XMLElement, for jid: XMPPJID) {
        
    }
}

extension MessageStorage: XMPPStreamDelegate {
    public func xmppStreamDidAuthenticate(_ sender: XMPPStream) {
        DispatchQueue.main.async {
            if Application.shared.applicationState != .background {
                self.performBlock(async: true) {
                    self.mamCatchupInProgress = false
                    self.connection.asyncRead { (transaction) in
                        guard let account = self.account(with: transaction) else { return }
                        // if we've never fetched MAM before, try to fetch the last week
                        // otherwise fetch since the last time we fetched
                        var dateToFetch = account.lastHistoryFetchDate
                        if dateToFetch == nil {
                            let currentDate = Date()
                            var dateComponents = DateComponents()
                            dateComponents.day = -7
                            let lastWeek = Calendar.current.date(byAdding: dateComponents, to: currentDate)!
                            dateToFetch = lastWeek
                        }
                        self.performBlock {
                            self.mamCatchupInProgress = true
                        }
                        self.archiving.fetchHistory(archiveJID: nil, userJID: nil, since: dateToFetch)
                    }
                }
            }
        }
    }
    
    public func xmppStream(_ sender: XMPPStream, didReceive message: XMPPMessage) {
        // We don't handle incoming group chat messages here
        // Check out OTRXMPPRoomYapStorage instead
        guard !message.containsGroupChatElements,
            // We handle carbons elsewhere via XMPPMessageCarbonsDelegate
            !message.isMessageCarbon,
            // We handle MAM elsewhere as well
            message.mamResult == nil,
            // OMEMO messages cannot be processed here
            !message.omemo_hasEncryptedElement(.conversationsLegacy),
            // Call info cannot be processed here
            !message.containsCallElements,
            let accountId = sender.accountId else {
            return
        }
        
        // plain text location
        guard var messageString = message.body,
            messageString.count > 0 else {
                handleDirectMessage(message, body: nil, original: nil, accountId: accountId)
                return
        }
        let messageCopy = message.body
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
                    size: CGSize(width: 375, height: 667))
                let snapshot = Snapshot(
                    options: options,
                    accessToken: defaultAccessToken)
                
                let imageURL = snapshot.url.absoluteString
                if imageURL.range(of:"https") != nil {
                    messageString = imageURL.replacingOccurrences(of: "https", with: "aesgcm")
                }
            }
            handleDirectMessage(message, body: messageString, original: messageCopy, accountId: accountId)
        } else {
            handleDirectMessage(message, body: nil, original: nil, accountId: accountId)
        }        
    }
}

extension MessageStorage: XMPPMessageCarbonsDelegate {

    public func xmppMessageCarbons(_ xmppMessageCarbons: XMPPMessageCarbons, didReceive message: XMPPMessage, outgoing isOutgoing: Bool) {
        guard let accountId = xmppMessageCarbons.xmppStream?.accountId,
        !message.omemo_hasEncryptedElement(.conversationsLegacy) else {
            return
        }
        var _forJID: XMPPJID? = nil
        if !isOutgoing {
            _forJID = message.from
        } else {
            _forJID = message.to
        }
        guard let forJID = _forJID else { return }
        handleForwardedMessage(message, forJID: forJID, body: nil, original: nil, accountId: accountId, delayed: nil, isIncoming: !isOutgoing, isOutgoingFromOtherDevice: false)
    }
}

extension MessageStorage: XMPPMessageArchiveManagementDelegate {
    public func xmppMessageArchiveManagement(_ xmppMessageArchiveManagement: XMPPMessageArchiveManagement, didFinishReceivingMessagesWith resultSet: XMPPResultSet) {
        mamCatchupInProgress = false
        connection.asyncReadWrite { (transaction) in
            guard let accountId = xmppMessageArchiveManagement.xmppStream?.accountId,
                let account = OTRXMPPAccount.fetchObject(withUniqueID: accountId, transaction: transaction)?.copyAsSelf() else {
                    return
            }
            account.lastHistoryFetchDate = Date()
            account.save(with: transaction)
        }
    }
    
    public func xmppMessageArchiveManagement(_ xmppMessageArchiveManagement: XMPPMessageArchiveManagement, didFailToReceiveMessages error: XMPPIQ) {
        DDLogError("Failed to receive messages \(error)")
    }
    
    public func xmppMessageArchiveManagement(_ xmppMessageArchiveManagement: XMPPMessageArchiveManagement, didReceiveMAMMessage message: XMPPMessage) {
        guard let accountId = xmppMessageArchiveManagement.xmppStream?.accountId,
            let myJID = xmppMessageArchiveManagement.xmppStream?.myJID,
            let result = message.mamResult,
            let forwarded = result.forwardedMessage,
            let from = forwarded.from,
            !forwarded.omemo_hasEncryptedElement(.conversationsLegacy) else {
                DDLogVerbose("Discarding incoming MAM message \(message)")
                return
        }
        let delayed = result.forwardedStanzaDelayedDeliveryDate
        let isIncoming = !from.isEqual(to: myJID, options: .bare)
        var _forJID: XMPPJID? = nil
        if isIncoming {
            _forJID = forwarded.from
        } else {
            _forJID = forwarded.to
        }
        guard let forJID = _forJID else { return }
        
        var isOutgoingFromOtherDevice = false
        if let origto = message.to {
            if (origto.bare == from.bare && origto.resource != from.resource) {
                isOutgoingFromOtherDevice = true
                if let messageString = message.body,
                    messageString.hasPrefix("geo:") {
                    handleForwardedMessage(forwarded, forJID: forJID, body: messageString, original: messageString, accountId: accountId, delayed: delayed, isIncoming: isIncoming, isOutgoingFromOtherDevice: isOutgoingFromOtherDevice)
                    return
                }
            }
        }
        
        handleForwardedMessage(forwarded, forJID: forJID, body: nil, original: nil, accountId: accountId, delayed: delayed, isIncoming: isIncoming, isOutgoingFromOtherDevice: isOutgoingFromOtherDevice)
    }
}

// MARK: - Private Extensions

extension XMPPMessage {
    /// We don't want any group chat stuff ending up in here, including invites
    var containsGroupChatElements: Bool {
        let message = self
        guard message.messageType != .groupchat,
        message.element(forName: "x", xmlns: XMPPMUCUserNamespace) == nil,
            message.element(forName: "x", xmlns: XMPPConferenceXmlns) == nil else {
                return true
        }
        return false
    }
    
    var containsCallElements: Bool {
        let message = self
        guard message.element(forName: "x", xmlns: "jabber:x:callupdate") == nil else {
            return true
        }
        return false
    }
}

extension OTRChatState {
    static func chatState(from fromState: XMPPMessage.ChatState?) -> OTRChatState {
        guard let from = fromState else {
            return .unknown
        }
        var chatState: OTRChatState = .unknown
        switch from {
        case .composing:
            chatState = .composing
        case .paused:
            chatState = .paused
        case .active:
            chatState = .active
        case .inactive:
            chatState = .inactive
        case .gone:
            chatState = .gone
        }
        return chatState
    }
}

extension String {
    /// https://otr.cypherpunks.ca/Protocol-v3-4.0.0.html
    static let OTRWhitespaceStart = String(bytes: [0x20,0x09,0x20,0x20,0x09,0x09,0x09,0x09,0x20,0x09,0x20,0x09,0x20,0x09,0x20,0x20], encoding: .utf8)!
    
    /// for separately handling OTR messages
    var isOtrText: Bool {
        return self.contains("?OTR") || self.contains(String.OTRWhitespaceStart)
    }
}

extension OTRBaseMessage {
    @objc public static func message(forMessageId messageId: String, incoming: Bool, transaction: YapDatabaseReadTransaction) -> OTRMessageProtocol? {
        var deliveredMessage: OTRMessageProtocol?
        transaction.enumerateMessages(elementId: messageId, originId: nil, stanzaId: nil) { (message, stop) in
            if message.isMessageIncoming == incoming {
                deliveredMessage = message
                stop = true
            }
        }
        return deliveredMessage
    }

    @objc public static func message(forMessageId messageId: String, transaction: YapDatabaseReadTransaction) -> OTRMessageProtocol? {
        if self is OTRIncomingMessage.Type {
            return self.message(forMessageId: messageId, incoming: true, transaction: transaction)
        } else {
            return self.message(forMessageId: messageId, incoming: false, transaction: transaction)
        }
    }
    
    /// You can override message body, for example if this is an encrypted message
    convenience init(xmppMessage: XMPPMessage, body: String?, account: OTRXMPPAccount, buddy: OTRXMPPBuddy, capabilities: XMPPCapabilities) {
        self.init()
        self.messageText = body ?? xmppMessage.body
        self.buddyUniqueId = buddy.uniqueId
        if let delayed = xmppMessage.delayedDeliveryDate {
            self.messageDate = delayed
        } else {
            self.messageDate = Date()
        }
        if let elementId = xmppMessage.elementID {
            self.messageId = elementId
        }
        
        // Extract XEP-0359 stanza-id
        self.originId = xmppMessage.originId
        self.stanzaId = xmppMessage.extractStanzaId(account: account, capabilities: capabilities)
    }
}

extension NSCopying {
    /// Creates a deep copy of the object
    func copyAsSelf() -> Self? {
        return self.copy() as? Self
    }
}

public extension MessageStorage {
    
    @objc static func markAsReadIfVisible(message: OTRMessageProtocol, account: OTRXMPPAccount) {
        guard message.isMessageRead == false,
            let connection = OTRDatabaseManager.shared.writeConnection else {
            return
        }
        OTRAppDelegate.visibleThread({ (ck) in
            guard let key = ck?.key,
            let collection = ck?.collection,
            key == message.threadId,
            collection == message.threadCollection else {
                    return
            }
            connection.asyncReadWrite({ (transaction) in
                if message.isMessageRead == false, let message = message.copyAsSelf() {
                    if let incoming = message as? OTRIncomingMessage {
                        incoming.read = true
                        
                        if message.isMarkable == true, let xmpp = OTRProtocolManager.shared.protocol(for: account) as? XMPPManager {
                            xmpp.sendReadReceipt(message)
                        }
                    } else if let roomMessage = message as? OTRXMPPRoomMessage {
                        roomMessage.read = true
                        if message.isMarkable == true, let xmpp = OTRProtocolManager.shared.protocol(for: account) as? XMPPManager {
                            xmpp.sendReadReceipt(message)
                        }
                    }
                    message.save(with: transaction)
                }
            })
        })
    }
}

