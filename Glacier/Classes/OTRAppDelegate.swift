//
//  OTRAppDelegate.swift
//  ChatSecureCore
//
//  Created by Chris Ballinger on 12/5/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

import Foundation
import YapDatabase
import UserNotifications
import CocoaLumberjack
import PushKit
import MBProgressHUD

public extension OTRAppDelegate {
    /// gets the last user interaction date, or current date if app is activate
    @objc static func getLastInteractionDate(_ block: @escaping (_ lastInteractionDate: Date?)->(), completionQueue: DispatchQueue? = nil) {
        DispatchQueue.main.async {
            var date: Date? = nil
            if Application.shared.applicationState == .active {
                date = Date()
            } else {
                date = self.lastInteractionDate
            }
            if let completionQueue = completionQueue {
                completionQueue.async {
                    block(date)
                }
            } else {
                block(date)
            }
        }
    }
    
    @objc static func setLastInteractionDate(_ date: Date) {
        DispatchQueue.main.async {
            self.lastInteractionDate = date
        }
    }

    /// @warn only access this from main queue
    private static var lastInteractionDate: Date? = nil
}

public extension OTRAppDelegate {
    
    /// Returns key/collection of visible thread, or nil if not visible or unset
    @objc static func visibleThread(_ block: @escaping (_ thread: YapCollectionKey?)->(), completionQueue: DispatchQueue? = nil) {
        DispatchQueue.main.async {
            let messagesVC = OTRAppDelegate.appDelegate.messagesViewController
            guard messagesVC.isViewLoaded,
                messagesVC.view.window != nil,
                let key = messagesVC.threadKey,
                let collection = messagesVC.threadCollection else {
                block(nil)
                return
            }
            let ck = YapCollectionKey(collection: collection, key: key)
            if let completionQueue = completionQueue {
                completionQueue.async {
                    block(ck)
                }
            } else {
                block(ck)
            }
        }
    }
    
    /// Temporary hack to fix corrupted development database. Empty incoming MAM messages were stored as unread
    @objc func fixUnreadMessageCount(_ completion: ((_ unread: UInt) -> Void)?) {
        OTRDatabaseManager.shared.writeConnection?.asyncReadWrite({ (transaction) in
            var messagesToRemove: [OTRIncomingMessage] = []
            var messagesToMarkAsRead: [OTRIncomingMessage] = []
            transaction.enumerateUnreadMessages({ (message, stop) in
                guard let incoming = message as? OTRIncomingMessage else {
                    return
                }
                if let buddy = incoming.buddy(with: transaction),
                    let _ = buddy.account(with: transaction),
                    incoming.messageText == nil {
                    messagesToMarkAsRead.append(incoming)
                } else {
                    messagesToRemove.append(incoming)
                }
            })
            messagesToRemove.forEach({ (message) in
                DDLogInfo("Deleting orphaned message: \(message)")
                message.remove(with: transaction)
            })
            messagesToMarkAsRead.forEach({ (message) in
                DDLogInfo("Marking message with no text as read \(message)")
                if let message = message.copyAsSelf() {
                    message.read = true
                    message.save(with: transaction)
                }
            })
        }, completionBlock: {
            var unread: UInt = 0
            OTRDatabaseManager.shared.writeConnection?.asyncRead({ (transaction) in
                unread = transaction.numberOfUnreadMessages()
            }, completionBlock: {
                completion?(unread)
            })
        })
    }
    
    @objc func markAllRead() {
        let conversationsVC = OTRAppDelegate.appDelegate.conversationViewController
        let hud = MBProgressHUD.showAdded(to: conversationsVC.view, animated: true)
        
        OTRDatabaseManager.shared.writeConnection?.asyncReadWrite({ (transaction) in
            var singleMessagesToMarkAsRead: [OTRIncomingMessage] = []
            var roomMessagesToMarkAsRead: [OTRXMPPRoomMessage] = []
            transaction.enumerateUnreadMessages({ (message, stop) in
                if let incomingSingle = message as? OTRIncomingMessage {
                    singleMessagesToMarkAsRead.append(incomingSingle)
                } else if let incomingRoom = message as? OTRXMPPRoomMessage {
                    roomMessagesToMarkAsRead.append(incomingRoom)
                }
            })
            var singleConversationsForReadReceipts = [String: OTRIncomingMessage]()
            var roomConversationsForReadReceipts = [String: OTRXMPPRoomMessage]()
            
            singleMessagesToMarkAsRead.forEach({ (message) in
                if let message = message.copyAsSelf() {
                    message.read = true
                    message.save(with: transaction)
                    // maybe only send once...if toBeSaved has objects
                    if (message.isMarkable) {
                        singleConversationsForReadReceipts[message.buddyUniqueId] = message
                    }
                }
            })
            roomMessagesToMarkAsRead.forEach({ (message) in
                if let message = message.copyAsSelf() {
                    message.read = true
                    message.save(with: transaction)
                    if let roomjid = message.roomJID, message.isMarkable == true {
                        roomConversationsForReadReceipts[roomjid] = message
                    }
                }
            })
            
            if let account = OTRAccount.allAccounts(with: transaction).first, let xmpp = OTRProtocolManager.shared.protocol(for: account) as? XMPPManager {
                for message in singleConversationsForReadReceipts.values {
                    xmpp.sendReadReceipt(message)
                }
                for message in roomConversationsForReadReceipts.values {
                    xmpp.sendReadReceipt(message)
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NotificationCenter.default.post(name: Notification.Name(rawValue: "ReloadDataNotificationName"), object: self, userInfo:nil)
                
                hud.hide(animated: true)
                hud.removeFromSuperview()
            }
        })
    }
    
    @objc func enterThread(key: String, collection: String) {
        var thread: OTRThreadOwner?
        OTRDatabaseManager.shared.uiConnection?.read({ (transaction) in
            thread = transaction.object(forKey: key, inCollection: collection) as? OTRThreadOwner
        })
        if let thread = thread {
            self.splitViewCoordinator.enterConversationWithThread(thread, sender: self)
        }
    }
    
    
}

// MARK: - UNUserNotificationCenterDelegate
extension OTRAppDelegate: UNUserNotificationCenterDelegate {
    
    private func extractNotificationType(notification: UNNotification) -> NotificationType? {
        let userInfo = notification.request.content.userInfo
        if let rawNotificationType = userInfo[kOTRNotificationType] as? String {
            return NotificationType(rawValue: rawNotificationType)
        } else {
            return nil
        }
    }

    private func extractThreadInformation(notification: UNNotification) -> (key: String, collection: String)? {
        let userInfo = notification.request.content.userInfo
        if let threadKey = userInfo[kOTRNotificationThreadKey] as? String,
            let threadCollection = userInfo[kOTRNotificationThreadCollection] as? String {
            return (threadKey, threadCollection)
        }
        return nil
    }
    
    private func extractAccountInformation(notification: UNNotification) -> OTRXMPPAccount? {
        let userInfo = notification.request.content.userInfo
        guard let accountKey = userInfo[kOTRNotificationAccountKey] as? String else {
            return nil
        }
        var account: OTRXMPPAccount?
        OTRDatabaseManager.shared.uiConnection?.read({ (transaction) in
            account = OTRXMPPAccount.fetchObject(withUniqueID: accountKey, transaction: transaction)
        })
        return account
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard let notificationType = extractNotificationType(notification: response.notification) else {
            completionHandler()
            return
        }
        
        switch notificationType {
        case .subscriptionRequest:
            splitViewCoordinator.showConversationsViewController()
        case .connectionError:
            break
        case .chatMessage, .approvedBuddy:
            if let threadInfo = extractThreadInformation(notification: response.notification) {
                enterThread(key: threadInfo.key, collection: threadInfo.collection)
            }
        }
        
        completionHandler()
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        guard let notificationType = extractNotificationType(notification: notification) else {
            // unknown notification type, so let's show one just in case?
            completionHandler([.badge, .sound, .alert])
            return
        }
        
        switch notificationType {
        case .subscriptionRequest:
            completionHandler([.badge, .sound, .alert])
        case .approvedBuddy:
            completionHandler([.badge, .sound, .alert])
        case .connectionError:
            completionHandler([.badge, .sound, .alert])
        case .chatMessage:
            if !self.doubleDone {
                return;
            }
            
            // Show chat notification while user is using the app, if they aren't already looking at it
            if let (key, _) = extractThreadInformation(notification: notification) {
                OTRAppDelegate.visibleThread({ (ck) in
                    if key == ck?.key {
                        completionHandler([])
                    } else {
                        completionHandler([.badge, .sound, .alert])
                    } 
                })
            }
        }
    }
}

extension OTRAppDelegate: PKPushRegistryDelegate {
    public func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        if type == .voIP {
            self.handleVoipPushToken(pushCredentials.token)
        }
    }
    
    @objc public func handleVoipPushToken(_ token: Data) {
        let tokString = token.hexString()
        OTRProtocolManager.pushController.setVoipToken(tokString);
    }
    
    open func pushRegistry(_ registry: PKPushRegistry,
                              didReceiveIncomingPushWith payload: PKPushPayload,
                              for type: PKPushType,
                              completion: @escaping () -> Void) {
        if type == .voIP {
            
            //if UIApplication.shared.applicationState == .background {
            if UIApplication.shared.applicationState != .active {
                self.checkConnectionOrTryLogin()
            }
            
            let userInfo = payload.dictionaryPayload
            if let caller = userInfo[kNotificationCallerKey] as? String, let callId = userInfo[kNotificationCallIdKey] as? NSNumber {
                CallManager.sharedCallManager().reportIncomingCall(uuid: UUID(), callId: callId, caller: caller) { _ in
                    // Always call the completion handler when done.
                    completion()
                }
            }
        }
    }
}
