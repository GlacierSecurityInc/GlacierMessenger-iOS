//
//  VPNManager.h
//  Copyright © 2019 Glacier Security. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@interface VPNManager : NSObject

- (void) handleIpsecProfile:(NSURL *)profile;
- (BOOL) vpnIsEnabled;
- (BOOL) vpnIsDisabled;
- (BOOL) vpnIsActive;
- (BOOL) isOnTrustedNetwork;
- (void) noVpnAvailable;
- (void) noAccessAvailable;
- (void) turnOnVpn;
- (void) turnOffVpn;
- (void) turnOnWifi;
- (void) turnOffWifi;
- (void) turnOnCellular;
- (void) turnOffCellular;
- (void) addSSID:(NSString *)ssid;
- (void) removeSSID:(NSString *)ssid;
- (void) removeSSIDs;
- (void) setVPNView:(UIViewController *)viewController;

+ (instancetype)sharedInstance;
@property (class, nonatomic, readonly) VPNManager *shared;

@end
NS_ASSUME_NONNULL_END
