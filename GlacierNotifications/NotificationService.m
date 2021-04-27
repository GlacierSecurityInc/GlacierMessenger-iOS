//
//  NotificationService.m
//  GlacierNotifications
//
//  Created by Andy Friedman on 9/21/20.
//  Copyright © 2020 Glacier. All rights reserved.
//

#import "NotificationService.h"
#import "OTRAccount.h"
#import "OTRXMPPAccount.h"
#import "OTRProtocolManager.h"
//#import "NotificationDatabaseManager.h"
#import "OTRDatabaseManager.h"
#import "OTRXMPPStream.h"
#import "GlacierNotifications-Swift.h"
@import YapDatabase;
@import XMPPFramework;
@import OTRKit;

@interface NotificationService () <NotificationMessageDelegate, XMPPStreamDelegate>

@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent *contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent *bestAttemptContent;
@property (nonatomic, strong, nullable) OTRXMPPStream *xmppStream;
@property (nonatomic, strong, nullable) OMEMOModule *omemoModule;
//@property (nonatomic, strong, nullable) XMPPMessageArchiveManagement *archiving;
@property (nonatomic, strong, nullable) NotificationOMEMOSignalCoordinator *omemoSignalCoordinator;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong, nullable) OTRAccount *acct;
//@property (nonatomic, strong, nullable) OTRDatabaseManager *dbmgr;
@property (nonatomic, strong, readonly) DatabaseConnections *connections;
@property (nonatomic, assign) BOOL msgDecrypted;

@end

@implementation NotificationService

- (instancetype)init
{
    if (self = [super init])
    {
        if (![OTRDatabaseManager isSharedInstanceInitialized]) {
            [[OTRDatabaseManager sharedInstance] setupDatabaseWithName:GlacierYapDatabaseName];
            [OTRDatabaseManager.shared.connections.write.database asyncRegisterGroupOccupantsView:nil completionBlock:nil];
        } else {
            [[OTRDatabaseManager sharedInstance] setupConnections];
        }
        _connections = OTRDatabaseManager.shared.connections;
    }
    return self;
}

- (void)dealloc
{
    [self teardownStream];
}

- (void)teardownStream
{
    [_xmppStream disconnect];
    
    [_xmppStream removeDelegate:self];
    [_omemoModule removeDelegate:self.omemoSignalCoordinator];
    
    [_omemoModule deactivate];
    
    _omemoSignalCoordinator = nil;
    _omemoModule = nil;
    _xmppStream = nil;
    _connections = nil;
    [[OTRDatabaseManager sharedInstance] teardownConnections];
}

- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent * _Nonnull))contentHandler {
    self.contentHandler = contentHandler;
    self.bestAttemptContent = [request.content mutableCopy];
    //NSLog(@"NotificationService didReceiveNotificationRequest %@", self.bestAttemptContent.body);
    
    [self loginAndOpenStream];
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
            self.omemoSignalCoordinator = [[NotificationOMEMOSignalCoordinator alloc] initWithAccountYapKey:self.acct.uniqueId databaseConnection:self.connections.write notificationDelegate:self error:nil];
            self.omemoModule = [[OMEMOModule alloc] initWithOMEMOStorage:self.omemoSignalCoordinator xmlNamespace:OMEMOModuleNamespaceConversationsLegacy];
            [self.omemoModule addDelegate:self.omemoSignalCoordinator delegateQueue:self.workQueue];
            [self.omemoModule activate:self.xmppStream];
        }
        
        NSError *error = nil;
        if (![self.xmppStream connectWithTimeout:(NSTimeInterval)6 error:&error])
        {
            NSLog(@"Error connecting: %@", error);
            NotificationMessage *msg = [[NotificationMessage alloc] init];
            [self failedToDecryptMessage:msg];
        }
    } else {
        self.contentHandler(self.bestAttemptContent);
    }
}

#pragma - mark XMPPStreamDelegate Methods
- (void)xmppStreamDidConnect:(XMPPStream *)sender
{
    NSError *error = nil;
    [self.xmppStream authenticateWithPassword:self.acct.password error:&error];
}

- (void)xmppStreamDidAuthenticate:(XMPPStream *)sender {
    //NSLog(@"NotificationService authenticated requesting archive");
    [self requestArchive];
}

- (void) requestArchive{
    NSDate *dateToFetch = [[NSDate date] dateByAddingTimeInterval:-30]; //30 seconds
    NSXMLElement *startElement = [XMPPMessageArchiveManagement fieldWithVar:@"start" type:nil andValue:dateToFetch.xmppDateTimeString];
    NSArray *fields  = @[startElement];
    
    NSXMLElement *formElement = [NSXMLElement elementWithName:@"x" xmlns:@"jabber:x:data"];
    [formElement addAttributeWithName:@"type" stringValue:@"submit"];
    [formElement addChild:[XMPPMessageArchiveManagement fieldWithVar:@"FORM_TYPE" type:@"hidden" andValue:XMLNS_XMPP_MAM]];
    
    for (NSXMLElement *field in fields) {
        [formElement addChild:field];
    }
    
    XMPPIQ *iq = [XMPPIQ iqWithType:@"set"];
    [iq addAttributeWithName:@"id" stringValue:[XMPPStream generateUUID]];
    [iq addAttributeWithName:@"to" stringValue:self.xmppStream.myJID.bareJID.full];

    NSString *queryId = [XMPPStream generateUUID];
    NSXMLElement *queryElement = [NSXMLElement elementWithName:@"query" xmlns:XMLNS_XMPP_MAM];
    [queryElement addAttributeWithName:@"queryid" stringValue:queryId];
    [iq addChild:queryElement];

    [queryElement addChild:formElement];
    
    self.msgDecrypted = NO;
    [self.xmppStream sendElement:iq];
}

- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)xmppMessage
{
    XMPPJID *myJID = sender.myJID;
    if (!myJID) { return; }
    NSXMLElement *mamResult = xmppMessage.mamResult;
    if (!mamResult) { return; }
    XMPPMessage *mam = mamResult.forwardedMessage;
    BOOL isIncoming = [mam.to isEqualToJID:myJID options:XMPPJIDCompareBare];
    XMPPJID *forJID = nil;
    if (isIncoming) {
        forJID = mam.from;
    } else {
        forJID = mam.to;
    }
    
    if (!forJID) {
        return;
    }
    
    NSXMLElement *offlinemsg = [mam omemo_offlineElement];
    if (offlinemsg) {
        XMPPMessage *offmsg = [XMPPMessage messageFromElement:offlinemsg];
        NSXMLElement *omemo = [offmsg omemo_encryptedElement:OMEMOModuleNamespaceConversationsLegacy];
        if (!omemo)
        {
            [self.omemoSignalCoordinator processUnencryptedData:isIncoming message:offmsg forJID:forJID];
        }
    }
}

- (void)xmppStream:(XMPPStream *)sender didReceiveError:(id)error
{
    NSLog(@"NotificationService Stream Error: %@", error);
}


#pragma - mark NotificationMessageDelegate method
- (void)decryptedMessage:(NotificationMessage *)message {
    //NSLog(@"NotificationService decryptedMessage %@", message);
    self.msgDecrypted = YES;
    
    if (message.from != nil) {
        self.bestAttemptContent.title = message.from;
        self.bestAttemptContent.body = message.message;
    } else {
        self.bestAttemptContent.title = message.message;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.contentHandler(self.bestAttemptContent);
    });
}

- (void)failedToDecryptMessage:(NotificationMessage *)message {
    NSLog(@"NotificationService failedToDecryptMessage");
    if (self.msgDecrypted) {return;}
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.msgDecrypted) {
            if (message != nil && message.from != nil) {
                self.bestAttemptContent.title = message.from;
                self.bestAttemptContent.body = @"New message";
            }
            self.contentHandler(self.bestAttemptContent);
        }
    });
}

- (void)serviceExtensionTimeWillExpire {
    NSLog(@"NotificationService serviceExtensionTimeWillExpire %@", self.bestAttemptContent.body);
    // Called just before the extension will be terminated by the system.
    // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
    self.contentHandler(self.bestAttemptContent);
}

@end
