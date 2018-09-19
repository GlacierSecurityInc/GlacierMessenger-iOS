//
//  OTRBuddyImageCell.m
//  Off the Record
//
//  Created by David Chiles on 3/3/14.
//  Copyright (c) 2014 Chris Ballinger. All rights reserved.
//

#import "OTRBuddyImageCell.h"
#import "OTRBuddy.h"
#import "OTRImages.h"
#import "OTRColors.h"
@import PureLayout;
@import OTRAssets;
@import JSQMessagesViewController; 

const CGFloat OTRBuddyImageCellPadding = 18.0;

@interface OTRBuddyImageCell ()

@property (nonatomic, strong) UIImageView *avatarImageView;
@property (nonatomic) BOOL addedConstraints;

@property (nonatomic, strong) UIImageView *unreadImageView;
@property (nonatomic, strong) UIImage *unreadImage;

@end


@implementation OTRBuddyImageCell

@synthesize imageViewBorderColor = _imageViewBorderColor;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.unreadImage = [OTRImages circleWithRadius:20 lineWidth:0 lineColor:nil
                                             fillColor:[UIColor jsq_messageBubbleBlueColor]];
        self.unreadImageView = [[UIImageView alloc] initWithImage:self.unreadImage];
        self.unreadImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self markRead];
        [self.contentView addSubview:self.unreadImageView];
        
        self.avatarImageView = [[UIImageView alloc] initWithImage:[self defaultImage]];
        self.avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
        CALayer *cellImageLayer = self.avatarImageView.layer;
        cellImageLayer.borderWidth = 0.0;
        
        [cellImageLayer setMasksToBounds:YES];
        [cellImageLayer setBorderColor:[self.imageViewBorderColor CGColor]];
        [self.contentView addSubview:self.avatarImageView];
        self.addedConstraints = NO;
    }
    return self;
}

- (void) markUnread {
    self.unreadImageView.image = self.unreadImage;
}

- (void) markRead {
    self.unreadImageView.image = nil;
}

- (UIColor *)imageViewBorderColor
{
    if (!_imageViewBorderColor) {
        _imageViewBorderColor = [UIColor blackColor];
    }
    return _imageViewBorderColor;
}

- (void)setImageViewBorderColor:(UIColor *)imageViewBorderColor
{
    _imageViewBorderColor = imageViewBorderColor;
    
    [self.avatarImageView.layer setBorderColor:[_imageViewBorderColor CGColor]];
}

- (void)setThread:(id<OTRThreadOwner>)thread
{
    UIImage *avatarImage = [thread avatarImage];
    if(avatarImage) {
        self.avatarImageView.image = avatarImage;
    }
    else {
        self.avatarImageView.image = [self defaultImage];
    }
    UIColor *statusColor =  [OTRColors colorWithStatus:[thread currentStatus]];
    if (statusColor) {
        self.avatarImageView.layer.borderWidth = 1.5;
    } else {
        self.avatarImageView.layer.borderWidth = 0.0;
    }
    self.imageViewBorderColor = [OTRColors colorWithStatus:OTRThreadStatusOffline];
    [self.contentView setNeedsUpdateConstraints];
}

- (UIImage *)defaultImage
{
    return [UIImage imageNamed:@"person" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil];
}

- (void)updateConstraints
{
    if (!self.addedConstraints) {
        [self.unreadImageView autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsMake(35, 10, 35, 10) excludingEdge:ALEdgeTrailing];
        [self.unreadImageView autoMatchDimension:ALDimensionHeight toDimension:ALDimensionWidth ofView:self.unreadImageView];
        
        [self.avatarImageView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:OTRBuddyImageCellPadding];
        [self.avatarImageView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:OTRBuddyImageCellPadding];
        [self.avatarImageView autoPinEdge:ALEdgeLeading toEdge:ALEdgeTrailing ofView:self.unreadImageView withOffset:5.0];
        [self.avatarImageView autoMatchDimension:ALDimensionHeight toDimension:ALDimensionWidth ofView:self.avatarImageView];
        
        self.addedConstraints = YES;
    }
    [super updateConstraints];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self.avatarImageView.layer setCornerRadius:(self.contentView.frame.size.height-2*OTRBuddyImageCellPadding)/2.0];
}

+ (NSString *)reuseIdentifier
{
    return NSStringFromClass([self class]);
}

@end
