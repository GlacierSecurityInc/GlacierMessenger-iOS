//
//  GlacierInfo.h
//  Glacier
//
//  Created by Andy Friedman on 6/17/20.
//  Copyright © 2020 Glacier. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const kOTRDefaultLanguageLocale;
FOUNDATION_EXPORT NSString *const kOTRSettingKeyLanguage;

@interface GlacierInfo : NSObject

/** Returns OTRResources.bundle */
@property (class, readonly) NSBundle* resourcesBundle;

/** The default XMPP resource (e.g. username@example.com/chatsecure) */
@property (class, readonly) NSString* xmppResource;

/** Email for user feedback e.g. support@chatsecure.org */
@property (class, readonly) NSString* feedbackEmail;

/** If enabled, will show a ⚠️ symbol next to your account when push may have issues */
@property (class, readonly) BOOL shouldShowPushWarning;

/** If enabled, the server selection cell will be shown when creating new accounts. Otherwise it will be hidden in the 'advanced' section. */
@property (class, readonly) BOOL shouldShowServerCell;

/** If enabled, will show colors for status indicators. */
@property (class, readonly) BOOL showsColorForStatus;

/** If enabled, will show UI for enabling OMEMO group encryption. Superceded by allowOMEMO setting. */
@property (class, readonly) BOOL allowGroupOMEMO;

/** If enabled, will show UI for managing debug log files. */
@property (class, readonly) BOOL allowDebugFileLogging;

/** If enabled, will allow OMEMO functionality within the app. Defaults to YES if setting key is not present. */
@property (class, readonly) BOOL allowOMEMO;

+ (NSString*) awsBucketConstant;
+ (NSString*) defaultHost;
+ (NSURL*) pushAPIURL;

@end
NS_ASSUME_NONNULL_END
