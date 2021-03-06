//
//  UITableView+ChatSecure.m
//  ChatSecure
//
//  Created by Chris Ballinger on 4/24/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

#import "UITableView+ChatSecure.h"
#import "OTRXMPPBuddy.h"
#import "Glacier-Swift.h"
#import "OTRXMPPManager_Private.h"
@import MBProgressHUD;

@implementation UITableView (ChatSecure)

NSString *const ReloadDataNotificationName = @"ReloadDataNotificationName";

/** Connection must be read-write */
+ (nullable NSArray<UITableViewRowAction *> *)editActionsForThread:(id<OTRThreadOwner>)thread deleteActionAlsoRemovesFromRoster:(BOOL)deleteActionAlsoRemovesFromRoster connection:(YapDatabaseConnection*)connection {
    NSParameterAssert(thread);
    NSParameterAssert(connection);
    if (!thread || !connection) {
        return nil;
    }
    
    // Bail out if it's a subscription request
    if ([thread isKindOfClass:[OTRXMPPBuddy class]] &&
        [(OTRXMPPBuddy*)thread askingForApproval]) {
        return nil;
    }

    NSString *archiveTitle = ARCHIVE_ACTION_STRING();
    if ([thread isArchived]) {
        archiveTitle = UNARCHIVE_ACTION_STRING();
    }
    
    UITableViewRowAction *archiveAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:archiveTitle handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
        [connection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            NSString *key = [thread threadIdentifier];
            NSString *collection = [thread threadCollection];
            id object = [transaction objectForKey:key inCollection:collection];
            if (![object conformsToProtocol:@protocol(OTRThreadOwner)]) {
                return;
            }
            id <OTRThreadOwner> thread = object;
            thread.isArchived = !thread.isArchived;
            [transaction setObject:thread forKey:key inCollection:collection];
        }];
    }];
    
    NSString *deleteTitle = DELETE_STRING();
    if ([thread isKindOfClass:[OTRXMPPRoom class]]) {
        deleteTitle = LEAVE_GROUP_STRING();
    }
    
    //__block UIView *view = self;
    UITableViewRowAction *deleteAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive title:deleteTitle handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
        
        [connection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [OTRBaseMessage deleteAllMessagesForBuddyId:[thread threadIdentifier] transaction:transaction];
        }];
        
        if ([thread isKindOfClass:[OTRXMPPRoom class]]) {
            MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:[OTRAppDelegate appDelegate].window animated:YES];
            
            OTRXMPPRoom *room = (OTRXMPPRoom*)thread;
            //Leave room
            NSString *accountKey = [thread threadAccountIdentifier];
            __block OTRAccount *account = nil;
            __block id<OTRMessageProtocol> message;
            [connection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
                account = [OTRAccount fetchObjectWithUniqueID:accountKey transaction:transaction];
                if (account) {
                    NSString *left = [account.displayName stringByAppendingString:@" left the group"];
                    message = [room outgoingMessageWithText:left transaction:transaction];
                }
            }];
            OTRXMPPManager *xmppManager = (OTRXMPPManager *)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
            
            XMPPRoom *xroom = [xmppManager.roomManager roomForJID:room.roomJID];
            XMPPJID *jid = [XMPPJID jidWithString:account.username];
            [xroom unsubscribeFromRoom:jid];
            
            [xmppManager.roomManager removeRoomsFromBookmarks:@[room]];
            
            if (message != nil) { [xmppManager enqueueMessage:message]; }
            // wrapped in dispatch to give time for enqueued message
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (room.roomJID) {
                    [xmppManager.roomManager leaveRoom:room.roomJID];
                }
                
                //Delete database items
                [connection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    [((OTRXMPPRoom *)thread) removeWithTransaction:transaction];
                }];
                
                // reload table view to get screen events working
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:ReloadDataNotificationName object:self userInfo:nil];
                    [hud removeFromSuperview];
                });
            });
        } else if ([thread isKindOfClass:[OTRBuddy class]] && deleteActionAlsoRemovesFromRoster) {
            OTRBuddy *dbBuddy = (OTRBuddy*)thread;
            OTRYapRemoveBuddyAction *action = [[OTRYapRemoveBuddyAction alloc] init];
            action.buddyKey = dbBuddy.uniqueId;
            action.buddyJid = dbBuddy.username;
            action.accountKey = dbBuddy.accountUniqueId;
            [connection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                [action saveWithTransaction:transaction];
                [dbBuddy removeWithTransaction:transaction];
            }];
        }
    }];
    
    return @[deleteAction, archiveAction];
}

@end
