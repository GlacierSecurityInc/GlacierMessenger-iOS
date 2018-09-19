//
//  NetworkTester.m
//
//  Created by Andy Friedman on 7/10/17.
//

#import <Foundation/Foundation.h>
#import "NetworkTester.h"
#import "SimplePing.h"
#import "OTRProtocol.h"
#import "OTRAppDelegate.h"

@implementation NetworkTester

NSString *const NetworkStatusNotificationName = @"NetworkStatusNotificationName";
NSUInteger const defaultPingNum = 10;

NSString *const OldNetworkStatusKey = @"OldNetworkStatusKey";
NSString *const NewNetworkStatusKey = @"NewNetworkStatusKey";

- (id) init {
    if (self = [super init]) {
        self.pingNum = defaultPingNum;
        self.simplePing = nil;
        self.networkStatus = OTRNetworkConnectionStatusUnknown;
    }
    return self;
}

- (void)changeNetworkStatus:(OTRNetworkConnectionStatus)status
{
    OTRNetworkConnectionStatus oldStatus = self.networkStatus;
    OTRNetworkConnectionStatus newStatus = status;
    self.networkStatus = status;
    
    NSMutableDictionary *userInfo = [@{OldNetworkStatusKey: @(oldStatus), NewNetworkStatusKey: @(newStatus)} mutableCopy];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:NetworkStatusNotificationName object:self userInfo:userInfo];
    });
}

- (void)setAddress:(NSString *)address{
    self.domainAddress = address;
}

- (BOOL)hasAddress {
    if (self.domainAddress) {
        return YES;
    }
    
    return NO;
}

- (void)setNetworkConnectAttempts:(NSUInteger)attempts {
    self.pingNum = attempts;
}

- (void) reset {
    [self pingDealloc];
    self.networkStatus = OTRNetworkConnectionStatusUnknown;
    [self changeNetworkStatus: OTRNetworkConnectionStatusUnknown];
}

- (void)tryConnectToNetwork {
    [self changeNetworkStatus: OTRNetworkConnectionStatusConnecting];
    self.pingCtr = (int)self.pingNum;
    [self ping];
}

- (void)pingResult:(NSNumber*)success {
    
    [self pingDealloc];
    if (success.boolValue) {
        self.pingCtr = 0;
        [self changeNetworkStatus: OTRNetworkConnectionStatusConnected];
        /*dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:NetworkStatusNotificationName object:self];
        });*/
    } else {
        NSLog(@"PING_FAILURE %@, with number %d", self.domainAddress, self.pingCtr);
        self.pingCtr--;
        if (self.pingCtr > 0) { //retry ping if ctr not finished
            dispatch_async(dispatch_get_main_queue(), ^{
                [self ping];
            });
        } else {
            [self changeNetworkStatus: OTRNetworkConnectionStatusDisconnected];
            /*dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:NetworkStatusNotificationName object:self];
            });*/
        }
    }
}

// Pings the address, and calls the selector when done. Selector must take a NSnumber which is a bool for success
- (void)ping {
    // The helper retains itself through the timeout function
    if (!self.domainAddress) {
        return;
    }
    
    self.simplePing = [[SimplePing alloc] initWithHostName:self.domainAddress];
    if (self.simplePing != nil) {
        self.simplePing.delegate = self;
        [self pingGo];
    }
}

#pragma mark - Init/dealloc

- (void)pingDealloc {
    self.simplePing = nil;
}

#pragma mark - Go

- (void)pingGo {
    
    [self.simplePing start];
    //LOGI(@"PING_START");
    [self performSelector:@selector(endTime) withObject:nil afterDelay:1]; // This timeout is what retains the ping helper
}

#pragma mark - Finishing and timing out

// Called on success or failure to clean up
- (void)killPing {
    [self.simplePing stop];
    self.simplePing = nil;
}

- (void)successPing {
    [self killPing];
    [self pingResult:[NSNumber numberWithBool:YES]];
}

- (void)failPing:(NSString*)reason {
    [self killPing];
    //LOGE(@"************************");
    NSLog(@"PING_FAILURE %@, with number %d", reason, self.pingCtr);
    [self pingResult:[NSNumber numberWithBool:NO]];
}

// Called 1s after ping start, to check if it timed out
- (void)endTime {
    if (self.simplePing) { // If it hasn't already been killed, then it's timed out
        [self failPing:@"timeout"];
    }
}

#pragma mark - Pinger delegate

/*- (void)simplePing:(SimplePing *)pinger didSendPacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber {
 LOGI(@"************************ PACKET SENT");
 }*/

// When the pinger starts, send the ping immediately
- (void)simplePing:(SimplePing *)pinger didStartWithAddress:(NSData *)address {
    [self.simplePing sendPingWithData:nil];
}

- (void)simplePing:(SimplePing *)pinger didFailWithError:(NSError *)error {
    [self failPing:@"didFailWithError"];
    [self failPing:error.localizedDescription];
}

- (void)simplePing:(SimplePing *)pinger didFailToSendPacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber error:(NSError *)error {
    // Eg they're not connected to any network
    [self failPing:@"didFailToSendPacket"];
    [self failPing:error.localizedDescription];
}

- (void)simplePing:(SimplePing *)pinger didReceivePingResponsePacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber{
    [self successPing];
}

/*- (void)simplePing:(SimplePing *)pinger didReceiveUnexpectedPacket:(NSData *)packet {
 [self failPing:@"unexpectedPacket"];
 }*/

@end
