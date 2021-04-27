//
//  AWSAccountManager.h
//  Copyright (c) 2018 Glacier Security. All rights reserved.
//

@import Foundation;
#import <AWSCognitoIdentityProvider/AWSCognitoIdentityProvider.h>

NS_ASSUME_NONNULL_BEGIN

@interface AWSAccountManager : NSObject

- (void)setupCognito;
- (void)teardownCognito;
- (void)removeLocalVPNFiles;
- (void)getUserDetails;
- (BOOL)loginWithoutUI:(NSString *)cpass;
- (BOOL)coreSignedIn;
- (void)handleSSO;
- (void)setAuthenticator:(UIViewController *)awsauth;
- (void) setExpiredSession;
- (void)addVPNConnection; 

+ (instancetype)sharedInstance;
@property (class, nonatomic, readonly) AWSAccountManager *shared;

@end
NS_ASSUME_NONNULL_END
