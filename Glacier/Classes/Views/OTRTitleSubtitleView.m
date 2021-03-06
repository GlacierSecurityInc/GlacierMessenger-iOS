//
//  OTRTitleSubtitleView.m
//  Off the Record
//
//  Created by David Chiles on 12/16/13.
//  Copyright (c) 2013 Chris Ballinger. All rights reserved.
//

#import "OTRTitleSubtitleView.h"
#import "OTRUtilities.h"

@import PureLayout;

static const CGFloat kOTRMaxImageViewHeight = 6;

@interface OTRTitleSubtitleView ()

@property (nonatomic, strong) UILabel * titleLabel;
@property (nonatomic, strong) UILabel * subtitleLabel;

@property (nonatomic, strong) UIImageView *titleImageView;
@property (nonatomic, strong) UIImageView *subtitleImageView;
@property (nonatomic, strong) DGActivityIndicatorView *dynConnectingView;

@property (nonatomic) BOOL addedConstraints;

@end

@implementation OTRTitleSubtitleView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.addedConstraints = NO;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizesSubviews = YES;
        
        self.titleLabel = [[UILabel alloc] initForAutoLayout];
        
        self.titleLabel.backgroundColor = [UIColor clearColor];
        
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.adjustsFontSizeToFitWidth = YES;
        
        self.subtitleLabel = [[UILabel alloc] initForAutoLayout];
        self.subtitleLabel.backgroundColor = [UIColor clearColor];
        self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
        
        self.subtitleLabel.textColor = [UIColor blackColor];
        if (@available(iOS 13.0, *)) {
            self.subtitleLabel.textColor = [UIColor labelColor];
        }
        
        UIFontDescriptor *userFont = [UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleBody];
        float fontSize = [userFont pointSize]-1;
        float subFontSize = [userFont pointSize]-6;
        
        self.titleLabel.font = [UIFont boldSystemFontOfSize:fontSize];//16];
        self.subtitleLabel.font = [UIFont systemFontOfSize:subFontSize];//11];
        
        self.titleImageView = [[UIImageView alloc] initForAutoLayout];
        self.subtitleImageView = [[UIImageView alloc] initForAutoLayout];
        
        self.dynConnectingView = [[[DGActivityIndicatorView alloc]
                                   initWithType:DGActivityIndicatorAnimationTypeBallBeat
                                   tintColor:self.subtitleLabel.textColor size:18.0f] initForAutoLayout];
        
        [self addSubview:self.titleImageView];
        [self addSubview:self.dynConnectingView];
        
        [self addSubview:self.titleLabel];
        [self addSubview:self.subtitleLabel];
        
        [self setNeedsUpdateConstraints];
    }
    return self;
}

- (void)updateConstraints {
    if (!self.addedConstraints) {
        [self setupContraints];
        self.addedConstraints = YES;
    } 
    
    [super updateConstraints];
}

- (void)setupContraints {
    
    if (@available(iOS 13.0, *)) {
        UIView *backingbar = self.superview;
        UIView *navbar = backingbar.superview;
        [backingbar autoAlignAxisToSuperviewAxis:ALAxisVertical];
        [self autoAlignAxisToSuperviewAxis:ALAxisVertical];
        [backingbar autoMatchDimension:ALDimensionWidth toDimension:ALDimensionWidth ofView:navbar withMultiplier:0.6 relation:NSLayoutRelationLessThanOrEqual];
        [self autoMatchDimension:ALDimensionWidth toDimension:ALDimensionWidth ofView:backingbar withMultiplier:1.0];
    }
    
    /////////TITLE LABEL ////////////////
    [self.titleLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.titleLabel autoAlignAxisToSuperviewAxis:ALAxisVertical];
    [self.titleLabel autoMatchDimension:ALDimensionHeight toDimension:ALDimensionHeight ofView:self withMultiplier:0.6];
    [self.titleLabel autoMatchDimension:ALDimensionWidth toDimension:ALDimensionWidth ofView:self withMultiplier:0.9 relation:NSLayoutRelationLessThanOrEqual];
    
    ///////////// SUBTITLE LABEL /////////////
    [self.subtitleLabel autoAlignAxisToSuperviewAxis:ALAxisVertical];
    [self.subtitleLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.subtitleLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.titleLabel withOffset:-4];
    
    ////// TITLE IMAGEVIEW //////
    [self setupConstraintsWithImageView:self.titleImageView withLabel:self.titleLabel];
    
    ////// SUBTITILE IMAGEVIEW //////
    [self setupConstraintsWithDynView:self.dynConnectingView withLabel:self.subtitleLabel];
    [self.dynConnectingView autoMatchDimension:ALDimensionHeight toDimension:ALDimensionHeight ofView:self.subtitleLabel withMultiplier:1.0 relation:NSLayoutRelationLessThanOrEqual];
}

- (void)setupConstraintsWithDynView:(DGActivityIndicatorView *)imageView withLabel:(UILabel *)label
{
    //Keeps trailing edge off of leading edge of label by at least 2
    [imageView autoPinEdge:ALEdgeTrailing toEdge:ALEdgeLeading ofView:label withOffset:-5.0];
    //Keep centered horizontaly
    [imageView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:label];
    
    //Keep leading edge inside superview
    [imageView autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:0 relation:NSLayoutRelationGreaterThanOrEqual];
    
    //Less than equal to height of label
    [imageView autoMatchDimension:ALDimensionHeight toDimension:ALDimensionHeight ofView:label withOffset:0 relation:NSLayoutRelationLessThanOrEqual];
    //Less than equal to max height
    [imageView autoSetDimension:ALDimensionHeight toSize:kOTRMaxImageViewHeight relation:NSLayoutRelationLessThanOrEqual];
}

- (void)setupConstraintsWithImageView:(UIImageView *)imageView withLabel:(UILabel *)label
{
    //Keeps trailing edge off of leading edge of label by at least 2
    [imageView autoPinEdge:ALEdgeTrailing toEdge:ALEdgeLeading ofView:label withOffset:-5.0];
    //Keep centered horizontaly
    [imageView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:label];
    
    //Keep leading edge inside superview
    [imageView autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:0 relation:NSLayoutRelationGreaterThanOrEqual];
    
    //Less than equal to height of label
    [imageView autoMatchDimension:ALDimensionHeight toDimension:ALDimensionHeight ofView:label withOffset:0 relation:NSLayoutRelationLessThanOrEqual];
    //Less than equal to max height
    [imageView autoSetDimension:ALDimensionHeight toSize:kOTRMaxImageViewHeight relation:NSLayoutRelationLessThanOrEqual];
    
    //Square ImageView
    [imageView autoMatchDimension:ALDimensionWidth toDimension:ALDimensionHeight ofView:imageView];
}

@end
