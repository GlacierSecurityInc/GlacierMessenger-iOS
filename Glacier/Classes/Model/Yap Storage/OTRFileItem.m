//
//  OTRFileItem.m
//  ChatSecure
//
//  Created by Chris Ballinger on 5/19/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

#import "OTRFileItem.h"
#if !TARGET_IS_EXTENSION
#import "OTRMediaItem+Private.h"
@import BButton;
#import "Glacier-Swift.h"
#endif

@interface OTRFileItem ()
@property (nonatomic, class, readonly) NSCache *fileCache;
@end

@implementation OTRFileItem

#if !TARGET_IS_EXTENSION
// Return empty view for now
- (UIView *)mediaView {
    UIView *errorView = [self errorView];
    if (errorView) { return errorView; }

    FilePreviewView *preview = [FilePreviewView glacierViewFromNib];
    if (!preview) {
        return nil;
    }
    [preview setFile:self.filename];
    CGSize size = [self mediaViewDisplaySize];
    preview.frame = CGRectMake(0, 0, size.width, size.height);

    if (self.isIncoming) {
        preview.backgroundColor = [UIColor jsq_messageBubbleLightGrayColor];
    } else {
        preview.backgroundColor = [UIColor jsq_messageBubbleBlueColor];
        [preview setOutgoing:YES];
    }
    [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:preview isOutgoing:!self.isIncoming];
    
    return preview;
}

- (CGSize)mediaViewDisplaySize
{
    return CGSizeMake(250.0f, 70.0f); 
}

- (BOOL) shouldFetchMediaData {
    return ![[[self class] fileCache] objectForKey:self.uniqueId];
}

- (BOOL) handleMediaData:(NSData *)mediaData message:(nonnull id<OTRMessageProtocol>)message {
    //NSParameterAssert(mediaData.length > 0);
    if (!mediaData.length) { return NO; }
    [[[self class] fileCache] setObject:mediaData forKey:self.uniqueId];
    return YES;
}
#endif

/** If mimeType is not provided, it will be guessed from filename */
- (instancetype) initWithFileURL:(NSURL*)url
                       isIncoming:(BOOL)isIncoming {
    NSParameterAssert(url);
    if (self = [super initWithFilename:url.lastPathComponent mimeType:nil isIncoming:isIncoming]) {
        
    }
    return self;
}

+ (NSCache*) fileCache {
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
    });
    return cache;
}

+ (NSString *)collection
{
    return [OTRMediaItem collection];
}

@end
