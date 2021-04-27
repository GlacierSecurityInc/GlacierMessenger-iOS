//
//  ProfileViewController.m
//  Glacier
//
//  Created by Andy Friedman on 11/5/20.
//  Copyright © 2020 Glacier. All rights reserved.
//
#import "ProfileViewController.h"
#import "OTRSettingsManager.h"
#import "OTRProtocolManager.h"
#import "OTRBoolSetting.h"
#import "OTRSettingTableViewCell.h"
#import "OTRSettingDetailViewController.h"
//#import "OTRQRCodeViewController.h"
//@import QuartzCore;
#import "OTRConstants.h"
#import "OTRAccountTableViewCell.h"
#import "UIActionSheet+ChatSecure.h"
@import YapDatabase;
#import "OTRDatabaseManager.h"
#import "OTRDatabaseView.h"
#import "OTRAccount.h"
#import "OTRAppDelegate.h"
#import "OTRUtilities.h"
//#import "OTRQRCodeActivity.h"
#import "OTRBaseLoginViewController.h"
#import "OTRXLFormCreator.h"
#import "OTRViewSetting.h"
#import "Glacier-Swift.h"
#import "GlacierInfo.h"
@import MobileCoreServices;
@import MBProgressHUD;

#import "NSURL+ChatSecure.h"

static NSString *const kSettingsCellIdentifier = @"kSettingsCellIdentifier";

@interface ProfileViewController () <UITableViewDataSource, UITableViewDelegate, OTRYapViewHandlerDelegateProtocol,OTRSettingDelegate, UIPopoverPresentationControllerDelegate, OTRAttachmentPickerDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) OTRYapViewHandler *viewHandler;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) OMEMODevice *currentDevice;
@property (nonatomic, strong) NSArray<OMEMODevice *>* allDevices;
@property (nonatomic, strong) NSArray* teams;
@property (nonatomic) CGFloat teamsHeight;
@property (nonatomic) CGFloat viewWidth;

/** This is only non-nil during avatar picking */
@property (nonatomic, nullable) OTRAttachmentPicker *avatarPicker;

@end

@implementation ProfileViewController

- (id) init
{
    if (self = [super init])
    {
        self.title = @"My Profile";
        _profileManager = [[ProfileManager alloc] init];
        self.viewWidth = 375;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    //User main thread database connection
    self.viewHandler = [[OTRYapViewHandler alloc] initWithDatabaseConnection:[OTRDatabaseManager sharedInstance].longLivedReadOnlyConnection databaseChangeNotificationName:[DatabaseNotificationName LongLivedTransactionChanges]];
    self.viewHandler.delegate = self;
    [self.viewHandler setup:OTRAllAccountDatabaseViewExtensionName groups:@[OTRAllAccountGroup]];
    
    
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.accessibilityIdentifier = @"profileTableView";
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:self.tableView];
    [self.tableView registerClass:[OTRAccountTableViewCell class] forCellReuseIdentifier:[OTRAccountTableViewCell cellIdentifier]];
    
    NSBundle *bundle = [NSBundle mainBundle];
    UINib *nib = [UINib nibWithNibName:[XMPPAccountCell cellIdentifier] bundle:bundle];
    [self.tableView registerNib:nib forCellReuseIdentifier:[XMPPAccountCell cellIdentifier]];
    
    //[OMEMODeviceFingerprintCell registerCellClass:[OMEMODeviceFingerprintCell defaultRowDescriptorType]];
    UINib *omemonib = [UINib nibWithNibName:[OMEMODeviceFingerprintCell cellIdentifier] bundle:bundle];
    [self.tableView registerNib:omemonib forCellReuseIdentifier:[OMEMODeviceFingerprintCell cellIdentifier]];
    
    [self getFingerprintData:NO];
}

- (BOOL) getFingerprintData:(BOOL)publish {
    NSIndexPath *acctpath = [NSIndexPath indexPathForRow:0 inSection:0];
    OTRXMPPAccount *account = [self accountAtIndexPath:acctpath];
    OTRXMPPManager *xmpp = (OTRXMPPManager*)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
    OMEMOBundle *bundle = [xmpp.omemoSignalCoordinator fetchMyBundle];
    self.teams = [xmpp getTeams];
    
    if (bundle != nil) {
        NSNumber *idNumber = [NSNumber numberWithInt:bundle.deviceId];
        
        self.currentDevice = [[OMEMODevice alloc] initWithDeviceId:idNumber trustLevel:OMEMOTrustLevelTrustedUser parentKey:account.uniqueId parentCollection:OTRAccount.collection publicIdentityKeyData:bundle.identityKey lastSeenDate:[xmpp getLastConnected]];
        
        __block NSArray<OMEMODevice *>* devices;
        __block NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            if ([evaluatedObject isKindOfClass:[OMEMODevice class]]) {
                OMEMODevice *device = (OMEMODevice *)evaluatedObject;
                if (device.publicIdentityKeyData != nil) {
                    return YES;
                }
            }
            return NO;
        }];
        
        [[OTRDatabaseManager sharedInstance].connections.read asyncReadWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            devices = [OMEMODevice allDevicesForParentKey:account.uniqueId collection:OTRAccount.collection transaction:transaction];
            if (devices != nil) {
                self.allDevices = [devices filteredArrayUsingPredicate:predicate];
            }
        }];
        
        if (publish) {
            [xmpp.omemoSignalCoordinator.omemoModule publishBundle:bundle elementId:nil];
            //NSArray<NSNumber *>* devices = @[self.currentDevice.deviceId];
            NSArray<NSNumber *>* devices = [xmpp.omemoSignalCoordinator fetchDeviceIdsForJID:account.bareJID];
            [xmpp.omemoSignalCoordinator.omemoModule publishDeviceIds:devices elementId:nil];
        }
        
        return true;
    }
    
    return false;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.viewWidth = self.view.bounds.size.width;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // get a reference to the table's footer view
    UIView *currentFooterView = [self.tableView tableFooterView];
    
    // if it's a valid reference (the table *does* have a footer view)
    if (currentFooterView) {
        
        // tell auto-layout to calculate the size based on the footer view's content
        CGFloat newHeight = [currentFooterView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
        
        // get the current frame of the footer view
        CGRect currentFrame = currentFooterView.frame;
        
        // we only want to do this when necessary (otherwise we risk infinite recursion)
        // so... if the calculated height is not the same as the current height
        if (newHeight != currentFrame.size.height) {
            // use the new (calculated) height
            currentFrame.size.height = newHeight;
            currentFooterView.frame = currentFrame;
        }
        
    }
}

- (void)clearDevicesButtonPressed {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear Devices" message:@"Are you sure you want to clear all your other devices? The next time your other devices with the same account connect they will reannounce themselves, but they might not receive messages sent in the meantime." preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *reset = [UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self doClearDevices:YES];
       
        //above is not returning for some reason, so assume it worked, wait a second and reload
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.allDevices = nil;
            [self.tableView reloadData];
        });
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:reset];
    [alert addAction:cancel];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetSecureConnectionsButtonPressed {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Secure Sessions" message:@"This may help if you are having problems with message delivery. All your messages will be kept." preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *reset = [UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self doResetSecureConnections];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:reset];
    [alert addAction:cancel];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void) doClearDevices:(BOOL)publish {
    NSIndexPath *acctpath = [NSIndexPath indexPathForRow:0 inSection:0];
    OTRXMPPAccount *account = [self accountAtIndexPath:acctpath];
    
    if (self.currentDevice != nil && account != nil) {
        NSArray<NSNumber *>* devices = @[self.currentDevice.deviceId];
        OTRXMPPManager *xmpp = (OTRXMPPManager*)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
        if (publish) {
            [xmpp.omemoSignalCoordinator.omemoModule publishDeviceIds:devices elementId:nil];
        }
        
        __block NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            if ([evaluatedObject isKindOfClass:[OMEMODevice class]]) {
                OMEMODevice *device = (OMEMODevice *)evaluatedObject;
                if (device.deviceId != self.currentDevice.deviceId) {
                    return YES;
                }
            }
            return NO;
        }];
        
        __block NSArray<OMEMODevice *>* allDevices;
        [[OTRDatabaseManager sharedInstance].connections.read readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            NSArray<OMEMODevice *>* devices = [OMEMODevice allDevicesForParentKey:account.uniqueId collection:OTRAccount.collection transaction:transaction];
            if (devices != nil) {
                allDevices = [devices filteredArrayUsingPredicate:predicate];
            }
        }];
        
        if (allDevices != nil) {
            [xmpp.omemoSignalCoordinator removeDevice:allDevices completion:^(BOOL success) {
                //
            }];
        }
    }
}

- (void) doResetSecureConnections {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    
    NSIndexPath *acctpath = [NSIndexPath indexPathForRow:0 inSection:0];
    __block OTRXMPPAccount *account = [self accountAtIndexPath:acctpath];
    __block OTRXMPPManager *xmpp = (OTRXMPPManager*)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
    
    __block NSMutableArray *allDevices = [[NSMutableArray alloc] init];
    __block NSArray<OTRXMPPBuddy*> *buddiesArray = nil;
    [[OTRDatabaseManager sharedInstance].connections.read readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        buddiesArray = [account allBuddiesWithTransaction:transaction];
        //buddiesArray = [OTRXMPPAccount allBuddiesWithAccountId:account.uniqueId transaction:transaction];
        [buddiesArray enumerateObjectsUsingBlock:^(OTRBuddy * _Nonnull buddy, NSUInteger idx, BOOL * _Nonnull stop) {
            NSArray<OMEMODevice*> *devices = [OMEMODevice allDevicesForParentKey:buddy.uniqueId collection:OTRXMPPBuddy.collection transaction:transaction];
            //NSArray<OMEMODevice*> *devices = [buddy omemoDevicesWithTransaction:transaction];
            [allDevices addObjectsFromArray:devices];
        }];
    }];
    
    [xmpp.omemoSignalCoordinator removeDevice:allDevices completion:^(BOOL success) {
        //[self doClearDevices:NO];
        //only clear current device
        if (self.currentDevice != nil) {
            NSArray<OMEMODevice *>* mydevices = @[self.currentDevice];
            [xmpp.omemoSignalCoordinator removeDevice:mydevices completion:^(BOOL success) {
                //
            }];
        }
        
        [[OTRDatabaseManager sharedInstance].connections.write asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            OTRAccountSignalIdentity *identityKeyPair = [OTRAccountSignalIdentity fetchObjectWithUniqueID:account.uniqueId transaction:transaction];
            if (identityKeyPair != nil) {
                [identityKeyPair removeWithTransaction:transaction];
            }
            OTRSignalSignedPreKey *signedPreKey = [OTRSignalSignedPreKey fetchObjectWithUniqueID:account.uniqueId transaction:transaction];
            if (signedPreKey != nil) {
                [signedPreKey removeWithTransaction:transaction];
            }
        }];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            self.allDevices = nil;
            [self getFingerprintData:YES];
            dispatch_async(dispatch_get_main_queue(), ^{
            //dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                //NSArray<NSNumber *>* devices = @[self.currentDevice.deviceId];
                //[xmpp.omemoSignalCoordinator.omemoModule publishDeviceIds:devices elementId:nil];
                [self.tableView reloadData];
                [hud removeFromSuperview];
            });
        });
    }];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.tableView.frame = self.view.bounds;
    [self.profileManager populateSettings];
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return YES;
    } else {
        return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
    }
}

- (OTRXMPPAccount *)accountAtIndexPath:(NSIndexPath *)indexPath
{
    OTRXMPPAccount *account = [self.viewHandler object:indexPath];
    return account;
}

#pragma mark UITableViewDataSource methods

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleNone;
}

-(UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0 && indexPath.row ==0) {
        UITableViewCell * cell = nil;
        if (indexPath.row != [self.viewHandler.mappings numberOfItemsInSection:indexPath.section]) {
            OTRXMPPAccount *account = [self accountAtIndexPath:indexPath];
            XMPPAccountCell *accountCell = [tableView dequeueReusableCellWithIdentifier:[XMPPAccountCell cellIdentifier] forIndexPath:indexPath];
            [accountCell setAppearanceWithAccount:account];
            accountCell.accessoryType = UITableViewCellAccessoryNone;
            accountCell.displayNameTop.constant = 10;
            [accountCell.userNameLabel setHidden:NO];
            NSString *userStr = [NSString stringWithFormat: @"@%@", account.bareJID.user];
            [accountCell.userNameLabel setText:userStr];
            
            // five taps to get to account settings
            UITapGestureRecognizer *fiveTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(gotoAccountSettings:)];
            fiveTapGesture.numberOfTapsRequired = 5;
            fiveTapGesture.cancelsTouchesInView = NO;
            [accountCell addGestureRecognizer:fiveTapGesture];
            
            accountCell.infoButton.hidden = YES;
            
            UITapGestureRecognizer *nameTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDisplayNameClick:)];
            [accountCell.displayNameLabel addGestureRecognizer:nameTapGesture];

            accountCell.avatarButtonAction = ^(UITableViewCell *cell, id sender) {
                self.avatarPicker = [[OTRAttachmentPicker alloc] initWithParentViewController:self delegate:self];
                self.avatarPicker.tag = account;
                [self.avatarPicker showAlertControllerFromSourceView:cell withCompletion:nil];
            };
            accountCell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell = accountCell;
        }
        return cell;
    } else if (indexPath.section == 1) {
        FlowLabelTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:[FlowLabelTableViewCell cellIdentifier]];
        if (cell == nil)
        {
            cell = FlowLabelTableViewCell.flowCell;
            //cell.myCollectionView.scrollEnabled = false;
        }
        //cell.backgroundColor = [UIColor clearColor];
        [cell updateWithTeams:self.teams];
        self.teamsHeight = [cell getHeightConstraint];
        return cell;
    } else if (indexPath.section == 2 && self.currentDevice != nil) {
        OMEMODeviceFingerprintCell *cell = [tableView dequeueReusableCellWithIdentifier:[OMEMODeviceFingerprintCell cellIdentifier]];
        if (cell == nil)
        {
            cell = [[OMEMODeviceFingerprintCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:[OMEMODeviceFingerprintCell cellIdentifier]];
        }
        if (self.currentDevice != nil) {
            [cell updateWithDevice:self.currentDevice];
            NSIndexPath *ip = [NSIndexPath indexPathForRow:0 inSection:0];
            OTRXMPPAccount *account = [self accountAtIndexPath:ip];
            if (account) {
                
            }
        }
        cell.fingerprintWidth.constant = self.viewWidth-24;
        [cell.trustSwitch setEnabled:NO];
        [cell.trustLevelLabel setHidden:YES];
        [cell.trustSwitch setHidden:YES];
        return cell;
    } else if (indexPath.section > 2) {
        if (indexPath.row == 0) {
            OTRSettingTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellIdentifier];
            if (cell == nil)
            {
                cell = [[OTRSettingTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kSettingsCellIdentifier];
            }
            OTRSetting *setting = [self.profileManager settingAtIndexPath:indexPath];
            if (self.allDevices == nil || self.allDevices.count == 0) {
                setting = [self.profileManager settingAtIndexPath:indexPath row:indexPath.row+1];
            }
            setting.delegate = self;
            cell.otrSetting = setting;
            return cell;
        } else if (self.allDevices != nil && self.allDevices.count > 0) {
            OMEMODeviceFingerprintCell *cell = [tableView dequeueReusableCellWithIdentifier:[OMEMODeviceFingerprintCell cellIdentifier]];
            if (cell == nil)
            {
                cell = [[OMEMODeviceFingerprintCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:[OMEMODeviceFingerprintCell cellIdentifier]];
            }
            OMEMODevice *device = [self.allDevices objectAtIndex:indexPath.row-1];
            if (device != nil) {
                [cell updateWithDevice:device];
            }
            [cell.trustLevelLabel setHidden:YES];
            [cell.lastSeenLabel setText:@"Glacier ID"];
            cell.fingerprintWidth.constant = self.viewWidth-82;
            return cell;
        }
    }
    
    OTRSettingTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellIdentifier];
    if (cell == nil)
    {
        cell = [[OTRSettingTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kSettingsCellIdentifier];
    }
    OTRSetting *setting = [self.profileManager settingAtIndexPath:indexPath];
    setting.delegate = self;
    cell.otrSetting = setting;
    
    return cell;
}

- (void) handleDisplayNameClick:(id)sender {
    if ([OTRAccountsManager allAccounts].count != 0) {
        [_profileManager handleChangeDisplayName:self];
    }
}

- (void)gotoAccountSettings:(id)sender
{
    NSIndexPath *ip = [NSIndexPath indexPathForRow:0 inSection:0];
    OTRXMPPAccount *account = [self accountAtIndexPath:ip];
    if (account) {
        OTRBaseLoginViewController *loginViewController = [[OTRBaseLoginViewController alloc] initWithAccount:account];
        [self.navigationController pushViewController:loginViewController animated:YES];
    }
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self.profileManager.settingsGroups count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)sectionIndex
{
    if (sectionIndex == 0) {
        if ([OTRAccountsManager allAccounts].count == 0) {
            return [self.viewHandler.mappings numberOfItemsInSection:0]+3;
        } else {
            return [self.viewHandler.mappings numberOfItemsInSection:0]+2;
        }
    }
    
    if (sectionIndex == 1) {
        return 1;
    }
    
    if (sectionIndex == 2) {
        return 1;
    }
    
    if (sectionIndex == 3) {
        if (self.allDevices == nil || self.allDevices.count == 0) {
            return 1;
        } else {
            return self.allDevices.count+1;
        }
    }
    
    return [self.profileManager numberOfSettingsInSection:sectionIndex];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        if (indexPath.row != 0) {
            return 50.0;
        } else {
            return [XMPPAccountCell cellHeight];
        }
    } else if (indexPath.section == 1) {
        if (self.teamsHeight > 0 && self.teamsHeight > UITableViewAutomaticDimension) {
            return self.teamsHeight;
        }
    }
    return UITableViewAutomaticDimension;
}

- (NSString*)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [self.profileManager stringForGroupInSection:section];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0 && indexPath.row == 0) {
        //do nothing
    } else if (indexPath.section > 2 && self.allDevices != nil && self.allDevices.count > 0) {
        if (indexPath.row == 0) { //clear devices
            OTRSetting *setting = [self.profileManager settingAtIndexPath:indexPath];
            OTRSettingActionBlock actionBlock = setting.actionBlock;
            if (actionBlock) {
                actionBlock(self);
            }
        }
    } else {
        OTRSetting *setting = [self.profileManager settingAtIndexPath:indexPath];
        OTRSettingActionBlock actionBlock = setting.actionBlock;
        if (actionBlock) {
            actionBlock(self);
        }
    }
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 0) {
        return;
    }
}

#pragma - mark Other Methods

-(void)changeDisplayName:(id)sender withNewName:(NSString *)newname {
    if ([OTRAccountsManager allAccounts].count == 0) {
        return;
    }
    OTRXMPPAccount *xcct = [self accountAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    
    if (!xcct.vCardTemp) {
        XMPPvCardTemp *newvCardTemp = [XMPPvCardTemp vCardTemp];
        xcct.vCardTemp = newvCardTemp;
    }
    
    xcct.vCardTemp.nickname = newname;
    OTRXMPPManager *xmgr = (OTRXMPPManager*)[[OTRProtocolManager sharedInstance] protocolForAccount:xcct];
    [xmgr updateNickname:xcct.vCardTemp];
}

- (NSIndexPath *)indexPathForSetting:(OTRSetting *)setting
{
    return [self.profileManager indexPathForSetting:setting];
}

#pragma mark OTRSettingDelegate method

- (void)refreshView
{
    [self.tableView reloadData];
}

- (void) otrSetting:(OTRSetting*)setting showDetailViewControllerClass:(Class)viewControllerClass
{
    
}

#pragma - mark OTRAttachmentPickerDelegate

- (void)attachmentPicker:(OTRAttachmentPicker *)attachmentPicker gotPhoto:(UIImage *)photo withInfo:(NSDictionary *)info {
    self.avatarPicker = nil;
    OTRXMPPAccount *account = attachmentPicker.tag;
    if (![account isKindOfClass:OTRXMPPAccount.class]) {
        return;
    }
    OTRXMPPManager *xmpp = (OTRXMPPManager*)[OTRProtocolManager.shared protocolForAccount:account];
    if (![xmpp isKindOfClass:OTRXMPPManager.class]) {
        return;
    }
    [xmpp setAvatar:photo completion:nil];
}

- (void)attachmentPicker:(OTRAttachmentPicker *)attachmentPicker gotVideoURL:(NSURL *)videoURL {
    self.avatarPicker = nil;
}

- (NSArray <NSString *>*)attachmentPicker:(OTRAttachmentPicker *)attachmentPicker preferredMediaTypesForSource:(UIImagePickerControllerSourceType)source
{
    return @[(NSString*)kUTTypeImage];
}

#pragma - mark YapDatabse Methods

- (void)didSetupMappings:(OTRYapViewHandler *)handler
{
    [self.tableView reloadData];
}

- (void)didReceiveChanges:(OTRYapViewHandler *)handler sectionChanges:(NSArray<YapDatabaseViewSectionChange *> *)sectionChanges rowChanges:(NSArray<YapDatabaseViewRowChange *> *)rowChanges
{
    if ([rowChanges count] == 0 || [[OTRProtocolManager sharedInstance] isLoggingOut]) {
        return;
    }
    
    [self.tableView beginUpdates];
    
    for (YapDatabaseViewRowChange *rowChange in rowChanges)
    {
        switch (rowChange.type)
        {
            case YapDatabaseViewChangeDelete :
            {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeInsert :
            {
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeMove :
            {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeUpdate :
            {
                [self.tableView reloadRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationNone];
                break;
            }
        }
    }
    
    [self.tableView endUpdates];
}

@end

