//
//  OTROutgoingMessage.m
//  ChatSecure
//
//  Created by David Chiles on 11/10/16.
//  Copyright © 2016 Chris Ballinger. All rights reserved.
//

#import "OTROutgoingMessage.h"
#if !TARGET_IS_EXTENSION
#import "Glacier-Swift.h"
#elif !TARGET_IS_SHARE
#import "GlacierNotifications-Swift.h"
#elif TARGET_IS_SHARE
#import "GlacierShare-Swift.h"
#endif
#import "OTRMessageEncryptionInfo.h"

@implementation OTROutgoingMessage

#pragma MARK - OTRMessageProtocol 

- (BOOL)isMessageIncoming
{
    return NO;
}

- (BOOL)isMessageIncomingOrDifferentDevice { 
    if (self.isOutgoingFromDifferentDevice) {
        return YES;
    }
    
    return NO;
}

- (BOOL)isMessageRead
{
    return YES;
}

- (BOOL) isMessageSent {
    return self.dateSent != nil;
}

- (BOOL) isMessageDelivered {
    return self.isDelivered;
}

- (BOOL) isMessageDisplayed {
    return self.isDisplayed;
}

@end
