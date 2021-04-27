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
#import "Glacier-Swift.h"
#import "GlacierInfo.h"

#import "OTRXMPPManager.h"
#import "OTRXMPPRoomManager.h"
#import "OTRBuddyApprovalCell.h"
#import "OTRStrings.h"
#import "OTRvCard.h"
#import "XMPPvCardTemp.h"

@import DGActivityIndicatorView;
#import "UIScrollView+EmptyDataSet.h"
#import "NetworkTester.h"
@import BButton;

@import SAMKeychain;
//@import os.log;

static CGFloat kOTRConversationCellHeight = 80.0;

@interface OTRConversationViewController () <OTRYapViewHandlerDelegateProtocol, OTRAccountDatabaseCountDelegate, DZNEmptyDataSetSource, DZNEmptyDataSetDelegate>

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

@property (nonatomic, strong) UIViewController *settingsViewController;
@property (nonatomic, strong) OTRAccount *currentacct;

// for single signon via AWS
@property (nonatomic, strong) OTRWelcomeViewController *awspauth;

@property int retryCtr;
@property (nonatomic) BOOL connectionSuccess;
@property (nonatomic) BOOL tryingGlacierAcct;
@property (nonatomic, strong) OTRXMPPManager *currentmgr;
@property (nonatomic) BOOL showSkeleton;

@property (nonatomic) BOOL hasPresentedOnboarding;

@property (nonatomic, strong) OTRAccountDatabaseCount *accountCounter;
@property (nonatomic, strong) UISegmentedControl *inboxArchiveControl;

@end

@implementation OTRConversationViewController

- (void)viewDidLoad
{
    [super viewDidLoad];    
   
    ///////////// Setup Navigation Bar //////////////
    UIColor *lblColor = [UIColor blackColor];
    if (@available(iOS 13.0, *)) {
        lblColor = [UIColor labelColor];
    }
    
    self.title = @" ";
    UIBarButtonItem *settingsBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OTRSettingsIcon-1" inBundle:[GlacierInfo resourcesBundle] compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(settingsButtonPressed:)];
    self.navigationItem.leftBarButtonItem = settingsBarButtonItem;
    
    self.composeBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"new_message" inBundle:[GlacierInfo resourcesBundle] compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(composeButtonPressed:)];
    self.navigationItem.rightBarButtonItems = @[self.composeBarButtonItem];
    [settingsBarButtonItem setTintColor:lblColor];
    [self.composeBarButtonItem setTintColor:lblColor];
    
    _inboxArchiveControl = [[UISegmentedControl alloc] initWithItems:@[INBOX_STRING(), ARCHIVE_STRING()]];
    _inboxArchiveControl.selectedSegmentIndex = 0;
    _inboxArchiveControl.tintColor = [UIColor colorWithRed:41/255.0 green:54/255.0 blue:62/255.0 alpha:1];
    
    UIFontDescriptor *userFont = [UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleBody];
    float fontSize = [userFont pointSize]-4;
    UIFont *segfont = [UIFont systemFontOfSize:fontSize];//16];
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:segfont
                                                           forKey:NSFontAttributeName];
    [_inboxArchiveControl setTitleTextAttributes:attributes
                                    forState:UIControlStateNormal];
    UIFont *selectedfont = [UIFont boldSystemFontOfSize:fontSize];//16];
    NSDictionary *selattributes = [NSDictionary dictionaryWithObject:selectedfont
                                                           forKey:NSFontAttributeName];
    [_inboxArchiveControl setTitleTextAttributes:selattributes
                                    forState:UIControlStateSelected];
    
    [self updateInboxArchiveFilteringAndShowArchived:NO];
    [_inboxArchiveControl addTarget:self action:@selector(inboxArchiveControlValueChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _inboxArchiveControl;
    
    // tint color is letters
    self.dynConnStatusView = [[DGActivityIndicatorView alloc]
                              initWithType:DGActivityIndicatorAnimationTypeBallBeat
                              tintColor:lblColor size:18.0f];
    self.dynConnStatusView.frame = CGRectMake(5, 5, 100, 20);
    
    [self resetStatusTimer];
    _repeatStr = [NSString fa_stringForFontAwesomeIcon:FAIconRepeat];
    
    self.navigationController.navigationBar.barTintColor = GlobalTheme.shared.lightThemeColor;
    self.navigationController.navigationBar.tintColor = lblColor;
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName : lblColor};
    
    self.navigationController.toolbarHidden = NO;
    self.dialpadBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"dialpad" inBundle:[GlacierInfo resourcesBundle] compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(dialpadButtonPressed:)];
    
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];
    
    UILabel *createLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 5, 100, 20)];
    [createLabel setFont:[UIFont fontWithName:kFontAwesomeFont size:11]];
    [createLabel setText:@"Create New Group"];
    NSArray *items = [NSArray arrayWithObjects:self.dialpadBarButtonItem, flex, nil];
    self.toolbarItems = items;
    
    self.navigationController.toolbar.barTintColor = GlobalTheme.shared.lightThemeColor;
    self.navigationController.toolbar.tintColor = lblColor;
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
    
    [self setupLongAndTapPress];
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

- (void) lookForAccountInfoIfNeeded {
    if (![self getFirstAccount]) {
        [self.navigationController popToRootViewControllerAnimated:YES];
        [self tryGlacierGroupAccount];
    }
}

- (void) showOnboardingIfNeeded {
    if (self.hasPresentedOnboarding) {
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

- (BOOL) tryGlacierGroupAccount {
    return [self tryGlacierGroupAccount:NO];
}

// user account info can be shared among Glacier apps. Check for existing account info.
- (BOOL) tryGlacierGroupAccount:(BOOL)altroute {
    if (self.tryingGlacierAcct) {
        return YES; // let the process finish
    }
    
    NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc]
                                       initWithSuiteName:kGlacierGroup];
    NSString *uservalue = [glacierDefaults stringForKey:@"username"];
    NSString *passvalue = [glacierDefaults stringForKey:@"password"];
    NSString *displayvalue = [glacierDefaults stringForKey:@"displayname"];
    
    NSError *error = nil;
    NSString *idvalue = [SAMKeychain passwordForService:kGlacierGroup account:kGlacierAcct accessGroup:kGlacierGroup error:&error];
    if (idvalue) {
        passvalue = [SAMKeychain passwordForService:kGlacierGroup account:idvalue accessGroup:kGlacierGroup error:&error];
    }
    if (error) {
        DDLogError(@"Error retreiving password from keychain: %@%@", [error localizedDescription], [error userInfo]);
        passvalue = [glacierDefaults stringForKey:@"password"];
    }
    
    if (uservalue.length && passvalue.length) {
        
        // load account from glacier storage
        OTRXMPPAccount *account = [OTRAccount accountWithUsername:@"" accountType:OTRAccountTypeJabber];
        
        NSArray *components = [uservalue componentsSeparatedByString:@"@"];
        if (components.count != 2) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self badLoginAlert];
            });
            return NO;
        }
        
        account.username = uservalue;
        if (!displayvalue.length) {
            displayvalue = components.firstObject;
        }
        account.domain = components.lastObject;
        
        self.tryingGlacierAcct = YES;
        [self resetStatusTimer];
        
        [self setConnectionStatus];
        
        account.password = passvalue;
        if (displayvalue.length) {
            account.displayName = displayvalue;
        } else {
            account.displayName = uservalue;
        }
        
        BOOL includesDomain = components.count == 2;
        
        if (account.password == nil) {
            DDLogError(@"Password nil, how is this possible?");
            //[GlacierLog glogWithLogMsg:@"Error logging in, Password in account is nil" detail:account.uniqueId];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[OTRAppDelegate appDelegate] setDomain:components.lastObject];
            [self doLogin:account includesDomain:includesDomain];
        });
        
        // if we had password from Voice and can delete from Keychain
        if (idvalue && !_awspauth) {
            [SAMKeychain deletePasswordForService:kGlacierGroup account:idvalue accessGroup:kGlacierGroup error:&error];
            //[GlacierLog glogWithLogMsg:@"Deleting Password set from glacier file" detail:account.uniqueId];
        }
        
        return YES;
    }
    return NO;
}

- (void) badLoginAlert {
    UIAlertAction * okButtonItem = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self doLogout];
    }];
        
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Warning" message:@"Problems logging in. Your account appears to be an invalid format. Please contact your Glacier account representative." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:okButtonItem];
    [self presentViewController:alert animated:YES completion:nil];
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
            __block BOOL accountExists = NO;
            [OTRDatabaseManager.shared.readConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                accountExists = [transaction objectForKey:account.uniqueId inCollection:[[OTRAccount class] collection]] != nil;
            }];
            NSString *pass = account.password;
            if (!accountExists) {
                [account removeKeychainPassword:nil];
                //[GlacierLog glogWithLogMsg:@"doLogin, Removed password" detail:account.uniqueId];
            
                [[OTRProtocolManager sharedInstance] removeProtocolForAccount:account];
                [[NSNotificationCenter defaultCenter] removeObserver:self.aloginHandler];
                self.aloginHandler = nil;
            }
            
            UIAlertController *certAlert = [UIAlertController certificateWarningAlertWithError:error saveHandler:^(UIAlertAction * _Nonnull action) {
                NSData *certData = error.userInfo[OTRXMPPSSLCertificateDataKey];
                NSString *hostname = error.userInfo[OTRXMPPSSLHostnameKey];
                [OTRCertificatePinning addCertificateData:certData withHostName:hostname];
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    self.tryingGlacierAcct = NO;
                    xaccount.password = pass;
                    [self doLogin:xaccount includesDomain:includesDomain];
                });
            }];
            
            //NSString *hostname = error.userInfo[OTRXMPPSSLHostnameKey];
            
            // try login once more if failed the first time
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
                xaccount.password = pass;
                [self doLogin:xaccount includesDomain:includesDomain];
            });
            
        } else if (account && !self.connectionSuccess) {
            self.connectionSuccess = YES;
            
            [[OTRAppDelegate appDelegate] resetDoubleNotificationHandlerIfNeeded];
            account.loginDate = [NSDate date];
            
            [OTRDatabaseManager.shared.writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                [account saveWithTransaction:transaction];
            }];
            
            _currentmgr = (OTRXMPPManager*)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
            
            if (_currentmgr) {
                [self.KVOController observe:_currentmgr keyPath:NSStringFromSelector(@selector(loginStatus)) options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld action:@selector(connectionStateDidChange:)];
            }
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (_currentmgr) {
                    [PushController setPushPreference:PushPreferenceEnabled];
                    [PushController registerForPushNotifications];
                    [_currentmgr.serverCheck refresh];
                    [_currentmgr.serverCheck.pushModule refresh];
                }
                
                CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
                if (status == kCLAuthorizationStatusNotDetermined)
                {
                    self.locationManager = [[CLLocationManager alloc] init];
                    [self.locationManager requestWhenInUseAuthorization];
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
            
            //If repeated issues, likely account setup problem or no path to network
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Warning" message:@"Problems logging in. Do you want to reset and try again? For assistance contact your Glacier account representative." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:cancelButtonItem];
            [alert addAction:okButtonItem];
            [self presentViewController:alert animated:YES completion:nil];
        }
    });
}

- (void) setWelcomeController:(BOOL)closeable {
    _welcoming = YES;
    UIStoryboard *onboardingStoryboard = [UIStoryboard storyboardWithName:@"Onboarding" bundle:[GlacierInfo resourcesBundle]];
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
    [self addStatusGestures:NO];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData:) name:ReloadDataNotificationName object:nil];
    if (_accountType == nil) {
        NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc] initWithSuiteName:kGlacierGroup];
        _accountType = [glacierDefaults stringForKey:@"connection"];
    }
    
    [self updateComposeButton:self.accountCounter.numberOfAccounts];
}

- (void) enteringForeground:(NSNotification *)notification {
    [self resetStatusTimer];
    
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

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self showOnboardingIfNeeded];
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

- (void)settingsButtonPressed:(id)sender
{
    [self gotoSettings];
}

- (void)gotoSettings {
    if (self.settingsViewController == nil) {
        self.settingsViewController = [GlobalTheme.shared settingsViewController];
    }
    [self.navigationController pushViewController:self.settingsViewController animated:YES];
}

// Seems to cause a crash sometimes in DNZEmptySet
-(void) doLogout {
    [AWSAccountManager.shared teardownCognito];
    
    [self addStatusGestures:NO];
    self.connectionSuccess = NO;
    self.retryCtr = 0;
    
    // unregister push, doesn't affect Apple, but mod_push removes subscriptions
    if (_currentmgr) {
        OTRAccount *acct = [self getFirstAccount];
        if (acct) {
            OTRXMPPAccount *xmppAccount = (OTRXMPPAccount *)acct;
            XMPPJID *serverJID = [XMPPJID jidWithUser:nil domain:xmppAccount.pushPubsubEndpoint resource:nil];
            [_currentmgr.serverCheck.pushModule disablePushForServerJID:serverJID node:xmppAccount.pushPubsubNode
                                                          elementId:nil];
        }
    }
    
    NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc] initWithSuiteName:kGlacierGroup];
    [glacierDefaults removePersistentDomainForName:kGlacierGroup];
    
    _statusCtr = 0;
    if (self.statusTimer) [self.statusTimer invalidate];
    self.statusTimer = nil;
    
    OTRAccount *account = [self getFirstAccount];
    if (account != nil) {
        [[OTRProtocolManager sharedInstance] setLoggingOut:YES];
        [[OTRProtocolManager sharedInstance] removeProtocolForAccount:account];
        [OTRAccountsManager removeAccount:account];
        _currentacct = nil;
        
        [VPNManager.shared turnOffVpn];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[OTRAppDelegate appDelegate] bypassNetworkCheck:NO];
        });
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[OTRProtocolManager sharedInstance] setLoggingOut:NO];
        });
    }
    
    NSError *error = nil;
    NSString *idvalue = [SAMKeychain passwordForService:kGlacierGroup account:kGlacierAcct error:&error];
    if (idvalue) {
        [SAMKeychain deletePasswordForService:kGlacierGroup account:idvalue accessGroup:kGlacierGroup error:&error];
        [SAMKeychain deletePasswordForService:kGlacierGroup account:kGlacierAcct accessGroup:kGlacierGroup error:nil];
    }
    if (error) {
        DDLogError(@"Error deleting password from keychain: %@%@", [error localizedDescription], [error userInfo]);
    }
    error = nil;
    idvalue = nil;
    idvalue = [SAMKeychain passwordForService:kGlacierGroup account:kCognitoAcct error:&error];
    if (idvalue) {
        [SAMKeychain deletePasswordForService:kGlacierGroup account:idvalue accessGroup:kGlacierGroup error:&error];
        [SAMKeychain deletePasswordForService:kGlacierGroup account:kCognitoAcct accessGroup:kGlacierGroup error:nil];
    }
    if (error) {
        DDLogError(@"Error deleting Cognito password from keychain: %@%@", [error localizedDescription], [error userInfo]);
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (_currentmgr != nil) {
            [self.KVOController unobserve:_currentmgr];
            [_currentmgr clearMemory];
            _currentmgr = nil;
        }
        _currentacct = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[OTRDatabaseManager sharedInstance] clearYapDatabase];
            //[[OTRMediaFileManager sharedInstance] vacuum:^() {}];
            DDLogWarn(@"*** Cleared DB");
            //[GlacierLog glogWithLogMsg:@"*** Cleared DB" detail:@"all"];
        });
    });
    
    self.hasPresentedOnboarding = NO;
    [self showOnboardingIfNeeded];
}

-(void) resetAfterLogout:(OTRXMPPAccount *)account {
    [self.navigationController popToRootViewControllerAnimated:NO];
    NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc] initWithSuiteName:kGlacierGroup];
    [glacierDefaults removePersistentDomainForName:kGlacierGroup];
    
    NSError *error = nil;
    NSString *idvalue = [SAMKeychain passwordForService:kGlacierGroup account:kCognitoAcct error:&error];
    if (idvalue) {
        [SAMKeychain deletePasswordForService:kGlacierGroup account:idvalue accessGroup:kGlacierGroup error:&error];
        [SAMKeychain deletePasswordForService:kGlacierGroup account:kCognitoAcct accessGroup:kGlacierGroup error:nil];
    }
    if (error) {
        DDLogError(@"Error deleting Cognito password from keychain: %@%@", [error localizedDescription], [error userInfo]);
    }
    
    [AWSAccountManager.shared teardownCognito];
    
    UIStoryboard *onboardingStoryboard = [UIStoryboard storyboardWithName:@"Onboarding" bundle:[GlacierInfo resourcesBundle]];
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
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        if (account) {
            //[GlacierLog glogWithLogMsg:@"resetAfterLogout removing account" detail:account.uniqueId];
            [[OTRProtocolManager sharedInstance] setLoggingOut:YES];
        
            [[OTRProtocolManager sharedInstance] removeProtocolForAccount:account];
            [OTRAccountsManager removeAccount:account];
            
            [VPNManager.shared turnOffVpn];
            dispatch_async(dispatch_get_main_queue(), ^{
                [[OTRAppDelegate appDelegate] bypassNetworkCheck:NO];
            });
            
            NSError *error = nil;
            NSString *idvalue = [SAMKeychain passwordForService:kGlacierGroup account:kGlacierAcct error:&error];
            if (idvalue) {
                [SAMKeychain deletePasswordForService:kGlacierGroup account:idvalue accessGroup:kGlacierGroup error:&error];
                [SAMKeychain deletePasswordForService:kGlacierGroup account:kGlacierAcct accessGroup:kGlacierGroup error:nil];
            }
            if (error) {
                DDLogError(@"Error deleting password from keychain: %@%@", [error localizedDescription], [error userInfo]);
                //[GlacierLog glogWithLogMsg:@"Error Removing Password" detail:idvalue];
            } else {
                //[GlacierLog glogWithLogMsg:@"Removed Password" detail:idvalue];
            }
        } 
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (_currentmgr != nil) {
                [self.KVOController unobserve:_currentmgr];
                [_currentmgr clearMemory];
                _currentmgr = nil;
            }
            _currentacct = nil;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [[OTRDatabaseManager sharedInstance] clearYapDatabase];
                //[[OTRMediaFileManager sharedInstance] vacuum:^() {}];
                DDLogWarn(@"*** Cleared DB");
                //[GlacierLog glogWithLogMsg:@"*** Cleared DB" detail:@"all"];
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
- (void) reloadData:(NSNotification*)notification {
    [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.connStatusLabel) {
        [self setConnectionStatus];
        return;
    }
    UIColor *txtColor = [UIColor whiteColor];
    UIColor *bckColor = [UIColor blackColor];
    if (@available(iOS 13.0, *)) {
        bckColor = [UIColor systemGray3Color];
        txtColor = [UIColor labelColor];
    }
        
    self.connStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 5, 100, 30)];
    [self.connStatusLabel setFont:[UIFont fontWithName:kFontAwesomeFont size:11]];
    [self.connStatusLabel setText:@"Connecting..."];
    self.connStatusLabel.textColor = txtColor;
    self.connStatusLabel.backgroundColor = bckColor;
    self.connStatusLabel.textAlignment = NSTextAlignmentCenter;
        
    self.connStatusView = self.connStatusLabel;
    [self setConnectionStatus];
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
            if ([[OTRProtocolManager sharedInstance] existsProtocolForAccount:firstAcct]) {
                if ([[OTRProtocolManager sharedInstance] isAccountConnected:firstAcct]) {
                    self.connStatusLabel.text = @"";
                    self.tableView.tableHeaderView = nil;
                    [self.dynConnStatusView stopAnimating];
                    _statusCtr = 20;
                }
                else {
                    [self handleConnectingStatus:YES accountExists:YES];
                }
            } else { 
                // this occurs when in process of trying to create new account
                // or first opening app with no VPN connectivity
                [self handleConnectingStatus:NO accountExists:YES];
            }
        } else {
            //DDLogWarn(@"*** no account yet with statusCtr %d", _statusCtr);
            [self handleConnectingStatus:NO accountExists:NO];
        }
    });
    
    // if contains tap, add " " +
    //[NSString fa_stringForFontAwesomeIcon:FAIconRepeat]
}

- (void) handleConnectingStatus:(BOOL)protocolExists accountExists:(BOOL)accountExists{
    //DDLogWarn(@"*** handleConnectingStatus with statusCtr %d", _statusCtr);
    if (accountExists) {
        self.showSkeleton = YES;
    } else {
        self.showSkeleton = NO;
    }
    
    if (_statusCtr < 2) {
        self.connStatusLabel.text = @"";
        self.tableView.tableHeaderView = nil;
    } else if (_statusCtr < 4) {
        self.tableView.tableHeaderView = self.dynConnStatusView;
        [self.dynConnStatusView startAnimating];
    } else {
        [self.dynConnStatusView stopAnimating];
        OTRNetworkConnectionStatus networkStatus = [[OTRAppDelegate appDelegate] getCurrentNetworkStatus];
        if (networkStatus == OTRNetworkConnectionStatusConnected) { // logging in
            //DDLogWarn(@"*** handleConnectingStatus with _networkStatus connected and statusCtr %d", _statusCtr);
            if (protocolExists) { // network is up, but problems logging into xmpp server
                if (_statusCtr < 14) {
                    self.connStatusLabel.text = @"Connecting";
                } else if (_statusCtr < 20) {
                    self.connStatusLabel.text = @"Still trying to log in";
                } else {
                    self.connStatusLabel.text = @"Offline - Tap to login";
                    self.showSkeleton = NO;
                    [self addStatusGestures:YES];
                }
            } else if (accountExists) { // can happen during account initialization
                if (_statusCtr < 10) {
                    self.connStatusLabel.text = @"Initializing account";
                } else {
                    self.connStatusLabel.text = @"Problems initializing account";
                    self.showSkeleton = NO;
                }
            } else { // no account
                if (_statusCtr < 10) {
                    self.connStatusLabel.text = @"Initializing account";
                } else if (_statusCtr < 16) {
                    self.connStatusLabel.text = @"Still trying to initialize";
                } else {
                    [self addStatusGestures:YES];
                    self.connStatusLabel.text = @"No account - Tap to configure";
                }
            }
        } else if (_statusCtr < 16) {
            self.connStatusLabel.text = @"Connecting";
        } else if (_statusCtr < 20) {
            self.connStatusLabel.text = @"Still Waiting for Core Connection";
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
    if ([VPNManager.shared vpnIsEnabled]) {
        self.connStatusLabel.text = @"Offline - Enable Core Connection in Settings";
    } else {
        self.connStatusLabel.text = @"Offline - Tap to try again";
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
    if ([statusString hasSuffix:@"login"] || [statusString hasSuffix:@"again"]) {
        [self resetStatusTimer];
        [self addStatusGestures:NO];
        [self retryLogin];
    } else if ([statusString hasPrefix:@"No account"]) {
        [self doLogout];
    }
}

- (void) resetStatusTimer {
    if (self.statusTimer) [self.statusTimer invalidate];
    _statusCtr = 0;
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateStatusTimer:) userInfo:nil repeats:YES];
}

- (void)updateStatusTimer:(id)sender
{
    //DDLogWarn(@"*** statusCtr %d", _statusCtr);
    if (_statusCtr < 22) {
        _statusCtr++;
    } else {
        if (self.statusTimer) [self.statusTimer invalidate];
        self.statusTimer = nil;
    }
    
    if (_statusCtr % 2 == 0) {
        [self setConnectionStatus];
    }
}

- (void) retryNetworkConnection {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OTRAppDelegate appDelegate] checkConnectionOrTryLogin];
    });
}

- (void) retryLogin {
    OTRNetworkConnectionStatus currentStatus = OTRNetworkConnectionStatusConnected;
    NSMutableDictionary *userInfo = [@{NewNetworkStatusKey: @(currentStatus)} mutableCopy];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:NetworkStatusNotificationName object:self userInfo:userInfo];
    });
}

- (void)connectPhoneCall:(TwilioCall *)call {
    __block OTRBuddy *buddy = nil;
    __block OTRAccount *account = [self getFirstAccount];
    if (account == nil) {
        return;
    }
    
    // need to keep separate accounts for receiver at least if outgoing
    //if its a group it should probably be handled by the group, not individually?
    //if call currently connected and open don't need to do anything here
    __block NSString *calltitle = call.calltitle;
    if (calltitle == nil) { //should be able to remove this because calltitle in all calls
        [OTRDatabaseManager.shared.readConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            XMPPJID *jid = [XMPPJID jidWithString:call.caller];
            if (call.outgoing) {
                jid = [XMPPJID jidWithString:call.receiver];
            }
            buddy = [OTRXMPPBuddy fetchBuddyWithJid:jid accountUniqueId:account.uniqueId transaction:transaction];
            if (buddy != nil) {
                calltitle = buddy.displayName;
            }
        }];
    }
    
    if (!calltitle) {
        return;
    }
    
    // concatenate names if needed
    [self openCallController:calltitle];
    OTRAppDelegate *appDelegate = (OTRAppDelegate *)[UIApplication sharedApplication].delegate;
    PhoneCallViewController *callVC = (PhoneCallViewController *)[appDelegate.callWindow.rootViewController presentedViewController];
    [callVC doConnectCall:call with:calltitle];
    
    if (call.systemMessage != nil) {
        [OTRDatabaseManager.shared.writeConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            
            __block id<OTRThreadOwner> thread = nil;
            if ([calltitle hasPrefix:@"#"]) {
                OTRXMPPAccount *xacct = (OTRXMPPAccount *)account;
                NSString *after = [NSString stringWithFormat: @"conference.%@", xacct.domain];
                NSString *groupname = [calltitle substringFromIndex:1];
                NSString *groupjid = [NSString stringWithFormat: @"%@@%@", groupname, after];
                NSString *databaseRoomKey = [OTRXMPPRoom createUniqueId:account.uniqueId jid:groupjid];
                OTRXMPPRoom *room = [OTRXMPPRoom fetchObjectWithUniqueID:databaseRoomKey transaction:transaction];
                if (room != nil) {
                    thread = (id<OTRThreadOwner>)room;
                }
            } else if (buddy == nil) {
                XMPPJID *jid = [XMPPJID jidWithString:call.caller];
                if (call.outgoing) {
                    jid = [XMPPJID jidWithString:call.receiver];
                }
                buddy = [OTRXMPPBuddy fetchBuddyWithJid:jid accountUniqueId:account.uniqueId transaction:transaction];
                thread = (id<OTRThreadOwner>)buddy;
            }
            if (thread != nil) {
                id<OTRMessageProtocol> message = [thread outgoingMessageWithText:call.systemMessage transaction:transaction];
                message.messageSecurity = OTRMessageTransportSecurityPlaintext;
                thread.lastMessageIdentifier = message.messageKey;
                
                if ([message isKindOfClass:[OTROutgoingMessage class]]) {
                    OTROutgoingMessage *systemMsg = (OTROutgoingMessage *)message;
                    systemMsg.systemUpdate = YES;
                    systemMsg.dateSent = [NSDate date];
                    systemMsg.readDate = [NSDate date];
                    systemMsg.originalText = call.systemMessage;
                    [systemMsg saveWithTransaction:transaction];
                } else if ([message isKindOfClass:[OTRXMPPRoomMessage class]]){
                    OTRXMPPRoomMessage *systemMsg = (OTRXMPPRoomMessage *)message;
                    systemMsg.state = RoomMessageStateSent;
                    systemMsg.systemUpdate = YES;
                    systemMsg.originalText = call.systemMessage;
                    [systemMsg saveWithTransaction:transaction];
                }
                [thread saveWithTransaction:transaction];
            }
        }];
    }
}

- (void)addSystemMessage:(NSString *)message withCallerJID:(NSString *)callerjid  withUser:(NSString *)username{
    if (message == nil) {
        return;
    }
    
    __block OTRBuddy *buddy = nil;
    __block OTRAccount *account = [self getFirstAccount];
    if (account == nil) {
        return;
    }
    
    [OTRDatabaseManager.shared.readConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        XMPPJID *jid = [XMPPJID jidWithString:callerjid];
        
        if (jid != nil) {
            buddy = [OTRXMPPBuddy fetchBuddyWithJid:jid accountUniqueId:account.uniqueId transaction:transaction];
        }
        
        NSString *str = [NSString stringWithFormat: @"%@ from %@", message, username];
        [[UIApplication sharedApplication] showLocalNotificationWithIdentifier:nil body:str badge:0 userInfo:nil recurring:NO];
    }];
    
    if (!buddy) {
        return;
    }
    
    [OTRDatabaseManager.shared.writeConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        id<OTRMessageProtocol> messageprot = [buddy outgoingMessageWithText:message transaction:transaction];
            
        OTROutgoingMessage *systemMsg = (OTROutgoingMessage *)messageprot;
        systemMsg.messageSecurity = OTRMessageTransportSecurityPlaintext;
        systemMsg.systemUpdate = YES;
        systemMsg.dateSent = [NSDate date];
        systemMsg.readDate = [NSDate date];
        systemMsg.originalText = message;
        buddy.lastMessageIdentifier = systemMsg.messageKey;
        [systemMsg saveWithTransaction:transaction];
        [buddy saveWithTransaction:transaction];
    }];
}


- (void) openCallController:(NSString *)nameTitle {
    OTRAppDelegate *appDelegate = (OTRAppDelegate *)[UIApplication sharedApplication].delegate;
    if (appDelegate.callWindow == nil) {
        appDelegate.callWindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    }
    
    if (appDelegate.callWindow.rootViewController == nil) {
        CGSize screenSize = [[UIScreen mainScreen] bounds].size;
        appDelegate.callWindow.frame = CGRectMake(0, 0, screenSize.width, screenSize.height);
        
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"PhoneCall" bundle:[GlacierInfo resourcesBundle]];
        PhoneCallViewController *callVC = (PhoneCallViewController *)[storyboard instantiateViewControllerWithIdentifier:@"PhoneCallVC"];
        [_currentmgr.callManager setTwilioDelegate:callVC];
        [callVC setCallManager:_currentmgr.callManager];
        [callVC setNameTitle:nameTitle];
        [callVC setModalPresentationStyle:UIModalPresentationOverCurrentContext];
        
        appDelegate.callWindow.rootViewController = [[UIViewController alloc] init];
        [appDelegate.callWindow makeKeyAndVisible];
        
        [appDelegate.callWindow.rootViewController presentViewController:callVC animated:true completion:nil];
    }
    [appDelegate.messagesViewController enablePhoneButton:NO];
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

#pragma - mark GestureRecognizerDelegate methods
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void) setupLongAndTapPress {
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
    longPressGesture.minimumPressDuration = 1.0; // 1 second press
    longPressGesture.delegate = self;
    longPressGesture.cancelsTouchesInView = false;
    [self.tableView addGestureRecognizer:longPressGesture];
    
    UITapGestureRecognizer *singlePressGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapPress:)];
    singlePressGesture.delegate = self;
    singlePressGesture.cancelsTouchesInView = false;
    [singlePressGesture requireGestureRecognizerToFail:longPressGesture];
    [self.tableView addGestureRecognizer:singlePressGesture];
}

- (void) tapPress:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        CGPoint touchPoint = [gestureRecognizer locationInView: self.tableView];
        NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:touchPoint];
        if (indexPath != nil) {
            [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
        }
    }
}

- (void) longPress:(UILongPressGestureRecognizer *)longPressGestureRecognizer {
    
    if (longPressGestureRecognizer.state == UIGestureRecognizerStateBegan) {
        CGPoint touchPoint = [longPressGestureRecognizer locationInView: self.tableView];
        NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:touchPoint];
        if (indexPath != nil) {
            UIMenuController *menu = [UIMenuController sharedMenuController];
            UIMenuItem *markAllRead = [[UIMenuItem alloc] initWithTitle:@"Mark All Read" action:@selector(markAllRead:)];
            [menu setMenuItems:@[markAllRead]];
            
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            [cell becomeFirstResponder];
            [menu setTargetRect:[self.tableView rectForRowAtIndexPath:indexPath] inView:self.tableView];
            
            [menu update];
            [menu setMenuVisible:YES animated:YES];
        }
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

-(BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    return (action == @selector(markAllRead:));
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    // required
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

- (void)mappingsUpdated
{
    [self.tableView reloadData];
}

- (void)didReceiveChanges:(OTRYapViewHandler *)handler sectionChanges:(NSArray<YapDatabaseViewSectionChange *> *)sectionChanges rowChanges:(NSArray<YapDatabaseViewRowChange *> *)rowChanges
{
    if ([rowChanges count] == 0 && sectionChanges == 0) {
        return;
    }
    
    if (self.showSkeleton || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) {  
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

- (UIImage *)imageForEmptyDataSet:(UIScrollView *)scrollView
{
    return [UIImage imageNamed:@"glacier" inBundle:[GlacierInfo resourcesBundle] compatibleWithTraitCollection:nil];
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
    [AWSAccountManager.shared removeLocalVPNFiles]; 
}

@end
