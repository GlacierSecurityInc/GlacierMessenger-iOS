//
//  OTRConversationCell.m
//  Off the Record
//
//  Created by David Chiles on 3/3/14.
//  Copyright (c) 2014 Chris Ballinger. All rights reserved.
//

#import "OTRConversationCell.h"
#import "OTRBuddy.h"
#import "OTRAccount.h"
#import "OTRIncomingMessage.h"
#import "OTROutgoingMessage.h"
#import "OTRDatabaseManager.h"
#import "OTRMediaItem.h"
#import "OTRImageItem.h"
#import "OTRAudioItem.h"
#import "OTRVideoItem.h"
@import OTRAssets;
@import YapDatabase;
@import BButton;
#import <ChatSecureCore/ChatSecureCore-Swift.h>

@interface OTRConversationCell ()

@property (nonatomic, strong) NSArray *verticalConstraints;
@property (nonatomic, strong) NSArray *accountHorizontalConstraints;

@end

@implementation OTRConversationCell

- (id) initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.showAccountLabel = NO;
        
        UIFont *faFontSmall = [UIFont fontWithName:kFontAwesomeFont size:[UIFont smallSystemFontSize]-1];
        UIFont *faFontLarger = [UIFont fontWithName:kFontAwesomeFont size:[UIFont systemFontSize]];
        
        UIColor *darkGreyColor = [UIColor colorWithWhite:.45 alpha:1.0];
        UIColor *lightGreyColor = [UIColor colorWithWhite:.6 alpha:1.0];
        self.dateLabel = [[UILabel alloc] init];
        self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.dateLabel.font = faFontSmall;
        self.dateLabel.textColor = [UIColor blackColor];
        
        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.nameLabel.font = faFontLarger;
        self.nameLabel.textColor = [UIColor blackColor];
        
        self.conversationLabel = [[UILabel alloc] init];
        self.conversationLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.conversationLabel.lineBreakMode = NSLineBreakByWordWrapping;
        self.conversationLabel.numberOfLines = 0;
        self.conversationLabel.font = faFontSmall;
        self.conversationLabel.textColor = lightGreyColor;
        
        self.accountLabel = [[UILabel alloc] init];
        self.accountLabel.translatesAutoresizingMaskIntoConstraints = NO;
        
        
        [self.contentView addSubview:self.dateLabel];
        [self.contentView addSubview:self.nameLabel];
        [self.contentView addSubview:self.conversationLabel];
        
    }
    return self;
}

- (void)setShowAccountLabel:(BOOL)showAccountLabel
{
    _showAccountLabel = showAccountLabel;
    
    if (!self.showAccountLabel) {
        [self.accountLabel removeFromSuperview];
    }
    else {
        [self.contentView addSubview:self.accountLabel];
    }
}

- (void)setThread:(id <OTRThreadOwner>)thread
{
    [super setThread:thread];
    NSString * nameString = [thread threadName];
    
    self.nameLabel.text = nameString;
    
    __block OTRAccount *account = nil;
    __block id <OTRMessageProtocol> lastMessage = nil;
    __block NSUInteger unreadMessages = 0;
    __block OTRMediaItem *mediaItem = nil;
    
    [[OTRDatabaseManager sharedInstance].readOnlyDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        account = [transaction objectForKey:[thread threadAccountIdentifier] inCollection:[OTRAccount collection]];
        unreadMessages = [thread numberOfUnreadMessagesWithTransaction:transaction];
        lastMessage = [thread lastMessageWithTransaction:transaction];
        if (lastMessage.messageMediaItemKey) {
            mediaItem = [OTRMediaItem fetchObjectWithUniqueID:lastMessage.messageMediaItemKey transaction:transaction];
        }
    }];
    
    self.accountLabel.text = account.username;
    
    NSString *shortusername = nil; // aka 'username' from username@example.com
    NSArray *acctcomponents = [account.username componentsSeparatedByString:@"@"];
    if (acctcomponents.count == 2) {
        shortusername = [acctcomponents firstObject];
        self.accountLabel.text = shortusername;
    }
    
    NSString *shortnamestring = nil; // aka 'username' from username@example.com
    NSArray *namecomponents = [nameString componentsSeparatedByString:@"@"];
    if (namecomponents.count == 2) {
        shortnamestring = [namecomponents firstObject];
        self.nameLabel.text = shortnamestring;
    }
    
    UIFont *currentFont = self.conversationLabel.font;
    CGFloat fontSize = currentFont.pointSize;
    NSError *messageError = lastMessage.messageError;
    NSString *messageText = lastMessage.messageText;
    
    if ([messageText hasPrefix:@"geo:"]) {
        messageText = [NSString stringWithFormat:@"%@ Location sent", [NSString fa_stringForFontAwesomeIcon:FAIconMapMarker]];
    }
    
    if (messageError &&
        !messageError.isAutomaticDownloadError) {
        if (!messageText.length) {
            messageText = ERROR_STRING();
        }
        
        self.conversationLabel.text = @"⚠️ Unable to send message";  //changed from "image"
    } else if (mediaItem) {
        self.conversationLabel.text = mediaItem.displayText;
    } else {
        self.conversationLabel.text = messageText;
    }
    
    self.nameLabel.textColor = [UIColor blackColor];
    if (unreadMessages > 0) {
        //unread message
        [self markUnread];
    } else {
        [self markRead];
    }
    
    self.dateLabel.textColor = self.nameLabel.textColor;
    
    [self updateDateString:lastMessage.messageDate];
}

- (void)updateDateString:(NSDate *)date
{
    self.dateLabel.text = [self dateString:date];
}

- (NSString *)dateString:(NSDate *)messageDate
{
    NSTimeInterval timeInterval = fabs([messageDate timeIntervalSinceNow]);
    NSString * dateString = nil;
    if (timeInterval < 60){
        dateString = @"Now";
    }
    else if (timeInterval < 60*60) {
        int minsInt = timeInterval/60;
        NSString * minString = @"mins";
        if (minsInt == 1) {
            minString = @"min";
        }
        dateString = [NSString stringWithFormat:@"%d %@",minsInt,minString];
    }
    else if (timeInterval < 60*60*24){
        // show time in format 11:00 PM
        dateString = [NSDateFormatter localizedStringFromDate:messageDate dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
    }
    else if (timeInterval < 60*60*24*7) {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEE" options:0 locale:[NSLocale currentLocale]];
        dateString = [dateFormatter stringFromDate:messageDate];
        
    }
    else if (timeInterval < 60*60*25*365) {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"dMMM" options:0
                                                                   locale:[NSLocale currentLocale]];
        dateString = [dateFormatter stringFromDate:messageDate];
    }
    else {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"dMMMYYYY" options:0
                                                                    locale:[NSLocale currentLocale]];
        dateString = [dateFormatter stringFromDate:messageDate];
    }
    
    
    
    return dateString;
}

- (void)updateConstraints
{
    NSDictionary *views = @{@"unreadView": self.unreadImageView,
                            @"imageView": self.avatarImageView,
                            @"conversationLabel": self.conversationLabel,
                            @"dateLabel":self.dateLabel,
                            @"nameLabel":self.nameLabel,
                            @"conversationLabel":self.conversationLabel,
                            @"accountLabel":self.accountLabel};
    
    NSDictionary *metrics = @{@"margin":[NSNumber numberWithFloat:OTRBuddyImageCellPadding]};
    if (!self.addedConstraints) {
        
        
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[unreadView]-margin-[imageView]-margin-[nameLabel]->=0-[dateLabel]-margin-|"
                                                                                 options:0
                                                                                 metrics:metrics
                                                                                   views:views]];
        
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[unreadView]-margin-[imageView]-margin-[conversationLabel]-margin-|"
                                                                                 options:0
                                                                                 metrics:metrics
                                                                                   views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-margin-[dateLabel(17)]" options:0 metrics:metrics
                                                                                   views:views]];
        
        
    }
    
    if([self.accountHorizontalConstraints count])
    {
        [self.contentView removeConstraints:self.accountHorizontalConstraints];
    }
    
    if([self.verticalConstraints count]) {
        [self.contentView removeConstraints:self.verticalConstraints];
    }
    
    if (self.showAccountLabel) {
        self.accountHorizontalConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"H:[unreadView]-margin-[imageView]-margin-[accountLabel]|"
                                                                                    options:0
                                                                                    metrics:metrics
                                                                                      views:views];
        
        self.verticalConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-margin-[nameLabel][conversationLabel][accountLabel]-margin-|"
                                                                           options:0
                                                                           metrics:metrics
                                                                             views:views];
        
    }
    else {
        self.accountHorizontalConstraints = @[];
        self.verticalConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-margin-[nameLabel(17)][conversationLabel]-margin-|"
                                                                           options:0
                                                                           metrics:metrics
                                                                             views:views];
    }
    if([self.accountHorizontalConstraints count]) {
        [self.contentView addConstraints:self.accountHorizontalConstraints];
    }
    
    [self.contentView addConstraints:self.verticalConstraints];
    [super updateConstraints];
}

@end
