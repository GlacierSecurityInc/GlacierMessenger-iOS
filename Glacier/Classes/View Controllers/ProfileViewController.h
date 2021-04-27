//
//  ProfileViewController.h
//  Glacier
//
//  Created by Andy Friedman on 11/5/20.
//  Copyright © 2020 Glacier. All rights reserved.
//
@import UIKit;
@import BButton;
#import "ProfileManager.h"

NS_ASSUME_NONNULL_BEGIN
@interface ProfileViewController : UIViewController

/** This property can be replaced with a custom subclass before displaying the view */
@property (nonatomic, strong) ProfileManager *profileManager;

- (void)changeDisplayName:(id)sender withNewName:(NSString *)newname;
- (void)clearDevicesButtonPressed;
- (void)resetSecureConnectionsButtonPressed; 

@end
NS_ASSUME_NONNULL_END
