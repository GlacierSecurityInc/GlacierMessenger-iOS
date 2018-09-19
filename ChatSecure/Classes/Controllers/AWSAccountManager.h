//
//  AWSAccountManager.h
//  Off the Record
//  Created by Christopher Ballinger on 10/17/13.
//  Copyright (c) 2013 Chris Ballinger. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@interface AWSAccountManager : NSObject

- (void)setupCognito;
- (void)teardownCognito;
- (BOOL)setupDatabaseWithName:(NSString*)databaseName
                    directory:(nullable NSString*)directory
                  withMediaStorage:(BOOL)withMediaStorage;

+ (instancetype)sharedInstance;
@property (class, nonatomic, readonly) AWSAccountManager *shared;

@end
NS_ASSUME_NONNULL_END
