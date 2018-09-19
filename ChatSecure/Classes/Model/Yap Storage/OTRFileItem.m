//
//  OTRFileItem.m
//  ChatSecure
//
//  Created by Chris Ballinger on 5/19/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

#import "OTRFileItem.h"
#import "OTRMediaItem+Private.h"


@implementation OTRFileItem

// Return empty view for now
- (UIView *)mediaView {
    UIView *errorView = [self errorView];
    if (errorView) { return errorView; }
    CGSize size = [self mediaViewDisplaySize];
    CGRect frame = CGRectMake(0, 0, size.width, size.height);
    return [[UIView alloc] initWithFrame:frame];
}

/*- (UIView *)mediaView
{
    UIView *errorView = [self errorView];
    if (errorView) { return errorView; }
    UIImage *image = [OTRImages imageWithIdentifier:self.uniqueId];
    if (!image) {
        [self fetchMediaData];
        return nil;
    }
    CGSize size = [self mediaViewDisplaySize];
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.frame = CGRectMake(0, 0, size.width, size.height);
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:imageView isOutgoing:!self.isIncoming];
    
    UIImage *playIcon = [[UIImage jsq_defaultPlayImage] jsq_imageMaskedWithColor:[UIColor lightGrayColor]];
    UIImageView *playImageView = [[UIImageView alloc] initWithImage:playIcon];
    playImageView.backgroundColor = [UIColor clearColor];
    playImageView.contentMode = UIViewContentModeCenter;
    playImageView.clipsToBounds = YES;
    playImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [imageView addSubview:playImageView];
    [playImageView autoCenterInSuperview];
    
    return imageView;
}

- (instancetype) initWithFileData:(NSData*)data
                                  isIncoming:(BOOL)isIncoming {
    NSParameterAssert(data);
    if (self = [super initWithFilename:url.lastPathComponent mimeType:nil isIncoming:isIncoming]) {
        AVURLAsset *asset = [AVURLAsset assetWithURL:url];
        AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
        CGSize videoSize = videoTrack.naturalSize;
        
        CGAffineTransform transform = videoTrack.preferredTransform;
        if ((videoSize.width == transform.tx && videoSize.height == transform.ty) || (transform.tx == 0 && transform.ty == 0))
        {
            _width = videoSize.width;
            _height = videoSize.height;
        }
        else
        {
            _width = videoSize.height;
            _height = videoSize.width;
        }
    }
    return self;
}

- (UIView *)mediaView {
    UIView *errorView = [self errorView];
    if (errorView) { return errorView; }
    UIImage *image = [OTRImages imageWithIdentifier:self.uniqueId];
    if (!image) {
        [self fetchMediaData];
        return nil;
    }
    self.size = image.size;
    CGSize size = [self mediaViewDisplaySize];
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:imageView isOutgoing:!self.isIncoming];
    
    NSString *thumbnailKey = [NSString stringWithFormat:@"%@-thumb", self.uniqueId];
    UIImage *imageThumb = [OTRImages imageWithIdentifier:thumbnailKey];
    if (!imageThumb) {
        __weak typeof(UIImageView *)weakImageView = imageView;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UIImage *resizedImage = [UIImage otr_imageWithImage:image scaledToSize:size];
            [OTRImages setImage:resizedImage forIdentifier:thumbnailKey];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakImageView)strongImageView = weakImageView;
                [strongImageView setImage:resizedImage];
            });
        });
    } else {
        [imageView setImage:imageThumb];
    }
    return imageView;
}

- (BOOL) shouldFetchMediaData {
    return ![OTRImages imageWithIdentifier:self.uniqueId];
}

- (BOOL) handleMediaData:(NSData *)mediaData message:(nonnull id<OTRMessageProtocol>)message {
    [super handleMediaData:mediaData message:message];
    UIImage *image = [UIImage imageWithData:mediaData];
    if (!image) {
        DDLogError(@"Media item data is not an image!");
        return NO;
    }
    self.size = image.size;
    [OTRImages setImage:image forIdentifier:self.uniqueId];
    return YES;
}*/

+ (NSString *)collection
{
    return [OTRMediaItem collection];
}

@end
