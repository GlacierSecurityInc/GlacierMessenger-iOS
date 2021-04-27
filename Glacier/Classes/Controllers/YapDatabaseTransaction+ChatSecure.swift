//
//  YapDatabaseReadTransaction+ChatSecure.swift
//  ChatSecure
//
//  Created by David Chiles on 10/27/15.
//  Copyright © 2015 Chris Ballinger. All rights reserved.
//

import Foundation
import YapDatabase
import CocoaLumberjack

extension YapDatabaseConnection {
    /// synchronously fetch object an object.
    public func fetch<T>(_ block: @escaping (YapDatabaseReadTransaction) -> T?) -> T? {
        var result: T?
        read { (transaction) in
            result = block(transaction)
        }
        return result
    }
    
    /// synchronously fetch object an object.
    @objc public func fetch(_ block: @escaping (YapDatabaseReadTransaction) -> Any?) -> Any? {
        return fetch(block)
    }
}

extension YapDatabaseReadWriteTransaction {
    @objc public func setMessageError(elementId:String?, originId: String?, stanzaId:String?, error: Error) {
        enumerateMessages(elementId: elementId, originId: originId, stanzaId: stanzaId) { (message, stop) in
            if let databaseMessage = message as? OTRBaseMessage {
                databaseMessage.error = error
                databaseMessage.save(with: self)
            }
        }
    }
}

extension YapDatabaseReadTransaction {
    
    /// elementId is the XMPP elementId, originId and stanzaId are from XEP-0359
    public func enumerateMessages(elementId:String?, originId: String?, stanzaId:String?, block:@escaping (_ message:OTRMessageProtocol,_ stop: inout Bool) -> Void) {
        guard let secondaryIndexTransaction = self.ext(SecondaryIndexName.messages) as? YapDatabaseSecondaryIndexTransaction else {
            return
        }
        
        var parameters: [String] = []
        var queryString = ""
        let addQuery: ((_ column: String, _ value: String?) -> Void) = { (column, value) in
            guard let value = value else { return }
            var stringStart = "WHERE"
            if parameters.count > 0 {
                stringStart = " OR"
            }
            queryString += "\(stringStart) \(column) = ?"
            parameters.append(value)
        }
        addQuery(MessageIndexColumnName.remoteMessageId, elementId)
        addQuery(MessageIndexColumnName.originId, originId)
        addQuery(MessageIndexColumnName.stanzaId, stanzaId)
        guard parameters.count > 0, queryString.count > 0 else {
            return
        }
        let query = YapDatabaseQuery(string: queryString, parameters: parameters)
        
        let _ = secondaryIndexTransaction.iterateKeys(matching: query) { (collection, key, stop) -> Void in
            if let message = self.object(forKey: key, inCollection: collection) as? OTRMessageProtocol {
                block(message, &stop)
            }
        }
    }
    
    public func enumerateSessions(accountKey:String, signalAddressName:String, block:@escaping (_ session:OTRSignalSession,_ stop: inout Bool) -> Void) {
        guard let secondaryIndexTransaction = self.ext(SecondaryIndexName.signal) as? YapDatabaseSecondaryIndexTransaction else {
            return
        }
        let queryString = "Where \(SignalIndexColumnName.session) = ?"
        let query = YapDatabaseQuery(string: queryString, parameters: [OTRSignalSession.sessionKey(accountKey: accountKey, name: signalAddressName)])
        let _ = secondaryIndexTransaction.iterateKeys(matching: query) { (collection, key, stop) -> Void in
            if let session = self.object(forKey: key, inCollection: collection) as? OTRSignalSession {
                block(session, &stop)
            }
        }
    }
    
    /** The jid here is the full jid not real jid or nickname */
//    @objc public func enumerateRoomOccupants(jid:String, block:@escaping (_ occupant:OTRXMPPRoomOccupant, _ stop:UnsafeMutablePointer<ObjCBool>) -> Void) {
//        guard let secondaryIndexTransaction = self.ext(SecondaryIndexName.signal) as? YapDatabaseSecondaryIndexTransaction else {
//            return
//        }
//
//        let queryString = "Where \(RoomOccupantIndexColumnName.jid) = ?"
//        let query = YapDatabaseQuery(string: queryString, parameters: [jid])
//
//        secondaryIndexTransaction.enumerateKeys(matching: query) { (collection, key, stop) -> Void in
//            if let occupant = self.object(forKey: key, inCollection: collection) as? OTRXMPPRoomOccupant {
//                block(occupant, stop)
//            }
//        }
//    }
    
    @objc public func numberOfUnreadMessages() -> UInt {
        guard let secondaryIndexTransaction = self.ext(SecondaryIndexName.messages) as? YapDatabaseSecondaryIndexTransaction else {
            return 0
        }
        
        let queryString = "Where \(MessageIndexColumnName.isMessageRead) == 0"
        let query = YapDatabaseQuery(string: queryString, parameters: [])
        
        return secondaryIndexTransaction.numberOfRows(matching: query) ?? 0
    }
    
    
    
    @objc public func allUnreadMessagesForThread(_ thread:OTRThreadOwner) -> [OTRMessageProtocol] {
        guard let indexTransaction = self.ext(SecondaryIndexName.messages) as? YapDatabaseSecondaryIndexTransaction else {
            return []
        }
        let queryString = "Where \(MessageIndexColumnName.threadId) == ? AND \(MessageIndexColumnName.isMessageRead) == 0"
        let query = YapDatabaseQuery(string: queryString, parameters: [thread.threadIdentifier])
        var result = [OTRMessageProtocol]()
        let success = indexTransaction.iterateKeysAndObjects(matching: query) { (collection, key, object, stop) in
            if let message = object as? OTRMessageProtocol {
                result.append(message)
            }
        }
        
        if (!success) {
            DDLogError("Query error for OTRXMPPRoom numberOfUnreadMessagesWithTransaction")
        }
        
        return result
    }
}

extension YapDatabaseReadTransaction {
    
    public func enumerateUnreadMessages(_ block:@escaping (_ message:OTRMessageProtocol,_ stop: inout Bool) -> Void) {
        guard let secondaryIndexTransaction = self.ext(SecondaryIndexName.messages) as? YapDatabaseSecondaryIndexTransaction else {
            return
        }
        let queryString = "Where \(MessageIndexColumnName.isMessageRead) == 0"
        let query = YapDatabaseQuery(string: queryString, parameters: [])
        let _ = secondaryIndexTransaction.iterateKeysAndObjects(matching: query) { (key, collection, object, stop) in
            if let message = object as? OTRMessageProtocol {
                block(message, &stop)
            } else {
                DDLogError("Non-message object in messages index \(String(describing: object))")
            }
        }
    }
}
#if !TARGET_IS_NOTIFICATION
extension YapDatabaseReadTransaction {
    
    public func unfinishedDownloads() -> [OTRMediaItem] {
        /// https://github.com/ChatSecure/ChatSecure-iOS/issues/1034
        return []
//        guard let secondaryIndexTransaction = self.ext(SecondaryIndexName.mediaItems) as? YapDatabaseSecondaryIndexTransaction else {
//            return []
//        }
//        var unfinished: [OTRMediaItem] = []
//        let queryString = "Where \(MediaItemIndexColumnName.transferProgress) < 1 AND \(MediaItemIndexColumnName.isIncoming) == 1"
//        let query = YapDatabaseQuery(string: queryString, parameters: [])
//        secondaryIndexTransaction.enumerateKeysAndObjects(matching: query) { (key, collection, object, stop) in
//            if let download = object as? OTRMediaItem {
//                unfinished.append(download)
//            } else {
//                DDLogError("Non-media item object in downloads index \(object)")
//            }
//        }
//        return unfinished
    }
    
    public func enumerateUnfinishedDownloads(_ block:@escaping (_ message:OTRMediaItem,_ stop: inout Bool) -> Void) {
        guard let secondaryIndexTransaction = self.ext(SecondaryIndexName.mediaItems) as? YapDatabaseSecondaryIndexTransaction else {
            return
        }
        let queryString = "Where \(MediaItemIndexColumnName.transferProgress) < 1 AND \(MediaItemIndexColumnName.isIncoming) == 1"
        let query = YapDatabaseQuery(string: queryString, parameters: [])
        let _ = secondaryIndexTransaction.iterateKeysAndObjects(matching: query) { (key, collection, object, stop) in
            if let download = object as? OTRMediaItem {
                block(download, &stop)
            } else {
                DDLogError("Non-media item object in downloads index \(String(describing: object))")
            }
        }
    }
}
#endif
