//
//  OTRConversationViewController.h
//  Off the Record
//
//  Created by David Chiles on 3/2/14.
//  Copyright (c) 2014 Chris Ballinger. All rights reserved.
//

@import UIKit;
#import "OTRThreadOwner.h"

@class OTRBuddy;
@class OTRConversationViewController;
@class OTRXMPPAccount;
@class TwilioCall;

@protocol OTRConversationViewControllerDelegate <NSObject>

- (void)conversationViewController:(OTRConversationViewController *)conversationViewController didSelectThread:(id <OTRThreadOwner>)threadOwner;
- (void)conversationViewController:(OTRConversationViewController *)conversationViewController didSelectCompose:(id)sender;

- (void)conversationViewController:(OTRConversationViewController *)conversationViewController didSelectDialpad:(id)sender;

@end

/**
 The puropose of this class is to list all curent conversations (with single buddy or group chats) in a list view.
 When the user selects a conversation to enter the delegate method fires.
 */
@interface OTRConversationViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate> 

@property (nonatomic, weak) id <OTRConversationViewControllerDelegate> delegate;

@property (nonatomic, strong) UITableView *tableView;

- (void) connectionStateDidChange:(NSNotification *)notification;

// these should maybe be moved to a different class that handles accounts from an external source
- (BOOL) tryGlacierGroupAccount;
- (void) lookForAccountInfoIfNeeded;
- (void) resetAfterLogout:(OTRXMPPAccount *)account;
- (void) setWelcomeController:(BOOL)closeable;
- (void) resetStatusTimer;

- (void) setShowSkeleton:(BOOL)shouldShowSkeleton;

- (void) connectPhoneCall:(nonnull TwilioCall *)call;
- (void) openCallController:(nullable NSString *)nameTitle;
- (void) addSystemMessage:(nonnull NSString *)message withCallerJID:(nonnull NSString *)callerjid withUser:(nonnull NSString *)username; 

@end
