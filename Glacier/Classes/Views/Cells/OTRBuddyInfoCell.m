//
//  OTRBuddyInfoCell.m
//  Off the Record
//
//  Created by David Chiles on 3/4/14.
//  Copyright (c) 2014 Chris Ballinger. All rights reserved.
//

#import "OTRBuddyInfoCell.h"
#import "OTRBuddy.h"

#import "OTRColors.h"
#import "OTRImages.h"

#import "OTRAccount.h"
#import "OTRXMPPBuddy.h"
#import "OTRStrings.h"
@import PureLayout;
#import "OTRDatabaseManager.h"

const CGFloat OTRBuddyInfoCellHeight = 80.0;

@interface OTRBuddyInfoCell ()

@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *identifierLabel;
@property (nonatomic, strong) UILabel *accountLabel;
@property (nonatomic, strong) UIImage *statusImage;

@end

@implementation OTRBuddyInfoCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.nameLabel = [[UILabel alloc] initForAutoLayout];
        self.nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        
        self.identifierLabel = [[UILabel alloc] initForAutoLayout];
        self.identifierLabel.textColor = [UIColor darkTextColor];
        self.identifierLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        
        self.accountLabel = [[UILabel alloc] initForAutoLayout];
        self.accountLabel.textColor = [UIColor lightGrayColor];
        self.accountLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
        
        NSArray<UILabel*> *labels = @[self.nameLabel, self.identifierLabel, self.accountLabel];
        [labels enumerateObjectsUsingBlock:^(UILabel * _Nonnull label, NSUInteger idx, BOOL * _Nonnull stop) {
            label.adjustsFontSizeToFitWidth = YES;
            [self.contentView addSubview:label];
        }];
        _infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
        [self.infoButton addTarget:self action:@selector(infoButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)setThread:(id<OTRThreadOwner>)thread {
    [self setThread:thread account:nil];
}

- (void)setThread:(id<OTRThreadOwner>)thread account:(nullable OTRAccount*)account
{
    [super setThread:thread];
    
    self.statusImage = [OTRImages circleWithRadius:20 lineWidth:0 lineColor:nil
                                         fillColor:[OTRColors colorWithStatus:[thread currentStatus]]];
    self.unreadImageView.image = self.statusImage;
    
    NSString * name = [thread threadName];
    
    self.nameLabel.text = name;
    self.accountLabel.text = account.username;
    
    NSString *shortnamestring = nil; // aka 'username' from username@example.com
    NSArray *namecomponents = [name componentsSeparatedByString:@"@"];
    if (namecomponents.count == 2) {
        shortnamestring = [namecomponents firstObject];
        self.nameLabel.text = shortnamestring;
    }
    
    NSString *identifier = nil;
    if ([thread isKindOfClass:[OTRBuddy class]]) {
        OTRBuddy *buddy = (OTRBuddy*)thread;
        identifier = buddy.username;
    } else if ([thread isGroupThread]) {
        identifier = GROUP_NAME_STRING();
    }
    self.identifierLabel.text = @"";
    
    UIColor *textColor = [UIColor darkTextColor];
    if (@available(iOS 13.0, *)) {
        textColor = [UIColor labelColor];
    } 
    if ([thread isArchived]) {
        textColor = [UIColor lightGrayColor];
    }
    
    [@[self.nameLabel, self.identifierLabel] enumerateObjectsUsingBlock:^(UILabel   * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        obj.textColor = textColor;
    }];
}

- (void)updateConstraints
{
    if (self.addedConstraints) {
        [super updateConstraints];
        return;
    }
    NSArray<UILabel*> *textLabelsArray = @[self.nameLabel,self.identifierLabel,self.accountLabel];
    
    //same horizontal contraints for all labels
    for(UILabel *label in textLabelsArray) {
        [label autoPinEdge:ALEdgeLeading toEdge:ALEdgeTrailing ofView:self.avatarImageView withOffset:OTRBuddyImageCellPadding];
        [label autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:OTRBuddyImageCellPadding relation:NSLayoutRelationGreaterThanOrEqual];
    }
    
    [self.nameLabel autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:OTRBuddyImageCellPadding];
    [self.nameLabel autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:self.accountLabel withOffset:0 relation:NSLayoutRelationGreaterThanOrEqual];
    [self.accountLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:OTRBuddyImageCellPadding];
    
    [super updateConstraints];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    
    UIColor *textColor = [UIColor darkTextColor];
    if (@available(iOS 13.0, *)) { 
        textColor = [UIColor labelColor];
    }
    
    self.nameLabel.textColor = textColor;
    self.identifierLabel.textColor = textColor;
    self.accountLabel.textColor = [UIColor lightGrayColor];
}

- (void) infoButtonPressed:(UIButton*)sender {
    if (!self.infoAction) {
        return;
    }
    self.infoAction(self, sender);
}

@end
