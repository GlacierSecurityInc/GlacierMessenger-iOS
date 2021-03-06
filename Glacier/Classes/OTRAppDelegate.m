//
//  OTRAppDelegate.m
//  Off the Record
//
//  Created by Chris Ballinger on 8/11/11.
//  Copyright (c) 2011 Chris Ballinger. All rights reserved.
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

#import "OTRAppDelegate.h"

#import "OTRConversationViewController.h"

#import "OTRMessagesHoldTalkViewController.h"
#import "OTRSettingsViewController.h"
#import "OTRSettingsManager.h"

#import "OTRConstants.h"

#import "OTRUtilities.h"
#import "OTRAccountsManager.h"
#import "OTRDatabaseManager.h"
@import SAMKeychain;

#import "OTRLog.h"
@import CocoaLumberjack;
#import "OTRAccount.h"
#import "OTRXMPPAccount.h"
#import "OTRBuddy.h"
@import YapDatabase;

#import "OTRCertificatePinning.h"
#import "NSURL+ChatSecure.h"
#import "OTRDatabaseUnlockViewController.h"
#import "OTRIncomingMessage.h"
#import "OTROutgoingMessage.h"
#import "OTRPasswordGenerator.h"
#import "UIViewController+ChatSecure.h"
@import XMPPFramework;
#import "OTRProtocolManager.h"
#import "Glacier-Swift.h"
#import "OTRMessagesViewController.h"
#import "NetworkTester.h"
#import "UITableView+ChatSecure.h"
@import OTRKit;
#import "OTRPushTLVHandlerProtocols.h"
@import UserNotifications;

@interface OTRAppDelegate ()

@property (nonatomic, strong) OTRSplitViewControllerDelegateObject *splitViewControllerDelegate;

// test to see if we can get to server before attempting login
@property (nonatomic, strong) NetworkTester *networkTester;
@property (assign, nonatomic) BOOL enteringForeground;
@property (nonatomic, readwrite) OTRNetworkConnectionStatus networkStatus;

@property (assign, nonatomic) BOOL bypass;
@property (assign, nonatomic) BOOL resortPauseDone;
@property (assign, nonatomic) BOOL newMessages;
@property (nonatomic, strong, readwrite) NSDate *lastOnline;

@property (nonatomic, strong) PKPushRegistry *voipRegistry;

@end

@implementation OTRAppDelegate
@synthesize window = _window;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [LogManager.shared setupLogging];
    
    //[self setupCrashReporting];

    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly];
    
    // Tell the NSKeyedUnarchiver that the class has been renamed
    [NSKeyedUnarchiver setClass:[OTRGroupDownloadMessage class] forClassName:@"ChatSecureCore.OTRGroupDownloadMessage"];
    [NSKeyedUnarchiver setClass:[OTRXMPPRoomMessage class] forClassName:@"ChatSecureCore.OTRXMPPRoomMessage"]; 
    [NSKeyedUnarchiver setClass:[OTRXMPPRoomOccupant class] forClassName:@"ChatSecureCore.OTRXMPPRoomOccupant"];
    
    UIViewController *rootViewController = nil;
    
    // Create 3 primary view controllers, settings, conversation list and messages
    _conversationViewController = [GlobalTheme.shared conversationViewController];
    _messagesViewController = [GlobalTheme.shared messagesViewController];
    
        ////// Normal launch to conversationViewController //////
        if (![OTRDatabaseManager existsSharedYapDatabase] && ![OTRDatabaseManager existsYapDatabase]) {
            /**
             First Launch
             Create password and save to keychain
             **/
            NSString *newPassword = [OTRPasswordGenerator passwordWithLength:OTRDefaultPasswordLength];
            NSError *error = nil;
            [[OTRDatabaseManager sharedInstance] setDatabasePassphrase:newPassword remember:YES error:&error];
            if (error) {
                DDLogError(@"Password Error: %@",error);
            }
            
            NSData *newSalt = [OTRPasswordGenerator randomDataWithLength:16];
            NSError *error2 = nil;
            [[OTRDatabaseManager sharedInstance] setDatabaseSalt:newSalt error:&error2];
            if (error2) {
                DDLogError(@"Salt Error: %@",error2);
            }
            
            NSData *newMediaSalt = [OTRPasswordGenerator randomDataWithLength:16];
            NSError *error3 = nil;
            [[OTRDatabaseManager sharedInstance] setMediaDatabaseSalt:newMediaSalt error:&error3];
            if (error3) {
                DDLogError(@"Salt Error: %@",error3);
            }
        }

        [[OTRDatabaseManager sharedInstance] setupDatabaseWithName:GlacierYapDatabaseName];
        rootViewController = [self setupDefaultSplitViewControllerWithLeadingViewController:[[UINavigationController alloc] initWithRootViewController:self.conversationViewController]];
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = rootViewController;
    
    [self.window makeKeyAndVisible];
    
    self.doubleDone = NO; // handle double notifications on login
    self.bypass = YES;
    
    self.resortPauseDone = NO;
    self.newMessages = NO;
    self.resortNeeded = NO;
    [[OTRDatabaseManager sharedInstance] setCanSortDataView:YES];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkConnectionStatusChange:) name:NetworkStatusNotificationName object:nil];
    self.enteringForeground = YES;
    self.networkTester = [[NetworkTester alloc] init];
    
    [self setDomainIfAvailable];
    [self checkConnectionOrTryLogin];
        
    // For disabling screen dimming while plugged in
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(batteryStateDidChange:) name:UIDeviceBatteryStateDidChangeNotification object:nil];
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    [self batteryStateDidChange:nil];
    
    [UNUserNotificationCenter currentNotificationCenter].delegate = self;
    
    [self registerVoIPNotifications];
    
    return YES;
}

- (void) registerVoIPNotifications {
    self.voipRegistry = [[PKPushRegistry alloc] initWithQueue:nil];
    self.voipRegistry.delegate = self;
    self.voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
    
    NSData *pushData = [self.voipRegistry pushTokenForType:PKPushTypeVoIP];
    if (pushData != nil) {
        [self handleVoipPushToken:pushData];
    }
}

/**
 * This creates a UISplitViewController using a leading view controller (the left view controller). It uses a navigation controller with
 * self.messagesViewController as teh right view controller;
 * This also creates and sets up teh OTRSplitViewCoordinator
 *
 * @param leadingViewController The leading or left most view controller in a UISplitViewController. Should most likely be some sort of UINavigationViewController
 * @return The base default UISplitViewController
 *
 */
- (UIViewController *)setupDefaultSplitViewControllerWithLeadingViewController:(nonnull UIViewController *)leadingViewController
{
    
    YapDatabaseConnection *connection = [OTRDatabaseManager sharedInstance].writeConnection;
    _splitViewCoordinator = [[OTRSplitViewCoordinator alloc] initWithDatabaseConnection:connection];
    self.splitViewControllerDelegate = [[OTRSplitViewControllerDelegateObject alloc] init];
    self.conversationViewController.delegate = self.splitViewCoordinator;
    
    //MessagesViewController Nav
    UINavigationController *messagesNavigationController = [[UINavigationController alloc ]initWithRootViewController:self.messagesViewController];
    
    //SplitViewController
    UISplitViewController *splitViewController = [[UISplitViewController alloc] init];
    splitViewController.viewControllers = @[leadingViewController,messagesNavigationController];
    splitViewController.delegate = self.splitViewControllerDelegate;
    splitViewController.title = CHAT_STRING();
    splitViewController.presentsWithGesture = NO;
    splitViewController.displayModeButtonItem.enabled = NO;
    
    // for preferred iPad views
    //splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModePrimaryOverlay;
    splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
    
    //setup 'back' button in nav bar
    messagesNavigationController.topViewController.navigationItem.leftBarButtonItem = splitViewController.displayModeButtonItem;
    messagesNavigationController.topViewController.navigationItem.leftItemsSupplementBackButton = YES;
    
    self.splitViewCoordinator.splitViewController = splitViewController;
    
    return splitViewController;
}

- (void)showConversationViewController
{
    self.window.rootViewController = [self setupDefaultSplitViewControllerWithLeadingViewController:[[UINavigationController alloc] initWithRootViewController:self.conversationViewController]];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    [OTRAppDelegate setLastInteractionDate:NSDate.date];
    
    /*
     Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
     Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
     */
    
    // for Splash/Privacy page
    if ([self.networkTester hasAddress]) {
        self.splitViewCoordinator.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeSecondaryOnly;
    
        // creates a "privacy" screen, showing splash screen when backgrounded
        UIView *splashUiView = [[[NSBundle mainBundle] loadNibNamed:@"LaunchMsgr" owner:self options:nil] objectAtIndex:0];
        splashUiView.frame = [[UIScreen mainScreen] bounds];
    
        splashUiView.tag = 12345;
        [self.window addSubview:splashUiView];
        [self.window bringSubviewToFront:splashUiView];
    
        // fade in the view
        [UIView animateWithDuration:0.5 animations:^{
            splashUiView.alpha = 1;
        }];
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    DDLogInfo(@"Application entered background state.");
    
    [self.networkTester reset];
    self.enteringForeground = NO;
    self.doubleDone = NO;
    
    self.resortPauseDone = NO;
    self.newMessages = NO;
    self.resortNeeded = NO; 
    [[OTRDatabaseManager sharedInstance] setCanSortDataView:NO];
    
    __block NSUInteger unread = 0;
    [[OTRDatabaseManager sharedInstance].readConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
        unread = [transaction numberOfUnreadMessages];
    } completionBlock:^{
        application.applicationIconBadgeNumber = unread;
    }];
    
    // logout when backgrounded. Push notifications should then occur with messages
    [[OTRProtocolManager sharedInstance] disconnectAllAccounts];
}

// allows us to check if network is available
- (void)setDomain:(NSString *)address {
    if (self.networkTester) {
        [self.networkTester setAddress:address];
    }
}

- (void)bypassNetworkCheck:(BOOL)bypass {
    self.bypass = bypass;
}

- (BOOL) tryOpenURL:(NSURL*)url {
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            return YES;
        }
    return NO;
}

- (void) networkConnectionStatusChange:(NSNotification*)notification {
    _networkStatus = [notification.userInfo[NewNetworkStatusKey] integerValue];
    if (_networkStatus == OTRNetworkConnectionStatusConnecting || _networkStatus == OTRNetworkConnectionStatusUnknown || _networkStatus == OTRNetworkConnectionStatusDisconnected) {
        return;
    }
    
    if (self.enteringForeground || [UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
        [self autoLoginFromBackground:NO];
    }
}

- (OTRNetworkConnectionStatus) getCurrentNetworkStatus {
    return _networkStatus;
}


/** Doesn't stop autoLogin if previous crash when it's a background launch */
- (void)autoLoginFromBackground:(BOOL)fromBackground
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *autoaccts = [OTRAccountsManager allAutoLoginAccounts];
        if (autoaccts && autoaccts.count > 0) {
            [[OTRProtocolManager sharedInstance] loginAccounts:autoaccts];
            [PushController registerForPushNotifications];
        } else if ([self.networkTester hasAddress]){
            [_conversationViewController tryGlacierGroupAccount];
        }
    });
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    self.splitViewCoordinator.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
    
    self.enteringForeground = YES;
    
    [self checkConnectionOrTryLogin];
}

// call just before checkConnectionOrTryLogin
- (void) setDomainIfAvailable {
    NSArray *accounts = [OTRAccountsManager allAutoLoginAccounts];
    [accounts enumerateObjectsUsingBlock:^(OTRAccount * account, NSUInteger idx, BOOL *stop) {
        if([account isKindOfClass:[OTRXMPPAccount class]]) {
            OTRXMPPAccount *xact = (OTRXMPPAccount *)account;
            [self setDomain:xact.domain];
            [self bypassNetworkCheck:xact.bypassNetworkCheck];
        }
    }];
}

// if there is a domain address, see if we can reach the server before attempting login
- (void) checkConnectionOrTryLogin {
    if ([self.networkTester hasAddress] && !_bypass) {
        [self.networkTester tryConnectToNetwork];
    } else {
        [self.networkTester changeNetworkStatus:OTRNetworkConnectionStatusConnected];
        [self autoLoginFromBackground:NO];
    }
}

// remove the privacy screen
- (void) removeSplashView {
    UIView *splashView = [self.window viewWithTag:12345];
    if (splashView == nil) {
        self.splitViewCoordinator.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
        return;
    }
    
    // fade away splash view from main view
    [UIView animateWithDuration:0.3 animations:^{
        splashView.alpha = 0;
    } completion:^(BOOL finished) {
        // remove when finished fading
        [splashView removeFromSuperview];
        
        // in case there are somehow more than one
        [self removeSplashView];
        self.splitViewCoordinator.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
    }];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // remove the privacy screen
    [self removeSplashView];
    
    [OTRAppDelegate setLastInteractionDate:NSDate.date];
    [self batteryStateDidChange:nil];
    DDLogInfo(@"Application became active");
    
    [UIApplication.sharedApplication removeExtraForegroundNotifications];
    
    self.doubleDone = NO;
    self.enteringForeground = NO;
    
    // allow app to login and receive existing messages before in-app notifications start
    [self performSelector:@selector(handleDoubleNotification:) withObject:nil afterDelay:15.0];
}

- (void) handleResortNeeded:(id)sender
{
    self.resortPauseDone = YES;
    if (self.newMessages) {
        self.newMessages = NO;
        self.resortPauseDone = NO;
        [self performSelector:@selector(handleResortNeeded:) withObject:nil afterDelay:0.5];
    } else {
        if (self.resortNeeded) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                self.resortNeeded = NO;
                [[OTRDatabaseManager sharedInstance] resortDataView];
                [[OTRDatabaseManager sharedInstance] setCanSortDataView:YES];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.conversationViewController setShowSkeleton:NO];
                });
            });
        } else {
            [[OTRDatabaseManager sharedInstance] setCanSortDataView:YES];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.conversationViewController setShowSkeleton:NO];
            });
        }
    }
}

- (void) setResortIfNeeded {
    if (!self.resortPauseDone && [self.conversationViewController otr_isVisible]) {
        
        //add other checks here?
        // is message from same as already is at the top of the list?
        if (!self.resortNeeded) {
            [[OTRDatabaseManager sharedInstance] setCanSortDataView:NO];
            self.resortNeeded = YES;
        }
        self.newMessages = YES;
    }
}

- (void) setResortHandler {
    BOOL doPause = NO;
    if (self.lastOnline) {
        NSTimeInterval span = [[NSDate date] timeIntervalSinceDate:self.lastOnline];
        NSTimeInterval sixHours = 60 * 60 * 6;
        if (span > sixHours) {
            doPause = YES;
        }
    }
    
    if (doPause && [UIApplication sharedApplication].applicationIconBadgeNumber >= 1) {
        self.resortPauseDone = NO;
        [self performSelector:@selector(handleResortNeeded:) withObject:nil afterDelay:2.5];
    } else {
        [self performSelector:@selector(handleResortNeeded:) withObject:nil];
    }
    self.lastOnline = [NSDate date];
}

- (void) handleDoubleNotification:(id)sender
{
    self.doubleDone = YES;
}

- (void) resetDoubleNotificationHandlerIfNeeded {
    self.doubleDone = NO;
    [self performSelector:@selector(handleDoubleNotification:) withObject:nil afterDelay:15.0];
}


- (void)applicationWillTerminate:(UIApplication *)application
{
    /*
     Called when the application is about to terminate.
     Save data if appropriate.
     See also applicationDidEnterBackground:.
     */
    
    
    [[OTRProtocolManager sharedInstance] disconnectAllAccounts];
}

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void(^)(NSArray * __nullable restorableObjects))restorationHandler {
    if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
        NSURL *url = userActivity.webpageURL;
        if ([url otr_isInviteLink]) {
            __block XMPPJID *jid = nil;
            __block NSString *fingerprint = nil;
            NSString *otr = [OTRAccount fingerprintStringTypeForFingerprintType:OTRFingerprintTypeOTR];
            [url otr_decodeShareLink:^(XMPPJID * _Nullable inJid, NSArray<NSURLQueryItem*> * _Nullable queryItems) {
                jid = inJid;
                [queryItems enumerateObjectsUsingBlock:^(NSURLQueryItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    if ([obj.name isEqualToString:otr]) {
                        fingerprint = obj.value;
                        *stop = YES;
                    }
                }];
            }];
            if (jid) {
                [OTRProtocolManager handleInviteForJID:jid otrFingerprint:fingerprint buddyAddedCallback:nil];
            }
            return YES;
        }
    } else if ([userActivity.activityType isEqualToString:@"INStartVideoCallIntent"] || [userActivity.activityType isEqualToString:@"INStartCallIntent"]) {
        [[CallManager sharedCallManager] performVideoAction];
    }
    return NO;
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    if ([url.scheme isEqualToString:@"xmpp"]) {
        XMPPURI *xmppURI = [[XMPPURI alloc] initWithURL:url];
        XMPPJID *jid = xmppURI.jid;
        NSString *otrFingerprint = xmppURI.queryParameters[@"otr-fingerprint"];
        if (jid) {
            [OTRProtocolManager handleInviteForJID:jid otrFingerprint:otrFingerprint buddyAddedCallback:^ (OTRBuddy *buddy) {
                OTRXMPPBuddy *xmppBuddy = (OTRXMPPBuddy *)buddy;
                if (xmppBuddy != nil) {
                    [self enterThreadWithKey:xmppBuddy.threadIdentifier collection:xmppBuddy.threadCollection];
                }
            }];
            return YES;
        }
    }
    // I think we only want this if no user exists or under certain conditions
    // maybe check what is in options?
    return [[AWSCognitoAuth defaultCognitoAuth] application:app openURL:url options:options];
}

- (void) showSubscriptionRequestForBuddy:(NSDictionary*)userInfo {
    // This is probably in response to a user requesting subscriptions from us
    [self.splitViewCoordinator showConversationsViewController];
}

- (void)application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OTRUserNotificationsChanged object:self userInfo:@{@"settings": notificationSettings}];
    if (notificationSettings.types == UIUserNotificationTypeNone) {
        NSLog(@"Push notifications disabled by user.");
    } else {
        [application registerForRemoteNotifications];
    }
}

- (void)application:(UIApplication *)app didRegisterForRemoteNotificationsWithDeviceToken:(nonnull NSData *)deviceToken
{
    [OTRProtocolManager.pushController setPushToken:[deviceToken hexString]];
}

- (void)application:(UIApplication *)app didFailToRegisterForRemoteNotificationsWithError:(NSError *)err {
    DDLogError(@"Error in registration. Error: %@%@", [err localizedDescription], [err userInfo]);
}

// To improve usability, keep the app open when you're plugged in
- (void) batteryStateDidChange:(NSNotification*)notification {
    UIDeviceBatteryState currentState = [[UIDevice currentDevice] batteryState];
    if (currentState == UIDeviceBatteryStateCharging || currentState == UIDeviceBatteryStateFull) {
        [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    } else {
        [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    }
}

#pragma - mark Class Methods
+ (instancetype)appDelegate
{
    return (OTRAppDelegate*)[[UIApplication sharedApplication] delegate];
}

#pragma mark - Theming

- (void) setupTheme { }

@end
