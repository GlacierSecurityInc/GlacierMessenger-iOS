//
//  RosterStorage.swift
//  ChatSecureCore
//
//  Created by N-Pex on 2018-01-21.
//  Copyright © 2018 Chris Ballinger. All rights reserved.
//

import Foundation
import XMPPFramework
import YapDatabase

@objc public class RosterStorage: NSObject {
    
    // MARK: Properties
    
    let readConnection: YapDatabaseConnection
    let writeConnection: YapDatabaseConnection
    
    var rosterSet: Set<OTRXMPPBuddy>
    
    // MARK: Init
    
    @objc public init(readConnection: YapDatabaseConnection,
                writeConnection: YapDatabaseConnection) {
        self.readConnection = readConnection
        self.writeConnection = writeConnection
        self.rosterSet = Set<OTRXMPPBuddy>()
    }
    
    // MARK: Private
    
    /// updates the subscription status
    /// sends out presence updates
    /// saves buddy and sends out a nasty NSNotification
    private func updateSubscription(buddy: OTRXMPPBuddy,
                                    presence: XMPPPresence,
                                    stream: XMPPStream) {
        guard let type = presence.presenceType,
            let jid = buddy.bareJID else {
            return
        }
        switch type {
        case .subscribed:
            writeConnection.asyncReadWrite({ (transaction) in
                let buddy = buddy.refetch(with: transaction)?.copyAsSelf()
                buddy?.pendingApproval = false
                buddy?.save(with: transaction)
            }, completionBlock: {
                NotificationCenter.default.post(name: NSNotification.Name.OTRBuddyPendingApprovalDidChange, object: self, userInfo: ["buddy": buddy])
            })
            let presence = XMPPPresence(type: .subscribe, to: jid)
            stream.send(presence)
            stream.resendMyPresence()
        case .unsubscribed:
            buddy.pendingApproval = false
            writeConnection.asyncReadWrite { (transaction) in
                let buddy = buddy.refetch(with: transaction)?.copyAsSelf()
                buddy?.pendingApproval = false
                buddy?.save(with: transaction)
            }
            let presence = XMPPPresence(type: .unsubscribe, to: jid)
            stream.send(presence)
        default:
            break
        }
    }
    
    private func updateLastSeen(buddy: OTRXMPPBuddy,
                                presence: XMPPPresence,
                                status: OTRThreadStatus) {
        var lastSeen: Date?
        let delayedDeliveryDate = presence.delayedDeliveryDate
        let idleDate = presence.idleSince
        if status == .available {
            lastSeen = Date()
        } else if idleDate != nil {
            lastSeen = idleDate
        } else if delayedDeliveryDate != nil {
            lastSeen = delayedDeliveryDate
        }
        if lastSeen != nil {
            OTRBuddyCache.shared.setLastSeenDate(lastSeen, for: buddy)
        }
    }
}

// MARK: XMPPRosterStorage

extension RosterStorage: XMPPRosterStorage {
    public func configure(withParent aParent: XMPPRoster, queue: DispatchQueue) -> Bool {
        return true
    }
    
    public func beginRosterPopulation(for stream: XMPPStream, withVersion version: String) {
        
    }
    
    public func endRosterPopulation(for stream: XMPPStream) {
        // compare list and remove any that shouldn't be there
        guard let accountId = stream.accountId else {
            return
        }
        
        if (self.rosterSet.count == 0) {
            return
        }
        
        let budjids = self.jids(for: stream)
        var kickList = Set<XMPPJID>()
        for budjid in budjids {
            var found = false
            for item in self.rosterSet {
                if let barejid = item.bareJID {
                    if (barejid.isEqual(to: budjid)) {
                        found = true
                    }
                }
            }
                    
            if (!found) {
                kickList.insert(budjid)
            }
        }
        
        var roomMgr:OTRXMPPRoomManager?
        for kicked in kickList {
            self.writeConnection.asyncReadWrite ({ (transaction) in
                if let buddy = OTRXMPPBuddy.fetchBuddy(jid: kicked, accountUniqueId: accountId, transaction: transaction) {
                    if let account = buddy.account(with: transaction), let xmpp = OTRProtocolManager.shared.protocol(for: account) as? XMPPManager {
                        roomMgr = xmpp.roomManager
                    }
                    
                    buddy.remove(with: transaction)
                }
            }, completionQueue: DispatchQueue.global(), completionBlock: {
                if let roomManager = roomMgr {
                    //This doesn't work yet because the server holds onto
                    // group affiliations even after user is removed
                    // So when we enter group details it queries the server
                    // and repopulates this
                    //roomManager.clearOccupantRole(with: kicked)
                }
            })
        }
        
        self.rosterSet.removeAll()
    }
    
    public func handleRosterItem(_ item: XMLElement, xmppStream stream: XMPPStream) {
        
    }
    
    public func handle(_ presence: XMPPPresence, xmppStream stream: XMPPStream) {
        guard let accountId = stream.accountId,
            let fromJID = presence.from,
            presence.isErrorPresence == false else {
            DDLogError("Ignoring presence \(presence)")
            return
        }
        var _buddy: OTRXMPPBuddy?
        readConnection.read { (transaction) in
            _buddy = OTRXMPPBuddy.fetchBuddy(jid: fromJID, accountUniqueId: accountId, transaction: transaction)
        }
        guard let buddy = _buddy else {
            return
        }
        let status = OTRThreadStatus(presence: presence)
        let resource = presence.from?.resource
        
        if (presence.type == "unavailable") {
            OTRBuddyCache.shared.setThreadStatus(OTRThreadStatus.offline, for: buddy, resource: resource)
            OTRBuddyCache.shared.setStatusMessage(OFFLINE_STRING(), for: buddy)
            OTRBuddyCache.shared.setChatState(OTRChatState.gone, for: buddy)
        } else {
            OTRBuddyCache.shared.setThreadStatus(status, for: buddy, resource: resource)
            OTRBuddyCache.shared.setStatusMessage(presence.status, for: buddy)
        }
        
        updateSubscription(buddy: buddy, presence: presence, stream: stream)
        updateLastSeen(buddy: buddy, presence: presence, status: status)
    }
    
    public func userExists(with jid: XMPPJID, xmppStream stream: XMPPStream) -> Bool {
        guard let accountId = stream.accountId else {
            return false
        }
        var result = false
        readConnection.read { (transaction) in
            if let buddy = OTRXMPPBuddy.fetchBuddy(jid: jid, accountUniqueId: accountId, transaction: transaction),
                buddy.trustLevel == .roster {
                result = true
            }
        }
        return result
    }
    
    public func clearAllResources(for stream: XMPPStream) {
        
    }
    
    public func clearAllUsersAndResources(for stream: XMPPStream) {
        
    }
    
    public func jids(for stream: XMPPStream) -> [XMPPJID] {
        guard let accountId = stream.accountId else {
            return []
        }
        var jids: [XMPPJID] = []
        readConnection.read { (transaction) in
            jids = OTRXMPPAccount.allBuddies(accountId: accountId, transaction: transaction)
            .filter {
                $0.trustLevel == .roster
            }
            .compactMap {
                $0.bareJID
            }
        }
        return jids
    }
    
    public func getSubscription(_ subscription: AutoreleasingUnsafeMutablePointer<NSString?>?, ask: AutoreleasingUnsafeMutablePointer<NSString?>?, nickname: AutoreleasingUnsafeMutablePointer<NSString?>?, groups: AutoreleasingUnsafeMutablePointer<NSArray?>?, for jid: XMPPJID, xmppStream stream: XMPPStream) {
        
    }
    
    
}

// MARK: XMPPRosterDelegate

extension RosterStorage: XMPPRosterDelegate {
    
    public func xmppRoster(_ sender: XMPPRoster, didReceiveRosterItem item: XMLElement) {
        
        guard let jidStr = item.attributeStringValue(forName: "jid"),
            let jid = XMPPJID(string: jidStr),
            let subscription = item.attributeStringValue(forName: "subscription"),
            let accountId = sender.accountId,
            let stream = sender.xmppStream
            else { return }
        
        if(jidStr == stream.myJID?.bare)
        {
            // ignore self buddy
            return;
        }
        
        let ask = item.attributeStringValue(forName: "ask")

        self.writeConnection.asyncReadWrite { (transaction) in
            var buddy = OTRXMPPBuddy.fetchBuddy(jid: jid, accountUniqueId: accountId, transaction: transaction)
            if subscription == "remove" {
                if let buddy = buddy {
                    buddy.remove(with: transaction)
                }
            } else {
                if buddy == nil {
                    buddy = OTRXMPPBuddy()
                    buddy?.accountUniqueId = accountId
                    
                    // We can be called with buddies that are not really on our roster, i.e.
                    // they are in state none + pendingIn, so default to BuddyTrustLevelUntrusted and set to BuddyTrustLevelRoster only when we are subscribed to them.
                    buddy?.trustLevel = .untrusted;
                    buddy?.displayName = jid.user ?? jidStr
                    buddy?.username = jid.bare
                } else {
                    buddy = buddy?.copyAsSelf()
                }
                guard let buddy = buddy else { return }
                buddy.subscription = SubscriptionAttribute(stringValue: subscription)
                buddy.pending.setPendingOut(pending: (ask == "subscribe"))
                if buddy.subscribedFrom {
                    buddy.pending.setPendingIn(pending: false)
                }
                if buddy.subscribedTo || buddy.subscribedFrom {
                    buddy.trustLevel = .roster
                }
                
                // Update name
                if let name = item.attributeStringValue(forName: "name"), name.count > 0 {
                    buddy.displayName = name
                }
                
                buddy.save(with: transaction)
                
                self.rosterSet.insert(buddy) 
            }
        }
    }
}


extension OTRThreadStatus {
    
    init(presence: XMPPPresence) {
        self = OTRThreadStatus.from(presence: presence)
    }
    
    static func from(presence: XMPPPresence) -> OTRThreadStatus {
        if presence.presenceType == .unavailable {
            return .offline
        }
        switch presence.showValue {
        case .DND:
            return .doNotDisturb
        case .XA:
            return .extendedAway
        case .away:
            return .away
        case .other,
             .chat:
            return .available
        }
    }
}
