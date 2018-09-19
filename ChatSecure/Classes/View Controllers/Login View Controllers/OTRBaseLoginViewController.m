//
//  OTRBaseLoginViewController.m
//  ChatSecure
//
//  Created by David Chiles on 5/12/15.
//  Copyright (c) 2015 Chris Ballinger. All rights reserved.
//

#import "OTRBaseLoginViewController.h"
#import "OTRColors.h"
#import "OTRCertificatePinning.h"
#import "OTRConstants.h"
#import "OTRXMPPError.h"
#import "OTRDatabaseManager.h"
#import "OTRAccount.h"
@import MBProgressHUD;
#import "OTRXLFormCreator.h"
#import <ChatSecureCore/ChatSecureCore-Swift.h>
#import "OTRXMPPServerInfo.h"
#import "OTRXMPPAccount.h"
@import OTRAssets;

#import "OTRInviteViewController.h"
#import "NSString+ChatSecure.h"
#import "XMPPServerInfoCell.h"

static NSUInteger kOTRMaxLoginAttempts = 5;

@interface OTRBaseLoginViewController ()

@property (nonatomic) bool showPasswordsAsText;
@property (nonatomic) bool existingAccount;
@property (nonatomic) NSUInteger loginAttempts;

@end

NSString *const kOTRXLFormTestFieldTag               = @"kOTRXLFormTestFieldTag"; 

@implementation OTRBaseLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [OTRUsernameCell registerCellClass:[OTRUsernameCell defaultRowDescriptorType]];
    
    self.loginAttempts = 0;
    
    UIImage *checkImage = [UIImage imageNamed:@"ic-check" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil];
    UIBarButtonItem *checkButton = [[UIBarButtonItem alloc] initWithImage:checkImage style:UIBarButtonItemStylePlain target:self action:@selector(loginButtonPressed:)];
    
    self.navigationItem.rightBarButtonItem = checkButton;
    
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1];
    self.navigationController.navigationBar.tintColor = [UIColor blackColor];
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName : [UIColor blackColor]};
    
    if (self.readOnly) {
        self.title = ACCOUNT_STRING();
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (self.showsCancelButton) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelButtonPressed:)];
    }
    
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self.tableView reloadData];
    [self.loginHandler moveAccountValues:self.account intoForm:self.form];
    
    // We need to refresh the username row with the default selected server
    [self updateUsernameRow];
}

- (void)setAccount:(OTRAccount *)account
{
    _account = account;
    [self.loginHandler moveAccountValues:self.account intoForm:self.form];
}

- (void) cancelButtonPressed:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)loginButtonPressed:(id)sender
{
    if (self.readOnly) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    self.existingAccount = (self.account != nil);
    
    XLFormRowDescriptor *usernameRow = [self.form formRowWithTag:kOTRXLFormUsernameTextFieldTag];
    BOOL pubdomain = NO;
    if (usernameRow != nil && usernameRow.value != nil) {
        NSArray *components = [usernameRow.value componentsSeparatedByString:@"@"];
        if (components.count != 2) {
            NSString *str = [NSString stringWithFormat: @"%@@%@", [components firstObject], [OTRXMPPAccount defaultHost]];
            usernameRow.value = str;
            [self updateFormRow:usernameRow];
            [[OTRAppDelegate appDelegate] setDomain:[OTRXMPPAccount defaultHost]];
        } else {
            [[OTRAppDelegate appDelegate] setDomain:[components lastObject]];
            if (![[components lastObject] isEqualToString:[OTRXMPPAccount defaultHost]]) {
                pubdomain = YES;
            }
        }
    }
    
    if ([self validForm]) {
        if (self.existingAccount) {
            NSString *password = [[self.form formRowWithTag:kOTRXLFormPasswordTextFieldTag] value];
            NSString *nickname = [[self.form formRowWithTag:kOTRXLFormNicknameTextFieldTag] value];
            NSString *username = [[self.form formRowWithTag:kOTRXLFormUsernameTextFieldTag] value];
            
            if ([password isEqualToString:self.account.password] && [username isEqualToString:self.account.username]) {
                //if username/password not changed, no need to re-login
                //just need to update displayName and dismiss
                if (![nickname isEqualToString:self.account.displayName]) {
                    [self handleUpdatedDisplayName:nickname];
                }
                
                NSNumber *bypass = [[self.form formRowWithTag:kOTRXLFormBypassNetworkSwitchTag] value];
                if (bypass || pubdomain) {
                    self.account.bypassNetworkCheck = [bypass boolValue];
                    OTRXMPPManager *xmgr = (OTRXMPPManager*)[[OTRProtocolManager sharedInstance] protocolForAccount:self.account];
                    [xmgr updateNetworkCheckBypass:[bypass boolValue]];
                    [[OTRAppDelegate appDelegate] bypassNetworkCheck:[bypass boolValue]];
                }

                [self.navigationController popViewControllerAnimated:true];
                
                return;
            }
        }
        
        self.form.disabled = YES;
        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        self.navigationItem.rightBarButtonItem.enabled = NO;
        self.navigationItem.leftBarButtonItem.enabled = NO;
        self.navigationItem.backBarButtonItem.enabled = NO;

		__weak __typeof__(self) weakSelf = self;
        self.loginAttempts += 1;
        [self.loginHandler performActionWithValidForm:self.form account:self.account progress:^(NSInteger progress, NSString *summaryString) {
            NSLog(@"Tor Progress %d: %@", (int)progress, summaryString);
            hud.progress = progress/100.0f;
            hud.label.text = summaryString;
            
            } completion:^(OTRAccount *account, NSError *error) {
                __typeof__(self) strongSelf = weakSelf;
                strongSelf.form.disabled = NO;
                strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
                strongSelf.navigationItem.backBarButtonItem.enabled = YES;
                strongSelf.navigationItem.leftBarButtonItem.enabled = YES;
                [hud hideAnimated:YES];
                if (error) {
                    // Unset/remove password from keychain if account
                    // is unsaved / doesn't already exist. This prevents the case
                    // where there is a login attempt, but it fails and
                    // the account is never saved. If the account is never
                    // saved, it's impossible to delete the orphaned password
                    __block BOOL accountExists = NO;
                    [[OTRDatabaseManager sharedInstance].uiConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                        accountExists = [transaction objectForKey:account.uniqueId inCollection:[[OTRAccount class] collection]] != nil;
                    }];
                    if (!accountExists) {
                        [account removeKeychainPassword:nil];
                    }
                    [strongSelf handleError:error];
                } else if (account) {
                    self.account = account;
                    [self handleSuccessWithNewAccount:account sender:sender];
                }
        }];
    }
}

- (void) handleUpdatedDisplayName:(NSString *)newName {
    OTRXMPPAccount *xcct = (OTRXMPPAccount *)self.account;
    
    if (!xcct.vCardTemp) {
        XMPPvCardTemp *newvCardTemp = [XMPPvCardTemp vCardTemp];
        xcct.vCardTemp = newvCardTemp;
    }
    
    xcct.vCardTemp.nickname = newName;
    OTRXMPPManager *xmgr = (OTRXMPPManager*)[[OTRProtocolManager sharedInstance] protocolForAccount:self.account];
    [xmgr updateNickname:xcct.vCardTemp];
    [xmgr forcevCardUpdateWithCompletion:^(BOOL success){}];
}

- (void) handleSuccessWithNewAccount:(OTRAccount*)account sender:(id)sender {
    NSParameterAssert(account != nil);
    if (!account) { return; }
    [[OTRDatabaseManager sharedInstance].writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [account saveWithTransaction:transaction];
    }];
    
    if (self.existingAccount) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
    
    // request push registration
    [PushController registerForPushNotifications];
    [PushController setPushPreference:PushPreferenceEnabled];
    
    // If push isn't enabled, prompt to enable it
    if ([PushController getPushPreference] == PushPreferenceEnabled) {
        [self pushInviteViewController:sender];
    } else {
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Onboarding" bundle:[OTRAssets resourcesBundle]];
        EnablePushViewController *pushVC = [storyboard instantiateViewControllerWithIdentifier:@"enablePush"];
        if (pushVC) {
            pushVC.account = account;
            [self.navigationController pushViewController:pushVC animated:YES];
        }
    }
}

- (void) pushInviteViewController:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)validForm
{
    BOOL validForm = YES;
    NSArray *formValidationErrors = [self formValidationErrors];
    if ([formValidationErrors count]) {
        validForm = NO;
    }
    
    [formValidationErrors enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        
        XLFormValidationStatus * validationStatus = [[obj userInfo] objectForKey:XLValidationStatusErrorKey];
        UITableViewCell * cell = [self.tableView cellForRowAtIndexPath:[self.form indexPathOfFormRow:validationStatus.rowDescriptor]];
        cell.backgroundColor = [UIColor orangeColor];
        [UIView animateWithDuration:0.3 animations:^{
            cell.backgroundColor = [UIColor whiteColor];
        }];
        
    }];
    return validForm;
}

- (void) updateUsernameRow {
    XLFormRowDescriptor *usernameRow = [self.form formRowWithTag:kOTRXLFormUsernameTextFieldTag];
    if (!usernameRow) {
        return;
    }
    XLFormRowDescriptor *serverRow = [self.form formRowWithTag:kOTRXLFormXMPPServerTag];
    NSString *domain = nil;
    if (serverRow) {
        OTRXMPPServerInfo *serverInfo = serverRow.value;
        domain = serverInfo.domain;
        usernameRow.value = domain;
    } else {
        usernameRow.value = self.account.username;
    }
    [self updateFormRow:usernameRow];
}

- (void) updateHostnameRow {
    XLFormRowDescriptor *usernameRow = [self.form formRowWithTag:kOTRXLFormUsernameTextFieldTag];
    if (!usernameRow) {
        return;
    }
    XLFormRowDescriptor *hostRow = [self.form formRowWithTag:kOTRXLFormHostnameTextFieldTag];
    if (hostRow) {
        NSString *uname = nil; // aka 'username' from username@example.com
        NSString *host = nil;
        
        NSArray *components = [usernameRow.value componentsSeparatedByString:@"@"];
        if (components.count == 2) {
            uname = [components firstObject];
            host = [components lastObject];
            hostRow.value = host;
        }
    }
    
    [self updateFormRow:hostRow];
}

#pragma mark UITableView methods

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    // This is required for the XMPPServerInfoCell buttons to work
    if ([cell isKindOfClass:[XMPPServerInfoCell class]]) {
        XMPPServerInfoCell *infoCell = (XMPPServerInfoCell*)cell;
        [infoCell setupWithParentViewController:self];
    }
    if (self.readOnly) {
        cell.userInteractionEnabled = NO;
    } else {
        XLFormRowDescriptor *desc = [self.form formRowAtIndex:indexPath];
        if (desc != nil && desc.tag == kOTRXLFormPasswordTextFieldTag) {
            cell.accessoryType = UITableViewCellAccessoryDetailButton;
            if ([cell isKindOfClass:XLFormTextFieldCell.class]) {
                [[(XLFormTextFieldCell*)cell textField] setSecureTextEntry:!self.showPasswordsAsText];
            }

        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    XLFormRowDescriptor *desc = [self.form formRowAtIndex:indexPath];
    if (desc != nil && desc.tag == kOTRXLFormPasswordTextFieldTag) {
        self.showPasswordsAsText = !self.showPasswordsAsText;
        [self.tableView reloadData];
    }
}

#pragma mark XLFormDescriptorDelegate

-(void)formRowDescriptorValueHasChanged:(XLFormRowDescriptor *)formRow oldValue:(id)oldValue newValue:(id)newValue
{
    [super formRowDescriptorValueHasChanged:formRow oldValue:oldValue newValue:newValue];
    if (formRow.tag == kOTRXLFormXMPPServerTag) {
        [self updateUsernameRow];
    } else if (formRow.tag == kOTRXLFormUsernameTextFieldTag) {
        [self updateHostnameRow];
    }
}

 #pragma - mark Errors and Alert Views

- (void)handleError:(NSError *)error
{
    NSParameterAssert(error);
    if (!error) {
        return;
    }
    UIAlertController *certAlert = [UIAlertController certificateWarningAlertWithError:error saveHandler:^(UIAlertAction * _Nonnull action) {
        [self loginButtonPressed:self.view];
    }];
    if (certAlert) {
        // accept and save since we are in closed network
        NSData *certData = error.userInfo[OTRXMPPSSLCertificateDataKey];
        NSString *hostname = error.userInfo[OTRXMPPSSLHostnameKey];
        [OTRCertificatePinning addCertificateData:certData withHostName:hostname];
        [self loginButtonPressed:self.view];
    } else {
        [self handleXMPPError:error];
    }
}

- (void)handleXMPPError:(NSError *)error
{
    if (error.code == OTRXMPPXMLErrorConflict && self.loginAttempts < kOTRMaxLoginAttempts) {
        //Caught the conflict error before there's any alert displayed on the screen
        //Create a new nickname with a random hex value at the end
        NSString *uniqueString = [[OTRPasswordGenerator randomDataWithLength:2] hexString];
        XLFormRowDescriptor* nicknameRow = [self.form formRowWithTag:kOTRXLFormNicknameTextFieldTag];
        NSString *value = [nicknameRow value];
        NSString *newValue = [NSString stringWithFormat:@"%@.%@",value,uniqueString];
        nicknameRow.value = newValue;
        [self loginButtonPressed:self.view];
        return;
    } else if (error.code == OTRXMPPXMLErrorPolicyViolation && self.loginAttempts < kOTRMaxLoginAttempts){
        // We've hit a policy violation. This occurs on duckgo because of special characters like russian alphabet.
        // We should give it another shot stripping out offending characters and retrying.
        XLFormRowDescriptor* nicknameRow = [self.form formRowWithTag:kOTRXLFormNicknameTextFieldTag];
        NSMutableString *value = [[nicknameRow value] mutableCopy];
        NSString *newValue = [value otr_stringByRemovingNonEnglishCharacters];
        if ([newValue length] == 0) {
            newValue = [OTRBranding xmppResource];
        }
        
        if (![newValue isEqualToString:value]) {
            nicknameRow.value = newValue;
            [self loginButtonPressed:self.view];
            return;
        }
    }
    
    [self showAlertViewWithTitle:ERROR_STRING() message:XMPP_FAIL_STRING() error:error];
}

- (void)showAlertViewWithTitle:(NSString *)title message:(NSString *)message error:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertAction * okButtonItem = [UIAlertAction actionWithTitle:OK_STRING() style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            
        }];
        UIAlertController * alertController = nil;
        if (error) {
            UIAlertAction * infoButton = [UIAlertAction actionWithTitle:INFO_STRING() style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                NSString* badpass = @"This could be the wrong password. Please try again.";
                NSString * errorDescriptionString = [NSString stringWithFormat:@"%@ : %@",[error domain],badpass];
                NSString *xmlErrorString = error.userInfo[OTRXMPPXMLErrorKey];
                if (xmlErrorString) {
                    // nothing right now
                }
                
                if ([[error domain] isEqualToString:@"kCFStreamErrorDomainSSL"]) {
                    NSString * sslString = [OTRXMPPError errorStringWithSSLStatus:(OSStatus)error.code];
                    if ([sslString length]) {
                        errorDescriptionString = [errorDescriptionString stringByAppendingFormat:@"\n%@",sslString];
                    }
                }
                
                
                UIAlertAction * copyButtonItem = [UIAlertAction actionWithTitle:COPY_STRING() style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    NSString * copyString = [NSString stringWithFormat:@"Domain: %@\nCode: %ld\nUserInfo: %@",[error domain],(long)[error code],[error userInfo]];
                    
                    UIPasteboard *pasteBoard = [UIPasteboard generalPasteboard];
                    [pasteBoard setString:copyString];
                }];
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:INFO_STRING() message:errorDescriptionString preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:okButtonItem];
                [alert addAction:copyButtonItem];
                [self presentViewController:alert animated:YES completion:nil];
            }];
            
            alertController = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
            [alertController addAction:okButtonItem];
            [alertController addAction:infoButton];
        }
        else {
            alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
            [alertController addAction:okButtonItem];
        }
        
        if (alertController) {
            [self presentViewController:alertController animated:YES completion:nil];
        }
    });
}

#pragma - mark Class Methods

- (instancetype) initWithAccount:(OTRAccount*)account
{
    NSParameterAssert(account != nil);
    XLFormDescriptor *form = [XLFormDescriptor existingAccountFormWithAccount:account];
    if (self = [super initWithForm:form style:UITableViewStyleGrouped]) {
        self.account = account;
        self.loginHandler = [OTRLoginHandler loginHandlerForAccount:account];
    }
    return self;
}

-(void)getServerInfo:(XLFormRowDescriptor *)sender
{
    OTRXMPPManager *protocol = (OTRXMPPManager*) [[OTRProtocolManager sharedInstance] protocolForAccount:self.account];
    OTRServerCapabilitiesViewController *serverInfoVC = [[OTRServerCapabilitiesViewController alloc] initWithServerCheck:protocol.serverCheck];
    [self.navigationController pushViewController:serverInfoVC animated:YES];
}

- (instancetype) initWithExistingAccountType:(OTRAccountType)accountType {
    XLFormDescriptor *form = [XLFormDescriptor existingAccountFormWithAccountType:accountType];
    if (self = [super initWithForm:form style:UITableViewStyleGrouped]) {
        self.loginHandler = [[OTRXMPPLoginHandler alloc] init];
    }
    return self;
}

/** This is for registering new accounts on a server */
- (instancetype) initWithNewAccountType:(OTRAccountType)accountType {
    XLFormDescriptor *form = [XLFormDescriptor registerNewAccountFormWithAccountType:accountType];
    if (self = [super initWithForm:form style:UITableViewStyleGrouped]) {
        self.loginHandler = [[OTRXMPPCreateAccountHandler alloc] init];
    }
    return self;
}

@end
