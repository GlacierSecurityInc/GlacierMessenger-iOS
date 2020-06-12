//
//  OTRXMPPRoomManager.m
//  ChatSecure
//
//  Created by David Chiles on 10/9/15.
//  Copyright © 2015 Chris Ballinger. All rights reserved.
//

#import "OTRXMPPRoomManager.h"
@import XMPPFramework;
@import CocoaLumberjack;
#import <ChatSecureCore/ChatSecureCore-Swift.h>
#import "OTRBuddy.h"
#import "OTRBuddyCache.h"
@import YapDatabase;
#import "OTRLog.h"
#import "UITableView+ChatSecure.h"


@interface OTRXMPPRoomManager () <XMPPMUCDelegate, XMPPRoomDelegate, XMPPStreamDelegate, OTRYapViewHandlerDelegateProtocol>

@property (nonatomic, strong, readonly) NSMutableDictionary<XMPPJID*,XMPPRoom*> *rooms;

@property (nonatomic, strong, readonly) XMPPMUC *mucModule;

/** This dictionary has jid as the key and array of buddy unique Ids to invite once we've joined the room*/
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString*,NSArray<NSString *> *> *inviteDictionary;
@property (nonatomic, strong, readonly) NSString *inviteAuthor;

/** This dictionary is a temporary holding for setting a room subject. Once the room is created teh subject is set from this dictionary. */
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString*,NSString*> *tempRoomSubject;

/** This dictionary holds the desired public/private status of rooms to create. */
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString*,NSNumber*> *roomStatusDict;

/** This array is a temporary holding with rooms we should configure once connected */
@property (nonatomic, strong, readonly) NSMutableArray<NSString*> *roomsToConfigure;

@property (nonatomic) BOOL addedCapsDelegate;

@property (nonatomic) NSInteger highSeedNum;

@end

@implementation OTRXMPPRoomManager

-  (instancetype) initWithDatabaseConnection:(YapDatabaseConnection*)databaseConnection
                                roomStorage:(RoomStorage*)roomStorage
                                   archiving:(XMPPMessageArchiveManagement*)archiving
                               dispatchQueue:(nullable dispatch_queue_t)dispatchQueue {
    if (self = [super initWithDispatchQueue:dispatchQueue]) {
        _databaseConnection = databaseConnection;
        _roomStorage = roomStorage;
        _archiving = archiving;
        _mucModule = [[XMPPMUC alloc] init];
        _inviteDictionary = [[NSMutableDictionary alloc] init];
        _roomStatusDict = [[NSMutableDictionary alloc] init];
        _tempRoomSubject = [[NSMutableDictionary alloc] init];
        _roomsToConfigure = [[NSMutableArray alloc] init];
        _rooms = [[NSMutableDictionary alloc] init];
        _bookmarksModule = [[XMPPBookmarksModule alloc] initWithMode:XMPPBookmarksModePrivateXmlStorage dispatchQueue:nil];
    }
    self.addedCapsDelegate = NO;
    self.highSeedNum = -1;
    return self;
}

- (BOOL)activate:(XMPPStream *)aXmppStream
{
    BOOL result = [super activate:aXmppStream];
    [self.mucModule activate:aXmppStream];
    [self.mucModule addDelegate:self delegateQueue:moduleQueue];
    [multicastDelegate addDelegate:self delegateQueue:moduleQueue];
    
    [self.bookmarksModule activate:self.xmppStream];
    
    //Register view for sending message queue and occupants
    [self.databaseConnection.database asyncRegisterGroupOccupantsView:nil completionBlock:nil];
    
    return result;
}

- (void) deactivate {
    
    // clear rooms
    [self.rooms enumerateKeysAndObjectsUsingBlock:^(id jid, id room, BOOL* stop) {
        [self removeRoomForJID:jid];
        [room removeDelegate:self];
        [room deactivate];
    }];
    
    [self.mucModule removeDelegate:self];
    [self.mucModule deactivate];
    [self.bookmarksModule deactivate];
    
    [multicastDelegate removeDelegate:self];
    
    [super deactivate];
    
    _databaseConnection = nil;
    _roomStorage = nil;
    _archiving = nil;
    _mucModule = nil;
    _inviteDictionary = nil;
    _roomStatusDict = nil;
    _tempRoomSubject = nil;
    _roomsToConfigure = nil;
    _rooms = nil;
    _bookmarksModule = nil;
}

- (NSString *)joinRoom:(XMPPJID *)jid withNickname:(NSString *)name subject:(NSString *)subject password:(nullable NSString *)password
{
    return [self joinRoom:jid withNickname:name subject:subject password:password isPublic:NO];
}

- (NSString *)joinRoom:(XMPPJID *)jid withNickname:(NSString *)name subject:(NSString *)subject password:(nullable NSString *)password isPublic:(BOOL)ispublic
{
    dispatch_async(moduleQueue, ^{
        if ([subject length]) {
            [self.tempRoomSubject setObject:subject forKey:jid.bare];
        }
    });
    
    XMPPRoom *room = [self roomForJID:jid];
    NSString* accountId = self.xmppStream.tag;
    NSString *databaseRoomKey = [OTRXMPPRoom createUniqueId:accountId jid:jid.bare];
    __block NSString *nickname = name;

    // Already joined? Can happen if we have auto-join bookmarks.
    if (room && room.isJoined) {
        return databaseRoomKey;
    }
    
    if (!room) {
        room = [[XMPPRoom alloc] initWithRoomStorage:self.roomStorage jid:jid];
        [self setRoom:room forJID:room.roomJID];
        [room activate:self.xmppStream];
        [room addDelegate:self delegateQueue:moduleQueue];
    }
    
    /** Create room database object */
    __block id<OTRMessageProtocol> lastMessage = nil;
    [self.databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        OTRXMPPRoom *room = [[OTRXMPPRoom fetchObjectWithUniqueID:databaseRoomKey transaction:transaction] copy];
        if(!room) {
            room = [[OTRXMPPRoom alloc] init];
            room.lastRoomMessageId = @""; // Hack to make it show up in list
            room.accountUniqueId = accountId;
            room.roomJID = jid;
            if (ispublic) {
                room.isPublic = YES;
            }
            room.avatarSeedNum = [room nextAvatarNumWith:self.highSeedNum];
            
        } else {
            if (room.avatarSeedNum < 0) {
                room.avatarSeedNum = [room nextAvatarNumWith:self.highSeedNum];
            }
        }
        
        // query for disco#info to find public/private
        dispatch_async(moduleQueue, ^{
            @try {
                OTRXMPPAccount *account = [OTRXMPPAccount accountForStream:self.xmppStream transaction:transaction];
                OTRXMPPManager *xmppManager = [[OTRProtocolManager sharedInstance] xmppManagerForAccount:account];
                if (xmppManager != nil) {
                    if(!self.addedCapsDelegate) {
                        self.addedCapsDelegate = YES;
                        [xmppManager.serverCheck.xmppCapabilities addDelegate:self delegateQueue:moduleQueue];
                    }
                    [xmppManager.serverCheck.xmppCapabilities sendDiscoInfoQueryTo:jid withNode:nil ver:nil];
                }
            }
            @catch ( NSException *e ) {
                //
            }
        });
        
        //Other Room properties should be set here
        if ([subject length]) {
            room.subject = subject;
        }
        room.roomPassword = password;
        
        [room saveWithTransaction:transaction];
        
        if (!nickname) {
            OTRXMPPAccount *account = [OTRXMPPAccount fetchObjectWithUniqueID:accountId transaction:transaction];
            nickname = account.bareJID.user;
        }
        lastMessage = [room lastMessageWithTransaction:transaction];
    }];
    
    //Get history if any
    NSXMLElement *historyElement = nil;
    NSDate *lastMessageDate = [lastMessage messageDate];
    if (lastMessageDate) {
        //Use since as our history marker if we have a last message
        //http://xmpp.org/extensions/xep-0045.html#enter-managehistory
        NSString *dateTimeString = [lastMessageDate xmppDateTimeString];
        historyElement = [NSXMLElement elementWithName:@"history"];
        [historyElement addAttributeWithName:@"since" stringValue:dateTimeString];
    }
    
    [room joinRoomUsingNickname:nickname history:historyElement password:password];
    return databaseRoomKey;
}

- (void)xmppCapabilities:(XMPPCapabilities *)sender didDiscoverCapabilities:(NSXMLElement *)caps forJID:(XMPPJID *)jid {
    DDLogInfo(@"New caps in OTRXMPPManager: %@ for %@", caps, [jid bare]);
    NSXMLElement * identity  = [caps elementForName:@"identity"];
    if (identity) {
        NSString* cat = [identity attributeStringValueForName:@"category"];
        NSString* type = [identity attributeStringValueForName:@"type"];
        if ([cat isEqualToString:@"conference"] && [type isEqualToString:@"text"]) {
            __block BOOL publicfound = NO;
            NSArray<NSXMLElement*> *features = [caps elementsForName:@"feature"];
            [features enumerateObjectsUsingBlock:^(NSXMLElement * _Nonnull feature, NSUInteger idx, BOOL * _Nonnull stop) {
                NSString *value = [feature attributeStringValueForName:@"var"];
                if (value && [value isEqualToString:@"muc_public"]) {
                    publicfound = YES;
                }
            }];
            
            if (publicfound) {
                XMPPRoom *room = [self roomForJID:jid];
                if (room) {
                    OTRXMPPRoom *xroom = [self roomWithXMPPRoom:room];
                    if (xroom) {
                        [self.databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
                            xroom.isPublic = YES;
                            [xroom saveWithTransaction:transaction];
                        }];
                    }
                }
            }
        }
    }
}

- (void)leaveRoom:(nonnull XMPPJID *)jid
{
    XMPPRoom *room = [self roomForJID:jid];
    [room leaveRoom];
    [self removeRoomForJID:jid];
    [room removeDelegate:self];
    [room deactivate];
}

- (void)clearOccupantRolesInRoom:(OTRXMPPRoom *)room withTransaction:(YapDatabaseReadWriteTransaction * _Nonnull)transaction {
    //Enumerate of room eges to occupants
    NSString *extensionName = [YapDatabaseConstants extensionName:DatabaseExtensionNameRelationshipExtensionName];
    [[transaction ext:extensionName] enumerateEdgesWithName:[OTRXMPPRoomOccupant roomEdgeName] destinationKey:room.uniqueId collection:[OTRXMPPRoom collection] usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
        
        OTRXMPPRoomOccupant *occupant = [transaction objectForKey:edge.sourceKey inCollection:edge.sourceCollection];
        occupant.role = RoomOccupantRoleNone;
        [occupant saveWithTransaction:transaction];
    }];
}

// doesn't work yet due to server issues
- (void)clearOccupantRoleWithJID:(XMPPJID *)occupantJID {
    NSString *extensionName = [YapDatabaseConstants extensionName:DatabaseExtensionNameRelationshipExtensionName];
    [self.rooms enumerateKeysAndObjectsUsingBlock:^(id jid, id room, BOOL* stop) {
        [self.databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            XMPPRoom *thisroom = (XMPPRoom*)room;
            NSString *databaseRoomKey = [OTRXMPPRoom createUniqueId:self.xmppStream.tag jid:[thisroom.roomJID bare]];
            OTRXMPPRoom *xroom = [OTRXMPPRoom fetchObjectWithUniqueID:databaseRoomKey transaction:transaction];
            
            [[transaction ext:extensionName] enumerateEdgesWithName:[OTRXMPPRoomOccupant roomEdgeName] destinationKey:xroom.uniqueId collection:[OTRXMPPRoom collection] usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
                
                OTRXMPPRoomOccupant *occupant = [transaction objectForKey:edge.sourceKey inCollection:edge.sourceCollection];
                if (occupant.realJID != nil && [occupant.realJID isEqualToJID:occupantJID]) {
                    DDLogInfo(@"Removing %@ from %@", occupant.realJID.bare, thisroom.roomJID.bare);
                    [occupant removeWithTransaction:transaction];
                }
            }];
        }];
    }];
}

- (NSString *)startGroupChatWithBuddies:(NSArray<NSString *> *)buddiesArray roomJID:(XMPPJID *)roomName nickname:(NSString *)name subject:(nullable NSString *)subject isPublic:(BOOL)ispublic
{
    if (buddiesArray.count) {
        [self performBlockAsync:^{
            [self.inviteDictionary setObject:buddiesArray forKey:roomName.bare];
        }];
    }
    if (!ispublic) {
        _inviteAuthor = name;
    }
    [self.roomStatusDict setObject:[NSNumber numberWithBool:ispublic] forKey:roomName.bare];
    [self.roomsToConfigure addObject:roomName.bare];
    XMPPConferenceBookmark *bookmark = [[XMPPConferenceBookmark alloc] initWithJID:roomName bookmarkName:subject nick:name autoJoin:YES];
    [self.bookmarksModule fetchAndPublishWithBookmarksToAdd:@[bookmark] bookmarksToRemove:nil completion:^(NSArray<id<XMPPBookmark>> * _Nullable newBookmarks, XMPPIQ * _Nullable responseIq) {
        if (newBookmarks) {
            DDLogInfo(@"Joined new room, added to merged bookmarks: %@", newBookmarks);
        }
    } completionQueue:nil];
    return [self joinRoom:roomName withNickname:name subject:subject password:nil isPublic:ispublic];
}

- (void)inviteBuddies:(NSArray<NSString *> *)buddyUniqueIds toRoom:(XMPPRoom *)room {
    if (!buddyUniqueIds.count) {
        return;
    }
    
    NSMutableArray<NSString*> *buddyNames = [NSMutableArray arrayWithCapacity:buddyUniqueIds.count];
    if (_inviteAuthor != nil) {
        [buddyNames addObject:[_inviteAuthor copy]];
        _inviteAuthor = nil;
    }
    
    NSMutableArray<XMPPJID*> *buddyJIDs = [NSMutableArray arrayWithCapacity:buddyUniqueIds.count];
    
    [self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        [buddyUniqueIds enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            OTRXMPPBuddy *buddy = [OTRXMPPBuddy fetchObjectWithUniqueID:obj transaction:transaction];
            XMPPJID *buddyJID = buddy.bareJID;
            if (buddyJID) {
                [buddyJIDs addObject:buddyJID];
                [buddyNames addObject:buddy.threadName];
            }
        }];
    }];
    // XMPPRoom.inviteUsers doesn't seem to work, so you have
    // to send an individual invitation for each person.
    [buddyJIDs enumerateObjectsUsingBlock:^(XMPPJID * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [room inviteUser:obj withMessage:nil];
    }];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self publishInvitedBuddyList:room withBuddies:buddyNames];
    });
}

// send message to the room with invitedBuddy list
- (void) publishInvitedBuddyList:(XMPPRoom *)room withBuddies:(NSArray<NSString *> *)buddyNames{
    NSString *invitedString = [[buddyNames componentsJoinedByString:@", "] stringByAppendingString:@" added to the group"];
    OTRXMPPRoom *xroom = [self roomWithXMPPRoom:room];
    if (xroom) {
        __block OTRXMPPRoomMessage *roommsg = nil;
        __block OTRXMPPManager *xmppManager = nil;
        [self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            id<OTRMessageProtocol> message = [xroom outgoingMessageWithText:invitedString transaction:transaction];
            roommsg = (OTRXMPPRoomMessage *)message;
            roommsg.memberUpdate = YES;
            roommsg.originalText = invitedString;
            OTRXMPPAccount *account = [OTRXMPPAccount accountForStream:self.xmppStream transaction:transaction];
            xmppManager = (OTRXMPPManager *)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
        }];
        
        if (roommsg != nil && xmppManager != nil) {
            [xmppManager enqueueMessage:roommsg];
        }
    }
}

// send message to the room joined
- (void) publishJoinedRoom:(XMPPJID *)roomjid withName:(NSString *)name{
    NSArray *buddyme = [NSArray arrayWithObjects: name, nil];
    XMPPRoom *room = [self roomForJID:roomjid];
    [self publishInvitedBuddyList:room withBuddies:buddyme];
}

#pragma - mark XMPPStreamDelegate Methods

- (void)xmppStreamDidAuthenticate:(XMPPStream *)sender {
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
            //back to xmppQueue
            [self performBlockAsync:^{
                [self handleStreamDidAuthenticate:sender];
            }];
        }
    });
}

- (void)handleStreamDidAuthenticate:(XMPPStream *)sender {
    //Once we've connecected and authenticated we find what room services are available
    [self.mucModule discoverServices];
    //Once we've authenitcated we need to rejoin existing rooms
    
    NSMutableArray <OTRXMPPRoom *>*roomArray = [[NSMutableArray alloc] init];
    __block NSString *nickname = self.xmppStream.myJID.user;
    [self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        OTRXMPPAccount *account = [OTRXMPPAccount accountForStream:sender transaction:transaction];
        if (account) {
            nickname = account.displayName;
        }
        [transaction enumerateKeysAndObjectsInCollection:[OTRXMPPRoom collection] usingBlock:^(NSString * _Nonnull key, id  _Nonnull object, BOOL * _Nonnull stop) {
            
            if ([object isKindOfClass:[OTRXMPPRoom class]]) {
                OTRXMPPRoom *room = (OTRXMPPRoom *)object;
                if (room.roomJID) {
                    [roomArray addObject:room];
                    
                    if (room.avatarSeedNum > self.highSeedNum) {
                        self.highSeedNum = room.avatarSeedNum;
                    }
                }
            }
            
        } withFilter:^BOOL(NSString * _Nonnull key) {
            //OTRXMPPRoom is saved with the jid and account id as part of the key
            if ([key containsString:sender.tag]) {
                return YES;
            }
            return NO;
        }];
    }];
    
    [roomArray enumerateObjectsUsingBlock:^(OTRXMPPRoom * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self joinRoom:obj.roomJID withNickname:nickname subject:obj.subject password:obj.roomPassword];
    }];
    
    [self addRoomsToBookmarks:roomArray];
    
    [self.bookmarksModule fetchBookmarks:^(NSArray<id<XMPPBookmark>> * _Nullable bookmarks, XMPPIQ * _Nullable responseIq) {
        
    } completionQueue:nil];
}

- (void)xmppStream:(XMPPStream *)sender didFailToSendMessage:(XMPPMessage *)message error:(NSError *)error
{
    //Check id and mark as needs sending
    
}

- (void)xmppStream:(XMPPStream *)sender didSendMessage:(XMPPMessage *)message
{
    //Check id and mark as sent
}

- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message
{
    XMPPJID *from = [message from];
    XMPPRoom *room = [self roomForJID:from]; 
    //Check that this is a message for one of our rooms
    if([message isGroupChatMessageWithSubject] && room != nil) {
        
        NSString *subject = [message subject];
        
        NSString *databaseRoomKey = [OTRXMPPRoom createUniqueId:self.xmppStream.tag jid:from.bare];
        
        [self.databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            OTRXMPPRoom *room = [OTRXMPPRoom fetchObjectWithUniqueID:databaseRoomKey transaction:transaction];
            room.subject = subject;
            [room saveWithTransaction:transaction];
        }];
        
    }
    
    // Handle group chat message receipts
    [OTRXMPPRoomMessage handleDeliveryReceiptResponseWithMessage:message writeConnection:self.databaseConnection];
}

// looking for errors when (re)joining room
- (void)xmppStream:(XMPPStream *)sender didReceivePresence:(XMPPPresence *)presence
{
    DDLogVerbose(@"%@: %@\n%@", THIS_FILE, THIS_METHOD, presence.prettyXMLString);
    XMPPJID *to = [presence to];
    
    if (![to isEqualToJID:self.xmppStream.myJID options:XMPPJIDCompareBare]){
        return; // Stanza isn't for me
    }
    
    NSString *presenceType = [presence type];
    if (presenceType == nil) { return; }
    
    if ([presenceType isEqualToString:@"error"]) {
        XMPPJID *from = [presence from];
        NSString *fromDomain = from.domain;
        if (fromDomain != nil && [fromDomain hasPrefix:@"conference"]) {
            // check group size before putting it in list?
            NSXMLElement * errorel  = [presence elementForName:@"error"];
            if (errorel) {
                NSXMLElement * errortext  = [errorel elementForName:@"text"];
                if (errortext && [[errortext stringValue] containsString:@"destroyed"]) {
                    dispatch_async(dispatch_get_main_queue(), ^(void){
                        [self performSelector:@selector(removeRoomOnDestroyed:) withObject:from afterDelay:1.0];
                    });
                } else if (errortext && [[errortext stringValue] containsString:@"Too many users"]){
                    dispatch_async(dispatch_get_main_queue(), ^(void){
                        [self performSelector:@selector(tooManyUsersError:) withObject:from afterDelay:1.0];
                    });
                }
            }
        }
    } else if ([presenceType isEqualToString:@"unavailable"]) {
        NSXMLElement *x = [presence elementForName:@"x" xmlns:XMPPMUCUserNamespace];
        if (x) {
            NSXMLElement *destroy = [x elementForName:@"destroy"];
            if (destroy) {
                XMPPJID *xjid = [presence from].bareJID;
                dispatch_async(dispatch_get_main_queue(), ^(void){
                    [self removeRoomOnDestroyed:xjid];
                });
            }
        }
    }
}

- (void) tooManyUsersError:(XMPPJID*)roomjid  {
    NSString *amsg = [NSString stringWithFormat:@"The %@ group is currently full. Please try again later.", roomjid.user];
    UIAlertAction * cancelButtonItem = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Problem joining group" message:amsg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:cancelButtonItem];
    [OTRAppDelegate.appDelegate.window.rootViewController  presentViewController:alert animated:YES completion:nil];
}

// this happens when room no longer exists or we are kicked out and we try to enter it
- (void) removeRoomOnDestroyed:(XMPPJID*)roomjid  {
    NSMutableArray <OTRXMPPRoom *>*curRoomArray = [[NSMutableArray alloc] init];
    
    XMPPRoom *room = [self roomForJID:roomjid];
    [self removeRoomForJID:roomjid];
    [room removeDelegate:self];
    [room deactivate];
    
    [self.databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        [transaction enumerateKeysAndObjectsInCollection:[OTRXMPPRoom collection] usingBlock:^(NSString * _Nonnull key, id  _Nonnull object, BOOL * _Nonnull stop) {
            if ([object isKindOfClass:[OTRXMPPRoom class]]) {
                OTRXMPPRoom *room = (OTRXMPPRoom *)object;
                if (room.roomJID != nil && [roomjid.bare isEqualToString:room.roomJID.bare]) {
                    [curRoomArray addObject:room];
                }
            }
        }];
        
        if ([curRoomArray count]) {
            OTRXMPPRoom *room = (OTRXMPPRoom *)[curRoomArray firstObject];
            [self removeRoomsFromBookmarks:@[room]];
            
            XMPPRoom *xroom = [self roomForJID:room.roomJID];
            OTRXMPPAccount *account = [OTRXMPPAccount accountForStream:self.xmppStream transaction:transaction];
            if (xroom != nil && account != nil) {
                [xroom unsubscribeFromRoom: account.bareJID];
            }
            
            [room removeWithTransaction:transaction];
        }
    }];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ReloadDataNotificationName object:self userInfo:nil];
    });
    
    NSString *amsg = [NSString stringWithFormat:@"The %@ group was removed from the server, so it will no longer be in your conversations list.", roomjid.user];
    UIAlertAction * cancelButtonItem = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Group removed" message:amsg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:cancelButtonItem];
    [OTRAppDelegate.appDelegate.window.rootViewController  presentViewController:alert animated:YES completion:nil];
}


#pragma - mark XMPPMUCDelegate Methods

- (void)xmppMUC:(XMPPMUC *)sender didDiscoverServices:(NSArray *)services
{
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:[services count]];
    [services enumerateObjectsUsingBlock:^(NSXMLElement   * _Nonnull element, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *jid = [element attributeStringValueForName:@"jid"];
        if ([jid length] && [jid containsString:@"conference"]) {
            [array addObject:jid];
            //TODO instead of just checking if it has the word 'confernce' in the name we need to preform a iq 'get' to see it's capabilities.
            
        }
        
    }];
    _conferenceServicesJID = array;
    
    if ([_conferenceServicesJID count] > 0) {
        [self.mucModule discoverRoomsForServiceNamed:[_conferenceServicesJID firstObject]];
    }
}

// what rooms are available for our service
- (void)xmppMUC:(XMPPMUC *)sender didDiscoverRooms:(NSArray *)rooms forServiceNamed:(NSString *)serviceName
{
    NSMutableArray <NSString *>*curRoomArray = [[NSMutableArray alloc] init];
    [self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        [transaction enumerateKeysAndObjectsInCollection:[OTRXMPPRoom collection] usingBlock:^(NSString * _Nonnull key, id  _Nonnull object, BOOL * _Nonnull stop) {
            
            if ([object isKindOfClass:[OTRXMPPRoom class]]) {
                OTRXMPPRoom *room = (OTRXMPPRoom *)object;
                if (room.roomJID != nil) {
                    [curRoomArray addObject:room.roomJID.bare];
                }
            }
        }];
    }];
    
    
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:[rooms count]];
    NSMutableArray *allarray = [NSMutableArray arrayWithCapacity:[rooms count]];
    [rooms enumerateObjectsUsingBlock:^(NSXMLElement   * _Nonnull element, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *jid = [element attributeStringValueForName:@"jid"];
        if ([jid length] && ![curRoomArray containsObject:jid]) {
            [array addObject:jid];
        }
        if ([jid length]) {
            [allarray addObject:jid];
        }
    }];
    _availableRooms = array;
    _allRooms = allarray;
}

- (void)xmppMUC:(XMPPMUC *)sender roomJID:(XMPPJID *)roomJID didReceiveInvitation:(XMPPMessage *)message
{
    // We must check if we trust the person who invited us
    // because some servers will send you invites from anyone
    // We should probably move some of this code upstream into XMPPFramework
    
    // Since XMPP is super great, there are (at least) two ways to receive a room invite.

    // Examples from XEP-0045:
    // Example 124. Room Sends Invitation to New Member:
    //
    // <message from='darkcave@chat.shakespeare.lit' to='hecate@shakespeare.lit'>
    //   <x xmlns='http://jabber.org/protocol/muc#user'>
    //     <invite from='bard@shakespeare.lit'/>
    //     <password>cauldronburn</password>
    //   </x>
    // </message>
    //
    
    // Examples from XEP-0249:
    //
    //
    // Example 1. A direct invitation
    //
    // <message from='crone1@shakespeare.lit/desktop' to='hecate@shakespeare.lit'>
    //   <x xmlns='jabber:x:conference'
    //      jid='darkcave@macbeth.shakespeare.lit'
    //      password='cauldronburn'
    //      reason='Hey Hecate, this is the place for all good witches!'/>
    // </message>
    
    XMPPJID *fromJID = nil;
    NSString *password = nil;
    
    NSXMLElement * roomInvite = [message elementForName:@"x" xmlns:XMPPMUCUserNamespace];
    NSXMLElement * directInvite = [message elementForName:@"x" xmlns:@"jabber:x:conference"];
    if (roomInvite) {
        // XEP-0045
        NSXMLElement * invite  = [roomInvite elementForName:@"invite"];
        fromJID = [XMPPJID jidWithString:[invite attributeStringValueForName:@"from"]];
        password = [roomInvite elementForName:@"password"].stringValue;
    } else if (directInvite) {
        // XEP-0249
        fromJID = [message from];
        password = [directInvite attributeStringValueForName:@"password"];
    }
    if (!fromJID) {
        DDLogWarn(@"Could not parse fromJID from room invite: %@", message);
        return;
    }
    __block OTRXMPPBuddy *buddy = nil;
    XMPPStream *stream = self.xmppStream;
    NSString *accountUniqueId = stream.tag;
    __block NSString *nickname = stream.myJID.user;
    [self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        OTRXMPPAccount *account = [OTRXMPPAccount accountForStream:stream transaction:transaction];
        if (account) {
            nickname = account.displayName;
        }
        buddy = [OTRXMPPBuddy fetchBuddyWithJid:fromJID accountUniqueId:accountUniqueId transaction:transaction];
    }];
    // We were invited by someone not on our roster. Shady business!
    if (!buddy) {
        DDLogWarn(@"Received room invitation from someone not on our roster! %@ %@", fromJID, message);
        return;
    }
    [self joinRoom:roomJID withNickname:nickname subject:nil password:password];
}

#pragma - mark XMPPRoomDelegate Methods

- (OTRXMPPRoom*)roomWithXMPPRoom:(XMPPRoom*)xmppRoom {
    NSString *databaseRoomKey = [OTRXMPPRoom createUniqueId:self.xmppStream.tag jid:[xmppRoom.roomJID bare]];
    __block OTRXMPPRoom *room = nil;
    [self.databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        room = [OTRXMPPRoom fetchObjectWithUniqueID:databaseRoomKey transaction:transaction];
    }];
    return room;
}

- (OTRXMPPRoomRuntimeProperties *)roomRuntimeProperties:(XMPPRoom*)xmppRoom {
    OTRXMPPRoom *room = [self roomWithXMPPRoom:xmppRoom];
    if (room) {
        return [OTRBuddyCache.shared runtimePropertiesForRoom:room];
    }
    return nil;
}

- (void) fetchHistoryIfListsDownloaded:(XMPPRoom *)xmppRoom {
    OTRXMPPRoomRuntimeProperties *properties = [self roomRuntimeProperties:xmppRoom];
    if (properties && !properties.hasFetchedHistory &&
        properties.hasFetchedMembers &&
        properties.hasFetchedAdmins &&
        properties.hasFetchedOwners) {
        properties.hasFetchedHistory = YES;
        [self fetchHistoryFor:xmppRoom];
    }
}

- (void) xmppRoom:(XMPPRoom *)room didFetchMembersList:(NSArray<NSXMLElement*> *)items {
    //DDLogInfo(@"Fetched members list: %@", items);
    [self xmppRoom:room addOccupantItems:items];
    [[self roomRuntimeProperties:room] setHasFetchedMembers:YES];
    [self fetchHistoryIfListsDownloaded:room];
}

- (void)xmppRoom:(XMPPRoom *)room didNotFetchMembersList:(XMPPIQ *)iqError {
    [[self roomRuntimeProperties:room] setHasFetchedMembers:YES];
    [self fetchHistoryIfListsDownloaded:room];
}

- (void) xmppRoom:(XMPPRoom *)room didFetchAdminsList:(NSArray<NSXMLElement*> *)items {
    //DDLogInfo(@"Fetched admins list: %@", items);
    [self xmppRoom:room addOccupantItems:items];
    [[self roomRuntimeProperties:room] setHasFetchedAdmins:YES];
    [self fetchHistoryIfListsDownloaded:room];
}
     
- (void)xmppRoom:(XMPPRoom *)room didNotFetchAdminsList:(XMPPIQ *)iqError {
    [[self roomRuntimeProperties:room] setHasFetchedAdmins:YES];
    [self fetchHistoryIfListsDownloaded:room];
}

- (void) xmppRoom:(XMPPRoom *)room didFetchOwnersList:(NSArray<NSXMLElement*> *)items {
    //DDLogInfo(@"Fetched owners list: %@", items);
    [self xmppRoom:room addOccupantItems:items];
    [[self roomRuntimeProperties:room] setHasFetchedOwners:YES];
    [self fetchHistoryIfListsDownloaded:room];
}

- (void)xmppRoom:(XMPPRoom *)room didNotFetchOwnersList:(XMPPIQ *)iqError {
    [[self roomRuntimeProperties:room] setHasFetchedOwners:YES];
    [self fetchHistoryIfListsDownloaded:room];
}

- (void)xmppRoom:(XMPPRoom *)room didFetchModeratorsList:(NSArray *)items {
    //DDLogInfo(@"Fetched moderators list: %@", items);
    [self xmppRoom:room addOccupantItems:items];
}

- (void) xmppRoom:(XMPPRoom *)room addOccupantItems:(NSArray<NSXMLElement*> *)items {
    NSAssert([room.xmppRoomStorage isKindOfClass:RoomStorage.class], @"Wrong room storage class");
    if ([room.xmppRoomStorage isKindOfClass:RoomStorage.class]) {
        RoomStorage *roomStorage = (RoomStorage*)room.xmppRoomStorage;
        [roomStorage insertOccupantItems:items into:room];
    } else {
        DDLogError(@"Could not store occupants. Wrong room storage class!");
    }
}

- (void)xmppRoomDidCreate:(XMPPRoom *)sender {
    [self.roomsToConfigure removeObject:sender.roomJID.bare];
    [sender fetchConfigurationForm];
}

- (void)xmppRoom:(XMPPRoom *)sender didFetchConfigurationForm:(DDXMLElement *)configForm {
    BOOL ispublic = NO;
    NSNumber *pubnum = [self.roomStatusDict objectForKey:sender.roomJID.bare];
    if (pubnum != nil) {
        ispublic = [pubnum boolValue];
        [self.roomStatusDict removeObjectForKey:sender.roomJID.bare];
    }
    
    [sender configureRoomUsingOptions:[[self class] defaultRoomConfiguration:ispublic]];
}

- (void)xmppRoom:(XMPPRoom *)sender didConfigure:(XMPPIQ *)iqResult {
    //Set Room Subject
    NSString *subject = [self.tempRoomSubject objectForKey:sender.roomJID.bare];
    if (subject) {
        [self.tempRoomSubject removeObjectForKey:sender.roomJID.bare];
        [sender changeRoomSubject:subject];
    }
    
    //Invite buddies
    NSArray<NSString*> *buddyUniqueIds = [self.inviteDictionary objectForKey:sender.roomJID.bare];
    if (buddyUniqueIds) {
        [self.inviteDictionary removeObjectForKey:sender.roomJID.bare];
        [self inviteBuddies:buddyUniqueIds toRoom:sender];
    }

    // Fetch member list. Ideally this would be done after the invites above have been sent to the network, but the messages pass all kinds of async delegates before they are actually sent, so unfortunately we can't wait for that.
    [self performBlockAsync:^{
            [sender fetchMembersList];
            [sender fetchAdminsList];
            [sender fetchOwnersList];
            [sender fetchModeratorsList];
    }];
}

- (void)xmppRoomDidJoin:(XMPPRoom *)sender
{
    // Older prosody servers have a bug where they consider all room as already
    // existing, so the status 201 is never sent.
    if ([self.roomsToConfigure containsObject:sender.roomJID.bare]) {
        [self xmppRoomDidCreate:sender];
    } else {
        // Fetch member list
        [self performBlockAsync:^{
            [sender fetchMembersList];
            [sender fetchAdminsList];
            [sender fetchOwnersList];
            [sender fetchModeratorsList];
        }];
    }
}

- (void)xmppRoomDidLeave:(XMPPRoom *)sender {
    NSString *databaseRoomKey = [OTRXMPPRoom createUniqueId:self.xmppStream.tag jid:[sender.roomJID bare]];
    [self.databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        OTRXMPPRoom *room = [OTRXMPPRoom fetchObjectWithUniqueID:databaseRoomKey transaction:transaction];
        if (room) {
            [self clearOccupantRolesInRoom:room withTransaction:transaction];
        }
    }];
}

// placeholder for better tracking room member list? (next one also)
- (void)xmppRoom:(XMPPRoom *)sender occupantDidJoin:(XMPPJID *)occupantJID withPresence:(XMPPPresence *)presence
{
    /*DDLogError(@"***** occupantDidJoin %@ with roomJID %@ and presence %@", occupantJID.full, sender.roomJID.bare, presence.type);
    NSString *databaseRoomKey = [OTRXMPPRoom createUniqueId:self.xmppStream.tag jid:[sender.roomJID bare]];
    __block NSArray<OTRXMPPRoomOccupant*> *allOccs = @[];
    [self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        OTRXMPPRoom *room = [OTRXMPPRoom fetchObjectWithUniqueID:databaseRoomKey transaction:transaction];
        if (room) {
            allOccs = [room allOccupants:transaction];
        }
    }];
    
    [allOccs enumerateObjectsUsingBlock:^(OTRXMPPRoomOccupant * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        //[room inviteUser:obj withMessage:nil];
    }];*/
    
    
    // check against current list
    // OTRXMPPRoom -> allOccupants (array of OTRXMPPRoomOccupant, can then use .roomName)
    // if not exists, add and then add message
    
}

- (void)xmppRoom:(XMPPRoom *)sender occupantDidLeave:(XMPPJID *)occupantJID withPresence:(XMPPPresence *)presence {
    //DDLogError(@"***** occupantDidLeave %@ with roomJID %@ and presence %@", occupantJID.full, sender.roomJID.bare, presence.type);
    /*NSString *databaseRoomKey = [OTRXMPPRoom createUniqueId:self.xmppStream.tag jid:[sender.roomJID bare]];
    [self.databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        OTRXMPPRoom *room = [OTRXMPPRoom fetchObjectWithUniqueID:databaseRoomKey transaction:transaction];
        if (room) {
            [self clearOccupantRolesInRoom:room withTransaction:transaction];
        }
    }];*/
}

#pragma mark - Utility

- (void) removeRoomForJID:(nonnull XMPPJID*)jid {
    NSParameterAssert(jid != nil);
    if (!jid) { return; }
    [self performBlockAsync:^{
        [self.rooms removeObjectForKey:jid.bareJID];
    }];
}

- (void) setRoom:(nonnull XMPPRoom*)room forJID:(nonnull XMPPJID*)jid {
    NSParameterAssert(room != nil);
    NSParameterAssert(jid != nil);
    if (!room || !jid) {
        return;
    }
    [self performBlockAsync:^{
        [self.rooms setObject:room forKey:jid.bareJID];
    }];
}

- (nullable XMPPRoom*) roomForJID:(nonnull XMPPJID*)jid {
    NSParameterAssert(jid != nil);
    if (!jid) { return nil; }
    __block XMPPRoom *room = nil;
    [self performBlock:^{
        room = [self.rooms objectForKey:jid.bareJID];
    }];
    return room;
}

#pragma - mark Class Methods

+ (NSXMLElement *)defaultRoomConfiguration:(BOOL)ispublicroom
{
    NSXMLElement *form = [[NSXMLElement alloc] initWithName:@"x" xmlns:@"jabber:x:data"];

    NSXMLElement *formTypeField = [[NSXMLElement alloc] initWithName:@"field"];
    [formTypeField addAttributeWithName:@"var" stringValue:@"FORM_TYPE"];
    [formTypeField addChild:[[NSXMLElement alloc] initWithName:@"value" stringValue:@"http://jabber.org/protocol/muc#roomconfig"]];

    NSXMLElement *publicField = [[NSXMLElement alloc] initWithName:@"field"];
    [publicField addAttributeWithName:@"var" stringValue:@"muc#roomconfig_publicroom"];
    if (ispublicroom) { 
        [publicField addChild:[[NSXMLElement alloc] initWithName:@"value" numberValue:@(1)]];
    } else {
        [publicField addChild:[[NSXMLElement alloc] initWithName:@"value" numberValue:@(0)]];
    }
    
    NSXMLElement *persistentField = [[NSXMLElement alloc] initWithName:@"field"];
    [persistentField addAttributeWithName:@"var" stringValue:@"muc#roomconfig_persistentroom"];
    [persistentField addChild:[[NSXMLElement alloc] initWithName:@"value" numberValue:@(1)]];
    
    NSXMLElement *whoisField = [[NSXMLElement alloc] initWithName:@"field"];
    [whoisField addAttributeWithName:@"var" stringValue:@"muc#roomconfig_whois"];
    [whoisField addChild:[[NSXMLElement alloc] initWithName:@"value" stringValue:@"anyone"]];
    
    // whether to allow subscription to room notifications
    NSXMLElement *allowSubscriptionField = [[NSXMLElement alloc] initWithName:@"field"];
    [allowSubscriptionField addAttributeWithName:@"var" stringValue:@"muc#roomconfig_allow_subscription"];
    [allowSubscriptionField addChild:[[NSXMLElement alloc] initWithName:@"value" numberValue:@(1)]];

    NSXMLElement *membersOnlyField = [[NSXMLElement alloc] initWithName:@"field"];
    [membersOnlyField addAttributeWithName:@"var" stringValue:@"muc#roomconfig_membersonly"];
    if (ispublicroom) {
        [membersOnlyField addChild:[[NSXMLElement alloc] initWithName:@"value" numberValue:@(0)]];
    } else {
        [membersOnlyField addChild:[[NSXMLElement alloc] initWithName:@"value" numberValue:@(1)]];
    }

    NSXMLElement *getMemberListField = [[NSXMLElement alloc] initWithName:@"field"];
    [getMemberListField addAttributeWithName:@"var" stringValue:@"muc#roomconfig_getmemberlist"];
    [getMemberListField addChild:[[NSXMLElement alloc] initWithName:@"value" stringValue:@"moderator"]];
    [getMemberListField addChild:[[NSXMLElement alloc] initWithName:@"value" stringValue:@"participant"]];

    NSXMLElement *presenceBroadcastField = [[NSXMLElement alloc] initWithName:@"field"];
    [presenceBroadcastField addAttributeWithName:@"var" stringValue:@"muc#roomconfig_presencebroadcast"];
    [presenceBroadcastField addChild:[[NSXMLElement alloc] initWithName:@"value" stringValue:@"moderator"]];
    [presenceBroadcastField addChild:[[NSXMLElement alloc] initWithName:@"value" stringValue:@"participant"]];

    [form addChild:formTypeField];
    [form addChild:publicField];
    [form addChild:persistentField];
    [form addChild:whoisField];
    [form addChild:membersOnlyField];
    [form addChild:presenceBroadcastField];
    [form addChild:allowSubscriptionField];
    
    return form;
}

@end

