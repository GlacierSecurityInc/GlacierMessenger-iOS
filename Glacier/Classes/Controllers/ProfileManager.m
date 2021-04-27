//
//  ProfileManager.m
//  Glacier
//
//  Created by Andy Friedman on 11/5/20.
//  Copyright © 2020 Glacier. All rights reserved.
//

#import "ProfileManager.h"
#import "ProfileViewController.h"
#import "OTRViewSetting.h"
#import "OTRSetting.h"
#import "OTRBoolSetting.h"
#import "OTRViewSetting.h"
#import "OTRDoubleSetting.h"
#import "OTRConstants.h"
#import "OTRSettingsGroup.h"
#import "OTRIntSetting.h"
#import "OTRUtilities.h"
#import "Glacier-Swift.h"
#import "GlacierInfo.h"
#import "OTRStrings.h"

@implementation ProfileManager

- (instancetype) init
{
    if (self = [super init])
    {
        [self populateSettings];
    }
    return self;
}

- (void) populateSettings
{
    NSMutableArray<OTRSettingsGroup*> *settingsGroups = [NSMutableArray array];
    NSMutableDictionary *newSettingsDictionary = [NSMutableDictionary dictionary];
    // Leave this in for now
    OTRViewSetting *accountsViewSetting = [[OTRViewSetting alloc] initWithTitle:ACCOUNTS_STRING() description:nil viewControllerClass:nil];
    
    OTRViewSetting *resetPasswordSetting = [[OTRViewSetting alloc] initWithTitle:@"Reset Password" description:nil viewControllerClass:nil];
    resetPasswordSetting.actionBlock = ^void(id sender) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://console.glaciersec.cc/forget-password/"] options:@{} completionHandler:nil];
    };
    
    OTRViewSetting *resetSecureConnectionsSetting = [[OTRViewSetting alloc] initWithTitle:@"Reset Secure Sessions" description:nil viewControllerClass:nil];
    resetSecureConnectionsSetting.actionBlock = ^void(id sender) {
        ProfileViewController *sourceVC = sender;
        if ([sender isKindOfClass:[ProfileViewController class]]) {
            [sourceVC resetSecureConnectionsButtonPressed];
        }
    };
    
    OTRSettingsGroup *accountsGroup = [[OTRSettingsGroup alloc] initWithTitle:@"Account" settings:@[accountsViewSetting,resetPasswordSetting,resetSecureConnectionsSetting]];
    [settingsGroups addObject:accountsGroup];
    
    //get teams
    OTRSettingsGroup *teamsGroup = [[OTRSettingsGroup alloc] initWithTitle:@"Teams" settings:@[]];
    [settingsGroups addObject:teamsGroup];
    
    OTRViewSetting *noCurrentSessionSetting = [[OTRViewSetting alloc] initWithTitle:@"No current session" description:nil viewControllerClass:nil];
    OTRSettingsGroup *currentSessionGroup = [[OTRSettingsGroup alloc] initWithTitle:@"Current Session" settings:@[noCurrentSessionSetting]];
    [settingsGroups addObject:currentSessionGroup];
    
    OTRViewSetting *removeOtherDevicesSetting = [[OTRViewSetting alloc] initWithTitle:@"Clear Devices" description:nil viewControllerClass:nil];
    removeOtherDevicesSetting.actionBlock = ^void(id sender) {
        ProfileViewController *sourceVC = sender;
        if ([sender isKindOfClass:[ProfileViewController class]]) {
            [sourceVC clearDevicesButtonPressed];
        }
    };
    OTRViewSetting *noOtherDevicesSetting = [[OTRViewSetting alloc] initWithTitle:@"No other devices" description:nil viewControllerClass:nil];
    OTRSettingsGroup *otherDevicesGroup = [[OTRSettingsGroup alloc] initWithTitle:@"Other Devices" settings:@[removeOtherDevicesSetting, noOtherDevicesSetting]];
    [settingsGroups addObject:otherDevicesGroup];
    
    _settingsDictionary = newSettingsDictionary;
    _settingsGroups = settingsGroups;
}

- (void) handleChangeDisplayName:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Change Display Name" message:nil preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Display Name";
    }];
    
    UIAlertAction *change = [UIAlertAction actionWithTitle:@"Change" style:UIAlertActionStyleDefault        handler:^(UIAlertAction * _Nonnull action) {
        ProfileViewController *sourceVC = sender;
        if (![sender isKindOfClass:[ProfileViewController class]]) {
            return;
        }
        if ([sourceVC respondsToSelector:@selector(changeDisplayName:withNewName:)]) {
            NSString *newname = alert.textFields.firstObject.text;
            if (newname.length > 1) {
                [sourceVC changeDisplayName:self withNewName:newname];
            }
        }
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:cancel];
    [alert addAction:change];
    
    UIViewController *sourceVC = sender;
    if (![sender isKindOfClass:[UIViewController class]]) {
        return;
    } else {
        alert.popoverPresentationController.sourceView = sourceVC.view;
        alert.popoverPresentationController.sourceRect = sourceVC.view.bounds;
    }
    [sourceVC presentViewController:alert animated:YES completion:nil];
}

- (OTRSetting*) settingAtIndexPath:(NSIndexPath*)indexPath
{
    OTRSettingsGroup *settingsGroup = [self.settingsGroups objectAtIndex:indexPath.section];
    return [settingsGroup.settings objectAtIndex:indexPath.row];
}

- (OTRSetting*) settingAtIndexPath:(NSIndexPath*)indexPath row:(NSUInteger)row
{
    OTRSettingsGroup *settingsGroup = [self.settingsGroups objectAtIndex:indexPath.section];
    return [settingsGroup.settings objectAtIndex:row];
}

- (NSString*) stringForGroupInSection:(NSUInteger)section
{
    OTRSettingsGroup *settingsGroup = [self.settingsGroups objectAtIndex:section];
    return settingsGroup.title;
}

- (NSUInteger) numberOfSettingsInSection:(NSUInteger)section
{
    OTRSettingsGroup *settingsGroup = [self.settingsGroups objectAtIndex:section];
    return [settingsGroup.settings count];
}

- (nullable NSIndexPath *)indexPathForSetting:(OTRSetting *)setting
{
    __block NSIndexPath *indexPath = nil;
    [self.settingsGroups enumerateObjectsUsingBlock:^(OTRSettingsGroup *group, NSUInteger idx, BOOL *stop) {
        NSUInteger row = [group.settings indexOfObject:setting];
        if (row != NSNotFound) {
            indexPath = [NSIndexPath indexPathForItem:row inSection:idx];
            *stop = YES;
        }
    }];
    return indexPath;
}

+ (BOOL) boolForOTRSettingKey:(NSString*)key
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults boolForKey:key];
}

+ (double) doubleForOTRSettingKey:(NSString*)key
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults doubleForKey:key];
}

+ (NSInteger) intForOTRSettingKey:(NSString *)key
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults integerForKey:key];
}

+ (float) floatForOTRSettingKey:(NSString *)key
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults floatForKey:key];
}

- (nullable OTRSetting*) settingForOTRSettingKey:(NSString*)key {
    return [self.settingsDictionary objectForKey:key];
}

// currently used for global expiration timer
+ (nullable NSString *) stringForOTRSettingKey:(NSString *)key
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults stringForKey:key];
}

@end

