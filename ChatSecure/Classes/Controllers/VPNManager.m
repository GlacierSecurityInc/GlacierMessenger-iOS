//
//  VPNManager.m
//  Copyright © 2019 Glacier Security. All rights reserved.
//

#import "OTRLog.h"

#import <ChatSecureCore/ChatSecureCore-Swift.h>
#import <NetworkExtension/NEVPNManager.h>
#import <SystemConfiguration/CaptiveNetwork.h>

@import SAMKeychain;


@interface VPNManager ()
@property (nonatomic, strong) UIAlertController *vpnalert;
@property (nonatomic, strong) CoreConnectionViewController *vpnView;
@property (nonatomic, strong) NEVPNManager *manager;
//@property (assign, nonatomic) NEVPNStatus lastStatus;
@property (assign, nonatomic) BOOL turningOff;
@property (assign, nonatomic) BOOL turningOn;
@end

@implementation VPNManager

- (instancetype)init
{
    self.manager = [NEVPNManager sharedManager];
    [self.manager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
        if(error) {
            DDLogInfo(@"IPSEC loadFromPreferencesWithCompletionHandler error: %@", error.localizedDescription);
            return;
        }
    }];
    self.turningOn = NO;
    self.turningOff = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(vpnConnectionStatusChanged:) name:NEVPNStatusDidChangeNotification object:nil];
        
    return self;
}

- (void) setVPNView:(UIViewController *)viewController  {
    if ([viewController isKindOfClass:CoreConnectionViewController.class]) {
        self.vpnView = (CoreConnectionViewController *)viewController;
    }
}

- (void) handleIpsecProfile:(NSURL *)profile {
    // read file
    if (!profile) {
        return;
    }
    
    NSDictionary *ipdict = [NSDictionary dictionaryWithContentsOfURL:profile];
    
    //NEVPNManager *manager = [NEVPNManager sharedManager];
    //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(vpnConnectionStatusChanged:) name:NEVPNStatusDidChangeNotification object:nil];
    
    NEVPNProtocolIKEv2 *protocol = [[NEVPNProtocolIKEv2 alloc] init];
    //protocol.authenticationMethod = NEVPNIKEAuthenticationMethodCertificate;
    protocol.authenticationMethod = NEVPNIKEAuthenticationMethodNone;
    
    protocol.childSecurityAssociationParameters.diffieHellmanGroup = NEVPNIKEv2DiffieHellmanGroup14;
    protocol.childSecurityAssociationParameters.encryptionAlgorithm = NEVPNIKEv2EncryptionAlgorithmAES256;
    protocol.childSecurityAssociationParameters.integrityAlgorithm = NEVPNIKEv2IntegrityAlgorithmSHA256;
    protocol.childSecurityAssociationParameters.lifetimeMinutes = 1440;
    
    protocol.deadPeerDetectionRate = NEVPNIKEv2DeadPeerDetectionRateMedium;
    protocol.disableMOBIKE = NO;
    protocol.disableRedirect = NO;
    protocol.enableRevocationCheck = NO;
    protocol.enablePFS = NO;
    
    protocol.IKESecurityAssociationParameters.diffieHellmanGroup = NEVPNIKEv2DiffieHellmanGroup14;
    protocol.IKESecurityAssociationParameters.encryptionAlgorithm = NEVPNIKEv2EncryptionAlgorithmAES256;
    protocol.IKESecurityAssociationParameters.integrityAlgorithm = NEVPNIKEv2IntegrityAlgorithmSHA256;
    protocol.IKESecurityAssociationParameters.lifetimeMinutes = 1440;
    
    //protocol.NEVPNProtocolIKEv2.PayloadDisplayName = [pcontent valueForKeyPath:@"IKEv2.PayloadDisplayName"];
    
    NSArray *parray = [ipdict objectForKey:@"PayloadContent"];
    NSDictionary *pcontent = parray[0];
    //NSDictionary *pcontent2 = parray[1];
    NSDictionary *ikev2 = [pcontent objectForKey:@"IKEv2"];
    
    self.manager.onDemandEnabled = YES;
    if ([[pcontent valueForKey:@"IKEv2.OnDemandEnabled"] intValue] == 0) {
        self.manager.onDemandEnabled = NO;
    }
    
    NSMutableArray *rules = [[NSMutableArray alloc] init];
    NSArray *ondemand = [ikev2 objectForKey:@"OnDemandRules"];
    for (NSDictionary *rule in ondemand) {
        //Action, InterfaceTypeMatch, SSIDMatch, URLStringProbe
        NSString *action = [rule objectForKey:@"Action"];
        NSString *interface = [rule objectForKey:@"InterfaceTypeMatch"];
        NSString *urlprobe = [rule objectForKey:@"URLStringProbe"];
        NSArray *ssidmatch = [rule objectForKey:@"SSIDMatch"];
        if ([action isEqualToString:@"Connect"]) {
            NEOnDemandRuleConnect *connectRule = [NEOnDemandRuleConnect new];
            if (interface) {
                if ([interface isEqualToString:@"WiFi"]) {
                    connectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceTypeWiFi;
                    if (ssidmatch) {
                        NSMutableArray *matchAr = [[NSMutableArray alloc] initWithCapacity:[ssidmatch count]];
                        for (NSString *match in ssidmatch) {
                            [matchAr addObject: match];
                        }
                        connectRule.SSIDMatch = matchAr;
                    }
                } else if ([interface isEqualToString:@"Cellular"]) {
                    connectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceTypeCellular;
                } else if ([interface isEqualToString:@"Any"]) {
                    connectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceTypeAny;
                }
            }
            if (urlprobe) {
                connectRule.probeURL = [NSURL URLWithString:urlprobe];
            }
            [rules addObject:connectRule];
        } else if ([action isEqualToString:@"Disconnect"]) {
            NEOnDemandRuleDisconnect *disconnectRule = [NEOnDemandRuleDisconnect new];
            if (interface) {
                if ([interface isEqualToString:@"WiFi"]) {
                    disconnectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceTypeWiFi;
                    if (ssidmatch) {
                        NSMutableArray *matchAr = [[NSMutableArray alloc] initWithCapacity:[ssidmatch count]];
                        for (NSString *match in ssidmatch) {
                            [matchAr addObject: match];
                        }
                        disconnectRule.SSIDMatch = matchAr;
                    }
                } else if ([interface isEqualToString:@"Cellular"]) {
                    disconnectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceTypeCellular;
                } else if ([interface isEqualToString:@"Any"]) {
                    disconnectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceTypeAny;
                }
            }
            if (urlprobe) {
                disconnectRule.probeURL = [NSURL URLWithString:urlprobe];
            }
            [rules addObject:disconnectRule];
        }
    }
    
    protocol.username = [pcontent valueForKeyPath:@"IKEv2.AuthName"];
    
    NSString* pword = [pcontent valueForKeyPath:@"IKEv2.AuthPassword"];
    protocol.passwordReference = [self persistentReferenceForSavedPassword:pword service:kGlacierGroup account:kGlacierVpn];
    //protocol.NEVPNProtocolIKEv2.PayloadDisplayName = [pcontent valueForKeyPath:@"IKEv2.PayloadDisplayName"];
    
    protocol.localIdentifier = [pcontent valueForKeyPath:@"IKEv2.LocalIdentifier"];
    //protocol.certificateType = NEVPNIKEv2CertificateTypeECDSA384;
    //protocol.serverCertificateIssuerCommonName = @"Let's Encrypt Authority X3"; //[pcontent valueForKeyPath:@"IKEv2.ServerCertificateIssuerCommonName"];
    protocol.serverAddress = [pcontent valueForKeyPath:@"IKEv2.RemoteAddress"];//@"algo41.ceares.net";
    protocol.remoteIdentifier = [pcontent valueForKeyPath:@"IKEv2.RemoteIdentifier"];//@"algo41.ceares.net";
    protocol.useConfigurationAttributeInternalIPSubnet = NO;
    
    protocol.proxySettings.HTTPEnabled = NO;
    protocol.proxySettings.HTTPSEnabled = NO;

    //protocol.identityDataPassword = [pcontent2 valueForKey:@"Password"];
    //protocol.identityReference = [pcontent2 valueForKeyPath:@"PayloadCertificateFileName"];
    
    //NSData *straightData = [pcontent2 valueForKey:@"PayloadContent"];
    //DDLogInfo(@"Uhhhhhh: %@", straightData); // foo
    //protocol.identityData = straightData;
    
    //test store data first
    //NSData *certData = error.userInfo[OTRXMPPSSLCertificateDataKey];
    //NSString *hostname = error.userInfo[OTRXMPPSSLHostnameKey];
    //[OTRCertificatePinning addCertificateData:protocol.identityData withHostName:protocol.serverCertificateIssuerCommonName];
    
    protocol.useExtendedAuthentication = YES;
    protocol.disconnectOnSleep = NO;
    
    DDLogInfo(@"Connection desciption: %@", self.manager.localizedDescription);
    DDLogInfo(@"IPSEC VPN status:  %li", (long)self.manager.connection.status);

    [self.manager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
        if(error) {
            DDLogInfo(@"IPSEC loadFromPreferencesWithCompletionHandler error: %@", error.localizedDescription);
            return;
        }
        //self.manager.onDemandEnabled = YES;
        [self.manager setOnDemandRules:rules];
        self.manager.protocolConfiguration = protocol;
        [self.manager setLocalizedDescription:@"Glacier VPN"];
        
        [self turnOffNetworkBypassInAccount];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[OTRAppDelegate appDelegate] bypassNetworkCheck:NO];
            [self turnOnVpn];
        });
    }];
}

- (void) turnOffNetworkBypassInAccount {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block OTRAccount *account = nil;
        [OTRDatabaseManager.shared.readConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            NSArray<OTRAccount*> *accounts = [OTRAccount allAccountsWithTransaction:transaction];
            if (accounts) {
                account = accounts.firstObject;
            }
        }];
        
        if (account) {
            OTRXMPPManager *xmppManager = (OTRXMPPManager *)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
            [xmppManager updateNetworkCheckBypass:NO];
        }
    });
}

- (void) addSSID:(NSString *)ssid {
    [self turnOffVpn];
    
    // pause three seconds or use completion handler
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        NSArray *currules = self.manager.onDemandRules;
        BOOL foundDisconnect = NO;
        NSMutableArray *newrules = [[NSMutableArray alloc] initWithCapacity:currules.count];
        for (NEOnDemandRule *rule in currules) {
            if ([rule isKindOfClass:[NEOnDemandRuleDisconnect class]] && rule.SSIDMatch != nil) {
                NSArray *ssidstuff = rule.SSIDMatch;
                NSMutableArray *newmatch = [[NSMutableArray alloc] initWithCapacity:ssidstuff.count+1];
                for (NSString *match in ssidstuff) {
                    [newmatch addObject:match];
                }
                [newmatch addObject:ssid];
                foundDisconnect = YES;
                rule.SSIDMatch = newmatch;
            }
            [newrules addObject:rule];
        }
        
        if (!foundDisconnect) {
            //create and insert
            NEOnDemandRuleDisconnect *disconnectRule = [NEOnDemandRuleDisconnect new];
            disconnectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceTypeWiFi;
            NSMutableArray *matchAr = [[NSMutableArray alloc] initWithCapacity:1];
            [matchAr addObject: ssid];
            disconnectRule.SSIDMatch = matchAr;
            [newrules insertObject:disconnectRule atIndex:0];
        }
        
        [self.manager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
            if(error) {
                DDLogInfo(@"IPSEC loadFromPreferencesWithCompletionHandler error: %@", error.localizedDescription);
                return;
            }
            
            [self.manager setOnDemandRules:newrules];
            [self turnOnVpn];
        }];
    });
}

- (void) removeSSID:(NSString *)ssid {
    [self turnOffVpn];
    
    // pause three seconds or use completion handler
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        NSArray *currules = self.manager.onDemandRules;
        NSMutableArray *newrules = [[NSMutableArray alloc] initWithCapacity:currules.count];
        for (NEOnDemandRule *rule in currules) {
            if ([rule isKindOfClass:[NEOnDemandRuleDisconnect class]] && rule.SSIDMatch != nil) {
                if ([rule.SSIDMatch count] == 1 && [rule.SSIDMatch[0] isEqualToString:ssid]) {
                    //skip and don't re-add this rule
                } else {
                    NSMutableArray *matchAr = [[NSMutableArray alloc] initWithCapacity:[rule.SSIDMatch count]];
                    for (NSString *match in rule.SSIDMatch) {
                        if (![match isEqualToString:ssid]) {
                            [matchAr addObject: match];
                        }
                    }
                    rule.SSIDMatch = matchAr;
                    [newrules addObject:rule];
                }
            } else {
                [newrules addObject:rule];
            }
        }
        
        [self.manager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
            if(error) {
                DDLogInfo(@"IPSEC loadFromPreferencesWithCompletionHandler error: %@", error.localizedDescription);
                return;
            }
            
            [self.manager setOnDemandRules:newrules];
            [self turnOnVpn];
        }];
    });
}

- (void) removeSSIDs {
    [self turnOffVpn];
    
    // pause three seconds or use completion handler
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        NSArray *currules = self.manager.onDemandRules;
        NSMutableArray *newrules = [[NSMutableArray alloc] initWithCapacity:currules.count];
        for (NEOnDemandRule *rule in currules) {
            if ([rule isKindOfClass:[NEOnDemandRuleDisconnect class]] && rule.SSIDMatch != nil) {
                //do nothing
            } else {
                [newrules addObject:rule];
            }
        }
        
        [self.manager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
            if(error) {
                DDLogInfo(@"IPSEC loadFromPreferencesWithCompletionHandler error: %@", error.localizedDescription);
                return;
            }
            
            [self.manager setOnDemandRules:newrules];
            [self turnOnVpn];
        }];
    });
}

- (NSData *)persistentReferenceForSavedPassword:(NSString *)password service:(NSString *)service account:(NSString *)account {
    NSData *        result;
    NSData *        passwordData;
    OSStatus        err;
    CFTypeRef      secResult;
  
    NSParameterAssert(password != nil);
    NSParameterAssert(service != nil);
    NSParameterAssert(account != nil);
  
    result = nil;
  
    passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
  
    err = SecItemCopyMatching( (__bridge CFDictionaryRef) @{
        (__bridge id) kSecClass:                (__bridge id) kSecClassGenericPassword,
        (__bridge id) kSecAttrService:          service,
        (__bridge id) kSecAttrAccount:          account,
        (__bridge id) kSecReturnPersistentRef:  @YES,
        (__bridge id) kSecReturnData:          @YES
    }, &secResult);
    if (err == errSecSuccess) {
        NSDictionary *  resultDict;
        NSData *        currentPasswordData;
  
        resultDict = CFBridgingRelease( secResult );
        assert([resultDict isKindOfClass:[NSDictionary class]]);
  
        result = resultDict[ (__bridge NSString *) kSecValuePersistentRef ];
        assert([result isKindOfClass:[NSData class]]);
  
        currentPasswordData = resultDict[ (__bridge NSString *) kSecValueData ];
        assert([currentPasswordData isKindOfClass:[NSData class]]);
  
        if ( ! [passwordData isEqual:currentPasswordData] ) {
            err = SecItemUpdate( (__bridge CFDictionaryRef) @{
                (__bridge id) kSecClass:        (__bridge id) kSecClassGenericPassword,
                (__bridge id) kSecAttrService:  service,
                (__bridge id) kSecAttrAccount:  account,
            }, (__bridge CFDictionaryRef) @{
                (__bridge id) kSecValueData:    passwordData
            } );
            if (err != errSecSuccess) {
                DDLogError(@"Error %d saving password (SecItemUpdate)", (int) err);
                result = nil;
            }
        }
    } else if (err == errSecItemNotFound) {
        err = SecItemAdd( (__bridge CFDictionaryRef) @{
            (__bridge id) kSecClass:                (__bridge id) kSecClassGenericPassword,
            (__bridge id) kSecAttrService:          service,
            (__bridge id) kSecAttrAccount:          account,
            (__bridge id) kSecValueData:            passwordData,
            (__bridge id) kSecReturnPersistentRef:  @YES
        }, &secResult);
        if (err == errSecSuccess) {
            result = CFBridgingRelease( secResult );
            assert([result isKindOfClass:[NSData class]]);
        } else {
            DDLogError(@"Error %d saving password (SecItemAdd)", (int) err);
        }
    } else {
        DDLogError(@"Error %d saving password (SecItemCopyMatching)", (int) err);
    }
    return result;
}

- (BOOL) vpnIsEnabled {
    if (self.manager.isEnabled) {
        return YES;
    }
    
    return NO;
}

- (BOOL) vpnIsActive {
    if (self.manager.isEnabled && self.manager.connection.status == NEVPNStatusConnected) {
        return YES;
    }
    
    return NO;
}

- (BOOL) vpnIsDisabled {
    if (!self.manager.isEnabled ||
        (!self.manager.onDemandEnabled && (self.manager.connection.status == NEVPNStatusDisconnected || self.manager.connection.status == NEVPNStatusDisconnecting
            || self.manager.connection.status == NEVPNStatusInvalid))) {
        return YES;
    }
    
    return NO;
}

- (BOOL) isOnTrustedNetwork {
    BOOL trusted = NO;
    
    if (!self.manager.isEnabled) {
        return trusted;
    }
    
    CFArrayRef interfaces = CNCopySupportedInterfaces();
    if(interfaces == nil){
        return trusted;
    }
    CFIndex count = CFArrayGetCount(interfaces);
    if(count == 0){
        return trusted;
    }
    CFDictionaryRef captiveNtwrkDict = CNCopyCurrentNetworkInfo(CFArrayGetValueAtIndex(interfaces, 0));
    NSDictionary *dict = ( __bridge NSDictionary*) captiveNtwrkDict;
    CFRelease(interfaces);
    
    if ([dict objectForKey:@"SSID"]==nil) {
        return trusted;
    }
    
    NSString *curssid = [dict objectForKey:@"SSID"];
    NSArray *currules = self.manager.onDemandRules;
    for (NEOnDemandRule *rule in currules) {
        if ([rule isKindOfClass:[NEOnDemandRuleDisconnect class]] && rule.SSIDMatch != nil) {
            for (NSString *match in rule.SSIDMatch) {
                if ([match isEqualToString:curssid]) {
                    trusted = YES;
                }
            }
        }
    }
    
    return trusted;
}

- (void) noVpnAvailable {
    [self.manager setEnabled:NO];
    if (self.vpnView != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self alertWithTitle:@"No Core Connection available" message:@"There doesn't appear to be any Core profile available for your account. Please ask your Glacier representative if you have additional questions."];
            [self.vpnView setCoreOn:NO];
        });
    }
}

- (void) noAccessAvailable {
    [self.manager setEnabled:NO];
    if (self.vpnView != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self alertWithTitle:@"Account Problem" message:@"There was a problem with your account. For assistance contact your Glacier account representative."];
            [self.vpnView setCoreOn:NO];
        });
    }
}

- (void) turnOnVpn {
    // if not loaded, should attempt to install. How do I know if its loaded?
    if (self.manager.protocolConfiguration == nil) {
        [AWSAccountManager.shared addVPNConnection];
        return;
    }
    
    self.turningOn = YES;
    [self.manager setEnabled:YES];
    self.manager.onDemandEnabled = YES;
    [self.manager saveToPreferencesWithCompletionHandler:^(NSError *error) {
        if(error) {
            DDLogInfo(@"IPSEC saveToPreferencesWithCompletionHandler error: %@", error.localizedDescription);
        }
        
        [self.manager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
            if(error) {
                DDLogInfo(@"IPSEC loadFromPreferencesWithCompletionHandler2 error: %@", error.localizedDescription);
            }
            
            NSError *startError;
            [self.manager.connection startVPNTunnelAndReturnError:&startError];
            if(startError) {
                DDLogInfo(@"IPSEC Start error: %@", startError.localizedDescription);
            }
        }];
    }];
}

- (void) turnOffVpn {
    if ([NEVPNManager sharedManager].isEnabled) {
        self.turningOff = YES;
        self.manager.onDemandEnabled = NO;
        [self.manager saveToPreferencesWithCompletionHandler:^(NSError *error) {
            if(error) {
                DDLogInfo(@"IPSEC saveToPreferencesWithCompletionHandler error: %@", error.localizedDescription);
                return;
            }
            
            [self.manager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
                if(error) {
                    DDLogInfo(@"IPSEC loadFromPreferencesWithCompletionHandler2 error: %@", error.localizedDescription);
                    return;
                }
                
                [[NEVPNManager sharedManager].connection stopVPNTunnel];
            }];
        }];
    }
}

- (void) turnOnWifi {
    [self turnOffVpn];
    
    // pause three seconds or use completion handler
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        BOOL found = NO;
        NSArray *currules = self.manager.onDemandRules;
        NSMutableArray *newrules = [[NSMutableArray alloc] initWithCapacity:currules.count];
        for (NEOnDemandRule *rule in currules) {
            if ([rule isKindOfClass:[NEOnDemandRuleConnect class]] && rule.interfaceTypeMatch == NEOnDemandRuleInterfaceTypeWiFi) {
                found = YES;
            } else if ([rule isKindOfClass:[NEOnDemandRuleDisconnect class]] && rule.interfaceTypeMatch == NEOnDemandRuleInterfaceTypeAny) {
                NEOnDemandRuleConnect *connectRule = [NEOnDemandRuleConnect new];
                connectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceTypeWiFi;
                connectRule.probeURL = [NSURL URLWithString:@"http://captive.apple.com/hotspot-detect.html"];
                [newrules addObject:connectRule];
                found = YES;
            }
            [newrules addObject:rule];
        }
        
        if (!found) {
            NEOnDemandRuleConnect *connectRule = [NEOnDemandRuleConnect new];
            connectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceTypeWiFi;
            connectRule.probeURL = [NSURL URLWithString:@"http://captive.apple.com/hotspot-detect.html"];
            [newrules addObject:connectRule];
        }
        
        [self.manager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
            if(error) {
                DDLogInfo(@"IPSEC loadFromPreferencesWithCompletionHandler error: %@", error.localizedDescription);
                return;
            }
            
            [self.manager setOnDemandRules:newrules];
            [self turnOnVpn];
        }];
    });
}

- (void) turnOffWifi {
    [self turnOffVpn];
    
    // pause three seconds or use completion handler
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        NSArray *currules = self.manager.onDemandRules;
        NSMutableArray *newrules = [[NSMutableArray alloc] initWithCapacity:currules.count];
        for (NEOnDemandRule *rule in currules) {
            if ([rule isKindOfClass:[NEOnDemandRuleConnect class]] && rule.interfaceTypeMatch == NEOnDemandRuleInterfaceTypeWiFi) {
                //skip to remove
            } else if ([rule isKindOfClass:[NEOnDemandRuleConnect class]] && rule.interfaceTypeMatch == NEOnDemandRuleInterfaceTypeAny) {
                //remove Any, and instead add Cellular
                NEOnDemandRuleConnect *connectRule = [NEOnDemandRuleConnect new];
                connectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceTypeCellular;
                connectRule.probeURL = [NSURL URLWithString:@"http://captive.apple.com/hotspot-detect.html"];
                [newrules addObject:rule];
            } else {
                [newrules addObject:rule];
            }
        }
        
        [self.manager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
            if(error) {
                DDLogInfo(@"IPSEC loadFromPreferencesWithCompletionHandler error: %@", error.localizedDescription);
                return;
            }
            
            [self.manager setOnDemandRules:newrules];
            [self turnOnVpn];
        }];
    });
}

- (void) turnOnCellular {
    [self turnOffVpn];
    
    // pause three seconds or use completion handler
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        BOOL found = NO;
        NSArray *currules = self.manager.onDemandRules;
        NSMutableArray *newrules = [[NSMutableArray alloc] initWithCapacity:currules.count];
        for (NEOnDemandRule *rule in currules) {
            if ([rule isKindOfClass:[NEOnDemandRuleConnect class]] && rule.interfaceTypeMatch == NEOnDemandRuleInterfaceTypeCellular) {
                found = YES;
            } else if ([rule isKindOfClass:[NEOnDemandRuleDisconnect class]] && rule.interfaceTypeMatch == NEOnDemandRuleInterfaceTypeAny) {
                NEOnDemandRuleConnect *connectRule = [NEOnDemandRuleConnect new];
                connectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceTypeCellular;
                connectRule.probeURL = [NSURL URLWithString:@"http://captive.apple.com/hotspot-detect.html"];
                [newrules addObject:connectRule];
                found = YES;
            }
            [newrules addObject:rule];
        }
        
        if (!found) {
            NEOnDemandRuleConnect *connectRule = [NEOnDemandRuleConnect new];
            connectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceTypeCellular;
            connectRule.probeURL = [NSURL URLWithString:@"http://captive.apple.com/hotspot-detect.html"];
            [newrules addObject:connectRule];
        }
        
        [self.manager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
            if(error) {
                DDLogInfo(@"IPSEC loadFromPreferencesWithCompletionHandler error: %@", error.localizedDescription);
                return;
            }
            
            [self.manager setOnDemandRules:newrules];
            [self turnOnVpn];
        }];
    });
}

- (void) turnOffCellular {
    [self turnOffVpn];
    
    // pause three seconds or use completion handler
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        NSArray *currules = self.manager.onDemandRules;
        NSMutableArray *newrules = [[NSMutableArray alloc] initWithCapacity:currules.count];
        for (NEOnDemandRule *rule in currules) {
            if ([rule isKindOfClass:[NEOnDemandRuleConnect class]] && rule.interfaceTypeMatch == NEOnDemandRuleInterfaceTypeCellular) {
                //skip to remove
            } else if ([rule isKindOfClass:[NEOnDemandRuleConnect class]] && rule.interfaceTypeMatch == NEOnDemandRuleInterfaceTypeAny) {
                //remove Any, and instead add Cellular
                NEOnDemandRuleConnect *connectRule = [NEOnDemandRuleConnect new];
                connectRule.interfaceTypeMatch = NEOnDemandRuleInterfaceTypeWiFi;
                connectRule.probeURL = [NSURL URLWithString:@"http://captive.apple.com/hotspot-detect.html"];
                [newrules addObject:rule];
            } else {
                [newrules addObject:rule];
            }
        }
        
        [self.manager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
            if(error) {
                DDLogInfo(@"IPSEC loadFromPreferencesWithCompletionHandler error: %@", error.localizedDescription);
                return;
            }
            
            [self.manager setOnDemandRules:newrules];
            [self turnOnVpn];
        }];
    });
}

- (void) vpnConnectionStatusChanged:(NSNotification*)notification {
    DDLogInfo(@"vpnConnectionStatusChanged new status:  %li", (long)self.manager.connection.status);
    if ((_turningOn && self.manager.connection.status == NEVPNStatusConnected) || (_turningOff && self.manager.connection.status == NEVPNStatusDisconnected)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[[OTRAppDelegate appDelegate] conversationViewController] resetStatusTimer];
            [[OTRAppDelegate appDelegate] checkConnectionOrTryLogin];
        });
        self.turningOff = NO;
        self.turningOn = NO;
    }
}

//call on main thread
- (void) alertWithTitle: (NSString *) title message:(NSString *)message {
    //dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:title
                                     message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *action = [UIAlertAction
                                 actionWithTitle:@"Ok"
                                 style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction * action) {
                                     [alert dismissViewControllerAnimated:NO completion:nil];
                                 }];
        [alert addAction:action];
        
        [self.vpnView presentViewController:alert animated:YES completion:nil];
    //});
}

#pragma - mark Singleton Method

+ (VPNManager*) shared {
    return [self sharedInstance];
}

+ (instancetype)sharedInstance
{
    static id vpnManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        vpnManager = [[self alloc] init];
    });
    
    return vpnManager;
}

@end
