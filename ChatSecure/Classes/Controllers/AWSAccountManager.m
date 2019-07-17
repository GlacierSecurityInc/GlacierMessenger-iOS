//
//  AWSAccountManager.m
//
//  Created by Andy Friedman on 10/17/17.
//  Copyright (c) 2017 Glacier Security. All rights reserved.
//  for single signon via AWS

@import OTRAssets;
#import "OTRLog.h"

// for AWS login and access functionality
#import "AWSCognitoIdentityProvider.h"
#import <AWSCore/AWSCore.h>
#import <AWSCognito/AWSCognito.h>
#import <AWSS3/AWSS3.h>
#import "CZPicker.h"

#import <ChatSecureCore/ChatSecureCore-Swift.h>


@interface AWSAccountManager () <AWSCognitoIdentityInteractiveAuthenticationDelegate, CZPickerViewDataSource, CZPickerViewDelegate, UIDocumentInteractionControllerDelegate>

@property (nonatomic,strong) AWSCognitoIdentityUserGetDetailsResponse * response;
@property (nonatomic, strong) AWSCognitoIdentityUser * user;
@property (nonatomic, strong) AWSCognitoIdentityUserPool * pool;
@property (nonatomic, strong) AWSCognitoAuth * auth;
@property (nonatomic, strong) AWSCognitoAuthUserSession * session;
@property (nonatomic, strong) NSMutableArray *dataArray;
@property (nonatomic, strong) UIDocumentInteractionController *controller;
@property (nonatomic, strong) NSURL *glacierData;
@property (nonatomic, strong) NSString *bucketPrefix;
@property (nonatomic, strong) NSString *bucketOrg;
@property (nonatomic, strong) NSString *s3BucketName;
@property (nonatomic, strong) NSString *userName;
@property (nonatomic, strong) OTRWelcomeViewController *awspauth;
@property (nonatomic, strong) NewCognitoPasswordRequiredViewController *awsnewpass;
@property (nonatomic, strong) UIAlertController *vpnalert;

@end

@implementation AWSAccountManager

- (instancetype)init
{
    [self setupDownloadDirectory];
    [self setupCognito]; //(may not have logged out when app closed)
    [self teardownCognito];
    self.dataArray = [NSMutableArray new];
    return self;
}

- (void)setupDownloadDirectory {
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"download"] withIntermediateDirectories:YES
                                                attributes:nil error:&error]) {
        DDLogWarn(@"Creating 'download' directory failed. Error: [%@]", error);
    }
}

// AWS login and interactions here till end
- (void)setupCognito {
    if (!self.pool) {
        self.pool = [AWSCognitoIdentityUserPool defaultCognitoIdentityUserPool];
        self.pool.delegate = self;
    }
    
    self.auth = [AWSCognitoAuth defaultCognitoAuth];
}

- (void) teardownCognito {
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

//set up password authentication ui to retrieve username and password from the user
-(id<AWSCognitoIdentityPasswordAuthentication>) startPasswordAuthentication {
    return self.awspauth;
}

// set up reset password ui
-(id<AWSCognitoIdentityNewPasswordRequired>) startNewPasswordRequired {
    if (self.awsnewpass == nil) {
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Onboarding" bundle:[OTRAssets resourcesBundle]];
        self.awsnewpass = (NewCognitoPasswordRequiredViewController *)[storyboard instantiateViewControllerWithIdentifier:@"NewCognitoPasswordRequiredViewController"];
    }
    //self.awsnewpass.modalPresentationStyle = UIModalPresentationFormSheet;
    [self.awspauth stopSpinner];
    [self.awspauth presentViewController:self.awsnewpass animated:YES completion:nil];
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

-(void) getUserDetails {
    if(!self.user)
        self.user = [self.pool currentUser];
    
    [self.awspauth startSpinner];
    
    [[self.user getDetails] continueWithBlock:^id _Nullable(AWSTask<AWSCognitoIdentityUserGetDetailsResponse *> * _Nonnull task) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if(task.error){
                [self.awspauth stopSpinner];
                [self alertWithTitle:task.error.userInfo[@"__type"] message:@"Problems logging in."];
            }else {
                self.userName = self.user.username;
                
                NSArray *components = [self.userName componentsSeparatedByString:@"@"];
                if (components.count == 2) {
                    NSString *domain = [self getDomainFromEmail:self.userName];
                    self.userName = components.firstObject;
                    
                    //Split off IdP if exists
                    NSArray *namecomponents = [self.userName componentsSeparatedByString:@"_"];
                    if (namecomponents.count == 2) {
                        self.userName = namecomponents.lastObject;
                        domain = [namecomponents.firstObject lowercaseString];
                    }
                    
                    NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc]
                                                       initWithSuiteName:@"group.com.glaciersec.apps"];
                    [glacierDefaults setObject:domain forKey:@"orgid"];
                    [glacierDefaults synchronize];
                }
                
                [self getS3Bucket];
            }
        });
        
        return nil;
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
    //get config from Info.plist
    NSDictionary * infoDictionary = [[NSBundle mainBundle] infoDictionary][@"AWS"][@"CredentialsProvider"][@"CognitoIdentity"][@"Default"];
    NSString *awsIdentityPoolId = infoDictionary[@"PoolId"];
    
    if (awsIdentityPoolId == nil) {
        DDLogError(@"Need to add AWS Cognito identity pool id access S3 bucket");
        [self.awspauth stopSpinner];
        return;
    }
    
    AWSCognitoCredentialsProvider *credentialsProvider = [[AWSCognitoCredentialsProvider alloc]
                                                          initWithRegionType:AWSRegionUSEast1
                                                          identityPoolId:awsIdentityPoolId identityProviderManager:self.pool];
    
    AWSServiceConfiguration *configuration = [[AWSServiceConfiguration alloc] initWithRegion:AWSRegionUSEast1 credentialsProvider:credentialsProvider];
    
    [AWSServiceManager defaultServiceManager].defaultServiceConfiguration = configuration;
    [AWSS3 registerS3WithConfiguration:configuration forKey:@"defaultKey"];
    
    [self setupS3Request];
}

- (void) setupS3Request {
    NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc]
                                       initWithSuiteName:@"group.com.glaciersec.apps"];
    self.bucketOrg = [glacierDefaults objectForKey:@"orgid"];
    if (self.bucketOrg) {
        AWSS3ListObjectsRequest *listObjectsRequest = [AWSS3ListObjectsRequest new];
        self.bucketPrefix = @"users"; //identityId;
        listObjectsRequest.prefix = self.bucketPrefix;
        self.s3BucketName = [[OTRSecrets awsBucketConstant] stringByAppendingString:self.bucketOrg];
        listObjectsRequest.bucket = self.s3BucketName;
        
        [self listObjects:listObjectsRequest];
    } else {
        [self.awspauth stopSpinner];
        NSLog(@"Could not createListObjectsRequestWithId due to no Org Id");
    }
}

- (void) listObjects:(AWSS3ListObjectsRequest*)listObjectsRequest {
    AWSS3 *s3 = [AWSS3 S3ForKey:@"defaultKey"];
    [[s3 listObjects:listObjectsRequest] continueWithBlock:^id(AWSTask *task) {
        if (task.error) {
            DDLogWarn(@"listObjects failed: [%@]", task.error);
            [self.awspauth stopSpinner];
            // This happens is we fat fingered the org and no bucket exists.
            [self alertWithTitle:@"No Account" message:@"We cannot find your account information. Please make sure you entered the correct Org ID. For assistance contact your Glacier account representative."];
        } else {
            AWSS3ListObjectsOutput *listObjectsOutput = task.result;
            NSString *undername = [@"_" stringByAppendingString:self.userName];
            NSString *gstring = [self.userName stringByAppendingPathExtension:@"glacier"];
            NSString *ostring = [undername stringByAppendingPathExtension:@"ovpn"];
            
            [self.dataArray removeAllObjects];
            
            for (AWSS3Object *s3Object in listObjectsOutput.contents) {
                NSString *downloadingFilePath = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"download"] stringByAppendingPathComponent:[s3Object.key lastPathComponent]];
                NSURL *downloadingFileURL = [NSURL fileURLWithPath:downloadingFilePath];
                
                if ([[downloadingFilePath lastPathComponent] isEqualToString:gstring]) { //hasSuffix:gstring]) {
                    self.glacierData = downloadingFileURL;
                } else if ([downloadingFilePath hasSuffix:ostring]) {
                    [self.dataArray addObject:downloadingFileURL];
                }
            }
            
            [self getGlacierData];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.dataArray.count > 0 && [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"openvpn://"]]) {
                    [self.awspauth stopSpinner];
                    CZPickerView *picker = [[CZPickerView alloc] initWithHeaderTitle:@"Add VPN Connection"
                                                                   cancelButtonTitle:@"Cancel"
                                                                  confirmButtonTitle:@"Confirm"];
                    picker.delegate = self;
                    picker.dataSource = self;
                    /** picker header background color */
                    picker.headerBackgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"color_Gl" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil]];
                    
                    [picker show];
                }
            });
        }
        return nil;
    }];
}

- (void) getGlacierData {
    if (self.glacierData) {
        NSString *downloadingFilePath = self.glacierData.absoluteString;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:downloadingFilePath]) {
            [self readAndStoreGlacierData];
        } else {
            AWSS3TransferManagerDownloadRequest *downloadRequest = [AWSS3TransferManagerDownloadRequest new];
            downloadRequest.bucket = self.s3BucketName;
            NSString *keytest = [self.bucketPrefix stringByAppendingPathComponent:[self.glacierData lastPathComponent]];
            downloadRequest.key = keytest;
            downloadRequest.downloadingFileURL = self.glacierData;
            [self download:downloadRequest];
        }
    } else {
        // can't find user file, which is a problem
        DDLogWarn(@"No user file for: %@", self.userName);
        [self.awspauth stopSpinner];
        [self alertWithTitle:@"No Account" message:@"We cannot find your account information. For assistance contact your Glacier account representative."];
    }
}

- (void) readAndStoreGlacierData {
    // read file
    if (!self.glacierData) {
        return;
    }
    
    NSError *error;
    NSString *fileContents = [NSString stringWithContentsOfURL:self.glacierData encoding:NSUTF8StringEncoding error:&error];
    
    if (error)
        NSLog(@"Error reading file: %@", error.localizedDescription);
    
    // maybe for debugging...
    //NSLog(@"contents: %@", fileContents);
    
    NSArray *listArray = [fileContents componentsSeparatedByString:@"\n"];
    
    if (listArray.count) {
        NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc]
                                           initWithSuiteName:@"group.com.glaciersec.apps"];
        
        for (NSString *gTemp in listArray) {
            NSArray *props = [gTemp componentsSeparatedByString:@"="];
            if (props.count == 2) {
                [glacierDefaults setObject:props.lastObject forKey:props.firstObject];
            }
        }
        [glacierDefaults synchronize];
        
        if ([self.dataArray count] == 0) {
            [self endLogin];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"openvpn://"]]) {
                    [self endLogin];
                }
            });
        }
    }
}

- (void)download:(AWSS3TransferManagerDownloadRequest *)downloadRequest {
    
    AWSS3TransferManager *transferManager = [AWSS3TransferManager defaultS3TransferManager];
    [[transferManager download:downloadRequest] continueWithBlock:^id(AWSTask *task) {
        if ([task.error.domain isEqualToString:AWSS3TransferManagerErrorDomain]
            && task.error.code == AWSS3TransferManagerErrorPaused) {
            NSLog(@"Download paused.");
        } else if (task.error) {
            NSLog(@"Download failed: [%@]", task.error);
        } else {
            NSURL *downloadFileURL = downloadRequest.downloadingFileURL;
            if ([[downloadFileURL pathExtension] isEqualToString:@"glacier"]) {
                [self readAndStoreGlacierData];
            } else if ([[downloadFileURL pathExtension] isEqualToString:@"ovpn"]) {
                [self tryOpenUrl:downloadFileURL];
            }
        }
        return nil;
    }];
}

- (UIDocumentInteractionController *)controller {
    
    if (!_controller) {
        _controller = [[UIDocumentInteractionController alloc]init];
        _controller.delegate = self;
        _controller.UTI = @"net.openvpn.formats.ovpn";
    }
    return _controller;
}

- (void) tryOpenUrl:(NSURL *)fileURL {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (fileURL) {
            //Starting to send this to net.openvpn.connect.app
            self.controller.URL = fileURL;
            [self.controller presentOpenInMenuFromRect:self.awspauth.view.frame inView:self.awspauth.view animated:YES];
        }
        
        // close window?
    });
}

- (void) removeLocalVPNFiles {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSURL *url in self.dataArray) {
        NSString *filePath = [url path];
        NSError *error;
        if ([fileManager fileExistsAtPath:filePath]) {
            BOOL success = [fileManager removeItemAtPath:filePath error:&error];
            if (success) {
                DDLogInfo(@"Success removing profile");
            } else {
                DDLogWarn(@"Failure removing profile: %@", [error localizedDescription]);
            }
        }
    }
    
    [self.dataArray removeAllObjects];
}

- (BOOL)checkLocalVPNProfiles {
    if (self.dataArray.count > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.awspauth stopSpinner];
            CZPickerView *picker = [[CZPickerView alloc] initWithHeaderTitle:@"Add VPN Connection" cancelButtonTitle:@"Cancel" confirmButtonTitle:@"Confirm"];
            picker.delegate = self;
            picker.dataSource = self;
            // picker header background color
            picker.headerBackgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"color_Gl" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil]];
            
            [picker show];
        });
        return YES;
    }
    return NO;
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
        [self.awspauth dismissViewControllerAnimated:YES completion:nil];
        self.awspauth = nil;
    }
    if (self.awsnewpass != nil) {
        self.awsnewpass = nil;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[[OTRAppDelegate appDelegate] conversationViewController] lookForAccountInfoIfNeeded];
    });
}

#pragma mark - Delegate Methods
- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    return  self.awspauth;
}

- (void)documentInteractionController:(UIDocumentInteractionController *)controller willBeginSendingToApplication:(NSString *)application {
    //NSLog(@"Starting to send this puppy to %@", application);
}

- (void)documentInteractionController:(UIDocumentInteractionController *)controller didEndSendingToApplication:(NSString *)application {
    NSLog(@"We're done sending the document.");
    
    [self endLogin];
}

#pragma mark - CZPickerViewDataSource

/* number of items for picker */
- (NSInteger)numberOfRowsInPickerView:(CZPickerView *)pickerView {
    return [self.dataArray count];
}

/* picker item title for each row */
- (NSString *)czpickerView:(CZPickerView *)pickerView titleForRow:(NSInteger)row {
    NSURL *url = self.dataArray[row];
    return [[url lastPathComponent] stringByDeletingPathExtension];
}

#pragma mark - CZPickerViewDelegate
/** delegate method for picking one item */
- (void)czpickerView:(CZPickerView *)pickerView didConfirmWithItemAtRow:(NSInteger)row {
    
    NSURL *downloadingFileURL = self.dataArray[row];
    NSString *downloadingFilePath = downloadingFileURL.absoluteString;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:downloadingFilePath]) {
        [self tryOpenUrl:downloadingFileURL];
    } else {
        AWSS3TransferManagerDownloadRequest *downloadRequest = [AWSS3TransferManagerDownloadRequest new];
        downloadRequest.bucket = self.s3BucketName;
        NSString *keytest = [self.bucketPrefix stringByAppendingPathComponent:[downloadingFileURL lastPathComponent]];
        
        downloadRequest.key = keytest;
        downloadRequest.downloadingFileURL = downloadingFileURL;
        [self download:downloadRequest];
    }
}

/** delegate method for canceling */
- (void)czpickerViewDidClickCancelButton:(CZPickerView *)pickerView {
    [self endLogin];
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
