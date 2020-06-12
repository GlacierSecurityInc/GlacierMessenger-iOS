//
//  OTRSettingsViewController.m
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

#import "OTRSettingsViewController.h"
#import "OTRSettingsManager.h"
#import "OTRProtocolManager.h"
#import "OTRBoolSetting.h"
#import "OTRSettingTableViewCell.h"
#import "OTRSettingDetailViewController.h"
#import "OTRQRCodeViewController.h"
@import QuartzCore;
#import "OTRConstants.h"
#import "OTRAccountTableViewCell.h"
#import "UIActionSheet+ChatSecure.h"
#import "OTRSecrets.h"
@import YapDatabase;
#import "OTRDatabaseManager.h"
#import "OTRDatabaseView.h"
#import "OTRAccount.h"
#import "OTRAppDelegate.h"
#import "OTRUtilities.h"
#import "OTRShareSetting.h"
#import "OTRActivityItemProvider.h"
#import "OTRQRCodeActivity.h"
#import "OTRBaseLoginViewController.h"
#import "OTRXLFormCreator.h"
#import "OTRViewSetting.h"
@import KVOController;
#import "OTRInviteViewController.h"
#import <ChatSecureCore/ChatSecureCore-Swift.h>
@import OTRAssets;
@import MobileCoreServices;

#import "NSURL+ChatSecure.h"

static NSString *const circleImageName = @"31-circle-plus-large.png";

static NSString *const kSettingsCellIdentifier = @"kSettingsCellIdentifier";

@interface OTRSettingsViewController () <UITableViewDataSource, UITableViewDelegate, OTRShareSettingDelegate, OTRYapViewHandlerDelegateProtocol,OTRSettingDelegate, UIPopoverPresentationControllerDelegate, OTRAttachmentPickerDelegate, UIPickerViewDataSource,UIPickerViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) OTRYapViewHandler *viewHandler;
@property (nonatomic, strong) UITableView *tableView;

/** This is only non-nil during avatar picking */
@property (nonatomic, nullable) OTRAttachmentPicker *avatarPicker;

// for global message expiration setting
@property (nonatomic, strong) UIPickerView *timePickerView;
@property (strong, nonatomic) NSArray *pickerArray;
@property (nonatomic, strong) UITextField *timePickerTextField;
@property (nonatomic, strong) UITapGestureRecognizer *timeTapGesture;
@property (nonatomic, strong) UITapGestureRecognizer *timeTapGesture2;
@property (nonatomic, strong) id<TimerPickerDelegate> timeDel;

@end

@implementation OTRSettingsViewController

- (id) init
{
    if (self = [super init])
    {
        self.title = SETTINGS_STRING();
        _settingsManager = [[OTRSettingsManager alloc] init];
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
    self.tableView.accessibilityIdentifier = @"settingsTableView";
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:self.tableView];
    [self.tableView registerClass:[OTRAccountTableViewCell class] forCellReuseIdentifier:[OTRAccountTableViewCell cellIdentifier]];
    
    NSBundle *bundle = [OTRAssets resourcesBundle];
    UINib *nib = [UINib nibWithNibName:[XMPPAccountCell cellIdentifier] bundle:bundle];
    [self.tableView registerNib:nib forCellReuseIdentifier:[XMPPAccountCell cellIdentifier]];
    
    [self createFooterStack];
    
    self.pickerArray = @[@"Off", @"15 seconds", @"1 minute", @"5 minutes", @"1 day", @"1 week"];
    
    ////// KVO //////
    __weak typeof(self)weakSelf = self;
    [self.KVOController observe:[OTRProtocolManager sharedInstance] keyPaths:@[NSStringFromSelector(@selector(numberOfConnectedProtocols)),NSStringFromSelector(@selector(numberOfConnectingProtocols))] options:NSKeyValueObservingOptionNew block:^(id observer, id object, NSDictionary *change) {
        __strong typeof(weakSelf)strongSelf = weakSelf;
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.tableView reloadSections:[[NSIndexSet alloc] initWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
        });
    }];
}

- (void) setupVersionLabel {
    UIButton *versionButton = [[UIButton alloc] init];
    NSString *bundleVersion = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"];
    NSString *buildNumber = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"];
    NSString *versionTitle = [NSString stringWithFormat:@"%@ %@ (%@)", VERSION_STRING(), bundleVersion, buildNumber];
    [versionButton setTitle:versionTitle forState:UIControlStateNormal];
    [versionButton setTitleColor:UIColor.lightGrayColor forState:UIControlStateNormal];
    [versionButton addTarget:self action:@selector(versionButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [versionButton sizeToFit];
    CGRect frame = versionButton.frame;
    frame.size.height = frame.size.height * 2;
    versionButton.frame = frame;
    self.tableView.tableFooterView = versionButton;
}

- (void) createFooterStack {
    UIStackView *footerStackView = [[UIStackView alloc] init];
 
    footerStackView.axis = UILayoutConstraintAxisVertical;
    footerStackView.distribution = UIStackViewDistributionEqualSpacing;
    footerStackView.alignment = UIStackViewAlignmentCenter;
    footerStackView.spacing = 10;
        
    UIButton *versionButton = [[UIButton alloc] init];
    NSString *bundleVersion = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"];
    NSString *buildNumber = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"];
    NSString *versionTitle = [NSString stringWithFormat:@"%@ %@ (%@)", VERSION_STRING(), bundleVersion, buildNumber];
    [versionButton setTitle:versionTitle forState:UIControlStateNormal];
    [versionButton setTitleColor:UIColor.lightGrayColor forState:UIControlStateNormal];
    [versionButton addTarget:self action:@selector(versionButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    versionButton.titleLabel.font = [UIFont systemFontOfSize:10.0];
    [versionButton sizeToFit];
    CGRect frame = versionButton.frame;
    frame.size.height = frame.size.height * 2;
    versionButton.frame = frame;
 
    UIButton *logoutButton = [[UIButton alloc] init];
    
    [logoutButton setTitle:@"Log Out" forState:UIControlStateNormal];
    [logoutButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [logoutButton setBackgroundColor:UIColor.redColor];
    logoutButton.titleLabel.font = [UIFont systemFontOfSize:16.0];
    
    [logoutButton addTarget:self action:@selector(logoutButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
 
    [footerStackView addArrangedSubview:logoutButton];
    [footerStackView addArrangedSubview:versionButton];
    
    self.tableView.tableFooterView = footerStackView;
    
    logoutButton.translatesAutoresizingMaskIntoConstraints = NO;
    [logoutButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15.0].active = YES;
    [logoutButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15.0].active = YES;
    [logoutButton.heightAnchor constraintEqualToConstant:40].active = true;
    [logoutButton.layer setCornerRadius:3.0];
    [logoutButton setClipsToBounds:YES];
    [logoutButton setAutoresizesSubviews:YES];
    [logoutButton setClearsContextBeforeDrawing:YES];
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

- (void)logoutButtonPressed:(id)sender {
    UIAlertAction * cancelButtonItem = [UIAlertAction actionWithTitle:CANCEL_STRING() style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction * okButtonItem = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self doLogout:sender];
    }];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Warning" message:@"Logging out will also clear your message history. Are you sure you want to logout?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:cancelButtonItem];
    [alert addAction:okButtonItem];
    [self presentViewController:alert animated:YES completion:nil];
}

-(void) doLogout:(id)sender {
    //try running all this on a background thread while first pullingup the Cognito login page first
    NSIndexPath *ip = [NSIndexPath indexPathForRow:0 inSection:0];
    OTRXMPPAccount *account = [self accountAtIndexPath:ip];
    
    if (account && [[OTRProtocolManager sharedInstance] existsProtocolForAccount:account]) {
        OTRXMPPManager *xmpp = (OTRXMPPManager*)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
        if (account.pushPubsubEndpoint) {
            XMPPJID *serverJID = [XMPPJID jidWithUser:nil domain:account.pushPubsubEndpoint resource:nil];
            [xmpp.serverCheck.pushModule disablePushForServerJID:serverJID node:account.pushPubsubNode elementId:nil];
        }
        
        [OTRProtocolManager.pushController deactivateWithCompletion:nil callbackQueue:nil];
    }
    
    [self.KVOController unobserve:[OTRProtocolManager sharedInstance]];
    [[[OTRAppDelegate appDelegate] conversationViewController] resetAfterLogout:account];
}

- (void) versionButtonPressed:(id)sender {
    // Licenses are in Settings bundle now
    NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    [UIApplication.sharedApplication openURL:settingsURL];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(serverCheckUpdate:) name:ServerCheck.UpdateNotificationName object:nil];
    self.tableView.frame = self.view.bounds;
    [self.settingsManager populateSettings];
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void) serverCheckUpdate:(NSNotification*)notification {
    //
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
    if (indexPath.section == 0 && indexPath.row != [self.settingsManager numberOfSettingsInSection:indexPath.section]-1) {
        static NSString *addAccountCellIdentifier = @"addAccountCellIdentifier";
        UITableViewCell * cell = nil;
        if (indexPath.row == [self.viewHandler.mappings numberOfItemsInSection:indexPath.section]) {
            cell = [tableView dequeueReusableCellWithIdentifier:addAccountCellIdentifier];
            if (cell == nil) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:addAccountCellIdentifier];
                cell.textLabel.text = NEW_ACCOUNT_STRING();
                cell.imageView.image = [UIImage imageNamed:circleImageName inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil];
                cell.detailTextLabel.text = nil;
            }
        } else {
            OTRXMPPAccount *account = [self accountAtIndexPath:indexPath];
            OTRXMPPManager *xmpp = (OTRXMPPManager*)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
            XMPPAccountCell *accountCell = [tableView dequeueReusableCellWithIdentifier:[XMPPAccountCell cellIdentifier] forIndexPath:indexPath];
            [accountCell setAppearanceWithAccount:account];
            
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
    }
    OTRSettingTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellIdentifier];
	if (cell == nil)
	{
		cell = [[OTRSettingTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kSettingsCellIdentifier];
	}
    OTRSetting *setting = [self.settingsManager settingAtIndexPath:indexPath];
    setting.delegate = self;
    cell.otrSetting = setting;
    
    return cell;
}

- (void) handleDisplayNameClick:(id)sender {
    if ([OTRAccountsManager allAccounts].count != 0) {
        [_settingsManager handleChangeDisplayName:self];
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

- (void) accountCellShareButtonPressed:(id)sender {
    if ([sender isKindOfClass:[UIButton class]]) {
        UIButton *button = sender;
        OTRAccountTableViewCell *cell = (OTRAccountTableViewCell*)button.superview;
        OTRAccount *account = cell.account;
        [ShareController shareAccount:account sender:sender viewController:self];
    }
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView 
{
    return [self.settingsManager.settingsGroups count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)sectionIndex
{
    if (sectionIndex == 0) {
        if ([OTRAccountsManager allAccounts].count == 0) { 
            return [self.viewHandler.mappings numberOfItemsInSection:0]+2;
        } else {
            return [self.viewHandler.mappings numberOfItemsInSection:0]+1;
        }
    }
    return [self.settingsManager numberOfSettingsInSection:sectionIndex];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0 && indexPath.row != [self.settingsManager numberOfSettingsInSection:indexPath.section]-1) {
        if (indexPath.row == [self.viewHandler.mappings numberOfItemsInSection:indexPath.section]) {
            return 50.0;
        } else {
            return [XMPPAccountCell cellHeight];
        }
    }
    return UITableViewAutomaticDimension;
}

- (NSString*)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [self.settingsManager stringForGroupInSection:section];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0 && indexPath.row != [self.settingsManager numberOfSettingsInSection:indexPath.section]-1) {
        if (indexPath.row == [self.viewHandler.mappings numberOfItemsInSection:0]) {
            OTRBaseLoginViewController *baseLoginViewController = [[OTRBaseLoginViewController alloc] init];
            baseLoginViewController.showsCancelButton = YES;
            baseLoginViewController.form = [XLFormDescriptor existingAccountFormWithAccountType:OTRAccountTypeJabber];
            baseLoginViewController.loginHandler = [[OTRXMPPLoginHandler alloc] init];
            UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:baseLoginViewController];
            navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
            [self presentViewController:navigationController animated:YES completion:nil];
        }
    } else {
        OTRSetting *setting = [self.settingsManager settingAtIndexPath:indexPath];
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

- (void) showAccountDetailsView:(OTRXMPPAccount*)account {
    id<OTRProtocol> protocol = [[OTRProtocolManager sharedInstance] protocolForAccount:account];
    OTRXMPPManager *xmpp = nil;
    if ([protocol isKindOfClass:[OTRXMPPManager class]]) {
        xmpp = (OTRXMPPManager*)protocol;
    }
    OTRAccountDetailViewController *detailVC = [GlobalTheme.shared accountDetailViewControllerForAccount:account];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:detailVC];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navigationController animated:YES completion:nil];
}

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

- (void) addAccount:(id)sender {
    UIStoryboard *onboardingStoryboard = [UIStoryboard storyboardWithName:@"Onboarding" bundle:[OTRAssets resourcesBundle]];
    UINavigationController *welcomeNavController = [onboardingStoryboard instantiateInitialViewController];
    welcomeNavController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:welcomeNavController animated:YES completion:nil];
}

- (NSIndexPath *)indexPathForSetting:(OTRSetting *)setting
{
    return [self.settingsManager indexPathForSetting:setting];
}

#pragma mark OTRSettingDelegate method

- (void)refreshView
{
    [self.tableView reloadData];
}

#pragma mark OTRSettingViewDelegate method
- (void) otrSetting:(OTRSetting*)setting showDetailViewControllerClass:(Class)viewControllerClass
{
    if (viewControllerClass == [EnablePushViewController class]) {
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Onboarding" bundle:[OTRAssets resourcesBundle]];
        EnablePushViewController *enablePushVC = [storyboard instantiateViewControllerWithIdentifier:@"enablePush"];
        enablePushVC.modalPresentationStyle = UIModalPresentationFormSheet;
        if (enablePushVC) {
            [self presentViewController:enablePushVC animated:YES completion:nil];
        }
        return;
    } else if (viewControllerClass == [CoreConnectionViewController class]) {
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"CoreConnection" bundle:[OTRAssets resourcesBundle]];
        CoreConnectionViewController *coreConnectionVC = [storyboard instantiateViewControllerWithIdentifier:@"coreConnection"];
        coreConnectionVC.modalPresentationStyle = UIModalPresentationFormSheet;
        if (coreConnectionVC) {
            [coreConnectionVC addSettings:self.settingsManager];
            [self.navigationController pushViewController:coreConnectionVC animated:YES];
        }
        return;
    }
    UIViewController *viewController = [[viewControllerClass alloc] init];
    viewController.title = setting.title;
    if ([viewController isKindOfClass:[OTRSettingDetailViewController class]]) 
    {
        OTRSettingDetailViewController *detailSettingViewController = (OTRSettingDetailViewController*)viewController;
        detailSettingViewController.otrSetting = setting;
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:detailSettingViewController];
        navController.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:navController animated:YES completion:nil];
    } else {
        [self.navigationController pushViewController:viewController animated:YES];
    }
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

#pragma - mark OTRShareSettingDelegate Method

- (void)didSelectShareSetting:(OTRShareSetting *)shareSetting
{
    OTRActivityItemProvider * itemProvider = [[OTRActivityItemProvider alloc] initWithPlaceholderItem:@""];
    OTRQRCodeActivity * qrCodeActivity = [[OTRQRCodeActivity alloc] init];
    
    UIActivityViewController * activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[itemProvider] applicationActivities:@[qrCodeActivity]];
    activityViewController.excludedActivityTypes = @[UIActivityTypePrint, UIActivityTypeAssignToContact, UIActivityTypeSaveToCameraRoll];
    
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[self indexPathForSetting:shareSetting]];
    
    activityViewController.popoverPresentationController.sourceView = cell;
    activityViewController.popoverPresentationController.sourceRect = cell.bounds;
    
    [self presentViewController:activityViewController animated:YES completion:nil];
}

#pragma mark OTRFeedbackSettingDelegate method

- (void) presentFeedbackViewForSetting:(OTRSetting *)setting {
    NSURL *githubURL = OTRBranding.githubURL;
    if (!githubURL) { return; }
    NSURL *githubIssues = [githubURL URLByAppendingPathComponent:@"issues"];
    [UIApplication.sharedApplication openURL:githubIssues];
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

// for global message expiration setting
- (void) showTimerSelector:(id<TimerPickerDelegate>)tdel withSelectedRow:(NSInteger)selrow {
    self.timePickerView = [[UIPickerView alloc]init];
    self.timePickerView.dataSource = self;
    self.timePickerView.delegate = self;
    self.timePickerView.backgroundColor = [UIColor colorWithRed:41/255.0 green:54/255.0 blue:62/255.0 alpha:1];
    self.timeDel = tdel;
    
    self.timeTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clearTimePicker:)];
    self.timeTapGesture.delegate = self;
    self.timeTapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:self.timeTapGesture];
    
    self.timeTapGesture2 = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clearTimePicker:)];
    self.timeTapGesture2.delegate = self;
    self.timeTapGesture2.cancelsTouchesInView = NO;
    [self.timePickerView addGestureRecognizer:self.timeTapGesture2];
    
    NSString *strHeader = @"Set a time for messages to disappear";
    float lblWidth = self.view.frame.size.width;
    float lblXposition = self.timePickerView.frame.origin.x;
    float lblYposition = (self.timePickerView.frame.origin.y);
    
    UILabel *lblHeader = [[UILabel alloc] initWithFrame:CGRectMake(lblXposition, lblYposition,
                                                                   lblWidth, 20)];
    [lblHeader setText:strHeader];
    [lblHeader setTextAlignment:NSTextAlignmentCenter];
    lblHeader.textColor = [UIColor whiteColor];
    lblHeader.font = [UIFont fontWithName:kFontAwesomeFont size:10];
    [self.timePickerView addSubview:lblHeader];
    
    self.timePickerTextField = [[UITextField alloc]initWithFrame:CGRectZero];
    [self.view addSubview:self.timePickerTextField];
    
    self.timePickerTextField.inputView = self.timePickerView;
    [self.timePickerTextField becomeFirstResponder];
    
    [self.timePickerView selectRow:selrow inComponent:0 animated:YES];
}

#pragma - mark UIPickerViewDelegate
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    
    return 1;
}


-(NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{
    return self.pickerArray.count;
}

- (NSAttributedString *)pickerView:(UIPickerView *)pickerView attributedTitleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    NSString *title = self.pickerArray[row];
    NSAttributedString *attString =
    [[NSAttributedString alloc] initWithString:title attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    
    return attString;
}


-(NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    return self.pickerArray[row];
}


-(void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
    [self.timeDel timeSelected:row];
}

-(BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer{
    return true;
}

- (void)clearTimePicker:(UITapGestureRecognizer *)gesture {
    [self.timePickerTextField resignFirstResponder];
    [self.timePickerTextField removeFromSuperview];
    self.timePickerTextField = nil;
    [self.view removeGestureRecognizer:self.timeTapGesture];
    [self.timePickerView removeGestureRecognizer:self.timeTapGesture2];
    self.timeTapGesture = nil;
    self.timeTapGesture2 = nil;
    self.timePickerView = nil;
    self.timeDel = nil;
    
    [self performSelector:@selector(performTimerTitleRefresh:) withObject:nil afterDelay:.5];
}

- (void) performTimerTitleRefresh:(id)sender {
    [self.tableView reloadData];
}

@end
