//
//  OTRSettingsManager.m
//  Off the Record
//
//  Created by Chris Ballinger on 4/10/12.
//  Copyright (c) 2012 Chris Ballinger. All rights reserved.
//
//  This file is part of ChatSecure.
//
//  ChatSecure is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ChatSecure is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with ChatSecure.  If not, see <http://www.gnu.org/licenses/>.

#import "OTRSettingsManager.h"
#import "OTRViewSetting.h"
@import OTRAssets;
#import "OTRSetting.h"
#import "OTRBoolSetting.h"
#import "OTRViewSetting.h"
#import "OTRDoubleSetting.h"
#import "OTRFeedbackSetting.h"
#import "OTRConstants.h"
#import "OTRShareSetting.h"
#import "OTRSettingsGroup.h"
#import "OTRLanguageSetting.h"
#import "OTRDonateSetting.h"
#import "OTRIntSetting.h"
#import "OTRCertificateSetting.h"
#import "OTRUtilities.h"
#import <ChatSecureCore/ChatSecureCore-Swift.h>

#import "OTRUtilities.h"

@interface OTRSettingsManager () <TimerPickerDelegate>
@property (nonatomic, strong) OTRValueSetting *globalMessageTimerSetting;
@end

@implementation OTRSettingsManager

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
    OTRSettingsGroup *accountsGroup = [[OTRSettingsGroup alloc] initWithTitle:@"Account" settings:@[accountsViewSetting]];
    [settingsGroups addObject:accountsGroup];
    
    if (OTRBranding.allowsDonation) {
        NSString *donateTitle = DONATE_STRING();
        if (TransactionObserver.hasValidReceipt) {
            donateTitle = [NSString stringWithFormat:@"%@    ✅", DONATE_STRING()];
        } else {
            donateTitle = [NSString stringWithFormat:@"%@    🆕", DONATE_STRING()];
        }
        OTRDonateSetting *donateSetting = [[OTRDonateSetting alloc] initWithTitle:donateTitle description:nil];
        //donateSetting.imageName = @"29-heart.png";
        OTRSetting *moreSetting = [[OTRSetting alloc] initWithTitle:MORE_WAYS_TO_HELP_STRING() description:nil];
        moreSetting.actionBlock = ^void(id sender) {
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Purchase" bundle:[OTRAssets resourcesBundle]];
            UIViewController *moreVC = [storyboard instantiateViewControllerWithIdentifier:@"moreWaysToHelp"];
            UIViewController *sourceVC = sender;
            if (![sender isKindOfClass:[UIViewController class]]) {
                return;
            }
            [sourceVC presentViewController:moreVC animated:YES completion:nil];
        };
        OTRSettingsGroup *donateGroup = [[OTRSettingsGroup alloc] initWithTitle:DONATE_STRING() settings:@[donateSetting, moreSetting]];
        [settingsGroups addObject:donateGroup];
    }
    
    OTRBoolSetting *deletedDisconnectedConversations = [[OTRBoolSetting alloc] initWithTitle:DELETE_CONVERSATIONS_ON_DISCONNECT_TITLE_STRING()
                                                                                 description:DELETE_CONVERSATIONS_ON_DISCONNECT_DESCRIPTION_STRING()
                                                                                 settingsKey:kOTRSettingKeyDeleteOnDisconnect];
    
    [newSettingsDictionary setObject:deletedDisconnectedConversations forKey:kOTRSettingKeyDeleteOnDisconnect];
    
    OTRCertificateSetting * certSetting = [[OTRCertificateSetting alloc] initWithTitle:PINNED_CERTIFICATES_STRING()
                                                                           description:PINNED_CERTIFICATES_DESCRIPTION_STRING()];
    
    certSetting.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    OTRBoolSetting *backupKeySetting = [[OTRBoolSetting alloc] initWithTitle:ALLOW_DB_PASSPHRASE_BACKUP_TITLE_STRING()
                                                                 description:ALLOW_DB_PASSPHRASE_BACKUP_DESCRIPTION_STRING()
                                                                 settingsKey:kOTRSettingKeyAllowDBPassphraseBackup];

    OTRViewSetting *clearHistorySetting = [[OTRViewSetting alloc] initWithTitle:@"Clear all history"
                                                                    description:nil viewControllerClass:nil];
    clearHistorySetting.actionBlock = ^void(id sender) {
        [self handleClearMessages:sender];
    };
    [newSettingsDictionary setObject:clearHistorySetting forKey:@"kOTRSettingKeyClearHistory"];
    
    self.globalMessageTimerSetting = [[OTRValueSetting alloc] initWithTitle:@"Global message timer (off)" description:nil settingsKey:@"globalTimer"];
    NSInteger selrow = [self currentGlobalTimeSelectedRow];
    [self timeSelected:selrow];
    __unsafe_unretained typeof(self) weakSelf = self;
    self.globalMessageTimerSetting.actionBlock = ^void(id sender) {
        [weakSelf handleGlobalMessageTimer:sender];
    };
    [newSettingsDictionary setObject:self.globalMessageTimerSetting forKey:@"kOTRSettingKeyGlobalTimer"];
    
    if (![PushController canReceivePushNotifications] ||
        [PushController getPushPreference] != PushPreferenceEnabled) {
        
        //always try to enable push notifications
        [PushController setPushPreference:PushPreferenceEnabled];
        [PushController registerForPushNotifications];
    }
    
    NSArray *chatSettings = @[self.globalMessageTimerSetting,clearHistorySetting];
    OTRSettingsGroup *chatSettingsGroup = [[OTRSettingsGroup alloc] initWithTitle:@"Privacy" settings:chatSettings];
    [settingsGroups addObject:chatSettingsGroup];
    
    OTRViewSetting *privacyInfoSetting = [[OTRViewSetting alloc] initWithTitle:@"Privacy Information" description:nil viewControllerClass:nil];
    privacyInfoSetting.actionBlock = ^void(id sender) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://www.glaciersecurity.com/privacy-policy/"]];
    };
    [newSettingsDictionary setObject:privacyInfoSetting forKey:@"kOTRSettingKeyPrivacyInfo"];
    
    NSArray * otherSettings = nil;
    if ( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ) {
        OTRBoolSetting *enterToSendSetting = [[OTRBoolSetting alloc] initWithTitle:@"Tap enter to send" description:nil settingsKey:@"kOTREnterToSendKey"];
        [newSettingsDictionary setObject:enterToSendSetting forKey:@"kOTREnterToSendKey"];
        otherSettings = @[privacyInfoSetting,enterToSendSetting];
    } else {
        otherSettings = @[privacyInfoSetting];
    }
    OTRSettingsGroup *otherSettingsGroup = [[OTRSettingsGroup alloc] initWithTitle:@"Other" settings:otherSettings];
    [settingsGroups addObject:otherSettingsGroup];
    
    OTRSettingsGroup *advancedGroup = [[OTRSettingsGroup alloc] initWithTitle:ADVANCED_STRING()];
    
    if (OTRBranding.allowDebugFileLogging) {
        OTRViewSetting *logsSetting = [[OTRViewSetting alloc] initWithTitle:MANAGE_DEBUG_LOGS_STRING()
                                                                description:nil
                                                        viewControllerClass:[OTRLogListViewController class]];
        logsSetting.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        [advancedGroup addSetting:logsSetting];
    }
    
    if (advancedGroup.settings.count > 0) {
        [settingsGroups addObject:advancedGroup];
    }
    
    _settingsDictionary = newSettingsDictionary;
    _settingsGroups = settingsGroups;
}

- (void) handleGlobalMessageTimer:(id)sender {
    OTRSettingsViewController *sourceVC = sender;
    if (![sender isKindOfClass:[OTRSettingsViewController class]]) {
        return;
    }
    if ([sourceVC respondsToSelector:@selector(showTimerSelector:withSelectedRow:)]) {
        NSInteger selrow = [self currentGlobalTimeSelectedRow];
        [sourceVC showTimerSelector:self withSelectedRow:selrow];
    }
}

- (NSInteger) currentGlobalTimeSelectedRow {
    if([OTRSettingsManager stringForOTRSettingKey:@"globalTimer"] != nil) {
        NSString *gtime = [OTRSettingsManager stringForOTRSettingKey:@"globalTimer"];
        if ([gtime isEqualToString:@"604800"]) {
            return 5;
        } else if ([gtime isEqualToString:@"86400"]) {
            return 4;
        } else if ([gtime isEqualToString:@"300"]) {
            return 3;
        } else if ([gtime isEqualToString:@"60"]) {
            return 2;
        } else if ([gtime isEqualToString:@"15"]) {
            return 1;
        } else  {
            return 0;
        }
    } else {
        return 0;
    }
}

- (void)timeSelected:(NSInteger)row {
    
    NSString *time = nil;
    switch (row)
    {
        case 1:
            [self.globalMessageTimerSetting setValue:@"15"];
            time = @"15 seconds";
            break;
        case 2:
            [self.globalMessageTimerSetting setValue:@"60"];
            time = @"1 minute";
            break;
        case 3:
            [self.globalMessageTimerSetting setValue:@"300"];
            time = @"5 minutes";
            break;
        case 4:
            [self.globalMessageTimerSetting setValue:@"86400"];
            time = @"1 day";
            break;
        case 5:
            [self.globalMessageTimerSetting setValue:@"604800"];
            time = @"1 week";
            break;
        default:
            [self.globalMessageTimerSetting setValue:@"Off"];
            break;
    }
    
    if (time == nil) {
        self.globalMessageTimerSetting.title = @"Global message timer (off)";
    } else {
        NSString *gtitle = [NSString stringWithFormat:@"Global message timer - %@", time];
        self.globalMessageTimerSetting.title = gtitle;
    }
}

// delete all messages
- (void) handleClearMessages:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear all history" message:@"Are you sure you want to delete all your history and attachments? This cannot be reverted." preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *clear = [UIAlertAction actionWithTitle:@"Clear Now" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSArray *accounts = [OTRAccountsManager allAccounts];
        [accounts enumerateObjectsUsingBlock:^(OTRAccount * account, NSUInteger idx, BOOL *stop) {
            YapDatabaseConnection *rwDatabaseConnection = [OTRDatabaseManager sharedInstance].writeConnection;
            [rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                [OTRBaseMessage deleteAllMessagesForAccountId:account.uniqueId transaction:transaction];
            }];
        }];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:clear];
    [alert addAction:cancel];
    
    UIViewController *sourceVC = sender;
    if (![sender isKindOfClass:[UIViewController class]]) {
        return;
    }
    [sourceVC presentViewController:alert animated:YES completion:nil];
}

- (void) handleChangeDisplayName:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Change Display Name" message:nil preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Display Name";
    }];
    
    UIAlertAction *change = [UIAlertAction actionWithTitle:@"Change" style:UIAlertActionStyleDefault        handler:^(UIAlertAction * _Nonnull action) {
        OTRSettingsViewController *sourceVC = sender;
        if (![sender isKindOfClass:[OTRSettingsViewController class]]) {
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

+ (BOOL) allowGroupOMEMO {
    return true;
}

@end
