//
//  GlacierInfo.m
//  Glacier
//
//  Created by Andy Friedman on 6/17/20.
//  Copyright © 2020 Glacier. All rights reserved.
//

#import "GlacierInfo.h"
@import Foundation;

NSString *const kOTRSettingKeyLanguage                 = @"userSelectedSetting";
NSString *const kOTRDefaultLanguageLocale = @"kOTRDefaultLanguageLocale";

static NSString *const kOTRXMPPResource = @"kOTRXMPPResource";
static NSString *const kOTRFeedbackEmail = @"kOTRFeedbackEmail";

@implementation GlacierInfo

+ (NSString*) awsBucketConstant {
    return [[self defaultPlist] objectForKey:@"s3BucketConstant"];
}

+ (NSString*) defaultHost {
    return [[self defaultPlist] objectForKey:@"defaultHost"];
}

+ (NSURL *)pushAPIURL {
    NSString *urlString = [[self defaultPlist] objectForKey:@"pushAPIURL"];
    NSURL *url = [NSURL URLWithString:urlString];
    return url;
}

/** The default XMPP resource (e.g. username@example.com/glacier) */
+ (NSString*) xmppResource {
    return [[self brandingPlist] objectForKey:kOTRXMPPResource];
}

/** Email for user feedback  */
+ (NSString*) feedbackEmail {
    return [[self brandingPlist] objectForKey:kOTRFeedbackEmail];
}

/** If enabled, will show a ⚠️ symbol next to your account when push may have issues */
+ (BOOL) shouldShowPushWarning {
    BOOL result = [[[self brandingPlist] objectForKey:@"ShouldShowPushWarning"] boolValue];
    return result;
}

/** If enabled, the server selection cell will be shown when creating new accounts. Otherwise it will be hidden in the 'advanced' section. */
+ (BOOL) shouldShowServerCell {
    BOOL result = [[[self brandingPlist] objectForKey:@"ShouldShowServerCell"] boolValue];
    return result;
}

+ (BOOL) showsColorForStatus {
    BOOL result = [[[self brandingPlist] objectForKey:@"ShowsColorForStatus"] boolValue];
    return result;
}

+ (BOOL) allowGroupOMEMO {
    /*if (![self allowOMEMO]) {
        return NO;
    }
    BOOL result = [[[self brandingPlist] objectForKey:@"AllowGroupOMEMO"] boolValue];
    return result;*/
    return true;
}

+ (BOOL) allowDebugFileLogging {
    BOOL result = [[[self brandingPlist] objectForKey:@"AllowDebugFileLogging"] boolValue];
    return result;
}

+ (BOOL) allowOMEMO {
    return true;
    /*NSNumber *result = [[self brandingPlist] objectForKey:@"AllowOMEMO"];
    if (!result) {
        return YES;
    } else {
        return result.boolValue;
    }*/
}

+ (NSDictionary*) brandingPlist {
    // Normally this won't be nil, but they WILL be nil during tests.
    NSBundle *bundle = [self resourcesBundle];
    NSString *path = [bundle pathForResource:@"Branding" ofType:@"plist"];
    //NSParameterAssert(path != nil);
    NSDictionary *plist = [[NSDictionary alloc] initWithContentsOfFile:path];
    //NSParameterAssert(plist != nil);
    return plist;
}


+ (NSDictionary*) defaultPlist {
    NSBundle *bundle = [self resourcesBundle];
    NSString *path = [bundle pathForResource:@"Secrets" ofType:@"plist"];
    NSParameterAssert(path != nil);
    NSDictionary *plist = [[NSDictionary alloc] initWithContentsOfFile:path];
    NSParameterAssert(plist != nil);
    return plist;
}

+ (NSBundle*) resourcesBundle {
    // Use resources from main bundle first, assuming the defaults are being overridden
    NSString *folderName = @"OTRResources.bundle";
    NSString *bundlePath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:folderName];
    NSBundle *dataBundle = [NSBundle bundleWithPath:bundlePath];
    
    // Usually this is only the case for tests
    if (!dataBundle) {
        NSBundle *containingBundle = [NSBundle bundleForClass:self.class];
        NSString *bundlePath = [[containingBundle resourcePath] stringByAppendingPathComponent:folderName];
        dataBundle = [NSBundle bundleWithPath:bundlePath];
    }
    return dataBundle;
}

@end

