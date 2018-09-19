//
//  AWSAccountManager.m
//  for AWS login and access functionality
//
//  Created by Christopher Ballinger on 10/17/13.
//  Copyright (c) 2013 Chris Ballinger. All rights reserved.

@import OTRAssets;
#import "OTRLog.h"

// for AWS login and access functionality
#import "AWSCognitoIdentityProvider.h"
#import <AWSCore/AWSCore.h>
#import <AWSCognito/AWSCognito.h>
#import <AWSS3/AWSS3.h>
#import "CZPicker.h"

#import <ChatSecureCore/ChatSecureCore-Swift.h>


@interface AWSAccountManager ()

// for single signon via AWS
@property (nonatomic,strong) AWSCognitoIdentityUserGetDetailsResponse * response;
@property (nonatomic, strong) AWSCognitoIdentityUser * user;
@property (nonatomic, strong) AWSCognitoIdentityUserPool * pool;
@property (nonatomic, strong) NSMutableArray *dataArray;
@property (nonatomic, strong) UIDocumentInteractionController *controller;
@property (nonatomic, strong) NSURL *glacierData;
@property (nonatomic, strong) NSString *bucketPrefix;
@property (nonatomic, strong) NSString *bucketOrg;
@property (nonatomic, strong) NSString *s3BucketName;
@property (nonatomic, strong) OTRWelcomeViewController *awspauth;

@end

@implementation AWSAccountManager

- (instancetype)init
{
    return self;
}

// AWS login and interactions here till end
- (void)setupCognito {
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"download"] withIntermediateDirectories:YES
                                                    attributes:nil error:&error]) {
        DDLogWarn(@"Creating 'download' directory failed. Error: [%@]", error);
    }
    
    if (!self.pool) {
        AWSServiceConfiguration *serviceConfiguration = [[AWSServiceConfiguration alloc] initWithRegion:AWSRegionUSEast1 credentialsProvider:nil];
        
        // environment variables supplied by user in Secrets.plist
        NSString *awsClientId = [OTRSecrets awsClientID];
        NSString *awsClientSecret = [OTRSecrets awsClientSecret];
        NSString *awsPoolId = [OTRSecrets awsPoolID];
        
        if (awsClientId == nil || awsClientSecret == nil || awsPoolId == nil) {
            DDLogError(@"Need to add AWS Cognito id info to instantiate Cognito Identity Pool");
        } else {
            AWSCognitoIdentityUserPoolConfiguration *configuration = [[AWSCognitoIdentityUserPoolConfiguration alloc] initWithClientId:awsClientId clientSecret:awsClientSecret poolId:awsPoolId];
            [AWSCognitoIdentityUserPool registerCognitoIdentityUserPoolWithConfiguration:serviceConfiguration userPoolConfiguration:configuration forKey:@"GlacierUserPool"];
            self.pool = [AWSCognitoIdentityUserPool CognitoIdentityUserPoolForKey:@"GlacierUserPool"];
            self.pool.delegate = self;
        }
    }
}

- (void) teardownCognito {
    if(self.pool && [self.pool currentUser]) {
        [[self.pool currentUser] signOut];
        self.pool = nil;
    }
}

- (BOOL) coreSignedIn {
    BOOL isSignedIn = FALSE;
    if(self.pool && [self.pool currentUser]) {
        isSignedIn = [self.pool currentUser].signedIn;
    }
    
    return isSignedIn;
}

//set up password authentication ui to retrieve username and password from the user
-(id<AWSCognitoIdentityPasswordAuthentication>) startPasswordAuthentication {
    return self.awspauth;
}

-(void) getUserDetails {
    //AWSCognitoIdentityUser *testuser = [self.pool getUser:@"andy"];
    if(!self.user)
        self.user = [self.pool currentUser];
    
    [[self.user getDetails] continueWithBlock:^id _Nullable(AWSTask<AWSCognitoIdentityUserGetDetailsResponse *> * _Nonnull task) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if(task.error){
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:task.error.userInfo[@"__type"] message:@"Some error." preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
                [alert addAction:cancel];
                //[self presentViewController:alert animated:YES completion:nil];
            }else {
                [self getS3Bucket];
            }
            
            if (self.awspauth != nil) {
                [self.awspauth dismissViewControllerAnimated:YES completion:nil];
                self.awspauth = nil;
            }
        });
        
        return nil;
    }];
}

- (void) getS3Bucket {
    // supplied in Secrets.plist
    NSString *awsIdentityPoolId = [OTRSecrets awsIdentityPoolID];
    if (awsIdentityPoolId == nil) {
        DDLogError(@"Need to add AWS Cognito identity pool id access S3 bucket");
        return;
    }
    
    AWSCognitoCredentialsProvider *credentialsProvider = [[AWSCognitoCredentialsProvider alloc]
                                                          initWithRegionType:AWSRegionUSEast1
                                                          identityPoolId:awsIdentityPoolId identityProviderManager:self.pool];
    
    AWSServiceConfiguration *configuration = [[AWSServiceConfiguration alloc] initWithRegion:AWSRegionUSEast1 credentialsProvider:credentialsProvider];
    
    [AWSServiceManager defaultServiceManager].defaultServiceConfiguration = configuration;
    [AWSS3 registerS3WithConfiguration:configuration forKey:@"defaultKey"];
    
    [self createListObjectsRequest];
}

//- (void) createListObjectsRequestWithId:(NSString *)identityId {
- (void) createListObjectsRequest {
    NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc]
                                       initWithSuiteName:@"group.com.glaciersec.apps"];
    self.bucketOrg = [glacierDefaults objectForKey:@"orgid"];
    if (self.bucketOrg) {
        AWSS3ListObjectsRequest *listObjectsRequest = [AWSS3ListObjectsRequest new];
        self.bucketPrefix = @"users"; //identityId;
        //self.bucketPrefix = [@"users" stringByAppendingPathComponent:@"jason"];
        //self.bucketPrefix = [self.bucketPrefix stringByAppendingString:@"/"];
        listObjectsRequest.prefix = self.bucketPrefix;
        self.s3BucketName = [[OTRSecrets awsBucketConstant] stringByAppendingString:self.bucketOrg];
        listObjectsRequest.bucket = self.s3BucketName;
        
        [self listObjects:listObjectsRequest];
    } else {
        NSLog(@"Could not createListObjectsRequestWithId due to no Org Id");
    }
}

- (void) listObjects:(AWSS3ListObjectsRequest*)listObjectsRequest {
    AWSS3 *s3 = [AWSS3 S3ForKey:@"defaultKey"];
    [[s3 listObjects:listObjectsRequest] continueWithBlock:^id(AWSTask *task) {
        if (task.error) {
            NSLog(@"listObjects failed: [%@]", task.error);
            // This happens is we fat fingered the org and no bucket exists. Appropriate notification?
            // Go back to login screen?
        } else {
            AWSS3ListObjectsOutput *listObjectsOutput = task.result;
            NSString *undername = [@"_" stringByAppendingString:self.user.username];
            NSString *gstring = [self.user.username stringByAppendingPathExtension:@"glacier"];
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
            
            if (self.dataArray.count > 0 && [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"openvpn://"]]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    CZPickerView *picker = [[CZPickerView alloc] initWithHeaderTitle:@"Add VPN Connection"
                                                                   cancelButtonTitle:@"Cancel"
                                                                  confirmButtonTitle:@"Confirm"];
                    picker.delegate = self;
                    picker.dataSource = self;
                    /** picker header background color */
                    picker.headerBackgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"color_Gl" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil]];
                    
                    [picker show];
                });
            }
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
            //self.bucketPrefix = [org stringByAppendingPathComponent:userpath];
            //downloadRequest.prefix = self.bucketPrefix;
            //request.Key = "RootFolder/SubFolder/MyObject.txt";
            downloadRequest.key = keytest;
            //downloadRequest.key = [self.glacierData lastPathComponent];
            downloadRequest.downloadingFileURL = self.glacierData;
            [self download:downloadRequest];
        }
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
        
        dispatch_async(dispatch_get_main_queue(), ^{
            //[self lookForAccountInfoIfNeeded];
        });
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
            //[self.controller presentOpenInMenuFromRect:self.view.frame inView:self.view animated:YES];
        }
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

- (BOOL) needsOpenVPN {
    if (![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"openvpn://"]])
    {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:@"You do not have an app that can open this file. Please download OpenVPN Connect from the App Store." preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:cancel];
        //[self presentViewController:alert animated:YES completion:nil];
        return true;
    }
    
    return false;
}

#pragma mark - Delegate Methods
- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    return  self;
}

- (void)documentInteractionController:(UIDocumentInteractionController *)controller willBeginSendingToApplication:(NSString *)application {
    //NSLog(@"Starting to send this puppy to %@", application);
}

- (void)documentInteractionController:(UIDocumentInteractionController *)controller didEndSendingToApplication:(NSString *)application {
    //NSLog(@"We're done sending the document.");
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
        //downloadRequest.key = [downloadingFileURL lastPathComponent];//s3Object.key;
        downloadRequest.key = keytest;
        downloadRequest.downloadingFileURL = downloadingFileURL;
        [self download:downloadRequest];
    }
}

/** delegate method for canceling */
- (void)czpickerViewDidClickCancelButton:(CZPickerView *)pickerView {
    
}

#pragma - mark Singlton Methodd

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
