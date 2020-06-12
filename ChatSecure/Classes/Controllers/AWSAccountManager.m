//
//  AWSAccountManager.m
//  Copyright (c) 2019 Glacier Security. All rights reserved.
//  for single signon via AWS

@import OTRAssets;
#import "OTRLog.h"

#import "AWSCognitoIdentityProvider.h"
#import <AWSCore/AWSCore.h>
#import <AWSCognito/AWSCognito.h>
#import <AWSS3/AWSS3.h>
#import <AWSCognito/AWSCognitoService.h>

#import <ChatSecureCore/ChatSecureCore-Swift.h>

@import SAMKeychain;


@interface AWSAccountManager () <AWSCognitoIdentityInteractiveAuthenticationDelegate>

@property (nonatomic,strong) AWSCognitoIdentityUserGetDetailsResponse * response;
@property (nonatomic, strong) AWSCognitoIdentityUser * user;
@property (nonatomic, strong) AWSCognitoIdentityUserPool * pool;
@property (nonatomic, strong) AWSCognitoAuth * auth;
@property (nonatomic, strong) AWSCognitoAuthUserSession * session;
@property (nonatomic, strong) NSString *bucketPrefix;
@property (nonatomic, strong) NSString *bucketOrg;
@property (nonatomic, strong) NSString *s3BucketName;
@property (nonatomic, strong) NSString *userName;
@property (nonatomic, strong) OTRWelcomeViewController *awspauth;
@property (nonatomic, strong) NewCognitoPasswordRequiredViewController *awsnewpass;

@property (nonatomic, strong) AppSyncMgr *appSyncMgr;

@property (nonatomic, strong) NSURL *ipsecProfile;
@property (assign, nonatomic) BOOL vpnOnly;

@property (assign, nonatomic) BOOL sessionExpired;

@end

@implementation AWSAccountManager

- (instancetype)init
{
    [self setupDownloadDirectory];
    [self teardownCognito];
    self.vpnOnly = NO;
    self.appSyncMgr = [[AppSyncMgr alloc] init];
    
    return self;
}

- (void)setupDownloadDirectory {
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"download"] withIntermediateDirectories:YES
                                                attributes:nil error:&error]) {
        DDLogWarn(@"Creating 'download' directory failed. Error: [%@]", error);
    }
}

- (void)setupCognito {
    if (!self.pool) {
        self.pool = [AWSCognitoIdentityUserPool defaultCognitoIdentityUserPool];
        self.pool.delegate = self;
    }
    
    self.auth = [AWSCognitoAuth defaultCognitoAuth];
}

- (void) teardownCognito {
    [self setupCognito];
    if(self.pool && [self.pool currentUser]) {
        [[self.pool currentUser] signOut];
        self.pool = nil;
    }
    
    if (self.auth && self.auth.isSignedIn) {
        [self.auth signOut:^(NSError * _Nullable error) {
            // do nothing
        }];
    }
}

- (BOOL) coreSignedIn {
    BOOL isSignedIn = FALSE;
    if(self.pool && [self.pool currentUser]) {
        isSignedIn = [self.pool currentUser].signedIn;
    }
    
    return isSignedIn;
}

-(void) setAuthenticator:(OTRWelcomeViewController *)awsauth {
    self.awspauth = awsauth;
    self.auth.delegate = awsauth;
}

- (void) setExpiredSession {
    self.sessionExpired = YES;
}

//set up password authentication ui to retrieve username and password from the user
-(id<AWSCognitoIdentityPasswordAuthentication>) startPasswordAuthentication {
    return self.awspauth;
}

// set up reset password ui
-(id<AWSCognitoIdentityNewPasswordRequired>) startNewPasswordRequired {
    
    if (self.awsnewpass == nil) {
        dispatch_group_t group = dispatch_group_create();
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Onboarding" bundle:[OTRAssets resourcesBundle]];
            self.awsnewpass = (NewCognitoPasswordRequiredViewController *)[storyboard instantiateViewControllerWithIdentifier:@"NewCognitoPasswordRequiredViewController"];
            dispatch_group_leave(group);
        });
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.awspauth stopSpinner];
        if (!self.sessionExpired) {
            [self.awspauth presentViewController:self.awsnewpass animated:YES completion:nil];
        } else { 
            [self alertWithTitle:@"Retry Login" message:@"You took too long! Starting login process again."];
        }
    });
    
    return self.awsnewpass;
}

-(void) handleSSO {
    if (![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"octopusauth://"]]) {
        [self alertWithTitle:@"Authenticator Missing" message:@"You do not have the Octopus Authenticator app used for single sign on. Please make sure you have an account and download Octopus Authenticator from the App Store."];
        return;
    }
    
    if (self.auth != nil && self.auth.isSignedIn && [self coreSignedIn]) {
        [self getUserDetails];
    } else {
        [self.auth getSession:self.awspauth completion:^(AWSCognitoAuthUserSession * _Nullable session, NSError * _Nullable error) {
            if(error){
                [self alertWithTitle:@"Authentication issue" message:@"Could not authenticate. For assistance contact your Glacier account representative."];
                self.session = nil;
            }else {
                self.session = session;
                if (self.session != nil) {
                    [self setupCognito];
                    [self getUserDetails];
                }
            }
        }];
    }
}

- (BOOL) loginWithoutUI:(NSString *)cpass {
    [self setupCognito];
    if(!self.user) {
        self.user = [self.pool currentUser];
    }
    
    if(!self.user) {
        return NO;
    }
    
    [[self.user getSession:self.user.username password:cpass validationData:nil] continueWithSuccessBlock:^id _Nullable(AWSTask<AWSCognitoIdentityUserSession *> * _Nonnull task) {
        //success, task.result has user session
        
        if(task.error){
            //TODO need to reroute to UI? Or at least post an alert?
        }else {
            self.userName = self.user.username;
            
            [[self.user getDetails] continueWithBlock:^id _Nullable(AWSTask<AWSCognitoIdentityUserGetDetailsResponse *> * _Nonnull task) {
                
                for (AWSCognitoIdentityProviderAttributeType *attr in task.result.userAttributes) {
                    if ([attr.name isEqualToString:@"custom:organization"]) {
                        self.bucketOrg = attr.value;
                    }
                }
            
                [self getS3Bucket];
                return nil;
            }];
        }
        
        return nil;
    }];
    
    return YES;
}

-(void) getUserDetails {
    if(!self.user)
        self.user = [self.pool currentUser];
    self.sessionExpired = NO;
    
    [self.awspauth startSpinner];
    
    [[self.user getDetails] continueWithBlock:^id _Nullable(AWSTask<AWSCognitoIdentityUserGetDetailsResponse *> * _Nonnull task) {
        
        //dispatch_async(dispatch_get_main_queue(), ^{
            if(task.error){
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.awspauth stopSpinner];
                    [self alertWithTitle:task.error.userInfo[@"__type"] message:@"Problems logging in."];
                });
            }else {
                self.userName = self.user.username;
                
                for (AWSCognitoIdentityProviderAttributeType *attr in task.result.userAttributes) {
                    if ([attr.name isEqualToString:@"custom:organization"]) {
                        self.bucketOrg = attr.value;
                    }
                }
                
                if (self.vpnOnly) {
                    [self getS3Bucket];
                } else {
                    [self getAppSyncData];
                }
            }
        //});
        
        return nil;
    }];
}

- (void) getAppSyncData {
    [self.appSyncMgr getUserInfoWithUsername:self.userName org:self.bucketOrg completion:^(GlacierUser *guser) {
        //use password and get org
        if (guser == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.awspauth stopSpinner];
                [self alertWithTitle:@"No user info" message:@"Problems logging in."];
                [self endLogin];
            });
            return;
        }
        
        NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc] initWithSuiteName:kGlacierGroup];
        if (guser.organization != nil) {
            self.bucketOrg = guser.organization;
            [glacierDefaults setObject:guser.organization forKey:@"orgid"];
        }
        
        [glacierDefaults setObject:guser.displayName forKey:@"displayname"];
        [glacierDefaults setObject:@"none" forKey:@"connection"];
        [glacierDefaults setObject:guser.username forKey:@"username"];
        if ([guser.voiceext length] > 0) {
            [glacierDefaults setObject:guser.voiceext forKey:@"extension"];
        }
        
        if (guser.password) {
            
            NSError *error = nil;
            //TODO maybe check for existing ID here?
            //in case i'm coming back in for something else like just profile
            NSString *userid = [NSUUID UUID].UUIDString;
            BOOL idresult = [SAMKeychain setPassword:userid forService:kGlacierGroup account:kGlacierAcct accessGroup:kGlacierGroup error:&error];
            BOOL result = [SAMKeychain setPassword:guser.password forService:kGlacierGroup account:userid accessGroup:kGlacierGroup error:&error];
            if (!result || !idresult) {
                DDLogError(@"Error saving id or password to keychain: %@%@", [error localizedDescription], [error userInfo]);
            }
        }
        [glacierDefaults synchronize];
        [self endLogin];
    }];
}

- (NSString *) getDomainFromEmail:(NSString*)email {
    NSString *domain;
    NSString *fulldomain = [email componentsSeparatedByString:@"@"].lastObject;
    if (fulldomain != nil && ![fulldomain isEqualToString:OTRSecrets.defaultHost]) {
        domain = [fulldomain componentsSeparatedByString:@"."].firstObject;
    } else if (fulldomain != nil) {
        domain = fulldomain;
    }
    
    return domain;
}

- (void) getS3Bucket {
    AWSServiceInfo *serviceInfo = [[AWSInfo defaultAWSInfo] defaultServiceInfo:@"CognitoUserPool"];
    AWSCognitoCredentialsProvider *credentialsProvider = [[AWSCognitoCredentialsProvider alloc]
        initWithRegionType:serviceInfo.region identityPoolId:serviceInfo.cognitoCredentialsProvider.identityPoolId identityProviderManager:self.pool];
    
    AWSServiceConfiguration *configuration = [[AWSServiceConfiguration alloc] initWithRegion:serviceInfo.region credentialsProvider:credentialsProvider];
    
    [AWSServiceManager defaultServiceManager].defaultServiceConfiguration = configuration;
    [AWSS3 registerS3WithConfiguration:configuration forKey:@"defaultKey"];
    [AWSS3TransferManager registerS3TransferManagerWithConfiguration:configuration forKey:@"defaultKey"];
    
    [self setupS3Request];
}

//- (void) createListObjectsRequestWithId:(NSString *)identityId {
- (void) setupS3Request {
    if (self.bucketOrg) {
        AWSS3ListObjectsRequest *listObjectsRequest = [AWSS3ListObjectsRequest new];
        self.bucketPrefix = @"users"; //identityId;
        listObjectsRequest.prefix = self.bucketPrefix;
        self.s3BucketName = [[OTRSecrets awsBucketConstant] stringByAppendingString:self.bucketOrg];
        listObjectsRequest.bucket = self.s3BucketName;
        
        [self listObjects:listObjectsRequest];
    } else {
        [self.awspauth stopSpinner];
        [VPNManager.shared noAccessAvailable];
        NSLog(@"Could not createListObjectsRequestWithId due to no Org Id");
    }
}

- (void) listObjects:(AWSS3ListObjectsRequest*)listObjectsRequest {
    AWSS3 *s3 = [AWSS3 S3ForKey:@"defaultKey"];
    [[s3 listObjects:listObjectsRequest] continueWithBlock:^id(AWSTask *task) {
        if (task.error) {
            DDLogWarn(@"listObjects failed: [%@]", task.error);
            self.vpnOnly = NO;
            [self.awspauth stopSpinner];
            [VPNManager.shared noAccessAvailable]; 
        } else {
            AWSS3ListObjectsOutput *listObjectsOutput = task.result;
            NSString *mstring = [self.bucketOrg stringByAppendingPathExtension:@"mobileconfig"];
            
            for (AWSS3Object *s3Object in listObjectsOutput.contents) {
                NSString *downloadingFilePath = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"download"] stringByAppendingPathComponent:[s3Object.key lastPathComponent]];
                NSURL *downloadingFileURL = [NSURL fileURLWithPath:downloadingFilePath];
                
                if ([downloadingFilePath hasSuffix:mstring] && self.vpnOnly) {
                    self.ipsecProfile = downloadingFileURL;
                }
            }
            
            if (self.vpnOnly) {
                if (self.ipsecProfile == nil) {
                    [VPNManager.shared noVpnAvailable];
                } else {
                    [self getIpsecProfile];
                }
                self.vpnOnly = NO;
            }
            
        }
        return nil;
    }];
}

- (void) getIpsecProfile {
    if (self.ipsecProfile) {
        NSString *downloadingFilePath = self.ipsecProfile.absoluteString;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:downloadingFilePath]) {
            [self handleIpsecProfile];
        } else {
            AWSS3TransferManagerDownloadRequest *downloadRequest = [AWSS3TransferManagerDownloadRequest new];
            downloadRequest.bucket = self.s3BucketName;
            NSString *keytest = [self.bucketPrefix stringByAppendingPathComponent:[self.ipsecProfile lastPathComponent]];
            downloadRequest.key = keytest;
            downloadRequest.downloadingFileURL = self.ipsecProfile;
            [self download:downloadRequest];
        }
    }
}

- (void) handleIpsecProfile {
    // read file
    if (!self.ipsecProfile) {
        return;
    }
    
    [VPNManager.shared handleIpsecProfile:self.ipsecProfile];
    [self endLogin];
}

- (void)addVPNConnection {
    self.vpnOnly = YES;
    if (![self coreSignedIn]) {
        
        NSError *error = nil;
        NSString *passvalue = nil;
        NSString *idvalue = [SAMKeychain passwordForService:kGlacierGroup account:kCognitoAcct accessGroup:kGlacierGroup error:&error];
        if (idvalue) {
            passvalue = [SAMKeychain passwordForService:kGlacierGroup account:idvalue accessGroup:kGlacierGroup error:&error];
            if (passvalue) {
                @try {
                    if ([self loginWithoutUI:passvalue]) {
                        return;
                    }
                }
                @catch ( NSException *e ) {
                    //
                }
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[[OTRAppDelegate appDelegate] conversationViewController] setWelcomeController:YES];
        });
    } else {
        //self.vpnOnly = YES;
        [self getUserDetails];
    }
}

- (void)download:(AWSS3TransferManagerDownloadRequest *)downloadRequest {
    AWSS3TransferManager *transferManager = [AWSS3TransferManager S3TransferManagerForKey:@"defaultKey"];
    [[transferManager download:downloadRequest] continueWithBlock:^id(AWSTask *task) {
        if ([task.error.domain isEqualToString:AWSS3TransferManagerErrorDomain]
            && task.error.code == AWSS3TransferManagerErrorPaused) {
            NSLog(@"Download paused.");
        } else if (task.error) {
            NSLog(@"Download failed: [%@]", task.error);
            [VPNManager.shared noAccessAvailable];
        } else {
            NSURL *downloadFileURL = downloadRequest.downloadingFileURL;
            if ([[downloadFileURL pathExtension] isEqualToString:@"mobileconfig"]) {
                [self handleIpsecProfile];
            }
        }
        return nil;
    }];
}

- (void) removeLocalVPNFiles {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (self.ipsecProfile != nil) {
        NSString *filePath = [self.ipsecProfile path];
        NSError *error;
        if ([fileManager fileExistsAtPath:filePath]) {
            BOOL success = [fileManager removeItemAtPath:filePath error:&error];
            if (success) {
                DDLogInfo(@"Success removing profile");
            } else {
                DDLogWarn(@"Failure removing profile: %@", [error localizedDescription]);
            }
        }
        self.ipsecProfile = nil;
    }
}

- (void) alertWithTitle: (NSString *) title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:title
                                     message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *action = [UIAlertAction
                                 actionWithTitle:@"Ok"
                                 style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction * action) {
                                     [alert dismissViewControllerAnimated:NO completion:nil];
                                 }];
        [alert addAction:action];
        [self.awspauth presentViewController:alert animated:YES completion:nil];
    });
}

- (void) endLogin {
    if (self.awspauth != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.awspauth dismissViewControllerAnimated:YES completion:nil];
            self.awspauth = nil;
        });
    }
    if (self.awsnewpass != nil) { 
        self.awsnewpass = nil;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[[OTRAppDelegate appDelegate] conversationViewController] lookForAccountInfoIfNeeded];
    });
}

#pragma - mark Singleton Method

+ (AWSAccountManager*) shared {
    return [self sharedInstance];
}

+ (instancetype)sharedInstance
{
    static id awsManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        awsManager = [[self alloc] init];
    });
    
    return awsManager;
}

@end
