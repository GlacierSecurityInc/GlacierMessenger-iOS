//
//  OTRBuddy.m
//  Off the Record
//
//  Created by David Chiles on 3/28/14.
//  Copyright (c) 2014 Chris Ballinger. All rights reserved.
//
#import "OTRBuddy.h"
#import "OTRAccount.h"
@import YapDatabase;
#import "OTRLog.h"
#import "OTRDatabaseManager.h"
#import "OTRIncomingMessage.h"
#import "OTROutgoingMessage.h"
#if !TARGET_IS_EXTENSION
#import "OTRBuddyCache.h"
#import "OTRImages.h"
@import JSQMessagesViewController;
#import "Glacier-Swift.h"
@import OTRKit;
#import "OTRColors.h"
#elif !TARGET_IS_SHARE
#import "GlacierNotifications-Swift.h"
#elif TARGET_IS_SHARE
#import "GlacierShare-Swift.h"
#endif
#import "NSString+ChatSecure.h"

@implementation OTRBuddy
@synthesize displayName = _displayName;
@synthesize isArchived = _isArchived;
@synthesize muteExpiration = _muteExpiration;
@dynamic statusMessage, chatState, lastSentChatState, status;

- (id)init {
    if (self = [super init]) {
        self.preferredSecurity = OTRSessionSecurityOMEMO;
    }
    return self;
}

- (instancetype)initWithUniqueId:(NSString *)uniqueId
{
    if (self = [super initWithUniqueId:uniqueId]) {
        self.preferredSecurity = OTRSessionSecurityOMEMO;
    }
    return self;
}

/**
 The current or generated avatar image either from avatarData or the initials from displayName or username
 
 @return An UIImage from the OTRImages NSCache
 */
#if !TARGET_IS_EXTENSION
- (UIImage *)avatarImage
{
    //on setAvatar clear this buddies image cache
    //invalidate if jid or display name changes 
    return [OTRImages avatarImageWithUniqueIdentifier:self.uniqueId avatarData:self.avatarData displayName:self.displayName username:self.username];
}

- (void)setAvatarData:(NSData *)avatarData
{
    if (![_avatarData isEqualToData: avatarData]) {
        _avatarData = avatarData;
        [OTRImages removeImageWithIdentifier:self.uniqueId];
    }
}
#endif

- (void)setDisplayName:(NSString *)displayName
{
    // Never set displayName the same as the username
    if ([displayName isEqualToString:self.username]) {
        return;
    }
    if (![_displayName isEqualToString:displayName]) {
        _displayName = displayName;
#if !TARGET_IS_EXTENSION
        if (!self.avatarData) {
            [OTRImages removeImageWithIdentifier:self.uniqueId];
        }
#endif
    }
}

- (NSString*) displayName {
    // If user has set a displayName that isn't the JID, use that immediately
    if (_displayName.length > 0 && ![_displayName isEqualToString:self.username]) {
        return _displayName;
    }
    NSString *user = [self.username otr_displayName];
    if (!user.length) {
        return _displayName;
    }
    return user;
}


- (BOOL)hasMessagesWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    NSString *extensionName = [YapDatabaseConstants extensionName:DatabaseExtensionNameRelationshipExtensionName];
    NSString *edgeName = [YapDatabaseConstants edgeName:RelationshipEdgeNameMessageBuddyEdgeName];
    NSUInteger numberOfMessages = [[transaction ext:extensionName] edgeCountWithName:edgeName destinationKey:self.uniqueId collection:[OTRBuddy collection]];
    return (numberOfMessages > 0);
}

- (OTRAccount*)accountWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [OTRAccount fetchObjectWithUniqueID:self.accountUniqueId transaction:transaction];
}

+ (nullable instancetype) fetchObjectWithUniqueID:(NSString *)uniqueID transaction:(YapDatabaseReadTransaction *)transaction {
    OTRBuddy *buddy = (OTRBuddy*)[super fetchObjectWithUniqueID:uniqueID transaction:transaction];
    if (!buddy.username.length) {
        return nil;
    }
    return buddy;
}

- (NSUInteger)numberOfUnreadMessagesWithTransaction:(nonnull YapDatabaseReadTransaction*)transaction {
    YapDatabaseSecondaryIndexTransaction *indexTransaction = [transaction ext:SecondaryIndexName.messages];
    if (!indexTransaction) {
        return 0;
    }
    NSString *queryString = [NSString stringWithFormat:@"WHERE %@ == %@ AND %@ == ?", MessageIndexColumnName.isMessageRead, @(NO), MessageIndexColumnName.threadId];
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:queryString, self.uniqueId];
    NSUInteger numRows = 0;
    BOOL success = [indexTransaction getNumberOfRows:&numRows matchingQuery:query];
    if (!success) {
        DDLogError(@"Query error for OTRBuddy numberOfUnreadMessagesWithTransaction");
    }
    return numRows;
}

- (id <OTRMessageProtocol>)lastMessageWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    YapDatabaseViewTransaction *viewTransaction = [transaction ext:OTRFilteredChatDatabaseViewExtensionName];
    if (!viewTransaction) {
        return nil;
    }
    id <OTRMessageProtocol> message = [viewTransaction lastObjectInGroup:self.threadIdentifier];
    if (![message conformsToProtocol:@protocol(OTRMessageProtocol)]) {
        return nil;
    }
    return message;
}


/** Translates the preferredSecurity value first if set, otherwise bestTransportSecurityWithTransaction: */
- (OTRMessageTransportSecurity)preferredTransportSecurityWithTransaction:(nonnull YapDatabaseReadTransaction *)transaction {
    NSParameterAssert(transaction);
    if (!transaction) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Missing transaction for bestTransportSecurityWithTransaction!" userInfo:nil];
    }
    OTRMessageTransportSecurity messageSecurity = OTRMessageTransportSecurityInvalid;
    
    switch (self.preferredSecurity) {
        case OTRSessionSecurityPlaintextOnly: {
            messageSecurity = OTRMessageTransportSecurityPlaintext;
            break;
        }
        case OTRSessionSecurityPlaintextWithOTR: {
            messageSecurity = OTRMessageTransportSecurityPlaintextWithOTR;
            break;
        }
        case OTRSessionSecurityOTR: {
            messageSecurity = OTRMessageTransportSecurityOTR;
            break;
        }
        case OTRSessionSecurityOMEMOandOTR:
        case OTRSessionSecurityOMEMO: {
            messageSecurity = OTRMessageTransportSecurityOMEMO;
            break;
        }
        case OTRSessionSecurityBestAvailable: {
#if !TARGET_IS_EXTENSION
            messageSecurity = [self bestTransportSecurityWithTransaction:transaction];
#endif
            break;
        }
    }
    
    return messageSecurity;
}

#if !TARGET_IS_EXTENSION
- (OTRMessageTransportSecurity)bestTransportSecurityWithTransaction:(nonnull YapDatabaseReadTransaction *)transaction
{
    NSArray <OMEMODevice *>*devices = [self omemoDevicesWithTransaction:transaction];
    // If we have some omemo devices then that's the best we have.
    if ([devices count] > 0) {
        return OTRMessageTransportSecurityOMEMO;
    }
    
    OTRAccount *account = [OTRAccount fetchObjectWithUniqueID:self.accountUniqueId transaction:transaction];
    
    // Check if we have fingerprints for this buddy. This is the best proxy we have for detecting if we have had an otr session in the past.
    // If we had a session in the past then we should use that otherwise.
    NSArray<OTRFingerprint *> *allFingerprints = [OTRProtocolManager.encryptionManager.otrKit fingerprintsForUsername:self.username accountName:account.username protocol:account.protocolTypeString];
    if ([allFingerprints count]) {
        return OTRMessageTransportSecurityOTR;
    } else {
        return OTRMessageTransportSecurityPlaintextWithOTR;
    }
}
#endif

- (NSArray<OMEMODevice*>*)omemoDevicesWithTransaction:(YapDatabaseReadTransaction*)transaction {
    NSParameterAssert(transaction);
    if (!transaction) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Missing transaction for bestTransportSecurityWithTransaction!" userInfo:nil];
    }
    NSArray <OMEMODevice *>*devices = [OMEMODevice allDevicesForParentKey:self.uniqueId
                                                                     collection:[[self class] collection]
                                                                    transaction:transaction];
    return devices;
}

#pragma - mark OTRUserInfoProfile Protocol

- (UIColor *)avatarBorderColor
{
#if !TARGET_IS_EXTENSION
    OTRThreadStatus threadStatus = [self currentStatus];
    if (threadStatus == OTRThreadStatusOffline) {
        return nil;
    }
    return [OTRColors colorWithStatus:[self currentStatus]];
#else
    return nil;
#endif
}

#pragma - mark OTRThreadOwner Methods
/** New outgoing message w/ preferred message security. Unsaved! */
- (id<OTRMessageProtocol>) outgoingMessageWithText:(NSString *)text transaction:(YapDatabaseReadTransaction *)transaction {
    NSParameterAssert(text);
    NSParameterAssert(transaction);
    OTROutgoingMessage *message = [[OTROutgoingMessage alloc] init];
    message.text = text;
    message.buddyUniqueId = self.uniqueId;
    OTRMessageTransportSecurity preferredSecurity = [self preferredTransportSecurityWithTransaction:transaction];
    message.messageSecurityInfo = [[OTRMessageEncryptionInfo alloc] initWithMessageSecurity:preferredSecurity];
    return message;
}

- (NSString*) lastMessageIdentifier {
    return self.lastMessageId;
}

- (void) setLastMessageIdentifier:(NSString *)lastMessageIdentifier {
    self.lastMessageId = lastMessageIdentifier;
}

- (NSString *)threadName
{
    NSString *threadName = [self.displayName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(![threadName length]) {
        threadName = self.username;
    }
    return threadName;
}

- (NSString *)threadIdentifier {
    return self.uniqueId;
}

- (NSString *)threadAccountIdentifier {
    return self.accountUniqueId;
}

- (NSString *)threadCollection {
    return [OTRBuddy collection];
}

- (void)setCurrentMessageText:(NSString *)text
{
    self.composingMessageString = text;
}

- (NSString *)currentMessageText {
    return self.composingMessageString;
}

#if !TARGET_IS_EXTENSION
- (OTRThreadStatus)currentStatus {
    return [OTRBuddyCache.shared threadStatusForBuddy:self];
}
#endif

- (BOOL)isGroupThread {
    return NO;
}

#pragma mark Dynamic Properties
#if !TARGET_IS_EXTENSION
- (NSString*) statusMessage {
    return [OTRBuddyCache.shared statusMessageForBuddy:self];
}

- (OTRChatState) chatState {
    return [OTRBuddyCache.shared chatStateForBuddy:self];
}

- (OTRChatState) lastSentChatState {
    return [OTRBuddyCache.shared lastSentChatStateForBuddy:self];
}

- (OTRThreadStatus) status {
    return [OTRBuddyCache.shared threadStatusForBuddy:self];
}

- (BOOL) isMuted {
    if (!self.muteExpiration) {
        return NO;
    }
    if ([[NSDate date] compare:self.muteExpiration] == NSOrderedAscending) {
        return YES;
    }
    return NO;
}
#endif

#pragma - mark YapDatabaseRelationshipNode

- (NSArray *)yapDatabaseRelationshipEdges
{
    NSArray *edges = nil;
    if (self.accountUniqueId) {
        NSString *edgeName = [YapDatabaseConstants edgeName:RelationshipEdgeNameBuddyAccountEdgeName];
        YapDatabaseRelationshipEdge *accountEdge = [YapDatabaseRelationshipEdge edgeWithName:edgeName
                                                                              destinationKey:self.accountUniqueId
                                                                                  collection:[OTRAccount collection]
                                                                             nodeDeleteRules:YDB_DeleteSourceIfDestinationDeleted];
        edges = @[accountEdge];
    }
    
    
    return edges;
}

#pragma - mark Class Methods

#pragma mark Disable Mantle Storage of Dynamic Properties

+ (NSSet<NSString*>*) excludedProperties {
    static NSSet<NSString*>* excludedProperties = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        excludedProperties = [NSSet setWithArray:@[NSStringFromSelector(@selector(statusMessage)),
                               NSStringFromSelector(@selector(chatState)),
                               NSStringFromSelector(@selector(lastSentChatState)),
                               NSStringFromSelector(@selector(status))]];
    });
    return excludedProperties;
}

// See MTLModel+NSCoding.h
// This helps enforce that only the properties keys that we
// desire will be encoded. Be careful to ensure that values
// that should be stored in the keychain don't accidentally
// get serialized!
+ (NSDictionary *)encodingBehaviorsByPropertyKey {
    NSMutableDictionary *behaviors = [NSMutableDictionary dictionaryWithDictionary:[super encodingBehaviorsByPropertyKey]];
    NSSet<NSString*> *excludedProperties = [self excludedProperties];
    [excludedProperties enumerateObjectsUsingBlock:^(NSString * _Nonnull selector, BOOL * _Nonnull stop) {
        [behaviors setObject:@(MTLModelEncodingBehaviorExcluded) forKey:selector];
    }];
    return behaviors;
}

+ (MTLPropertyStorage)storageBehaviorForPropertyWithKey:(NSString *)propertyKey {
    NSSet<NSString*> *excludedProperties = [self excludedProperties];
    if ([excludedProperties containsObject:propertyKey]) {
        return MTLPropertyStorageNone;
    }
    return [super storageBehaviorForPropertyWithKey:propertyKey];
}

@synthesize expiresIn; 

@end
