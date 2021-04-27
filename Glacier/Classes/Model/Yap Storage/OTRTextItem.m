//
//  OTRTextItem.m
//  ChatSecure
//
//  Created by Chris Ballinger on 5/25/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

#import "OTRTextItem.h"
#import "OTRMediaItem+Private.h"

@implementation OTRTextItem

#if !TARGET_IS_EXTENSION
// Return empty view for now
- (UIView *)mediaView {
    UIView *errorView = [self errorView];
    if (errorView) { return errorView; }
    CGSize size = [self mediaViewDisplaySize];
    CGRect frame = CGRectMake(0, 0, size.width, size.height);
    return [[UIView alloc] initWithFrame:frame];
}
#endif

+ (NSString *)collection
{
    return [OTRMediaItem collection];
}

@end
