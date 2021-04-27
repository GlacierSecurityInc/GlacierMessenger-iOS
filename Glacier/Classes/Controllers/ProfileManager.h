//
//  ProfileManager.h
//  Glacier
//
//  Created by Andy Friedman on 11/5/20.
//  Copyright © 2020 Glacier. All rights reserved.
//

@import Foundation;
#import "OTRSetting.h"
#import "OTRConstants.h"

@class OTRSettingsGroup;
NS_ASSUME_NONNULL_BEGIN

@interface ProfileManager : NSObject

@property (nonatomic, strong, readonly) NSArray<OTRSettingsGroup*> *settingsGroups;
@property (nonatomic, strong, readonly) NSDictionary<NSString*,OTRSetting*> *settingsDictionary;

- (OTRSetting*) settingAtIndexPath:(NSIndexPath*)indexPath;
- (OTRSetting*) settingAtIndexPath:(NSIndexPath*)indexPath row:(NSUInteger)row;
- (NSString*) stringForGroupInSection:(NSUInteger)section;
- (NSUInteger) numberOfSettingsInSection:(NSUInteger)section;
- (nullable OTRSetting*) settingForOTRSettingKey:(NSString*)key;

- (nullable NSIndexPath *)indexPathForSetting:(OTRSetting *)setting;

- (void) handleChangeDisplayName:(id)sender;

+ (BOOL) boolForOTRSettingKey:(NSString*)key;
+ (double) doubleForOTRSettingKey:(NSString*)key;
+ (NSInteger) intForOTRSettingKey:(NSString *)key;
+ (float) floatForOTRSettingKey:(NSString *)key;

/** Recalculates current setting list */
- (void) populateSettings;

@end
NS_ASSUME_NONNULL_END
