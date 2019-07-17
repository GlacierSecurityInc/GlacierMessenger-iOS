//
//  AWSAccountManager.h
//  Off the Record
//  Created by Christopher Ballinger on 10/17/13.
//  Copyright (c) 2013 Chris Ballinger. All rights reserved.
//

@import Foundation;
#import <AWSCognitoIdentityProvider/AWSCognitoIdentityProvider.h>

NS_ASSUME_NONNULL_BEGIN

@interface AWSAccountManager : NSObject

- (void)setupCognito;
- (void)teardownCognito; 
- (void)removeLocalVPNFiles;
- (BOOL)checkLocalVPNProfiles;
- (void)getUserDetails;
- (BOOL)coreSignedIn;
- (void)handleSSO;
- (void)setAuthenticator:(UIViewController *)awsauth;

+ (instancetype)sharedInstance;
@property (class, nonatomic, readonly) AWSAccountManager *shared;

@end
NS_ASSUME_NONNULL_END
