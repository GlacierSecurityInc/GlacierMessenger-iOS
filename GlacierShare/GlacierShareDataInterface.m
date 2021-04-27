//
//  GlacierShareDataInterface.m
//  GlacierShare
//
//  Created by Andy Friedman on 12/15/20.
//  Copyright © 2020 Glacier. All rights reserved.
//

#import "GlacierShareDataInterface.h"
#import "OTRAccount.h"
#import "OTRXMPPAccount.h"
//#import "OTRProtocolManager.h"
#import "OTRDatabaseManager.h"
#import "OTRXMPPStream.h"
#import "GlacierShare-Swift.h"
//#import "OTRBaseMessage.h"
@import YapDatabase;
@import XMPPFramework;
@import OTRKit;

@interface GlacierShareDataInterface () <XMPPStreamDelegate, ShareMessageDelegate>

@property (nonatomic, strong, nullable) OTRXMPPStream *xmppStream;
@property (nonatomic, strong, nullable) OMEMOModule *omemoModule;
@property (nonatomic, strong, nullable) ShareOMEMOSignalCoordinator *omemoSignalCoordinator;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong, nullable) OTRAccount *acct;
@property (nonatomic, strong, readonly) DatabaseConnections *connections;
@property (assign, nonatomic) BOOL readyToShare;
@property (nonatomic, weak, readonly) id<ShareExtensionDelegate> shareDelegate;
@property (nonatomic, strong, nullable) ShareMediaManager *shareMediaManager;

@end

@implementation GlacierShareDataInterface

- (instancetype)initWithDelegate:(id<ShareExtensionDelegate>)delegate
{
    if (self = [super init]) {
        [NSKeyedUnarchiver setClass:[OTRGroupDownloadMessage class] forClassName:@"Glacier.OTRGroupDownloadMessage"];
        [NSKeyedUnarchiver setClass:[OTRXMPPRoomMessage class] forClassName:@"Glacier.OTRXMPPRoomMessage"];
        [NSKeyedUnarchiver setClass:[OTRXMPPRoomOccupant class] forClassName:@"Glacier.OTRXMPPRoomOccupant"];
        [NSKeyedUnarchiver setClass:[OTRXMPPRoom class] forClassName:@"Glacier.OTRXMPPRoom"];
        
        [NSKeyedArchiver setClassName:@"Glacier.OTRGroupDownloadMessage" forClass:[OTRGroupDownloadMessage class]];
        [NSKeyedArchiver setClassName:@"Glacier.OTRXMPPRoomMessage" forClass:[OTRXMPPRoomMessage class]];
        [NSKeyedArchiver setClassName:@"Glacier.OTRXMPPRoomOccupant" forClass:[OTRXMPPRoomOccupant class]];
        [NSKeyedArchiver setClassName:@"Glacier.OTRXMPPRoom" forClass:[OTRXMPPRoom class]];
        
        [[OTRDatabaseManager sharedInstance] setupDatabaseWithName:GlacierYapDatabaseName];
        [OTRDatabaseManager.shared.connections.write.database asyncRegisterGroupOccupantsView:nil completionBlock:nil];
        _connections = OTRDatabaseManager.shared.connections;
        _shareDelegate = delegate;
    
        [self loginAndOpenStream];
    }
    
    return self;
}

- (void) setupMediaManager {
    if (self.acct && self.xmppStream) {
        // File Transfer
        NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        
        __block NSString *uploaddomain = [GlacierInfo defaultHost];
        
        [self.connections.read readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            OTRXMPPAccount *xaccount = [OTRXMPPAccount accountForStream:self.xmppStream transaction:transaction];
            uploaddomain = xaccount.domain;
        }];
        
        self.shareMediaManager = [[ShareMediaManager alloc] initWithConnection:self.connections.write sessionConfiguration:sessionConfiguration delegate:self xmppStream:self.xmppStream uploadDomain:uploaddomain];
    }
}

- (void)dealloc
{
    //[_xmppStream disconnect];
    //[self teardownStream];
}

- (void)teardownStream
{
    if (_xmppStream) {
        [_xmppStream disconnect];
        [_xmppStream removeDelegate:self];
    }
    
    if (_omemoModule) {
        [_omemoModule removeDelegate:self.omemoSignalCoordinator];
        [_omemoModule deactivate];
    }
    
    if (self.shareMediaManager) {
        [self.shareMediaManager removeDelegates];
        [self.shareMediaManager teardownConnections];
        self.shareMediaManager = nil;
        //force wal write?
    }
    
    [[OTRDatabaseManager sharedInstance] teardownConnections];
    
    _omemoSignalCoordinator = nil;
    _omemoModule = nil;
    _xmppStream = nil;
    _connections = nil;
}

- (NSArray<Conversation*>*) getAllConversations {
    NSMutableArray <Conversation *>*convArray = [[NSMutableArray alloc] init];
    
    [self.connections.read readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        [transaction enumerateKeysAndObjectsInCollection:[OTRBuddy collection] usingBlock:^(NSString * _Nonnull key, id  _Nonnull object, BOOL * _Nonnull stop) {
            if ([object isKindOfClass:[OTRBuddy class]]) {
                OTRBuddy *buddy = (OTRBuddy *)object;
                if ([buddy hasMessagesWithTransaction:transaction]) {
                    Conversation *conv = [[Conversation alloc] init];
                    conv.key = buddy.uniqueId;
                    conv.name = buddy.displayName;
                    conv.owner = buddy;
                    [convArray addObject:conv];
                }
            }
        }];
    }];
    
    NSString *roomCollection = [[OTRXMPPRoom collection] stringByReplacingOccurrencesOfString:@"GlacierShare" withString:@"Glacier"];
    [self.connections.read readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        [transaction enumerateKeysAndObjectsInCollection:roomCollection usingBlock:^(NSString * _Nonnull key, id  _Nonnull object, BOOL * _Nonnull stop) {
            if ([object isKindOfClass:[OTRXMPPRoom class]]) {
                OTRXMPPRoom *room = (OTRXMPPRoom *)object;
                Conversation *conv = [[Conversation alloc] init];
                conv.key = room.uniqueId;
                conv.name = room.roomName;
                conv.owner = room;
                [convArray addObject:conv];
            }
        }];
    }];
    
    return convArray;
}

- (void) loginAndOpenStream {
    [[OTRDatabaseManager sharedInstance].readConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        NSArray<OTRAccount*> *accounts = [OTRAccount allAccountsWithTransaction:transaction];
        if (accounts) {
            self.acct = accounts.firstObject;
        }
    }];
    
    if (self.acct) {
        NSString * queueLabel = [NSString stringWithFormat:@"%@.work.%@",[self class],self];
        _workQueue = dispatch_queue_create([queueLabel UTF8String], 0);
        
        _xmppStream = [[OTRXMPPStream alloc] init];

        //Used to fetch correct account from XMPPStream in delegate methods especailly
        self.xmppStream.tag = self.acct.uniqueId;
        self.xmppStream.startTLSPolicy = XMPPStreamStartTLSPolicyRequired;
        [self.xmppStream addDelegate:self delegateQueue:self.workQueue];
        
        OTRXMPPAccount *xacct = (OTRXMPPAccount *)self.acct;
        XMPPJID *jid = [XMPPJID jidWithString:self.acct.username resource:xacct.resource];
        self.xmppStream.myJID = jid;
        
        NSString * domainString = xacct.domain;
        if ([domainString length]) {
            [self.xmppStream setHostName:domainString];
        }
        [self.xmppStream setHostPort:xacct.port];
        
        if (!self.omemoSignalCoordinator) {
            self.omemoSignalCoordinator = [[ShareOMEMOSignalCoordinator alloc] initWithAccountYapKey:self.acct.uniqueId databaseConnection:self.connections.write error:nil];
            self.omemoModule = [[OMEMOModule alloc] initWithOMEMOStorage:self.omemoSignalCoordinator xmlNamespace:OMEMOModuleNamespaceConversationsLegacy];
            [self.omemoModule addDelegate:self.omemoSignalCoordinator delegateQueue:self.workQueue];
            [self.omemoModule activate:self.xmppStream];
        }
        
        NSError *error = nil;
        if (![self.xmppStream connectWithTimeout:(NSTimeInterval)6 error:&error])
        {
            NSLog(@"Error connecting: %@", error);
        }
    }
}

- (void) sendMessage:(OTROutgoingMessage*)message
{
    NSParameterAssert(message);
    NSString *text = message.text;
    if (!text.length) {
        return;
    }
    __block OTRXMPPBuddy *buddy = nil;
    [[OTRDatabaseManager sharedInstance].readConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        buddy = (OTRXMPPBuddy *)[message threadOwnerWithTransaction:transaction];
    }];
    if (!buddy || ![buddy isKindOfClass:[OTRXMPPBuddy class]]) {
        return;
    }
    
    NSString * messageID = message.messageId;
    XMPPMessage * xmppMessage = [XMPPMessage messageWithType:@"chat" to:buddy.bareJID elementID:messageID];
    [xmppMessage addBody:text];
    
    //[xmppMessage addActiveChatState];
    
    [xmppMessage addMarkableChatMarker];
    
    [self.xmppStream sendElement:xmppMessage];
}

#pragma - mark XMPPStreamDelegate Methods
- (void)xmppStreamDidConnect:(XMPPStream *)sender
{
    NSError *error = nil;
    [self.xmppStream authenticateWithPassword:self.acct.password error:&error];
}

- (void)xmppStreamDidAuthenticate:(XMPPStream *)sender {
    NSLog(@"GlacierShare authenticated");
    self.readyToShare = YES;
}

- (void) doShare:(NSString *)text withOwner:(id<OTRThreadOwner>)owner {
    if (!self.readyToShare) {
        [self finishedSharing:NO];
        return;
    }
        //[[OTRDatabaseManager sharedInstance] setCanSortDataView:YES];
    __block id<OTRMessageProtocol> message;
        
    [self.connections.read readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        message = [owner outgoingMessageWithText:text transaction:transaction];
    }];
    
    message.messageSecurityInfo = [[OTRMessageEncryptionInfo alloc] initWithMessageSecurity:OTRMessageTransportSecurityOMEMO];
    message.messageSecurity = OTRMessageTransportSecurityOMEMO;
        
    if (message == nil) {
        [self finishedSharing:NO];
        return;
    } else {
        [self.connections.write readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            [message saveWithTransaction:transaction];
            
            if ([owner isKindOfClass:[OTRXMPPRoom class]]) {
                OTRXMPPRoom *roomie = (OTRXMPPRoom *)owner;
                [roomie saveWithTransaction:transaction];
            } else if ([owner isKindOfClass:[OTRBuddy class]]) {
                OTRBuddy *buddy = (OTRBuddy *)owner;
                [buddy saveWithTransaction:transaction];
            }
        }];
    }
        
    [self doShare:message];
}

- (void) doShare:(NSURL *)url withOwner:(id<OTRThreadOwner>)owner withType:(NSInteger)mediaType {
    if (self.shareMediaManager && mediaType == MediaURLTypeImage) {
        
        //get image from new method
        CGSize newSize = CGSizeMake(1000, 1000);
        UIImage* image = [self.shareMediaManager compressImage:url to:newSize scale:0.5];
        [self.shareMediaManager sendWithImage:image thread:owner];
    } else {
        [self finishedSharing:NO];
    }
}

//message: OTRMessageProtocol
- (void)doShare:(id<OTRMessageProtocol>)message {
    if (message == nil) {
        [self finishedSharing:NO];
    }
    
    if (self.readyToShare) {
        [self.omemoSignalCoordinator encryptAndSendMessage:message completion:^(BOOL success, NSError * error) {
            if (!success) {
                [self finishedSharing:success];
            } else {
                [self.connections.write asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
                    
                    if ([message isKindOfClass:[OTROutgoingMessage class]]) {
                        OTROutgoingMessage *msg = (OTROutgoingMessage *)message;
                        msg.dateSent = [NSDate date];
                        msg.readDate = [NSDate date];
                        [msg saveWithTransaction:transaction];
                    } else if ([message isKindOfClass:[OTRXMPPRoomMessage class]]){
                        OTRXMPPRoomMessage *msg = (OTRXMPPRoomMessage *)message;
                        msg.state = RoomMessageStateSent;
                        [msg saveWithTransaction:transaction];
                    }
                    
                    id<OTRThreadOwner> thread = [message threadOwnerWithTransaction:transaction];
                    if (thread) {
                        thread.currentMessageText = nil;
                        thread.lastMessageIdentifier = message.uniqueId;
                        //thread.lastMessageIdentifier = message.messageKey;
                        [thread saveWithTransaction:transaction];
                    }
                } completionBlock:^{
                    [self finishedSharing:success];
                }];
            }
        }];
    } else {
        [self finishedSharing:NO];
    }
}

- (void) finishedSharing:(BOOL)success {
    //[self teardownStream];
    if (self.shareDelegate != nil) {
        [self.shareDelegate doneSending:success];
    }
}

- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)xmppMessage
{
    //
}

- (void)xmppStream:(XMPPStream *)sender didReceiveError:(id)error
{
    NSLog(@"Glacier Share Stream Error: %@", error);
}

@end

