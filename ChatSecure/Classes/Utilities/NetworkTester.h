//
//  NetworkTester.h
//  ChatSecure
//
//  Created by Andy Friedman on 7/10/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

@import Foundation;
#import "SimplePing.h"
#import "OTRProtocol.h"

NS_ASSUME_NONNULL_BEGIN
@interface NetworkTester : NSObject <SimplePingDelegate>

extern NSString *const NetworkStatusNotificationName;
extern NSString *const OldNetworkStatusKey;
extern NSString *const NewNetworkStatusKey;

@property (nonatomic, retain) SimplePing* simplePing;
@property (nonatomic, retain) NSString * domainAddress;
@property int pingCtr;
@property (nonatomic, assign) NSUInteger pingNum;
@property (nonatomic, readwrite) OTRNetworkConnectionStatus networkStatus;

- (void)setNetworkConnectAttempts:(NSUInteger)attempts;
- (void)setAddress:(NSString *)address;
- (BOOL)hasAddress;
- (void)tryConnectToNetwork;
- (void)ping;
- (void)pingDealloc;
- (void)reset; 
- (void)changeNetworkStatus:(OTRNetworkConnectionStatus)status;

@end
NS_ASSUME_NONNULL_END
