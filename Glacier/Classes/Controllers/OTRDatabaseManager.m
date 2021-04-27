//
//  OTRDatabaseManager.m
//  Off the Record
//
//  Created by Christopher Ballinger on 10/17/13.
//  Copyright (c) 2013 Chris Ballinger. All rights reserved.
//

#import "OTRDatabaseManager.h"

//#import "OTREncryptionManager.h"
#import "OTRLog.h"
#import "OTRDatabaseView.h"
@import SAMKeychain;
#import "OTRConstants.h"
#import "OTRXMPPAccount.h"
#import "OTRAccount.h"
#import "OTRSignalSession.h"
//#import "OTRIncomingMessage.h"
//#import "OTROutgoingMessage.h"
#import "NSFileManager+ChatSecure.h"
#if !TARGET_IS_EXTENSION
#import "OTRMediaFileManager.h"
#import "OTRSettingsManager.h"
#import "OTRXMPPPresenceSubscriptionRequest.h"
#import "Glacier-Swift.h"
@import IOCipher;
#elif TARGET_IS_NOTIFICATION
#import "GlacierNotifications-Swift.h"
#elif TARGET_IS_SHARE
#import "OTRMediaFileManager.h"
#import "GlacierShare-Swift.h"
#endif

@import YapDatabase;
@import YapTaskQueue;


@interface OTRDatabaseManager ()

@property (nonatomic, strong, nullable) YapDatabase *database;
@property (nonatomic, strong, nullable) YapDatabaseActionManager *actionManager;
@property (nonatomic, strong, nullable) NSString *inMemoryPassphrase;

@property (nonatomic, strong) id yapDatabaseNotificationToken;
@property (nonatomic, strong) id yapExternalDatabaseNotificationToken;
@property (nonatomic, strong) id allowPassphraseBackupNotificationToken;

@property (nonatomic, readonly, nullable) YapTaskQueueBroker *messageQueueBroker;

@property (assign, nonatomic) BOOL canSortDatabaseView;

@end

@implementation OTRDatabaseManager

const NSUInteger kSqliteHeaderLength = 32;

- (instancetype)init
{
    self = [super init];

    return self;
}

- (BOOL) setupDatabaseWithName:(NSString*)databaseName {
    return [self setupDatabaseWithName:databaseName withMediaStorage:YES];
}

- (BOOL) setupDatabaseWithName:(NSString*)databaseName withMediaStorage:(BOOL)withMediaStorage {
    return [self setupDatabaseWithName:databaseName directory:nil withMediaStorage:withMediaStorage];
}

- (BOOL)setupDatabaseWithName:(NSString*)databaseName
                    directory:(nullable NSString*)directory
             withMediaStorage:(BOOL)withMediaStorage {
    BOOL success = NO;
    if ([self setupYapDatabaseWithName:databaseName directory:directory] )
    {
        success = YES;
    }

#if !TARGET_IS_NOTIFICATION
    if (success && withMediaStorage) success = [self setupSharedSecureMediaStorage];
#endif
    
#if !TARGET_IS_EXTENSION
    //Enumerate all files in yap database directory and exclude from backup
    if (success) success = [[NSFileManager defaultManager] otr_excludeFromBackUpFilesInDirectory:self.databaseDirectory];
    //fix file protection on existing files
    if (success) success = [[NSFileManager defaultManager] otr_setFileProtection:NSFileProtectionCompleteUntilFirstUserAuthentication forFilesInDirectory:self.databaseDirectory];
    
    [self resetMediaPasswords];
#endif

    return success;
}

//TODO remove this
- (void) resetMediaPasswords {
    NSError *error = nil;
    NSString *password = [SAMKeychain passwordForService:kOTRServiceName account:OTRYapDatabasePassphraseAccountName accessGroup:kGlacierKeyGroup error:&error];
    if (password == nil) {
        password = [self databasePassphrase];
        if (password != nil) {
            BOOL result = [SAMKeychain deletePasswordForService:kOTRServiceName account:OTRYapDatabasePassphraseAccountName];
            [self setDatabasePassphrase:password remember:YES error:&error];
        }
    }
    
    NSError *saltError = nil;
    NSData *saltData = [SAMKeychain passwordDataForService:kGlacierMediaSalt account:OTRYapDatabasePassphraseAccountName accessGroup:kGlacierKeyGroup error:nil];
    if (saltData == nil) {
        saltData = [self databaseSalt];
        if (saltData != nil) {
            BOOL result = [SAMKeychain deletePasswordForService:kGlacierMediaSalt account:OTRYapDatabasePassphraseAccountName];
            [self setMediaDatabaseSalt:saltData error:&saltError];
        }
    }
}

- (void)clearYapDatabase {
    
    [self.writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        [transaction removeAllObjectsInAllCollections];
    }];
}

- (void)dealloc {
    if (self.yapDatabaseNotificationToken != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.yapDatabaseNotificationToken];
    }
    if (self.yapExternalDatabaseNotificationToken != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.yapExternalDatabaseNotificationToken];
    }
    if (self.allowPassphraseBackupNotificationToken != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.allowPassphraseBackupNotificationToken];
    }
}

#if !TARGET_IS_NOTIFICATION
- (BOOL)setupSharedSecureMediaStorage
{
    NSString *password = [self databasePassphrase];
    NSString *path = self.databaseDirectory;
    NSData *saltData = [self mediaDatabaseSalt];
    if (saltData == nil) {
        saltData = [self databaseSalt];
    }
    
    NSString *salt = [NSString stringWithFormat:@"\"x'%@'\";", [YapDatabaseCryptoUtils hexadecimalStringForData:saltData]];
    path = [path stringByAppendingPathComponent:GlacierMediaDatabaseName];
    
    BOOL success = [[OTRMediaFileManager sharedInstance] setupWithPath:path password:password salt:salt];
    
#if !TARGET_IS_SHARE
    self.mediaServer = [OTRMediaServer sharedInstance];
    NSError *error = nil;
    BOOL mediaServerStarted = [self.mediaServer startOnPort:0 error:&error];
    if (!mediaServerStarted) {
        DDLogError(@"Error starting media server: %@",error);
    }
#endif
    return success;
}

- (void)resetMediaDB
{
    [self setupSharedSecureMediaStorage];
}
#endif

- (BOOL)setupYapDatabaseWithName:(NSString *)name directory:(nullable NSString*)directory
{
    YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
    options.corruptAction = YapDatabaseCorruptAction_Fail;
    options.cipherCompatability = YapDatabaseCipherCompatability_Version3;
    
    _databaseDirectory = [directory copy];
    
    if (!_databaseDirectory) {
        _databaseDirectory = [[self class] sharedDefaultYapDatabaseDirectory];
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.databaseDirectory]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:self.databaseDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSString *databasePath = [self.databaseDirectory stringByAppendingPathComponent:name];
    //if old exists and new doesn't, migrate
    
#if !TARGET_IS_EXTENSION
    if ([OTRDatabaseManager existsYapDatabase] && ![OTRDatabaseManager existsSharedYapDatabase]) {
        NSString *defaultDir = [[self class] defaultYapDatabaseDirectory];
        
        //copy all associated files to shared space
        NSFileManager *fileManager = [NSFileManager defaultManager];
        __block BOOL success = YES;
        [fileManager otr_enumerateFilesInDirectory:defaultDir block:^(NSString *fullPath, BOOL *stop) {
            NSURL *url = [NSURL fileURLWithPath:fullPath];
            NSString *lastpart = url.lastPathComponent;
            if ([lastpart containsString:@"sqlite"]) {
                NSString *filename = [url.lastPathComponent stringByReplacingOccurrencesOfString:@"ChatSecure" withString:@"Glacier"];
                NSString *newpath = [self.databaseDirectory stringByAppendingPathComponent:filename];
                NSError *error;
                if ([fileManager copyItemAtPath:fullPath toPath:newpath error:&error]){
                    NSLog(@"Copy Success");
                } else {
                    NSLog(@"Copy error: %@", error);
                    success = NO;
                }
            }
        }];
        
        if (success) {
            YapDatabaseSaltBlock saltBlock = ^(NSData *saltData){
                NSError *salterror = nil;
                [self setDatabaseSalt:saltData error:&salterror];
            };
            
            YapDatabaseKeySpecBlock keySpecBlock = ^(NSData *keySpecData){
                NSError *salterror = nil;
                [self setDatabaseKeySpec:keySpecData error:&salterror];
            };
            
            NSString *passphrase = [self databasePassphrase];
            NSData *passData = [passphrase dataUsingEncoding:NSUTF8StringEncoding];
            NSError *convertError = nil;
            // EVIDENCE-OF: R-43737-39999 Every valid SQLite database file begins
            // with the following 16 bytes (in hex): 53 51 4c 69 74 65 20 66 6f 72 6d
            // 61 74 20 33 00.
            convertError = [YapDatabaseCryptoUtils convertDatabaseIfNecessary:[OTRDatabaseManager sharedDefaultYapDatabasePathWithName:GlacierYapDatabaseName] databasePassword:passData saltBlock:saltBlock keySpecBlock:keySpecBlock];
            if (convertError) {
                NSLog(@"Convert error: %@", convertError);
                return NO; //i think this is a fail?
            }
            
            IOCipherSaltBlock msaltBlock = ^(NSData *msaltData){
                NSError *msalterror = nil;
                [self setMediaDatabaseSalt:msaltData error:&msalterror];
            };
            NSError *convertMediaError = nil;
            convertMediaError = [IOCipher convertDatabaseIfNecessary:[OTRDatabaseManager sharedDefaultYapDatabasePathWithName:GlacierMediaDatabaseName] databasePassword:passphrase saltBlock:msaltBlock];
            if (convertMediaError) {
                NSLog(@"Convert media error: %@", convertMediaError);
                return NO; //i think this is a fail?
            }
            
            [self outWithTheOld];
        } else {
            return NO;
        }
    }
#endif
    
    options.cipherKeySpecBlock = ^{
        NSData *keyspec = [self databaseKeySpec];
        if (!keyspec.length) {
            [NSException raise:@"Must have keyspec length > 0" format:@"keyspec length is %d.", (int)keyspec.length];
        }
        
        return keyspec;
    };
    
    options.cipherUnencryptedHeaderLength = kSqliteHeaderLength;
    options.enableMultiProcessSupport = YES;
    
    self.database = [[YapDatabase alloc] initWithURL:[NSURL fileURLWithPath:databasePath] options:options];
    
    // Stop trying to setup up the database. Something went wrong. Most likely the password is incorrect.
    if (self.database == nil) {
        return NO;
    }
    
    self.database.connectionDefaults.objectCacheLimit = 10000;
    
    [self setupConnections];
    
    __weak __typeof__(self) weakSelf = self;
    self.yapDatabaseNotificationToken = [[NSNotificationCenter defaultCenter] addObserverForName:YapDatabaseModifiedNotification object:self.database queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        NSArray <NSNotification *>*changes = [weakSelf.longLivedReadOnlyConnection beginLongLivedReadTransaction];
        if (changes != nil) {
            [[NSNotificationCenter defaultCenter] postNotificationName:[DatabaseNotificationName LongLivedTransactionChanges]
                                                                    object:weakSelf.longLivedReadOnlyConnection
                                                                  userInfo:@{[DatabaseNotificationKey ConnectionChanges]:changes}];
        }
            
    }];
    
    self.yapExternalDatabaseNotificationToken = [[NSNotificationCenter defaultCenter] addObserverForName:YapDatabaseModifiedExternallyNotification object:self.database queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        NSArray <NSNotification *>*changes = [weakSelf.longLivedReadOnlyConnection beginLongLivedReadTransaction];
        if (changes != nil) {
            [[NSNotificationCenter defaultCenter] postNotificationName:[DatabaseNotificationName LongLivedExternalTransactionChanges] object:weakSelf.longLivedReadOnlyConnection userInfo:@{[DatabaseNotificationKey ConnectionChanges]:changes}];
            [[NSNotificationCenter defaultCenter] postNotificationName:[DatabaseNotificationName LongLivedTransactionChanges] object:weakSelf.longLivedReadOnlyConnection
                    userInfo:@{[DatabaseNotificationKey ConnectionChanges]:changes}];
        }
            
    }];
    
    [self.longLivedReadOnlyConnection beginLongLivedReadTransaction];

    _messageQueueHandler = [[MessageQueueHandler alloc] initWithDbConnection:self.writeConnection];
        
        ////// Register Extensions////////
        
    //Async register all the views
    dispatch_block_t registerExtensions = ^{
        // Register realtionship extension
        YapDatabaseRelationship *databaseRelationship = [[YapDatabaseRelationship alloc] initWithVersionTag:@"1"];
            
        [self.database registerExtension:databaseRelationship withName:[YapDatabaseConstants extensionName:DatabaseExtensionNameRelationshipExtensionName]];
        
        YapDatabaseCrossProcessNotification* cpn = [[YapDatabaseCrossProcessNotification alloc] initWithIdentifier:@"crossnotification"];
        [self.database registerExtension:cpn withName:@"crossprocess"];
            
        // Register Secondary Indexes
        YapDatabaseSecondaryIndex *signalIndex = YapDatabaseSecondaryIndex.signalIndex;
        [self.database registerExtension:signalIndex withName:SecondaryIndexName.signal];
        YapDatabaseSecondaryIndex *messageIndex = YapDatabaseSecondaryIndex.messageIndex;
        [self.database registerExtension:messageIndex withName:SecondaryIndexName.messages];
        YapDatabaseSecondaryIndex *roomOccupantIndex = YapDatabaseSecondaryIndex.roomOccupantIndex;
        [self.database registerExtension:roomOccupantIndex withName:SecondaryIndexName.roomOccupants];
        YapDatabaseSecondaryIndex *buddyIndex = YapDatabaseSecondaryIndex.buddyIndex;
        [self.database registerExtension:buddyIndex withName:SecondaryIndexName.buddy];
        YapDatabaseSecondaryIndex *mediaItemIndex = YapDatabaseSecondaryIndex.mediaItemIndex;
        [self.database registerExtension:mediaItemIndex withName:SecondaryIndexName.mediaItems];

        // Register action manager
        self.actionManager = [[YapDatabaseActionManager alloc] init];
        NSString *actionManagerName = [YapDatabaseConstants extensionName:DatabaseExtensionNameActionManagerName];
        [self.database registerExtension:self.actionManager withName:actionManagerName];
            
        [OTRDatabaseView registerAllAccountsDatabaseViewWithDatabase:self.database];
        [OTRDatabaseView registerChatDatabaseViewWithDatabase:self.database];
        // Order is important - the conversation database view uses the lastMessageWithTransaction: method which in turn uses the OTRFilteredChatDatabaseViewExtensionName view registered above.
        [OTRDatabaseView registerConversationDatabaseViewWithDatabase:self.database];
        [OTRDatabaseView registerAllBuddiesDatabaseViewWithDatabase:self.database];
            
        NSString *name = [YapDatabaseConstants extensionName:DatabaseExtensionNameMessageQueueBrokerViewName];
        self->_messageQueueBroker = [YapTaskQueueBroker setupWithDatabase:self.database name:name handler:self.messageQueueHandler error:nil];
            
        //Register Buddy username & displayName FTS and corresponding view
        YapDatabaseFullTextSearch *buddyFTS = [OTRYapExtensions buddyFTS];
        NSString *FTSName = [YapDatabaseConstants extensionName:DatabaseExtensionNameBuddyFTSExtensionName];
        NSString *AllBuddiesName = OTRAllBuddiesDatabaseViewExtensionName;
        [self.database registerExtension:buddyFTS withName:FTSName];
        YapDatabaseSearchResultsView *searchResultsView = [[YapDatabaseSearchResultsView alloc] initWithFullTextSearchName:FTSName parentViewName:AllBuddiesName versionTag:nil options:nil];
        NSString* viewName = [YapDatabaseConstants extensionName:DatabaseExtensionNameBuddySearchResultsViewName];
        [self.database registerExtension:searchResultsView withName:viewName];
#if !TARGET_IS_EXTENSION
        // Remove old unused objects
        [self.writeConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            [transaction removeAllObjectsInCollection:OTRXMPPPresenceSubscriptionRequest.collection];
        }];
#endif
    };
        
    #if DEBUG
        NSDictionary *environment = [[NSProcessInfo processInfo] environment];
        // This can make it easier when writing tests
        if (environment[@"SYNC_DB_STARTUP"]) {
            registerExtensions();
        } else {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), registerExtensions);
        }
    #else
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), registerExtensions);
    #endif
        
        
    if (self.database != nil) {
        return YES;
    }
    else {
        return NO;
    }
}

#if !TARGET_IS_EXTENSION
- (void) outWithTheOld {
    YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
    options.corruptAction = YapDatabaseCorruptAction_Fail;
    options.cipherKeyBlock = ^{
        NSString *passphrase = [self databasePassphrase];
        NSData *keyData = [passphrase dataUsingEncoding:NSUTF8StringEncoding];
        if (!keyData.length) {
            [NSException raise:@"Must have passphrase of length > 0" format:@"password length is %d.", (int)keyData.length];
        }
        return keyData;
    };
    options.cipherCompatability = YapDatabaseCipherCompatability_Version3;
    
    //delete old database
    NSString *defaultDir = [[self class] defaultYapDatabaseDirectory];
    NSString *oldDatabasePath = [defaultDir stringByAppendingPathComponent:OTRYapDatabaseName];
    YapDatabase *olddatabase = [[YapDatabase alloc] initWithURL:[NSURL fileURLWithPath:oldDatabasePath] options:options];
    YapDatabaseConnection *oldWriteConnection = [olddatabase newConnection];
    [oldWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        [transaction removeAllObjectsInAllCollections];
    }];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager otr_enumerateFilesInDirectory:defaultDir block:^(NSString *fullPath, BOOL *stop) {
        NSURL *url = [NSURL fileURLWithPath:fullPath];
        NSString *lastpart = url.lastPathComponent;
        if ([lastpart containsString:@"sqlite"]) {
            NSError *error;
            if ([fileManager removeItemAtPath:fullPath error:&error]){
                NSLog(@"Delete Success");
            } else {
                NSLog(@"Delete error: %@", error);
            }
        }
    }];
}
#endif

- (void) setupConnections {
    _uiConnection = [self.database newConnection];
    self.uiConnection.name = @"uiConnection";
    
    _readConnection = [self.database newConnection];
    self.readConnection.name = @"readConnection";
    
    _writeConnection = [self.database newConnection];
    self.writeConnection.name = @"writeConnection";
    
    _longLivedReadOnlyConnection = [self.database newConnection];
    self.longLivedReadOnlyConnection.name = @"LongLivedReadOnlyConnection";
    
#if DEBUG
    self.uiConnection.permittedTransactions = YDB_SyncReadTransaction | YDB_MainThreadOnly;
    self.readConnection.permittedTransactions = YDB_AnyReadTransaction;
    // TODO: We can do better work at isolating work between connections
    //self.writeConnection.permittedTransactions = YDB_AnyReadWriteTransaction;
    self.longLivedReadOnlyConnection.permittedTransactions = YDB_AnyReadTransaction; // | YDB_MainThreadOnly;
#endif
}

- (void) teardownConnections {
    _uiConnection = nil;
    _readConnection = nil;
    _writeConnection = nil;
    _longLivedReadOnlyConnection = nil;
    
#if TARGET_IS_SHARE
    [[OTRMediaFileManager sharedInstance] releaseDBConnection];
    //maybe close, reopen, and close db too to force sync
    [self setupSharedSecureMediaStorage];
    [[OTRMediaFileManager sharedInstance] releaseDBConnection];
    
    [_database tryToCheckpoint];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self->_database quietlyResetInstance];
        self->_database = nil;
    });
#endif
}

- (YapDatabaseConnection *)newConnection
{
    return [self.database newConnection];
}

+ (NSString *)defaultYapDatabaseDirectory {
    NSString *applicationSupportDirectory = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject];
    NSString *applicationName = [[[NSBundle mainBundle] infoDictionary] valueForKey:(NSString *)kCFBundleNameKey];
    NSString *directory = [applicationSupportDirectory stringByAppendingPathComponent:applicationName];
    return directory;
}

+ (NSString *)defaultYapDatabasePathWithName:(NSString *)name
{
    return [[self defaultYapDatabaseDirectory] stringByAppendingPathComponent:name];
}

+ (BOOL)existsYapDatabase
{
    return [[NSFileManager defaultManager] fileExistsAtPath:[self defaultYapDatabasePathWithName:OTRYapDatabaseName]];
}

+ (NSString *)sharedDefaultYapDatabaseDirectory {
    NSURL *groupUrl = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:kGlacierGroup];
    NSString *groupDirectory = [groupUrl path];
    NSString *applicationName = @"Glacier"; //Hard coded due to Extension (GlacierNotification)
    //NSString *applicationName = [[[NSBundle mainBundle] infoDictionary] valueForKey:(NSString *)kCFBundleNameKey]; //Glacier
    NSString *directory = [groupDirectory stringByAppendingPathComponent:applicationName];
    return directory;
}

+ (NSString *)sharedDefaultYapDatabasePathWithName:(NSString *)name
{
    return [[self sharedDefaultYapDatabaseDirectory] stringByAppendingPathComponent:name];
}

+ (BOOL)existsSharedYapDatabase
{
    return [[NSFileManager defaultManager] fileExistsAtPath:[self sharedDefaultYapDatabasePathWithName:GlacierYapDatabaseName]];
}


- (void) setDatabasePassphrase:(NSString *)passphrase remember:(BOOL)rememeber error:(NSError**)error
{
    if (rememeber) {
        self.inMemoryPassphrase = nil;
        [SAMKeychain setPassword:passphrase forService:kOTRServiceName account:OTRYapDatabasePassphraseAccountName accessGroup:kGlacierKeyGroup error:error];
    } else {
        [SAMKeychain deletePasswordForService:kOTRServiceName account:OTRYapDatabasePassphraseAccountName];
        self.inMemoryPassphrase = passphrase;
    }
}

- (BOOL)hasPassphrase
{
    return [self databasePassphrase].length != 0;
}

- (NSString *)databasePassphrase
{
    if (self.inMemoryPassphrase) {
        return self.inMemoryPassphrase;
    }
    else {
        NSString *pass = [SAMKeychain passwordForService:kOTRServiceName account:OTRYapDatabasePassphraseAccountName accessGroup:kGlacierKeyGroup error:nil];
        if (pass == nil) {
            pass = [SAMKeychain passwordForService:kOTRServiceName account:OTRYapDatabasePassphraseAccountName];
        }
        return pass;
    }
    
}

- (void) setDatabaseSalt:(NSData *)salt error:(NSError**)error
{
    [SAMKeychain setPasswordData:salt forService:kGlacierSalt account:OTRYapDatabasePassphraseAccountName accessGroup:kGlacierKeyGroup error:error];
    
    //clear existing media salt
    [SAMKeychain deletePasswordForService:kGlacierMediaSalt account:OTRYapDatabasePassphraseAccountName];
    
    //if we have password and salt, set the keyspec
    NSString *passphrase = [self databasePassphrase];
    if (passphrase != nil) {
        NSData *keyData = [passphrase dataUsingEncoding:NSUTF8StringEncoding];
        NSData *keyspec = [YapDatabaseCryptoUtils databaseKeySpecForPassword:keyData saltData:salt];
        
        NSError *error = nil;
        [self setDatabaseKeySpec:keyspec error:&error];
        if (error) {
            DDLogError(@"Keyspec Error: %@",error);
        }
    }
}

- (NSData *)databaseSalt
{
    NSData *salt = [SAMKeychain passwordDataForService:kGlacierSalt account:OTRYapDatabasePassphraseAccountName accessGroup:kGlacierKeyGroup error:nil];
    if (salt == nil) {
        salt = [SAMKeychain passwordDataForService:kGlacierSalt account:OTRYapDatabasePassphraseAccountName];
    }
    
    return salt;
}

- (void) setDatabaseKeySpec:(NSData *)keyspec error:(NSError**)error
{
    [SAMKeychain setPasswordData:keyspec forService:kGlacierKeySpec account:OTRYapDatabasePassphraseAccountName accessGroup:kGlacierKeyGroup error:error];
}

- (NSData *)databaseKeySpec
{
    NSData *keyspec = [SAMKeychain passwordDataForService:kGlacierKeySpec account:OTRYapDatabasePassphraseAccountName accessGroup:kGlacierKeyGroup error:nil];
    if (keyspec == nil) {
        keyspec = [SAMKeychain passwordDataForService:kGlacierKeySpec account:OTRYapDatabasePassphraseAccountName];
    }
    
    return keyspec;
}

- (void) setMediaDatabaseSalt:(NSData *)salt error:(NSError**)error
{
    [SAMKeychain setPasswordData:salt forService:kGlacierMediaSalt account:OTRYapDatabasePassphraseAccountName accessGroup:kGlacierKeyGroup error:error];
    
    //if we have password and salt, set the keyspec
    NSString *passphrase = [self databasePassphrase];
    if (passphrase != nil) {
        NSData *keyData = [passphrase dataUsingEncoding:NSUTF8StringEncoding];
        NSData *keyspec = [YapDatabaseCryptoUtils databaseKeySpecForPassword:keyData saltData:salt];
        
        NSError *error = nil;
        [self setMediaDatabaseKeySpec:keyspec error:&error];
        if (error) {
            DDLogError(@"Keyspec Error: %@",error);
        }
    }
}

- (NSData *)mediaDatabaseSalt
{
    NSData *salt = [SAMKeychain passwordDataForService:kGlacierMediaSalt account:OTRYapDatabasePassphraseAccountName accessGroup:kGlacierKeyGroup error:nil];
    if (salt == nil) {
        salt = [SAMKeychain passwordDataForService:kGlacierMediaSalt account:OTRYapDatabasePassphraseAccountName];
    }
    
    return salt;
}

- (void) setMediaDatabaseKeySpec:(NSData *)keyspec error:(NSError**)error
{
    [SAMKeychain setPasswordData:keyspec forService:kGlacierMediaKeySpec account:OTRYapDatabasePassphraseAccountName accessGroup:kGlacierKeyGroup error:error];
}

- (NSData *)mediaDatabaseKeySpec
{
    NSData *keyspec = [SAMKeychain passwordDataForService:kGlacierMediaKeySpec account:OTRYapDatabasePassphraseAccountName accessGroup:kGlacierKeyGroup error:nil];
    if (keyspec == nil) {
        keyspec = [SAMKeychain passwordDataForService:kGlacierMediaKeySpec account:OTRYapDatabasePassphraseAccountName];
    }
    
    return keyspec;
}

- (BOOL) canSortDataView {
    return self.canSortDatabaseView;
}

- (void) setCanSortDataView:(BOOL)sort {
    self.canSortDatabaseView = sort;
}

- (void) resortDataView {
    [self.writeConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction){
        [[transaction ext:OTRConversationDatabaseViewExtensionName] setGrouping:[OTRDatabaseView conversationViewGrouping:self.database] sorting:[OTRDatabaseView conversationViewSorting:self.database] versionTag:[NSUUID UUID].UUIDString];
    }];
}

#pragma - mark Singlton Methodd
static BOOL isInitialized = NO;
+ (BOOL)isSharedInstanceInitialized {
    return isInitialized;
}

+ (OTRDatabaseManager*) shared {
    return [self sharedInstance];
}

+ (instancetype)sharedInstance
{
    static id databaseManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        databaseManager = [[self alloc] init];
        isInitialized = YES;
    });
    
    return databaseManager;
}

@end
