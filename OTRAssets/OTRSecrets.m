//
//  OTRSecrets.m
//  Off the Record
//
//  Created by Chris Ballinger on 12/9/11.
//  Copyright (c) 2012 Chris Ballinger. All rights reserved.
//

#import "OTRSecrets.h"
@import Foundation;
#import "OTRAssets.h"

static NSString *const kOTRGoogleAppSecret = @"kOTRGoogleAppSecret";
static NSString *const kOTRHockeyLiveIdentifier = @"kOTRHockeyLiveIdentifier";
static NSString *const kOTRHockeyBetaIdentifier = @"kOTRHockeyBetaIdentifier";

@implementation OTRSecrets

+ (NSString*) googleAppSecret {
    return [[self defaultPlist] objectForKey:kOTRGoogleAppSecret];
}

+ (NSString*) hockeyLiveIdentifier {
    return [[self defaultPlist] objectForKey:kOTRHockeyLiveIdentifier];
}

+ (NSString*) hockeyBetaIdentifier {
    return [[self defaultPlist] objectForKey:kOTRHockeyBetaIdentifier];
}

+ (NSString*) awsBucketConstant {
    return [[self defaultPlist] objectForKey:@"s3BucketConstant"];
}

+ (NSString*) defaultHost {
    return [[self defaultPlist] objectForKey:@"defaultHost"];
}

+ (NSString*) defaultPublicHost {
    return [[self defaultPlist] objectForKey:@"defaultPublicHost"];
}

+ (NSString*) altPublicHost {
    return [[self defaultPlist] objectForKey:@"alternatePublicHost"];
}

+ (NSURL *)pushAPIURL {
    NSString *urlString = [[self defaultPlist] objectForKey:@"pushAPIURL"];
    NSURL *url = [NSURL URLWithString:urlString];
    return url;
}

+ (NSDictionary*) defaultPlist {
    NSBundle *bundle = [OTRAssets resourcesBundle];
    NSString *path = [bundle pathForResource:@"Secrets" ofType:@"plist"];
    NSParameterAssert(path != nil);
    NSDictionary *plist = [[NSDictionary alloc] initWithContentsOfFile:path];
    NSParameterAssert(plist != nil);
    return plist;
}

@end
