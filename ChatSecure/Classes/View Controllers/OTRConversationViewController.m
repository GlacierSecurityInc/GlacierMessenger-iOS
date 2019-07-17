//
//  OTRConversationViewController.m
//  Off the Record
//
//  Created by David Chiles on 3/2/14.
//  Copyright (c) 2014 Chris Ballinger. All rights reserved.
//

#import "OTRConversationViewController.h"

#import "OTRSettingsViewController.h"
#import "OTRMessagesHoldTalkViewController.h"
#import "OTRComposeViewController.h"

#import "OTRConversationCell.h"
#import "OTRAccount.h"
#import "OTRBuddy.h"
#import "OTRXMPPBuddy.h"
#import "OTRIncomingMessage.h"
#import "OTROutgoingMessage.h"
#import "UIViewController+ChatSecure.h"
#import "OTRLog.h"
#import "UITableView+ChatSecure.h"
@import YapDatabase;

#import "OTRDatabaseManager.h"
#import "OTRDatabaseView.h"
@import KVOController;
#import "OTRAppDelegate.h"
#import "OTRProtocolManager.h"
#import "OTRInviteViewController.h"
#import <ChatSecureCore/ChatSecureCore-Swift.h>
@import OTRAssets;

#import "OTRXMPPManager.h"
#import "OTRXMPPRoomManager.h"
#import "OTRBuddyApprovalCell.h"
#import "OTRStrings.h"
#import "OTRvCard.h"
#import "XMPPvCardTemp.h"

@import DGActivityIndicatorView; 
#import "UIScrollView+EmptyDataSet.h" //can cause error when loggin out or resetting

#import "NetworkTester.h"
@import BButton;

static CGFloat kOTRConversationCellHeight = 80.0;

@interface OTRConversationViewController () <OTRYapViewHandlerDelegateProtocol, OTRAccountDatabaseCountDelegate, SideMenuDelegate, DZNEmptyDataSetSource, DZNEmptyDataSetDelegate>

@property (nonatomic, strong) NSTimer *cellUpdateTimer;
@property (nonatomic, strong) OTRYapViewHandler *conversationListViewHandler;

@property (nonatomic, strong) UIBarButtonItem *composeBarButtonItem;

@property (nonatomic, strong) UIBarButtonItem *groupBarButtonItem;
@property (nonatomic, strong) UIBarButtonItem *dialpadBarButtonItem;
@property (nonatomic, strong) UILabel *connStatusLabel;
@property (nonatomic, strong) UIView *connStatusView;
@property (nonatomic, strong) DGActivityIndicatorView *dynConnStatusView;
@property (nonatomic, strong) OTRXMPPLoginHandler *aloginHandler;
@property (nonatomic, strong) UITapGestureRecognizer *sideTapGestureRecognizer;
@property (nonatomic, strong) CLLocationManager *locationManager;

@property (nonatomic, strong) UITapGestureRecognizer *statusTapGestureRecognizer;
@property (nonatomic, strong) NSTimer *statusTimer;
@property int statusCtr;
@property (nonatomic, strong) NSString *accountType;
@property (nonatomic) BOOL welcoming;
@property (nonatomic, strong) NSString *repeatStr;
@property (nonatomic, strong) UIStackView *connStatusStackView;

@property (nonatomic, strong) SideMenuView *sideView;

@property (nonatomic, strong) UIViewController *settingsViewController;
@property (nonatomic, strong) OTRAccount *currentacct;

//for single signon via AWS
@property (nonatomic, strong) OTRWelcomeViewController *awspauth;

@property int retryCtr;
@property (nonatomic) BOOL connectionSuccess;

@property (nonatomic) BOOL tryingGlacierAcct;

@property (nonatomic, strong) OTRXMPPManager *currentmgr;

@property (nonatomic) BOOL showSkeleton;

@property (nonatomic) BOOL hasPresentedOnboarding;

@property (nonatomic, strong) UIAlertController *vpnalert;

@property (nonatomic, strong) OTRAccountDatabaseCount *accountCounter;
@property (nonatomic, strong) MigrationInfoHeaderView *migrationInfoHeaderView;
@property (nonatomic, strong) UISegmentedControl *inboxArchiveControl;

@end

@implementation OTRConversationViewController

- (void)viewDidLoad
{
    [super viewDidLoad];    
   
    ///////////// Setup Navigation Bar //////////////
    
    self.title = CHATS_STRING();
    UIBarButtonItem *settingsBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OTRSettingsIcon-1" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(settingsButtonPressed:)];
    self.navigationItem.leftBarButtonItem = settingsBarButtonItem;  //right to left
    
    self.composeBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"new_message" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(composeButtonPressed:)];
    self.navigationItem.rightBarButtonItems = @[self.composeBarButtonItem]; //left to right
    [settingsBarButtonItem setTintColor:[UIColor blackColor]];
    [self.composeBarButtonItem setTintColor:[UIColor blackColor]];
    
    _inboxArchiveControl = [[UISegmentedControl alloc] initWithItems:@[INBOX_STRING(), ARCHIVE_STRING()]];
    _inboxArchiveControl.selectedSegmentIndex = 0;
    _inboxArchiveControl.tintColor = [UIColor colorWithRed:41/255.0 green:54/255.0 blue:62/255.0 alpha:1];
    [self updateInboxArchiveFilteringAndShowArchived:NO];
    [_inboxArchiveControl addTarget:self action:@selector(inboxArchiveControlValueChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _inboxArchiveControl;
    
    self.dynConnStatusView = [[DGActivityIndicatorView alloc]
                              initWithType:DGActivityIndicatorAnimationTypeBallBeat
                              tintColor:[UIColor blackColor] size:18.0f];
    self.dynConnStatusView.frame = CGRectMake(5, 5, 100, 20);
    
    _statusCtr = 0;
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateStatusTimer:) userInfo:nil repeats:YES];
    _repeatStr = [NSString fa_stringForFontAwesomeIcon:FAIconRepeat];
    
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1];
    self.navigationController.navigationBar.tintColor = [UIColor blackColor];
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName : [UIColor blackColor]};
    
    //setting up toolbar (bottom bar), here to Create Tableview
    self.navigationController.toolbarHidden = NO;
    self.dialpadBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"dialpad" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(dialpadButtonPressed:)];
    self.groupBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"group_chat" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(groupButtonPressed:)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];
    
    UILabel *createLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 5, 100, 20)];
    [createLabel setFont:[UIFont fontWithName:kFontAwesomeFont size:11]];
    [createLabel setText:@"Create New Group"];
    UIBarButtonItem *labelItem = [[UIBarButtonItem alloc] initWithCustomView:createLabel];
    
    NSArray *items = [NSArray arrayWithObjects:self.dialpadBarButtonItem, flex, labelItem, self.groupBarButtonItem, nil];
    self.toolbarItems = items;
    
    self.navigationController.toolbar.barTintColor = [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1];
    self.navigationController.toolbar.tintColor = [UIColor blackColor];
    self.navigationController.toolbar.translucent = NO;
    
    self.connectionSuccess = NO;
    self.retryCtr = 0;
    
    self.showSkeleton = YES;
    
    ////////// Create TableView /////////////////
    
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.accessibilityIdentifier = @"conversationTableView";
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = kOTRConversationCellHeight;
    
    self.tableView.emptyDataSetSource = self;
    self.tableView.emptyDataSetDelegate = self;
    self.tableView.tableFooterView = [UIView new];
    
    [self.view addSubview:self.tableView];
    
    [self.tableView registerClass:[OTRConversationCell class] forCellReuseIdentifier:[OTRConversationCell reuseIdentifier]];
    [self.tableView registerClass:[OTRBuddyApprovalCell class] forCellReuseIdentifier:[OTRBuddyApprovalCell reuseIdentifier]];
    [self.tableView registerClass:[OTRBuddyInfoCell class] forCellReuseIdentifier:[OTRBuddyInfoCell reuseIdentifier]];
    
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[tableView]|" options:0 metrics:0 views:@{@"tableView":self.tableView}]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[tableView]|" options:0 metrics:0 views:@{@"tableView":self.tableView}]];
    
    ////////// Create YapDatabase View /////////////////
    
    self.conversationListViewHandler = [[OTRYapViewHandler alloc] initWithDatabaseConnection:[OTRDatabaseManager sharedInstance].longLivedReadOnlyConnection databaseChangeNotificationName:[DatabaseNotificationName LongLivedTransactionChanges]];
    self.conversationListViewHandler.delegate = self;
    [self.conversationListViewHandler setup:OTRArchiveFilteredConversationsName groups:@[OTRAllPresenceSubscriptionRequestGroup, OTRConversationGroup]];
    
    [self.tableView reloadData];
    [self updateInboxArchiveItems:self.navigationItem.titleView];
    
    self.accountCounter = [[OTRAccountDatabaseCount alloc] initWithDatabaseConnection:[OTRDatabaseManager sharedInstance].longLivedReadOnlyConnection delegate:self];
    
    OTRAccount *account = [self getFirstAccount];
    if (account != nil) {
        _currentmgr = (OTRXMPPManager*)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
        if (_currentmgr) {
            [self.KVOController observe:_currentmgr keyPath:NSStringFromSelector(@selector(loginStatus)) options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld action:@selector(connectionStateDidChange:)];
        }
        else {
            DDLogWarn(@"Account isn't setup yet! Skipping KVO...");
        }
    }
    
    self.statusTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleStatusGesture)];
    self.statusTapGestureRecognizer.numberOfTapsRequired = 1;
    
    self.sideTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closingSideMenu)];
    self.sideTapGestureRecognizer.numberOfTapsRequired = 1;
    
    [self loadSideMenu];
}

- (void) loadSideMenu {
    self.sideView = [SideMenuView otr_viewFromNib];
    if (!self.sideView) {
        return;
    }
    self.sideView.delegate = self;
    
    //resize for iPhoneX
    CGFloat vheight = self.view.frame.size.height;
    if (vheight == 812.0 || vheight == 896.0) { //added 896 for XR
        self.sideView.topConstraint.constant = 35;
    }
    
    CGRect sideFrame = CGRectMake(-1125, 0, self.view.frame.size.width, self.view.frame.size.height);
    self.sideView.frame = sideFrame;
    [self.navigationController.view addSubview:self.sideView];
}

- (OTRAccount *) getFirstAccount {
    if (_currentacct != nil) {
        return _currentacct;
    }
    
    [OTRDatabaseManager.shared.readConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        NSArray<OTRAccount*> *accounts = [OTRAccount allAccountsWithTransaction:transaction];
        if (accounts) {
            _currentacct = accounts.firstObject;
        }
    }];
    return _currentacct;
}

- (void) setSideAccount {
    OTRAccount *firstAcct = [self getFirstAccount];
    if (firstAcct != nil) {
        self.sideView.displayNameLabel.text = firstAcct.displayName;
    } else {
        self.sideView.displayNameLabel.text = nil;
    }
}

- (void) lookForAccountInfoIfNeeded {
    if (![self getFirstAccount]) {
        [self.navigationController popToRootViewControllerAnimated:YES];
        [self tryGlacierGroupAccount];
    }
}

- (void) showOnboardingIfNeeded {
    if (self.hasPresentedOnboarding) {
        if ([self checkAlternateRoute]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![self getFirstAccount]) {
                    [self.navigationController popToRootViewControllerAnimated:YES];
                    [self tryGlacierGroupAccount:YES];
                }
            });
        }
        
        return;
    }
    __block BOOL hasAccounts = NO;
    NSParameterAssert(OTRDatabaseManager.shared.uiConnection != nil);
    if (!OTRDatabaseManager.shared.uiConnection) {
        DDLogWarn(@"Database isn't setup yet! Skipping onboarding...");
        return;
    }
    [OTRDatabaseManager.shared.readConnection asyncReadWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        NSUInteger count = [transaction numberOfKeysInCollection:[OTRAccount collection]];
        if (count > 0) {
            hasAccounts = YES;
        }
    } completionBlock:^{
        [self continueOnboarding:hasAccounts];
    }];
}

- (void) continueOnboarding:(BOOL)hasAccounts {
    //If there is any number of accounts launch into default conversation view otherwise onboarding time
    if (!hasAccounts) {
        if (![self tryGlacierGroupAccount]) {
            [self setWelcomeController:NO];
        }
    } else if ([PushController getPushPreference] == PushPreferenceUndefined) {
        [PushController setPushPreference:PushPreferenceEnabled];
        [PushController registerForPushNotifications];
    }
    self.hasPresentedOnboarding = YES;
}

- (BOOL) checkAlternateRoute {
    NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc]
                                       initWithSuiteName:@"group.com.glaciersec.apps"];
    if ([glacierDefaults boolForKey:@"altroute"]) {
        [glacierDefaults removeObjectForKey:@"altroute"];
        [glacierDefaults synchronize];
        return YES;
    }
    
    return NO;
}

- (BOOL) tryGlacierGroupAccount {
    return [self tryGlacierGroupAccount:NO];
}

//user account info cn be shared among Glacier apps. Check for existing account info.
- (BOOL) tryGlacierGroupAccount:(BOOL)altroute {
    if (self.tryingGlacierAcct) {
        return YES; // let the process finish
    }
    
    NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc]
                                       initWithSuiteName:@"group.com.glaciersec.apps"];
    NSString *uservalue = [glacierDefaults stringForKey:@"username"];
    NSString *passvalue = [glacierDefaults stringForKey:@"password"];
    NSString *displayvalue = [glacierDefaults stringForKey:@"displayname"];
    NSString *connectionvalue = [glacierDefaults stringForKey:@"connection"];
    
    if (uservalue.length && passvalue.length) {
        // load account from glacier storage
        [[OTRAppDelegate appDelegate] setDomain:[OTRXMPPAccount defaultHost]];
        OTRXMPPAccount *account = [OTRAccount accountWithUsername:@"" accountType:OTRAccountTypeJabber];
        
        //if host included, use it
        NSArray *components = [uservalue componentsSeparatedByString:@"@"];
        if (components.count != 2) {
            account.username = [NSString stringWithFormat: @"%@@%@", uservalue, [OTRXMPPAccount defaultHost]];
        } else {
            account.username = uservalue;
            if (!displayvalue.length) {
                displayvalue = components.firstObject;
            }
            [[OTRAppDelegate appDelegate] setDomain:components.lastObject];
            account.domain = components.lastObject;
            
            if (![components.lastObject isEqualToString:[OTRXMPPAccount defaultHost]]) {
                account.bypassNetworkCheck = YES;
                [[OTRAppDelegate appDelegate] bypassNetworkCheck:YES];
            }
        }
        
        if (connectionvalue.length) {
            _accountType = connectionvalue;
            if ([connectionvalue isEqualToString:@"openvpn"]) {
                if ([self needsOpenVPN]) {
                    return YES; // because we don't want to go to Cognito login in this case
                }
            }
        }
        self.tryingGlacierAcct = YES;
        if (self.statusTimer) [self.statusTimer invalidate];
        _statusCtr = 0;
        _statusTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateStatusTimer:) userInfo:nil repeats:YES];
        
        [self setConnectionStatus];
        
        account.password = passvalue;
        if (displayvalue.length) {
            account.displayName = displayvalue;
        } else {
            account.displayName = uservalue;
        }
        
        if (altroute) {
            account.port = 5222;
        }
        BOOL includesDomain = components.count == 2;
        [self doLogin:account includesDomain:includesDomain];
        
        return YES;
    }
    return NO;
}

- (void) doLogin:(OTRXMPPAccount *)xaccount includesDomain:(BOOL)includesDomain{
    if (self.aloginHandler == nil) {
        self.aloginHandler = [[OTRXMPPLoginHandler alloc] init];
    }
    
    [self.aloginHandler finishConnectingWithAccount:xaccount completion:^(OTRAccount *account, NSError *error) {
        
        if (error) {
            // Unset/remove password from keychain if account
            // is unsaved / doesn't already exist. This prevents the case
            // where there is a login attempt, but it fails and
            // the account is never saved. If the account is never
            // saved, it's impossible to delete the orphaned password
            /*__block BOOL accountExists = NO;
            [OTRDatabaseManager.shared.readConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                accountExists = [transaction objectForKey:account.uniqueId inCollection:[[OTRAccount class] collection]] != nil;
            }];
            if (!accountExists) {
                [account removeKeychainPassword:nil];
            
                // need to completely remove account. Something isn't getting deleted.
                [[OTRProtocolManager sharedInstance] removeProtocolForAccount:account];
                [[NSNotificationCenter defaultCenter] removeObserver:self.aloginHandler];
                self.aloginHandler = nil;
            }*/
            
            UIAlertController *certAlert = [UIAlertController certificateWarningAlertWithError:error saveHandler:^(UIAlertAction * _Nonnull action) {
                NSData *certData = error.userInfo[OTRXMPPSSLCertificateDataKey];
                NSString *hostname = error.userInfo[OTRXMPPSSLHostnameKey];
                [OTRCertificatePinning addCertificateData:certData withHostName:hostname];
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    self.tryingGlacierAcct = NO;
                    [self doLogin:xaccount includesDomain:includesDomain];
                });
            }];
            
            NSString *hostname = error.userInfo[OTRXMPPSSLHostnameKey];
            BOOL glacierpublic = [hostname isEqualToString:[OTRSecrets defaultPublicHost]] || [hostname hasSuffix:[OTRSecrets defaultPublicHost]] || [hostname hasSuffix:[OTRSecrets altPublicHost]];
            
            if (includesDomain && certAlert && !glacierpublic) {
                [OTRCertificatePinning setAddingCert];
                [self presentViewController:certAlert animated:YES completion:nil];
            } else {
                if (self.retryCtr == 1) {
                    [self doLoginAlert];
                }
                self.retryCtr++;
                
                if (certAlert) {
                    NSData *certData = error.userInfo[OTRXMPPSSLCertificateDataKey];
                    NSString *hostname = error.userInfo[OTRXMPPSSLHostnameKey];
                    [OTRCertificatePinning addCertificateData:certData withHostName:hostname];
                }
                
                if (self.statusTimer) [self.statusTimer invalidate];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    self.tryingGlacierAcct = NO;
                    [self doLogin:xaccount includesDomain:includesDomain];
                });
            }
            
        } else if (account && !self.connectionSuccess) {
            self.connectionSuccess = YES;
            [[OTRAppDelegate appDelegate] resetDoubleNotificationHandlerIfNeeded];
            [OTRDatabaseManager.shared.writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                [account saveWithTransaction:transaction];
            }];
            
            // re-register push
            _currentmgr = (OTRXMPPManager*)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
            
            if (_currentmgr) {
                [self.KVOController observe:_currentmgr keyPath:NSStringFromSelector(@selector(loginStatus)) options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld action:@selector(connectionStateDidChange:)];
            }
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (_currentmgr) {
                    [_currentmgr.serverCheck.push resetWithCompletion:^{
                        [_currentmgr.serverCheck refresh];
                        [_currentmgr.serverCheck.pushModule refresh];
                    } callbackQueue:dispatch_get_main_queue()];
                }
                
                [[OTRProtocolManager sharedInstance] setLoggingOut:NO];
            });
            self.tryingGlacierAcct = NO;
        } else {
            self.tryingGlacierAcct = NO;
        }
    }];
}

- (void) doLoginAlert {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.connectionSuccess) {
            UIAlertAction * cancelButtonItem = [UIAlertAction actionWithTitle:CANCEL_STRING() style:UIAlertActionStyleCancel handler:nil];
            UIAlertAction * okButtonItem = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [self doLogout];
            }];
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Warning" message:@"Problems logging in. Do you want to reset and try again? For assistance contact your Glacier account representative." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:cancelButtonItem];
            [alert addAction:okButtonItem];
            [self presentViewController:alert animated:YES completion:nil];
        }
    });
}

- (void) setWelcomeController:(BOOL)closeable {
    _welcoming = YES;
    UIStoryboard *onboardingStoryboard = [UIStoryboard storyboardWithName:@"Onboarding" bundle:[OTRAssets resourcesBundle]];
    UINavigationController *welcomeNavController = [onboardingStoryboard instantiateInitialViewController];
    welcomeNavController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:welcomeNavController animated:YES completion:nil];
    self.awspauth = (OTRWelcomeViewController *)welcomeNavController.visibleViewController;
    
    [self.awspauth displayCloseFunction:closeable];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = NO;
    
    [self.cellUpdateTimer invalidate];
    [self.tableView reloadData];
    [self updateInboxArchiveItems:self.navigationItem.titleView];
    self.cellUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(updateVisibleCells:) userInfo:nil repeats:YES];
    
    self.tableView.tableHeaderView = nil;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enteringForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:[UIApplication sharedApplication]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enteringBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:[UIApplication sharedApplication]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkConnectionStatusChange:) name:NetworkStatusNotificationName object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(groupRemoved:) name:RemoveGroupNotificationName object:nil];
    if (_accountType == nil) {
        NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.glaciersec.apps"];
        _accountType = [glacierDefaults stringForKey:@"connection"];
    }
    
    [self updateComposeButton:self.accountCounter.numberOfAccounts];
    [self showMigrationViewIfNeeded];
}

- (void) enteringForeground:(NSNotification *)notification {
    
    if ([AWSAccountManager.shared checkLocalVPNProfiles]) {
        return;
    }
    
    if (self.statusTimer) [self.statusTimer invalidate];
    _statusCtr = 0;
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateStatusTimer:) userInfo:nil repeats:YES];
    
    self.tryingGlacierAcct = NO;
    
    [self setConnectionStatus];
    [self showOnboardingIfNeeded];
}

- (void) enteringBackground:(NSNotification *)notification {
    if (self.statusTimer) [self.statusTimer invalidate];
    self.statusTimer = nil;
    
    [self.dynConnStatusView stopAnimating];
    self.showSkeleton = YES;
    [self removeLocalVPNFiles];
}

- (OTRXMPPAccount *)checkIfNeedsMigration {
    __block OTRXMPPAccount *needsMigration;
    [[OTRDatabaseManager sharedInstance].uiConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        NSArray<OTRAccount*> *accounts = [OTRAccount allAccountsWithTransaction:transaction];
        [accounts enumerateObjectsUsingBlock:^(OTRAccount * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if (![obj isKindOfClass:[OTRXMPPAccount class]]) {
                return;
            }
            OTRXMPPAccount *xmppAccount = (OTRXMPPAccount *)obj;
            if ([xmppAccount needsMigration]) {
                needsMigration = xmppAccount;
                *stop = YES;
            }
        }];
    }];
    return needsMigration;
}

- (void)showMigrationViewIfNeeded {
    OTRXMPPAccount *needsMigration = [self checkIfNeedsMigration];
    if (needsMigration != nil) {
        self.migrationInfoHeaderView = [self createMigrationHeaderView:needsMigration];
        self.tableView.tableHeaderView = self.migrationInfoHeaderView;
    } else if (self.migrationInfoHeaderView != nil) {
        self.migrationInfoHeaderView = nil;
        self.tableView.tableHeaderView = nil;
    }
}

- (void) showDonationPrompt {
    if (!OTRBranding.allowsDonation ||
        self.hasPresentedOnboarding ||
        TransactionObserver.hasValidReceipt) {
        return;
    }
    NSDate *ignoreDate = [NSUserDefaults.standardUserDefaults objectForKey:kOTRIgnoreDonationDateKey];
    BOOL dateCheck = NO;
    if (!ignoreDate) {
        dateCheck = YES;
    } else {
        NSTimeInterval lastIgnored = [[NSDate date] timeIntervalSinceDate:ignoreDate];
        NSTimeInterval twoWeeks = 60 * 60 * 24 * 14;
        if (lastIgnored > twoWeeks) {
            dateCheck = YES;
        }
    }
    if (!dateCheck) {
        return;
    }
    NSString *title = [NSString stringWithFormat:@"❤️ %@", DONATE_STRING()];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:DID_YOU_KNOW_DONATION_STRING() preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *donate = [UIAlertAction actionWithTitle:DONATE_STRING() style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [PurchaseViewController showFrom:self];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:MAYBE_LATER_STRING() style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:donate];
    [alert addAction:cancel];
    [self presentViewController:alert animated:YES completion:nil];
    [NSUserDefaults.standardUserDefaults setObject:NSDate.date forKey:kOTRIgnoreDonationDateKey];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self showOnboardingIfNeeded];
    [self showDonationPrompt];
    
    //privacy page caused issues with location authorization for share Location
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    if (status == kCLAuthorizationStatusNotDetermined)
    {
        self.locationManager = [[CLLocationManager alloc] init];
        [self.locationManager requestWhenInUseAuthorization];
    }
}
         


- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    self.navigationController.toolbarHidden = YES;
    
    [self.dynConnStatusView stopAnimating];
    self.tableView.tableHeaderView = nil;
    
    [self.cellUpdateTimer invalidate];
    self.cellUpdateTimer = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_welcoming) {
        _statusCtr = 0;
        if (self.statusTimer) [self.statusTimer invalidate];
        self.statusTimer = nil;
        [self setConnectionStatus];
        _welcoming = NO;
    }
    
    [self removeLocalVPNFiles];
}

- (void)inboxArchiveControlValueChanged:(id)sender {
    if (![sender isKindOfClass:[UISegmentedControl class]]) {
        return;
    }
    UISegmentedControl *segment = sender;
    BOOL showArchived = NO;
    if (segment.selectedSegmentIndex == 0) {
        showArchived = NO;
    } else if (segment.selectedSegmentIndex == 1) {
        showArchived = YES;
    }
    [self updateInboxArchiveFilteringAndShowArchived:showArchived];
}

- (void) updateInboxArchiveFilteringAndShowArchived:(BOOL)showArchived {
    [[OTRDatabaseManager sharedInstance].writeConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        YapDatabaseFilteredViewTransaction *fvt = [transaction ext:OTRArchiveFilteredConversationsName];
        YapDatabaseViewFiltering *filtering = [YapDatabaseViewFiltering withObjectBlock:^BOOL(YapDatabaseReadTransaction * _Nonnull transaction, NSString * _Nonnull group, NSString * _Nonnull collection, NSString * _Nonnull key, id  _Nonnull object) {
            if ([object conformsToProtocol:@protocol(OTRThreadOwner)]) {
                id<OTRThreadOwner> threadOwner = object;
                BOOL isArchived = threadOwner.isArchived;
                return showArchived == isArchived;
            }
            return !showArchived; // Don't show presence requests in Archive
        }];
        [fvt setFiltering:filtering versionTag:[NSUUID UUID].UUIDString];
    }];
}

// use this to slide out sideMenu
- (void)settingsButtonPressed:(id)sender
{
    [self setSideAccount];
    self.navigationController.toolbarHidden = YES;
    self.sideView.frontConstraint.constant = self.sideView.frame.size.width-250;
    CGRect sideMenuFrame = self.sideView.frame;
    sideMenuFrame.origin.x = 260-self.sideView.frame.size.width;
    self.sideView.frame = sideMenuFrame;
    
    [self.navigationController.view addGestureRecognizer:self.sideTapGestureRecognizer];
    
    // animation doesn't seem to be working
    [UIView animateWithDuration:0.6f animations:^{
        [self.navigationController.view layoutIfNeeded];
    }];
}

#pragma - mark Side Menu Delegate functions
- (void)closingSideMenu {
    self.navigationController.toolbarHidden = NO;
    CGRect sideMenuFrame = self.sideView.frame;
    sideMenuFrame.origin.x = -1115;
    self.sideView.frame = sideMenuFrame;
    
    [self.navigationController.view removeGestureRecognizer:self.sideTapGestureRecognizer];
    
    [UIView animateWithDuration:0.6f animations:^{
        [self.navigationController.view layoutIfNeeded];
    }];
}

- (void)addVPNConnection {
    //check connection type. If not openvpn alert and return
    if (_accountType != nil && ![_accountType isEqualToString:@"openvpn"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Account notification" message:@"Your account does not support adding VPN configurations. Contact your administrator for more information." preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:cancel];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    if (![AWSAccountManager.shared coreSignedIn]) {
        [self setWelcomeController:YES];
    } else {
        [AWSAccountManager.shared getUserDetails];
    }
}

- (void)gotoSettings {
    if (self.settingsViewController == nil) {
        self.settingsViewController = [GlobalTheme.shared settingsViewController];
    }
    [self.navigationController pushViewController:self.settingsViewController animated:YES];
}

- (void)gotoSupport {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://glaciersecurity.zendesk.com"]];
}
// end SideMenuDelegate functions

// Seems to cause a crash sometimes in DNZEmptySet
-(void) doLogout {
    [AWSAccountManager.shared teardownCognito];
    
    [self addStatusGestures:NO];
    self.connectionSuccess = NO;
    self.retryCtr = 0;
    
    //unregister push, doesn't affect Apple, but mod_push removes subscriptions
    if (_currentmgr) {
        OTRAccount *acct = [self getFirstAccount];
        if (acct) {
            OTRXMPPAccount *xmppAccount = (OTRXMPPAccount *)acct;
            XMPPJID *serverJID = [XMPPJID jidWithUser:nil domain:xmppAccount.pushPubsubEndpoint resource:nil];
            [_currentmgr.serverCheck.pushModule disablePushForServerJID:serverJID node:xmppAccount.pushPubsubNode
                                                          elementId:nil];
        }
    }
    
    NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.glaciersec.apps"];
    NSString *saveorg = [glacierDefaults stringForKey:@"orgid"];
    [glacierDefaults removePersistentDomainForName:@"group.com.glaciersec.apps"];
    [glacierDefaults synchronize];
    if (saveorg) {
        glacierDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.glaciersec.apps"];
        [glacierDefaults setObject:saveorg forKey:@"orgid"];
    }
    
    _statusCtr = 0;
    if (self.statusTimer) [self.statusTimer invalidate];
    self.statusTimer = nil;
    
    OTRAccount *account = [self getFirstAccount];
    if (account != nil) {
        [[OTRProtocolManager sharedInstance] setLoggingOut:YES];
        [[OTRProtocolManager sharedInstance] removeProtocolForAccount:account];
        [OTRAccountsManager removeAccount:account];
        _currentacct = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[OTRProtocolManager sharedInstance] setLoggingOut:NO];
        });
    }
    
    self.hasPresentedOnboarding = NO;
    [self showOnboardingIfNeeded];
}

-(void) resetAfterLogout:(OTRXMPPAccount *)account {
    [self.navigationController popToRootViewControllerAnimated:NO];
    NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.glaciersec.apps"];
    NSString *saveorg = [glacierDefaults stringForKey:@"orgid"];
    [glacierDefaults removePersistentDomainForName:@"group.com.glaciersec.apps"];
    [glacierDefaults synchronize];
    if (saveorg) {
        glacierDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.glaciersec.apps"];
        [glacierDefaults setObject:saveorg forKey:@"orgid"];
    }
    
    [AWSAccountManager.shared teardownCognito];
    
    UIStoryboard *onboardingStoryboard = [UIStoryboard storyboardWithName:@"Onboarding" bundle:[OTRAssets resourcesBundle]];
    UINavigationController *welcomeNavController = [onboardingStoryboard instantiateInitialViewController];
    welcomeNavController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:welcomeNavController animated:NO completion:nil];
    OTRWelcomeViewController *welcomeView = (OTRWelcomeViewController *)welcomeNavController.visibleViewController;
    [welcomeView displayCloseFunction:NO];
    self.settingsViewController = nil;
    
    self.awspauth = (OTRWelcomeViewController *)welcomeNavController.visibleViewController;
    
    [self addStatusGestures:NO];
    self.connectionSuccess = NO;
    self.retryCtr = 0;
    
    _statusCtr = 0;
    if (self.statusTimer) [self.statusTimer invalidate];
    self.statusTimer = nil;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        if (account) {
            [[OTRProtocolManager sharedInstance] setLoggingOut:YES];
            if( [[OTRProtocolManager sharedInstance] isAccountConnected:account])
            {
                id<OTRProtocol> protocol = [[OTRProtocolManager sharedInstance] protocolForAccount:account];
                [protocol disconnect];
            }
            [[OTRProtocolManager sharedInstance] removeProtocolForAccount:account];
            [OTRAccountsManager removeAccount:account];
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (_currentmgr != nil) {
                [self.KVOController unobserve:_currentmgr];
                [_currentmgr clearMemory];
                _currentmgr = nil;
            }
            _currentacct = nil;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [[OTRDatabaseManager sharedInstance] clearYapDatabase];
                DDLogWarn(@"*** Cleared DB");
            });
        });
    });
    
    self.hasPresentedOnboarding = YES;
}

- (void)composeButtonPressed:(id)sender
{
    if ([self.delegate respondsToSelector:@selector(conversationViewController:didSelectCompose:)]) {
        [self.delegate conversationViewController:self didSelectCompose:sender];
    }
}

- (void)dialpadButtonPressed:(id)sender
{
    if ([self.delegate respondsToSelector:@selector(conversationViewController:didSelectDialpad:)]) {
        [self.delegate conversationViewController:self didSelectDialpad:sender];
    }
}

- (void)groupButtonPressed:(id)sender
{
    if ([self.delegate respondsToSelector:@selector(conversationViewController:didSelectGroup:)]) {
        [self.delegate conversationViewController:self didSelectGroup:sender];
    }
}

- (void)updateVisibleCells:(id)sender
{
    NSArray * indexPathsArray = [self.tableView indexPathsForVisibleRows];
    for(NSIndexPath *indexPath in indexPathsArray)
    {
        id <OTRThreadOwner> thread = [self threadForIndexPath:indexPath];
        UITableViewCell * cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if ([cell isKindOfClass:[OTRConversationCell class]]) {
            [(OTRConversationCell *)cell setThread:thread];
        }
    }
}

- (id) objectAtIndexPath:(NSIndexPath*)indexPath {
    return [self.conversationListViewHandler object:indexPath];
}

- (id <OTRThreadOwner>)threadForIndexPath:(NSIndexPath *)indexPath
{
    id object = [self objectAtIndexPath:indexPath];
    id <OTRThreadOwner> thread = object;
    return thread;
}

- (void)updateComposeButton:(NSUInteger)numberOfaccounts
{
    self.composeBarButtonItem.enabled = numberOfaccounts > 0;
}

- (void)updateInboxArchiveItems:(UIView*)sender
{
    //
}

// reload table view to get touches working again
- (void) groupRemoved:(NSNotification*)notification {
    [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.migrationInfoHeaderView != nil) {
        UIView *headerView = self.migrationInfoHeaderView;
        [headerView setNeedsLayout];
        [headerView layoutIfNeeded];
        int height = [headerView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
        CGRect frame = headerView.frame;
        frame.size.height = height + 1;
        headerView.frame = frame;
        self.tableView.tableHeaderView = headerView;
    } else {
        self.connStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 5, 100, 30)];
        [self.connStatusLabel setFont:[UIFont fontWithName:kFontAwesomeFont size:11]];
        [self.connStatusLabel setText:@"Connecting..."];
        self.connStatusLabel.textColor = [UIColor whiteColor];
        self.connStatusLabel.backgroundColor = [UIColor blackColor];
        self.connStatusLabel.textAlignment = NSTextAlignmentCenter;
        
        self.connStatusView = self.connStatusLabel;
        [self setConnectionStatus];
    }
}

- (void) networkConnectionStatusChange:(NSNotification*)notification {
    [self setConnectionStatus];
}

- (void) connectionStateDidChange:(NSNotification *)notification {
    [self setConnectionStatus];
}

- (void) setConnectionStatus {
    OTRAccount *firstAcct = [self getFirstAccount];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (firstAcct != nil) {
            [self addStatusGestures:NO];
            if ([[OTRProtocolManager sharedInstance] existsProtocolForAccount:firstAcct]) {
                if ([[OTRProtocolManager sharedInstance] isAccountConnected:firstAcct]) {
                    self.connStatusLabel.text = @"";
                    self.tableView.tableHeaderView = nil;
                    [self.dynConnStatusView stopAnimating];
                    self.showSkeleton = NO;
                }
                else {
                    [self handleConnectingStatus:YES accountExists:YES];
                }
            } else {
                // this occurs when in process of trying to create new account
                // or first opening app with no VPN connectivity
                [self handleConnectingStatus:NO accountExists:YES];
            }
        } else { // no account yet
            //DDLogWarn(@"*** no account yet with statusCtr %d", _statusCtr);
            [self handleConnectingStatus:NO accountExists:NO];
        }
    });
}

- (void) handleConnectingStatus:(BOOL)protocolExists accountExists:(BOOL)accountExists{
    //DDLogWarn(@"*** handleConnectingStatus with statusCtr %d", _statusCtr);
    if (accountExists) {
        self.showSkeleton = YES;
    } else {
        self.showSkeleton = NO;
    }
    
    if (_statusCtr < 3) {
        self.tableView.tableHeaderView = self.dynConnStatusView;
        [self.dynConnStatusView startAnimating];
    } else {
        [self.dynConnStatusView stopAnimating];
        OTRNetworkConnectionStatus networkStatus = [[OTRAppDelegate appDelegate] getCurrentNetworkStatus];
        if (networkStatus == OTRNetworkConnectionStatusConnected) { // logging in
            //DDLogWarn(@"*** handleConnectingStatus with _networkStatus connected and statusCtr %d", _statusCtr);
            if (protocolExists) { // network is up, but problems logging into xmpp server
                if (_statusCtr < 6) {
                    self.connStatusLabel.text = @"Connecting";
                } else if (_statusCtr < 9) {
                    self.connStatusLabel.text = @"Still trying to log in";
                } else {
                    self.connStatusLabel.text = @"Offline - Tap to login";
                    self.showSkeleton = NO;
                    [self addStatusGestures:YES];
                }
            } else if (accountExists) { // can happen during account initialization
                if (_statusCtr < 6) {
                    self.connStatusLabel.text = @"Initializing account";
                } else {
                    self.connStatusLabel.text = @"Problems initializing account";
                    self.showSkeleton = NO;
                }
            } else { // no account
                if (_statusCtr < 6) {
                    self.connStatusLabel.text = @"Initializing account";
                } else if (_statusCtr < 10) {
                    self.connStatusLabel.text = @"Still trying to initialize";
                } else {
                    [self addStatusGestures:YES];
                    self.connStatusLabel.text = @"No account - Tap to configure";
                }
            }
        } else if (_statusCtr < 6) {
            self.connStatusLabel.text = @"Connecting";
        } else if (_statusCtr < 9) {
            self.connStatusLabel.text = @"Still Waiting for VPN Connectivity";
            if (_accountType != nil && [_accountType isEqualToString:@"none"]) {
                self.connStatusLabel.text = @"Still Waiting for Connectivity";
            }
        } else {
            self.showSkeleton = NO;
            [self handleOfflineNetworkMessage];
        }
        self.tableView.tableHeaderView = self.connStatusView;
        [self.connStatusLabel setCenter:self.connStatusView.center];
    }
}

- (void) handleOfflineNetworkMessage {
    //DDLogWarn(@"*** handleOfflineNetworkMessage with statusCtr %d", _statusCtr);
    if (_accountType != nil) {
        if ([_accountType isEqualToString:@"ipsec"]) {
            self.connStatusLabel.text = @"Offline - Enable VPN in iOS Settings";
        } else if ([_accountType isEqualToString:@"none"]) {
            self.connStatusLabel.text = @"Offline - Tap to try again";
            [self addStatusGestures:YES];
        } else {
            self.connStatusLabel.text = @"Offline - Tap for OpenVPN";
            [self addStatusGestures:YES];
        }
    } else {
        self.connStatusLabel.text = self.connStatusLabel.text = @"Offline - Tap for OpenVPN";
        [self addStatusGestures:YES];
    }
}

- (void) setShowSkeleton:(BOOL)shouldShowSkeleton {
    if (shouldShowSkeleton != _showSkeleton) {
        _showSkeleton = shouldShowSkeleton;
        [self.tableView reloadData];
    }
}

- (void) addStatusGestures:(BOOL)turnon {
    if (turnon) {
        [self.connStatusView addGestureRecognizer:self.statusTapGestureRecognizer];
        self.connStatusView.userInteractionEnabled = YES;
    } else {
        [self.connStatusView removeGestureRecognizer:self.statusTapGestureRecognizer];
        self.connStatusView.userInteractionEnabled = NO;
    }
}

- (void) handleStatusGesture {
    NSString *statusString = self.connStatusLabel.text;
    if ([statusString hasSuffix:@"OpenVPN"]) {
        [self openOpenVPN];
    } else if ([statusString hasSuffix:@"login"]) {
        if (self.statusTimer) [self.statusTimer invalidate];
        _statusCtr = 0;
        _statusTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateStatusTimer:) userInfo:nil repeats:YES];
        
        [self retryLogin];
    } else if ([statusString hasSuffix:@"again"]) { // retry network
        [self retryNetworkConnection];
    } else if ([statusString hasPrefix:@"No account"]) {
        [self doLogout];
    }
}

- (void)updateStatusTimer:(id)sender
{
    //DDLogWarn(@"*** statusCtr %d", _statusCtr);
    if (_statusCtr < 12) {
        _statusCtr++;
    } else {
        if (self.statusTimer) [self.statusTimer invalidate];
        self.statusTimer = nil;
    }
    
    if (_statusCtr % 3 == 0) {
        [self setConnectionStatus];
    }
}

- (void) retryNetworkConnection {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OTRAppDelegate appDelegate] checkConnectionOrTryLogin];
    });
}

- (void) retryLogin {
    OTRNetworkConnectionStatus currentStatus = [[OTRAppDelegate appDelegate] getCurrentNetworkStatus];
    NSMutableDictionary *userInfo = [@{NewNetworkStatusKey: @(currentStatus)} mutableCopy];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:NetworkStatusNotificationName object:self userInfo:userInfo];
    });
}

- (void) openOpenVPN {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OTRAppDelegate appDelegate] gotoOpenVPN];
    });
}

#pragma - mark UITableViewDataSource Methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self.conversationListViewHandler.mappings numberOfSections];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.conversationListViewHandler.mappings numberOfItemsInSection:section];
}


- (void) handleSubscriptionRequest:(OTRXMPPBuddy*)buddy approved:(BOOL)approved {
    __block OTRAccount *account = nil;
    [self.conversationListViewHandler.databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        account = [buddy accountWithTransaction:transaction];
    }];
    OTRXMPPManager *manager = (OTRXMPPManager*)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
    [buddy setAskingForApproval:NO];
    if (approved) {
        [[OTRDatabaseManager sharedInstance].writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            buddy.trustLevel = BuddyTrustLevelRoster;
            [buddy saveWithTransaction:transaction];
        }];
        // TODO - use the queue for this!
        [manager.xmppRoster acceptPresenceSubscriptionRequestFrom:buddy.bareJID andAddToRoster:YES];
        if ([self.delegate respondsToSelector:@selector(conversationViewController:didSelectThread:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate conversationViewController:self didSelectThread:buddy];
            });
        }
    } else {
        [[OTRDatabaseManager sharedInstance].writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [buddy removeWithTransaction:transaction];
        }];
        [manager.xmppRoster rejectPresenceSubscriptionRequestFrom:buddy.bareJID];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OTRBuddyImageCell *cell = nil;
    id <OTRThreadOwner> thread = [self threadForIndexPath:indexPath];
    if ([thread isKindOfClass:[OTRXMPPBuddy class]] &&
        [(OTRXMPPBuddy*)thread askingForApproval]) {
        OTRBuddyApprovalCell *approvalCell = [tableView dequeueReusableCellWithIdentifier:[OTRBuddyApprovalCell reuseIdentifier] forIndexPath:indexPath];
        [approvalCell setActionBlock:^(OTRBuddyApprovalCell *cell, BOOL approved) {
            [self handleSubscriptionRequest:(OTRXMPPBuddy*)thread approved:approved];
        }];
        cell = approvalCell;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        OTRConversationCell *occell = [tableView dequeueReusableCellWithIdentifier:[OTRConversationCell reuseIdentifier] forIndexPath:indexPath];
        [occell setShowSkeleton:self.showSkeleton];
        cell = occell;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    
    [cell.avatarImageView.layer setCornerRadius:(kOTRConversationCellHeight-2.0*OTRBuddyImageCellPadding)/2.0];
    
    [cell setThread:thread];
    
    return cell;
}

#pragma - mark UITableViewDelegate Methods

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return kOTRConversationCellHeight;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return kOTRConversationCellHeight;
}

- (nullable NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath  {
    id <OTRThreadOwner> thread = [self threadForIndexPath:indexPath];
    return [UITableView editActionsForThread:thread deleteActionAlsoRemovesFromRoster:NO connection:OTRDatabaseManager.shared.writeConnection];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    id <OTRThreadOwner> thread = [self threadForIndexPath:indexPath];
    
    // Bail out if it's a subscription request
    if ([thread isKindOfClass:[OTRXMPPBuddy class]] &&
        [(OTRXMPPBuddy*)thread askingForApproval]) {
        return;
    }

    if ([self.delegate respondsToSelector:@selector(conversationViewController:didSelectThread:)]) {
        [self.delegate conversationViewController:self didSelectThread:thread];
    }
}

#pragma - mark OTRAccountDatabaseCountDelegate method

- (void)accountCountChanged:(OTRAccountDatabaseCount *)counter {
    [self updateComposeButton:counter.numberOfAccounts];
    
    if (counter.numberOfAccounts > 0) {
        [self setConnectionStatus];
    }
}

#pragma - mark YapDatabse Methods

- (void)didSetupMappings:(OTRYapViewHandler *)handler
{
    [self.tableView reloadData];
    [self updateInboxArchiveItems:self.navigationItem.titleView];
}

- (void)didReceiveChanges:(OTRYapViewHandler *)handler sectionChanges:(NSArray<YapDatabaseViewSectionChange *> *)sectionChanges rowChanges:(NSArray<YapDatabaseViewRowChange *> *)rowChanges
{
    if ([rowChanges count] == 0 && sectionChanges == 0) {
        return;
    }
    
    [self updateInboxArchiveItems:self.navigationItem.titleView];
    
    [self.tableView beginUpdates];
    
    for (YapDatabaseViewSectionChange *sectionChange in sectionChanges)
    {
        switch (sectionChange.type)
        {
            case YapDatabaseViewChangeDelete :
            {
                [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeInsert :
            {
                [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeUpdate:
            case YapDatabaseViewChangeMove:
                break;
        }
    }
    
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

#pragma - mark Account Migration Methods

- (MigrationInfoHeaderView *)createMigrationHeaderView:(OTRXMPPAccount *)account
{
    OTRServerDeprecation *deprecationInfo = [OTRServerDeprecation deprecationInfoWithServer:account.bareJID.domain];
    if (deprecationInfo == nil) {
        return nil; // Should not happen if we got here already
    }
    UINib *nib = [UINib nibWithNibName:@"MigrationInfoHeaderView" bundle:OTRAssets.resourcesBundle];
    MigrationInfoHeaderView *header = (MigrationInfoHeaderView*)[nib instantiateWithOwner:self options:nil][0];
    [header.titleLabel setText:MIGRATION_STRING()];
    if (deprecationInfo.shutdownDate != nil && [[NSDate date] compare:deprecationInfo.shutdownDate] == NSOrderedAscending) {
        // Show shutdown date
        [header.descriptionLabel setText:[NSString stringWithFormat:MIGRATION_INFO_WITH_DATE_STRING(), deprecationInfo.name, [NSDateFormatter localizedStringFromDate:deprecationInfo.shutdownDate dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterNoStyle]]];
    } else {
        // No shutdown date or already passed
        [header.descriptionLabel setText:[NSString stringWithFormat:MIGRATION_INFO_STRING(), deprecationInfo.name]];
    }
    [header.startButton setTitle:MIGRATION_START_STRING() forState:UIControlStateNormal];
    [header setAccount:account];
    return header;
}

- (IBAction)didPressStartMigrationButton:(id)sender {
    if (self.migrationInfoHeaderView != nil) {
        OTRXMPPAccount *oldAccount = self.migrationInfoHeaderView.account;
        OTRAccountMigrationViewController *migrateVC = [[OTRAccountMigrationViewController alloc] initWithOldAccount:oldAccount];
        migrateVC.showsCancelButton = YES;
        migrateVC.modalPresentationStyle = UIModalPresentationFormSheet;
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:migrateVC];
        [self presentViewController:navigationController animated:YES completion:nil];
    }
}

- (UIImage *)imageForEmptyDataSet:(UIScrollView *)scrollView
{
    return [UIImage imageNamed:@"glacier" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil];
}

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text = @"No Conversations";
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:18.0f],
                                 NSForegroundColorAttributeName: [UIColor darkGrayColor]};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString *)descriptionForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text = @"When you have conversations, you'll see them here.";
    
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.alignment = NSTextAlignmentCenter;
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:14.0f],
                                 NSForegroundColorAttributeName: [UIColor lightGrayColor],
                                 NSParagraphStyleAttributeName: paragraph};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (void) removeLocalVPNFiles {
    if (![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"openvpn://"]]) {
        
        if (self.vpnalert) {
            [self.vpnalert dismissViewControllerAnimated:YES completion:nil];
        }
        
        return;
    }
    
    [AWSAccountManager.shared removeLocalVPNFiles]; 
}

- (BOOL) needsOpenVPN {
    if (![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"openvpn://"]])
    {
        self.vpnalert = [UIAlertController alertControllerWithTitle:@"Error" message:@"You do not have an app that can open your VPN profile. Please download OpenVPN Connect from the App Store." preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
        [self.vpnalert addAction:cancel];
        [self presentViewController:self.vpnalert animated:YES completion:nil];
        return true;
    }
    
    return false;
}

@end
