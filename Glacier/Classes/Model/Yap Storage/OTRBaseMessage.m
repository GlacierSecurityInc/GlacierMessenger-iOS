//
//  OTRMessage.m
//  Off the Record
//
//  Created by David Chiles on 3/28/14.
//  Copyright (c) 2014 Chris Ballinger. All rights reserved.
//

#import "OTRBaseMessage.h"
#import "OTRBuddy.h"
#import "OTRAccount.h"
@import YapDatabase;
#import "OTRDatabaseManager.h"
#import "OTRConstants.h"
#import "OTRMediaItem.h"
#import "OTRDownloadMessage.h"
@import CocoaLumberjack;
#import "OTRLog.h"
#import "OTRMessageEncryptionInfo.h"
#if !TARGET_IS_EXTENSION
#import "Glacier-Swift.h"
#elif !TARGET_IS_SHARE
#import "GlacierNotifications-Swift.h"
#elif TARGET_IS_SHARE
#import "GlacierShare-Swift.h"
#endif

@interface OTRBaseMessage()
@property (nonatomic) BOOL transportedSecurely;
@end


@implementation OTRBaseMessage
@synthesize originId = _originId;
@synthesize stanzaId = _stanzaId;

- (id)init
{
    if (self = [super init]) {
        self.date = [NSDate date];
        self.messageId = [[NSUUID UUID] UUIDString];
        self.transportedSecurely = NO;
        self.systemUpdate = NO;
        self.markable = NO;
    }
    return self;
}

#pragma - mark MTLModel

- (id)decodeValueForKey:(NSString *)key withCoder:(NSCoder *)coder modelVersion:(NSUInteger)modelVersion {
    // Going from version 0 to version 1.
    // The dateSent is assumed to be the `date` created. In model version 1 this will be properly set using the sending queue
    if (modelVersion == 0 && [key isEqualToString:@"dateSent"] ) {
        return [super decodeValueForKey:@"date" withCoder:coder modelVersion:modelVersion];
    }
    return [super decodeValueForKey:key withCoder:coder modelVersion:modelVersion];
}

#pragma - mark YapDatabaseRelationshipNode

- (NSArray *)yapDatabaseRelationshipEdges
{
    NSArray *edges = nil;
    if (self.buddyUniqueId) {
        NSString *edgeName = [YapDatabaseConstants edgeName:RelationshipEdgeNameMessageBuddyEdgeName];
        YapDatabaseRelationshipEdge *buddyEdge = [YapDatabaseRelationshipEdge edgeWithName:edgeName
                                                                            destinationKey:self.buddyUniqueId
                                                                                collection:[OTRBuddy collection]
                                                                           nodeDeleteRules:YDB_DeleteSourceIfDestinationDeleted];
        
        edges = @[buddyEdge];
    }
    
    if (self.mediaItemUniqueId) {
        NSString *edgeName = [YapDatabaseConstants edgeName:RelationshipEdgeNameMessageMediaEdgeName];
        YapDatabaseRelationshipEdge *mediaEdge = [YapDatabaseRelationshipEdge edgeWithName:edgeName
                                                                            destinationKey:self.mediaItemUniqueId
                                                                                collection:[OTRMediaItem collection]
                                                                           nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted | YDB_NotifyIfSourceDeleted];
        
        if ([edges count]) {
            edges = [edges arrayByAddingObject:mediaEdge];
        }
        else {
            edges = @[mediaEdge];
        }
    }
    
    return edges;
}

/** Override normal behaviour to migrate from old way of storing encryption state */
- (OTRMessageEncryptionInfo *)messageSecurityInfo {
    if (self.transportedSecurely) {
        return [[OTRMessageEncryptionInfo alloc] initWithMessageSecurity:OTRMessageTransportSecurityOTR];
    }
    return _messageSecurityInfo;
}

#pragma mark OTRDownloadMessageProtocol

/**  If available, existing instances will be returned. */
- (NSArray<id<OTRDownloadMessage>>*) existingDownloadsWithTransaction:(YapDatabaseReadTransaction*)transaction {
    if (!self.isMessageIncomingOrDifferentDevice) {
        return @[];
    }
    id<OTRMessageProtocol> message = self;
    NSMutableArray<id<OTRDownloadMessage>> *downloadMessages = [NSMutableArray array];
    NSString *extensionName = [YapDatabaseConstants extensionName:DatabaseExtensionNameRelationshipExtensionName];
    NSString *edgeName = [YapDatabaseConstants edgeName:RelationshipEdgeNameDownload];
    YapDatabaseRelationshipTransaction *relationship = [transaction ext:extensionName];
    if (!relationship) {
        DDLogWarn(@"%@ not registered!", extensionName);
    }
    [relationship enumerateEdgesWithName:edgeName destinationKey:message.messageKey collection:message.messageCollection usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
        OTRDirectDownloadMessage *download = [OTRDirectDownloadMessage fetchObjectWithUniqueID:edge.sourceKey transaction:transaction];
        if (download) {
            [downloadMessages addObject:download];
        }
    }];
    return downloadMessages;
}

/** Returns an unsaved array of downloadable URLs. */
- (NSArray<id<OTRDownloadMessage>>*) downloads {
    if (!self.isMessageIncomingOrDifferentDevice) {
        return @[];
    }
    id<OTRMessageProtocol> message = self;
    NSMutableArray<id<OTRDownloadMessage>> *downloadMessages = [NSMutableArray array];
#if !TARGET_IS_EXTENSION
    [self.downloadableNSURLs enumerateObjectsUsingBlock:^(NSURL * _Nonnull url, NSUInteger idx, BOOL * _Nonnull stop) {
        id<OTRDownloadMessage> download = [OTRDirectDownloadMessage downloadWithParentMessage:message url:url];
        [downloadMessages addObject:download];
    }];
#endif
    return downloadMessages;
}

- (BOOL) hasExistingDownloadsWithTransaction:(YapDatabaseReadTransaction*)transaction {
    if (!self.isMessageIncomingOrDifferentDevice) { 
        return NO;
    }
    NSString *extensionName = [YapDatabaseConstants extensionName:DatabaseExtensionNameRelationshipExtensionName];
    NSString *edgeName = [YapDatabaseConstants edgeName:RelationshipEdgeNameDownload];
    YapDatabaseRelationshipTransaction *relationship = [transaction ext:extensionName];
    if (!relationship) {
        DDLogWarn(@"%@ not registered!", extensionName);
    }
    NSUInteger count = [relationship edgeCountWithName:edgeName destinationKey:self.messageKey collection:self.messageCollection];
    return count > 0;
}

#pragma - mark OTRMessage Protocol methods

- (NSDate*) messageDate {
    return self.date;
}

- (void) setMessageDate:(NSDate *)messageDate {
    self.date = messageDate;
}

- (NSDate*) messageReadDate {
    return self.readDate;
}

- (void) setMessageReadDate:(NSDate *)messageReadDate {
    self.readDate = messageReadDate;
}

- (BOOL) isMessageDelivered {
    return NO;
}

- (BOOL) isMessageDisplayed {
    return NO;
}

- (BOOL) isMessageSent {
    return NO;
}

// Override in subclass
- (BOOL)isMessageIncoming {
    return YES;
}

// Override in subclass
- (BOOL)isMessageIncomingOrDifferentDevice {
    return YES;
}

// Override in subclass
- (BOOL)isMessageRead {
    return YES;
}

- (BOOL) isSystemUpdate {
    return self.systemUpdate;
}

- (BOOL) isMarkable {
    return self.markable;
}

- (OTRMessageTransportSecurity) messageSecurity {
    return self.messageSecurityInfo.messageSecurity;
}

- (void) setMessageSecurity:(OTRMessageTransportSecurity)messageSecurity {
    OTRMessageEncryptionInfo *info = [[OTRMessageEncryptionInfo alloc] initWithMessageSecurity:messageSecurity];
    self.messageSecurityInfo = info;
}

- (NSString *)messageKey {
    return self.uniqueId;
}

- (NSString *)messageCollection {
    return [self.class collection];
}

- (NSString *)threadId {
    return self.buddyUniqueId;
}

- (NSString*)threadCollection {
    return [OTRBuddy collection];
}

- (NSString *)messageMediaItemKey
{
    return self.mediaItemUniqueId;
}

- (void) setMessageMediaItemKey:(NSString *)messageMediaItemKey {
    self.mediaItemUniqueId = messageMediaItemKey;
}

- (void) setMessageError:(NSError *)messageError {
    self.error = messageError;
}

- (NSError *)messageError {
    return self.error;
}

- (NSString*) messageText {
    return self.text;
}

- (void) setMessageText:(NSString *)messageText {
    self.text = messageText;
}

// used with share location
- (NSString*) messageOriginalText {
    return self.originalText;
}

- (NSString*) messageExpires {
    return self.expires;
}

- (NSString *)remoteMessageId
{
    return self.messageId;
}

- (id<OTRThreadOwner>)threadOwnerWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    id object = [transaction objectForKey:self.threadId inCollection:self.threadCollection];
    if ([object conformsToProtocol:@protocol(OTRThreadOwner)]) {
        return object;
    }
    return nil;
}

- (nullable OTRXMPPBuddy*) buddyWithTransaction:(nonnull YapDatabaseReadTransaction*)transaction {
    id <OTRThreadOwner> threadOwner = [self threadOwnerWithTransaction:transaction];
    if ([threadOwner isKindOfClass:[OTRXMPPBuddy class]]) {
        return (OTRXMPPBuddy*)threadOwner;
    }
    return nil;
}

#if !TARGET_IS_EXTENSION
+ (void)deleteAllMessagesWithTransaction:(YapDatabaseReadWriteTransaction*)transaction
{
    [transaction removeAllObjectsInCollection:[self collection]];
}

+ (void)deleteAllMessagesForBuddyId:(NSString *)uniqueBuddyId transaction:(YapDatabaseReadWriteTransaction*)transaction
{
    NSString *extensionName = [YapDatabaseConstants extensionName:DatabaseExtensionNameRelationshipExtensionName];
    NSString *edgeName = [YapDatabaseConstants edgeName:RelationshipEdgeNameMessageBuddyEdgeName];
    [[transaction ext:extensionName] enumerateEdgesWithName:edgeName destinationKey:uniqueBuddyId collection:[OTRBuddy collection] usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
        [transaction removeObjectForKey:edge.sourceKey inCollection:edge.sourceCollection];
    }];
    //Update Last message date for sorting and grouping
    OTRBuddy *buddy = [OTRBuddy fetchObjectWithUniqueID:uniqueBuddyId transaction:transaction];
    buddy = [buddy copy];
    buddy.lastMessageId = nil;
    [buddy saveWithTransaction:transaction];
}

+ (void)deleteAllMessagesForAccountId:(NSString *)uniqueAccountId transaction:(YapDatabaseReadWriteTransaction*)transaction
{
    NSString *extensionName = [YapDatabaseConstants extensionName:DatabaseExtensionNameRelationshipExtensionName];
    NSString *edgeName = [YapDatabaseConstants edgeName:RelationshipEdgeNameBuddyAccountEdgeName];
    [[transaction ext:extensionName] enumerateEdgesWithName:edgeName destinationKey:uniqueAccountId collection:[OTRAccount collection] usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
        [self deleteAllMessagesForBuddyId:edge.sourceKey transaction:transaction];
    }];
    
    [self removeAccountFromGroups:uniqueAccountId transaction:transaction];
}

+ (void)removeAccountFromGroups:(NSString *)uniqueAccountId transaction:(YapDatabaseReadWriteTransaction*)transaction {
    
    NSMutableArray <OTRXMPPRoom *>*roomArray = [[NSMutableArray alloc] init];
    [transaction enumerateKeysAndObjectsInCollection:[OTRXMPPRoom collection] usingBlock:^(NSString * _Nonnull key, id  _Nonnull object, BOOL * _Nonnull stop) {
        
        if ([object isKindOfClass:[OTRXMPPRoom class]]) {
            OTRXMPPRoom *room = (OTRXMPPRoom *)object;
            if (room.roomJID != nil) {
                [roomArray addObject:room];
            }
        }
    }];
    
    [roomArray enumerateObjectsUsingBlock:^(OTRXMPPRoom * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        //Leave room
        NSString *accountKey = [obj threadAccountIdentifier];
        OTRAccount *account = [OTRAccount fetchObjectWithUniqueID:accountKey transaction:transaction];
        OTRProtocolManager *protManager = [OTRProtocolManager sharedInstance];
        OTRXMPPManager *xmppManager = nil;
        if ([protManager existsProtocolForAccount:account]) {
            xmppManager = (OTRXMPPManager *)[protManager protocolForAccount:account];
            
            XMPPRoom *xroom = [xmppManager.roomManager roomForJID:obj.roomJID];
            XMPPJID *jid = [XMPPJID jidWithString:account.username];
            [xroom unsubscribeFromRoom:jid];
            
            [xmppManager.roomManager removeRoomsFromBookmarks:@[obj]];
            
            NSString *left = [account.displayName stringByAppendingString:@" left the group"];
            id<OTRMessageProtocol> message = [obj outgoingMessageWithText:left transaction:transaction];
            [xmppManager enqueueMessage:message];
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (xmppManager != nil) {
                [xmppManager.roomManager leaveRoom:obj.roomJID];
            }
            
            //Delete database items
            [self removeRoom:obj]; // needs new transaction due to pause and new thread
        });
    }];
}
#endif

+ (void)removeRoom:(OTRXMPPRoom *)room{
    YapDatabaseConnection *rwDatabaseConnection = [OTRDatabaseManager sharedInstance].writeConnection;
    [rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [room removeWithTransaction:transaction];
    }];
}

- (id<OTRMessageProtocol>)duplicateMessage {
    OTRBaseMessage *message = self;
    OTRBaseMessage *newMessage = [[[self class] alloc] init];
    newMessage.text = message.text;
    newMessage.error = message.error;
    newMessage.mediaItemUniqueId = message.mediaItemUniqueId;
    newMessage.buddyUniqueId = message.buddyUniqueId;
    newMessage.messageSecurityInfo = message.messageSecurityInfo;
    return newMessage;
}

+ (NSUInteger)modelVersion {
    return 1;
}

+ (NSString *)collection {
    return @"OTRMessage";
}

@end
