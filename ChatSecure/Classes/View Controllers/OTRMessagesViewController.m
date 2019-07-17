//
//  OTRMessagesViewController.m
//  Off the Record
//
//  Created by David Chiles on 5/12/14.
//  Copyright (c) 2014 Chris Ballinger. All rights reserved.
//

#import "OTRMessagesViewController.h"

#import "OTRDatabaseView.h"
#import "OTRDatabaseManager.h"
#import "OTRLog.h"

#import "OTRBuddy.h"
#import "OTRAccount.h"
#import "OTRMessage+JSQMessageData.h"
@import JSQMessagesViewController;
@import MobileCoreServices;
#import "OTRProtocolManager.h"
#import "OTRXMPPTorAccount.h"
#import "OTRXMPPManager.h"
#import "OTRLockButton.h"
#import "OTRButtonView.h"
@import OTRAssets;
#import "OTRTitleSubtitleView.h"
@import OTRKit;
@import FormatterKit;
#import "OTRImages.h"
#import "UIActivityViewController+ChatSecure.h"
#import "OTRUtilities.h"
#import "OTRProtocolManager.h"
#import "OTRColors.h"
#import "JSQMessagesCollectionViewCell+ChatSecure.h"
@import BButton;
#import "OTRAttachmentPicker.h"
#import "OTRImageItem.h"
#import "OTRVideoItem.h"
#import "OTRAudioItem.h"
#import "OTRFileItem.h"
@import JTSImageViewController;
#import "OTRAudioControlsView.h"
#import "OTRPlayPauseProgressView.h"
#import "OTRAudioPlaybackController.h"
#import "OTRMediaFileManager.h"
#import "OTRMediaServer.h"
#import "UIImage+ChatSecure.h"
#import "OTRBaseLoginViewController.h"

#import <ChatSecureCore/ChatSecureCore-Swift.h>
#import "OTRYapMessageSendAction.h"
#import "UIViewController+ChatSecure.h"
#import "OTRBuddyCache.h"
#import "OTRTextItem.h"
#import "OTRHTMLItem.h"
#import "OTRFileItem.h"
@import YapDatabase;
@import PureLayout;
@import KVOController;

@import AVFoundation;
@import MediaPlayer;
@import AVKit;

static NSTimeInterval const kOTRMessageSentDateShowTimeInterval = 60 * 60 * 12;
static NSUInteger const kOTRMessagePageSize = 50;

typedef NS_ENUM(int, OTRDropDownType) {
    OTRDropDownTypeNone          = 0,
    OTRDropDownTypeEncryption    = 1,
    OTRDropDownTypePush          = 2
};

@interface OTRMessagesViewController () <UITextViewDelegate, OTRAttachmentPickerDelegate, OTRYapViewHandlerDelegateProtocol, OTRMessagesCollectionViewFlowLayoutSizeProtocol, OTRRoomOccupantsViewControllerDelegate, JSQMessagesComposerTextViewPasteDelegate, JTSImageViewControllerInteractionsDelegate> {
    JSQMessagesAvatarImage *_warningAvatarImage;
    JSQMessagesAvatarImage *_accountAvatarImage;
    JSQMessagesAvatarImage *_buddyAvatarImage;
}

@property (nonatomic, strong) OTRYapViewHandler *viewHandler;

@property (nonatomic, strong) JSQMessagesBubbleImage *outgoingBubbleImage;
@property (nonatomic, strong) JSQMessagesBubbleImage *incomingBubbleImage;

@property (nonatomic, weak) id didFinishGeneratingPrivateKeyNotificationObject;
@property (nonatomic, weak) id messageStateDidChangeNotificationObject;
@property (nonatomic, weak) id pendingApprovalDidChangeNotificationObject;
@property (nonatomic, weak) id deviceListUpdateNotificationObject;
@property (nonatomic, weak) id serverCheckUpdateNotificationObject;

@property (nonatomic ,strong) UIBarButtonItem *lockBarButtonItem;
@property (nonatomic, strong) OTRLockButton *lockButton;
@property (nonatomic, strong) OTRButtonView *buttonDropdownView;

@property (nonatomic, strong) OTRAttachmentPicker *attachmentPicker;
@property (nonatomic, strong) OTRAudioPlaybackController *audioPlaybackController;

@property (nonatomic, strong) NSTimer *lastSeenRefreshTimer;
@property (nonatomic, strong) UIView *jidForwardingHeaderView;

@property (nonatomic) BOOL loadingMessages;
@property (nonatomic) BOOL messageRangeExtended;
@property (nonatomic, strong) NSIndexPath *currentIndexPath;
@property (nonatomic, strong) id currentMessage;
@property (nonatomic, strong) NSCache *messageSizeCache;

@property (assign, nonatomic) BOOL showConnStatus;

@property (nonatomic, strong) OTRTitleSubtitleView *titleSubView;

@property (nonatomic, strong) NSTimer *expiringRefreshTimer;
@property (nonatomic, strong) TTTTimeIntervalFormatter *exptf;

@property (nonatomic, strong) NSTimer *statusTimer;
@property int statusCtr;
@property (nonatomic, strong) NSString *accountType;
@property (nonatomic, strong) UITapGestureRecognizer *statusTapGestureRecognizer;

@property (nonatomic, strong) XMPPPinned *pins;

@end

@implementation OTRMessagesViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        self.senderId = @"";
        self.senderDisplayName = @"";
        _state = [[MessagesViewControllerState alloc] init];
        self.messageSizeCache = [NSCache new];
        self.messageSizeCache.countLimit = kOTRMessagePageSize;
        self.messageRangeExtended = NO;
    }
    return self;
}

- (YapDatabaseConnection*) readConnection {
    return self.connections.read;
}

- (YapDatabaseConnection*) writeConnection {
    return self.connections.write;
}

- (YapDatabaseConnection*) uiConnection {
    return self.connections.ui;
}

- (DatabaseConnections*) connections {
    return OTRDatabaseManager.shared.connections;
}

#pragma - mark Lifecylce Methods

- (void) dealloc {
    [self.lastSeenRefreshTimer invalidate];
    [self.expiringRefreshTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.additionalContentInset = UIEdgeInsetsMake(20, 0, 0, 0);
    
    self.automaticallyScrollsToMostRecentMessage = YES;
    self.showConnStatus = YES;
    
     ////// bubbles //////
    JSQMessagesBubbleImageFactory *bubbleImageFactory = [[JSQMessagesBubbleImageFactory alloc] init];
                                                         
    self.outgoingBubbleImage = [bubbleImageFactory outgoingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleBlueColor]];
    
    self.incomingBubbleImage = [bubbleImageFactory incomingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleLightGrayColor]];
    
    // for expiring message timer
    _exptf = [[TTTTimeIntervalFormatter alloc] init];
    _exptf.futureDeicticExpression = @"left";
    _exptf.usesAbbreviatedCalendarUnits = YES;
    
    ////// TitleView //////
    OTRTitleSubtitleView *titleView = [self titleView];
    [self refreshTitleView:titleView];
    self.navigationItem.titleView = titleView;
    
    self.titleView.subtitleLabel.text = nil;
    
    self.inputToolbar.contentView.textView.pasteDelegate = self;
    
    _statusCtr = 0;
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateStatusTimer:) userInfo:nil repeats:YES];
    
    self.titleView.dynConnectingView.hidden = YES;
    
    ////// Send Button //////
    self.sendButton = [JSQMessagesToolbarButtonFactory defaultSendButtonItem];
    
    ////// Attachment Button //////
    self.inputToolbar.contentView.leftBarButtonItem = nil;
    self.cameraButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.cameraButton.titleLabel.font = [UIFont fontWithName:kFontAwesomeFont size:20];
    self.cameraButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.cameraButton setTitle:[NSString fa_stringForFontAwesomeIcon:FAIconCamera] forState:UIControlStateNormal];
    self.cameraButton.frame = CGRectMake(0, 0, 32, 32);
    [self.cameraButton setTintColor:[UIColor jsq_messageBubbleBlueColor]];
    
    self.moreOptionsButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.moreOptionsButton.frame = CGRectMake(0, 0, 32, 32);
    self.moreOptionsButton.titleLabel.font = [UIFont fontWithName:kFontAwesomeFont size:20];
    self.moreOptionsButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.moreOptionsButton setTitle:[NSString fa_stringForFontAwesomeIcon:FAIconChevronRight] forState:UIControlStateNormal];
    [self.moreOptionsButton setTintColor:[UIColor jsq_messageBubbleBlueColor]];
    self.inputToolbar.contentView.leftBarButtonItem = self.moreOptionsButton;
    
    self.attachButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.attachButton.frame = CGRectMake(0, 0, 32, 32);
    self.attachButton.titleLabel.font = [UIFont fontWithName:kFontAwesomeFont size:20];
    self.attachButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.attachButton setTitle:[NSString fa_stringForFontAwesomeIcon:FAIconPaperclip] forState:UIControlStateNormal];
    [self.attachButton setTintColor:[UIColor jsq_messageBubbleBlueColor]];
    
    // for expiring messgages
    self.hourglassButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.hourglassButton.frame = CGRectMake(32, 0, 32, 32);
    self.hourglassButton.titleLabel.font = [UIFont fontWithName:kFontAwesomeFont size:20];
    self.hourglassButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.hourglassButton setTitle:[NSString fa_stringForFontAwesomeIcon:FAIconHourglass1] forState:UIControlStateNormal];
    [self.hourglassButton setTintColor:[UIColor jsq_messageBubbleBlueColor]];
    
    ////// Microphone Button //////
    self.microphoneButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.microphoneButton.frame = CGRectMake(0, 0, 32, 32);
    self.microphoneButton.titleLabel.font = [UIFont fontWithName:kFontAwesomeFont size:20];
    self.microphoneButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.microphoneButton setTitle:[NSString fa_stringForFontAwesomeIcon:FAIconMicrophone]
          forState:UIControlStateNormal];
    [self.microphoneButton setTintColor:[UIColor jsq_messageBubbleBlueColor]];
    
    self.audioPlaybackController = [[OTRAudioPlaybackController alloc] init];
    
    ////// TextViewUpdates //////
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receivedTextViewChangedNotification:) name:UITextViewTextDidChangeNotification object:self.inputToolbar.contentView.textView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enteringForegroundStatus:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:[UIApplication sharedApplication]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enteringBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:[UIApplication sharedApplication]];
    
    self.statusTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleStatusGesture)];
    self.statusTapGestureRecognizer.numberOfTapsRequired = 1;
    
    /** Setup databse view handler*/
    self.viewHandler = [[OTRYapViewHandler alloc] initWithDatabaseConnection:[OTRDatabaseManager sharedInstance].longLivedReadOnlyConnection databaseChangeNotificationName:[DatabaseNotificationName LongLivedTransactionChanges]];
    self.viewHandler.delegate = self;
    
    SupplementaryViewHandler *supp = [[SupplementaryViewHandler alloc] initWithCollectionView:self.collectionView viewHandler:self.viewHandler connections:self.connections];
    _supplementaryViewHandler = supp;
    supp.newDeviceViewActionButtonCallback = ^(NSString * _Nullable buddyId) {
        [self newDeviceButtonPressed:buddyId];
    };
    
    ///Custom Layout to account for no bubble cells
    OTRMessagesCollectionViewFlowLayout *layout = [[OTRMessagesCollectionViewFlowLayout alloc] init];
    layout.viewHandler = self.viewHandler;
    layout.sizeDelegate = self;
    layout.supplementaryViewDelegate = supp;
    self.collectionView.collectionViewLayout = layout;
    
    ///"Loading Earlier" header view
    [self.collectionView registerNib:[UINib nibWithNibName:@"OTRMessagesLoadingView" bundle:OTRAssets.resourcesBundle]
          forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                 withReuseIdentifier:[JSQMessagesLoadEarlierHeaderView headerReuseIdentifier]];

    //Subscribe to changes in encryption state
    __weak typeof(self)weakSelf = self;
    [self.KVOController observe:self.state keyPath:NSStringFromSelector(@selector(messageSecurity)) options:NSKeyValueObservingOptionInitial|NSKeyValueObservingOptionNew block:^(id  _Nullable observer, id  _Nonnull object, NSDictionary<NSString *,id> * _Nonnull change) {
        __typeof__(self) strongSelf = weakSelf;
        if (!strongSelf) { return; }
        
        if ([object isKindOfClass:[MessagesViewControllerState class]]) {
            MessagesViewControllerState *state = (MessagesViewControllerState*)object;
            NSString * placeHolderString = nil;
            switch (state.messageSecurity) {
                case OTRMessageTransportSecurityPlaintext:
                case OTRMessageTransportSecurityPlaintextWithOTR:
                    placeHolderString = @"Send message";
                    break;
                case OTRMessageTransportSecurityOTR:
                    placeHolderString = [NSString stringWithFormat:SEND_ENCRYPTED_STRING(),@"OTR"];
                    break;
                case OTRMessageTransportSecurityOMEMO:
                    placeHolderString = @"Send message";
                    break;
                    
                default:
                    placeHolderString = [NSBundle jsq_localizedStringForKey:@"new_message"];
                    break;
            }
            strongSelf.inputToolbar.contentView.textView.placeHolder = placeHolderString;
            [self didUpdateState];
        }
    }];
    
    __block OTRXMPPManager *xmpp = nil;
    [self.connections.read asyncReadWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        xmpp = [self xmppManagerWithTransaction:transaction];
    }];
    if (xmpp) {
         [self.KVOController observe:xmpp keyPath:NSStringFromSelector(@selector(loginStatus)) options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld action:@selector(setConnectionStatus)];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self tryToMarkAllMessagesAsRead];
    // This is a hack to attempt fixing https://github.com/ChatSecure/ChatSecure-iOS/issues/657
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self scrollToBottomAnimated:animated];
    });
    self.loadingMessages = NO;
    
    self.inputToolbar.contentView.textView.canShowKeyboard = YES;
}

- (BOOL) prefersStatusBarHidden {
    return NO;
}

- (void)viewWillAppear:(BOOL)animated
{
    self.currentIndexPath = nil;
    
    [super viewWillAppear:animated];
    
    self.inputToolbar.contentView.textView.canShowKeyboard = NO;
    
    if (self.lastSeenRefreshTimer) {
        [self.lastSeenRefreshTimer invalidate];
        _lastSeenRefreshTimer = nil;
    }
    _lastSeenRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(refreshTitleTimerUpdate:) userInfo:nil repeats:YES];
    
    if (self.expiringRefreshTimer) {
        [self.expiringRefreshTimer invalidate];
        self.expiringRefreshTimer = nil;
    }
    _expiringRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateForExpiringMessages:) userInfo:nil repeats:YES];
    
    __weak typeof(self)weakSelf = self;
    void (^refreshGeneratingLock)(OTRAccount *) = ^void(OTRAccount * account) {
        __strong typeof(weakSelf)strongSelf = weakSelf;
        __block NSString *accountKey = nil;
        [strongSelf.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            accountKey = [strongSelf buddyWithTransaction:transaction].accountUniqueId;
        }];
        if ([account.uniqueId isEqualToString:accountKey]) {
            [strongSelf updateEncryptionState];
        }
        
        
    };
    
    self.didFinishGeneratingPrivateKeyNotificationObject = [[NSNotificationCenter defaultCenter] addObserverForName:OTRDidFinishGeneratingPrivateKeyNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        if ([note.object isKindOfClass:[OTRAccount class]]) {
            refreshGeneratingLock(note.object);
        }
    }];
   
    self.messageStateDidChangeNotificationObject = [[NSNotificationCenter defaultCenter] addObserverForName:OTRMessageStateDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf)strongSelf = weakSelf;
        if ([note.object isKindOfClass:[OTRBuddy class]]) {
            OTRBuddy *notificationBuddy = note.object;
            __block NSString *buddyKey = nil;
            [strongSelf.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
                buddyKey = [strongSelf buddyWithTransaction:transaction].uniqueId;
            }];
            if ([notificationBuddy.uniqueId isEqualToString:buddyKey]) {
                [strongSelf updateEncryptionState];
            }
        }
    }];
    
    if ([self.threadKey length]) {
        [self.viewHandler.keyCollectionObserver observe:self.threadKey collection:self.threadCollection];
        [self updateViewWithKey:self.threadKey collection:self.threadCollection];
        [self.viewHandler setup:OTRFilteredChatDatabaseViewExtensionName groups:@[self.threadKey]];
        if(![self.inputToolbar.contentView.textView.text length]) {
            [self moveLastComposingTextForThreadKey:self.threadKey colleciton:self.threadCollection toTextView:self.inputToolbar.contentView.textView];
        }
    } else {
        [self.inputToolbar.contentView.textView setEditable:NO];
    }

    self.loadingMessages = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkConnectionStatusChange:) name:NetworkStatusNotificationName object:nil];
    if (_accountType == nil) {
        NSUserDefaults *glacierDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.glaciersec.apps"];
        _accountType = [glacierDefaults stringForKey:@"connection"];
    }
    
    self.showConnStatus = YES;
    [self setConnectionStatus];
    
    [self.messageSizeCache removeAllObjects];
    [self.collectionView.collectionViewLayout invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
    [self.collectionView reloadData];
    
    if ([self isGroupChat]) {
        [self getPins];
    }
}

- (void) enteringForegroundStatus:(NSNotification *)notification {
    if (self.statusTimer) [self.statusTimer invalidate];
    _statusCtr = 0;
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateStatusTimer:) userInfo:nil repeats:YES];
    
    [self setConnectionStatus];
}

- (void) enteringBackground:(NSNotification *)notification {
    
    if (self.statusTimer) [self.statusTimer invalidate];
    self.statusTimer = nil;
    _statusCtr = 0;
    
    [self.titleView.dynConnectingView stopAnimating];
    [self resetOptionsButton];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self.lastSeenRefreshTimer invalidate];
    self.lastSeenRefreshTimer = nil;
    
    [self.expiringRefreshTimer invalidate];
    self.expiringRefreshTimer = nil;
    
    [self saveCurrentMessageText:self.inputToolbar.contentView.textView.text threadKey:self.threadKey colleciton:self.threadCollection];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self.messageStateDidChangeNotificationObject];
    [[NSNotificationCenter defaultCenter] removeObserver:self.didFinishGeneratingPrivateKeyNotificationObject];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NetworkStatusNotificationName object:nil];
    [self resetOptionsButton];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];

    _warningAvatarImage = nil;
    _accountAvatarImage = nil;
    _buddyAvatarImage = nil;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    // After the transition is done, we need to reset the size caches and relayout
    // Do this using the technique in https://stackoverflow.com/questions/26943808/ios-how-to-run-a-function-after-device-has-rotated-swift
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self.messageSizeCache removeAllObjects];
        [self.collectionView.collectionViewLayout invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
    }];
}

#pragma - mark Setters & getters

- (OTRAttachmentPicker *)attachmentPicker
{
    if (!_attachmentPicker) {
        _attachmentPicker = [[OTRAttachmentPicker alloc] initWithParentViewController:self delegate:self];
    }
    return _attachmentPicker;
}

- (NSArray*) indexPathsToCount:(NSUInteger)count {
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
        [indexPaths addObject:indexPath];
    }
    return indexPaths;
}

- (nullable id<OTRThreadOwner>)threadObjectWithTransaction:(nonnull YapDatabaseReadTransaction *)transaction {
    if (!self.threadKey || !self.threadCollection || !transaction) { return nil; }
    id object = [transaction objectForKey:self.threadKey inCollection:self.threadCollection];
    if ([object conformsToProtocol:@protocol(OTRThreadOwner)]) {
        return object;
    }
    return nil;
}

- (nullable OTRXMPPBuddy *)buddyWithTransaction:(nonnull YapDatabaseReadTransaction *)transaction {
    id <OTRThreadOwner> object = [self threadObjectWithTransaction:transaction];
    if ([object isKindOfClass:[OTRXMPPBuddy class]]) {
        return (OTRXMPPBuddy *)object;
    }
    return nil;
}

- (nullable OTRXMPPRoom *)roomWithTransaction:(nonnull YapDatabaseReadTransaction *)transaction {
    id <OTRThreadOwner> object = [self threadObjectWithTransaction:transaction];
    if ([object isKindOfClass:[OTRXMPPRoom class]]) {
        return (OTRXMPPRoom *)object;
    }
    return nil;
}

- (nullable OTRXMPPAccount *)accountWithTransaction:(nonnull YapDatabaseReadTransaction *)transaction {
    id <OTRThreadOwner> thread =  [self threadObjectWithTransaction:transaction];
    if (!thread) { return nil; }
    OTRXMPPAccount *account = [OTRXMPPAccount fetchObjectWithUniqueID:[thread threadAccountIdentifier] transaction:transaction];
    return account;
}

- (void)setThreadKey:(NSString *)key collection:(NSString *)collection
{
    self.currentIndexPath = nil;
    NSString *oldKey = self.threadKey;
    NSString *oldCollection = self.threadCollection;
    
    self.threadKey = key;
    self.threadCollection = collection;
    __block NSString *senderId = nil;
    __block OTRXMPPAccount *account = nil;
    
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        senderId = [[self threadObjectWithTransaction:transaction] threadAccountIdentifier];
        account = [self accountWithTransaction:transaction];
    }];
    // this can be nil for an empty chat window
    if (senderId.length > 0) {
        self.senderId = senderId;
    } else {
        self.senderId = @"";
    }
    if (account) {
        self.automaticURLFetchingDisabled = account.disableAutomaticURLFetching;
    } else {
        self.automaticURLFetchingDisabled = YES;
    }
    
    
    // Clear out old state (don't just alloc a new object, we have KVOs attached to this!)
    [self.state reset];
    self.showTypingIndicator = NO;
    
    // This is set to nil so the refreshTitleView: method knows to reset username instead of last seen time
    [self titleView].subtitleLabel.text = nil;
    
    if (![oldKey isEqualToString:key] || ![oldCollection isEqualToString:collection]) {
        [self saveCurrentMessageText:self.inputToolbar.contentView.textView.text threadKey:oldKey colleciton:oldCollection];
        self.inputToolbar.contentView.textView.text = nil;
        [self receivedTextViewChanged:self.inputToolbar.contentView.textView];
    }

    [self.supplementaryViewHandler removeAllSupplementaryViews];
    
    [self.viewHandler.keyCollectionObserver stopObserving:oldKey collection:oldCollection];
    if (self.threadKey && self.threadCollection) {
        [self.viewHandler.keyCollectionObserver observe:self.threadKey collection:self.threadCollection];
        [self updateViewWithKey:self.threadKey collection:self.threadCollection];
        [self.viewHandler setup:OTRFilteredChatDatabaseViewExtensionName groups:@[self.threadKey]];
        [self moveLastComposingTextForThreadKey:self.threadKey colleciton:self.threadCollection toTextView:self.inputToolbar.contentView.textView];
        [self.inputToolbar.contentView.textView setEditable:YES];
    } else {
        [self.viewHandler setup:OTRFilteredChatDatabaseViewExtensionName groups:@[]];
        self.senderDisplayName = @"";
        self.senderId = @"";
    }
    
    // Reset scroll position
    [self.collectionView setContentOffset:CGPointZero animated:NO];
    
    // Reload collection view
    [self.messageSizeCache removeAllObjects];
    [self.collectionView.collectionViewLayout invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
    [self.collectionView reloadData];
    
    [self resetOptionsButton];
    
    // Profile Info Button
    [self setupInfoButton];
    
    [self updateEncryptionState];
    [self updateJIDForwardingHeader];
    
    __weak typeof(self)weakSelf = self;
    if (self.pendingApprovalDidChangeNotificationObject == nil) {
        self.pendingApprovalDidChangeNotificationObject = [[NSNotificationCenter defaultCenter] addObserverForName:OTRBuddyPendingApprovalDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            __strong typeof(weakSelf)strongSelf = weakSelf;
            OTRXMPPBuddy *notificationBuddy = [note.userInfo objectForKey:@"buddy"];
            __block NSString *buddyKey = nil;
            [strongSelf.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
                buddyKey = [strongSelf buddyWithTransaction:transaction].uniqueId;
            }];
            if ([notificationBuddy.uniqueId isEqualToString:buddyKey]) {
                [strongSelf fetchOMEMODeviceList];
                [strongSelf sendPresenceProbe];
            }
        }];
    }
    
    if (self.deviceListUpdateNotificationObject == nil) {
        self.deviceListUpdateNotificationObject = [[NSNotificationCenter defaultCenter] addObserverForName:OTROMEMOSignalCoordinator.DeviceListUpdateNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull notification) {
            __strong typeof(weakSelf)strongSelf = weakSelf;
            [strongSelf didReceiveDeviceListUpdateWithNotification:notification];
        }];
    }
    
    // We also add a listener for serverCheck updates, needed for group chats. Otherwise, if you start the app and directly enter a group chat, the media buttons will remain disabled, since in updateEncryptionState we set canSendMedia according to server capabilities, which may not have been fetched yet. This listener ensures that canSendMedia is updated correctly.
    if (self.serverCheckUpdateNotificationObject == nil) {
        self.serverCheckUpdateNotificationObject = [[NSNotificationCenter defaultCenter] addObserverForName:ServerCheck.UpdateNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
            __strong typeof(weakSelf)strongSelf = weakSelf;
            if ([self isGroupChat]) {
                __block OTRXMPPManager *xmpp = nil;
                [strongSelf.connections.read asyncReadWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
                    xmpp = [strongSelf xmppManagerWithTransaction:transaction];
                } completionBlock:^{
                    if (note.object == xmpp.serverCheck) {
                        [strongSelf updateEncryptionState];
                    }
                }];
            }
        }];
    }
    
    if (![self isGroupChat]) {
        [self sendPresenceProbe];
        [self fetchOMEMODeviceList];
    }
}

- (nullable OTRXMPPManager *)xmppManagerWithTransaction:(nonnull YapDatabaseReadTransaction *)transaction {
    OTRAccount *account = [self accountWithTransaction:transaction];
    if (!account) { return nil; }
    return (OTRXMPPManager *)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
}

/** Will send a probe to fetch last seen */
- (void) sendPresenceProbe {
    __block OTRXMPPManager *xmpp = nil;
    __block OTRXMPPBuddy *buddy = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        xmpp = [self xmppManagerWithTransaction:transaction];
        buddy = (OTRXMPPBuddy*)[self buddyWithTransaction:transaction];
    }];
    if (!xmpp || ![buddy isKindOfClass:[OTRXMPPBuddy class]] || buddy.pendingApproval) { return; }
    [xmpp sendPresenceProbeForBuddy:buddy];
}

- (void)updateViewWithKey:(NSString *)key collection:(NSString *)collection
{
    if ([collection isEqualToString:[OTRBuddy collection]]) {
        __block OTRBuddy *buddy = nil;
        __block OTRAccount *account = nil;
        [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            buddy = [OTRBuddy fetchObjectWithUniqueID:key transaction:transaction];
            account = [OTRAccount fetchObjectWithUniqueID:buddy.accountUniqueId transaction:transaction];
        }];
        
        // Update Buddy Status
        BOOL previousState = self.state.isThreadOnline;
        self.state.isThreadOnline = buddy.status != OTRThreadStatusOffline;
        
        if (self.state.isThreadOnline &&
            (buddy.chatState == OTRChatStateComposing || buddy.chatState == OTRChatStatePaused)) {
            self.showTypingIndicator = YES;
        } else {
            self.showTypingIndicator = NO;
        }
        
        [self didUpdateState];
        
        [self refreshTitleView:[self titleView]];

        // Auto-inititate OTR when contact comes online
        if (!previousState && self.state.isThreadOnline) {
            [OTRProtocolManager.encryptionManager maybeRefreshOTRSessionForBuddyKey:key collection:collection];
        }
    } else if ([collection isEqualToString:[OTRXMPPRoom collection]]) {
        __block OTRXMPPRoom *room = nil;
        [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            room = [OTRXMPPRoom fetchObjectWithUniqueID:key transaction:transaction];
        }];
        self.state.isThreadOnline = room.currentStatus != OTRThreadStatusOffline;
        [self didUpdateState];
        [self refreshTitleView:[self titleView]];
    }
    [self tryToMarkAllMessagesAsRead];
}

- (void)tryToMarkAllMessagesAsRead {
    // Set all messages as read
    if ([self otr_isVisible]) {
        __weak __typeof__(self) weakSelf = self;
        __block id <OTRThreadOwner>threadOwner = nil;
        __block NSArray <id <OTRMessageProtocol>>* unreadMessages = nil;
        [self.connections.read asyncReadWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            threadOwner = [weakSelf threadObjectWithTransaction:transaction];
            if (!threadOwner) { return; }
            unreadMessages = [transaction allUnreadMessagesForThread:threadOwner];
        } completionBlock:^{
            
            if ([unreadMessages count] == 0) {
                return;
            }
            
            //Mark as read
            
            NSMutableArray <id <OTRMessageProtocol>>*toBeSaved = [[NSMutableArray alloc] init];
            
            [unreadMessages enumerateObjectsUsingBlock:^(id<OTRMessageProtocol>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if ([obj isKindOfClass:[OTRIncomingMessage class]]) {
                    OTRIncomingMessage *message = [((OTRIncomingMessage *)obj) copy];
                    message.read = YES;
                    message.readDate = [NSDate date];
                    [toBeSaved addObject:message];
                } else if ([obj isKindOfClass:[OTRXMPPRoomMessage class]]) {
                    OTRXMPPRoomMessage *message = [((OTRXMPPRoomMessage *)obj) copy];
                    message.read = YES;
                    [toBeSaved addObject:message];
                }
            }];
            
            [weakSelf.connections.write asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
                [toBeSaved enumerateObjectsUsingBlock:^(id<OTRMessageProtocol>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    [transaction setObject:obj forKey:[obj messageKey] inCollection:[obj messageCollection]];
                }];
                [transaction touchObjectForKey:[threadOwner threadIdentifier] inCollection:[threadOwner threadCollection]];
            }];
        }];
    }
}

- (OTRTitleSubtitleView * __nonnull)titleView {
    UIView *titleView = self.navigationItem.titleView;
    if (![titleView isKindOfClass:[OTRTitleSubtitleView class]]) {
        titleView = [[OTRTitleSubtitleView alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
        self.navigationItem.titleView = titleView;
    }
    return (OTRTitleSubtitleView*)titleView;
}

- (void)refreshTitleTimerUpdate:(NSTimer*)timer {
    [self refreshTitleView:[self titleView]];
}

/** Updates the title view with the current thread information on this view controller*/
- (void)refreshTitleView:(OTRTitleSubtitleView *)titleView
{
    __block id<OTRThreadOwner> thread = nil;
    __block OTRAccount *account = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        thread = [self threadObjectWithTransaction:transaction];
        account =  [self accountWithTransaction:transaction];
    }];
    
    titleView.titleLabel.text = [thread threadName];
    
    NSArray *namecomponents = [[thread threadName] componentsSeparatedByString:@"@"];
    if (namecomponents.count == 2) {
        self.titleView.titleLabel.text = [namecomponents firstObject];
    }
    
    UIImage *statusImage = nil;
    if ([thread isKindOfClass:[OTRBuddy class]]) {
        OTRBuddy *buddy = (OTRBuddy*)thread;
        UIColor *color = [buddy avatarBorderColor];
        if (color) { // only show online status
            statusImage = [OTRImages circleWithRadius:50
                                      lineWidth:0
                                      lineColor:nil
                                      fillColor:color];
        }
        
        dispatch_block_t refreshTimeBlock = ^{
            __block OTRBuddy *buddy = nil;
            [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
                buddy = (OTRBuddy*)[self threadObjectWithTransaction:transaction];
            }];
            if (![buddy isKindOfClass:[OTRBuddy class]]) {
                return;
            }
            NSDate *lastSeen = [OTRBuddyCache.shared lastSeenDateForBuddy:buddy];
            OTRThreadStatus status = [OTRBuddyCache.shared threadStatusForBuddy:buddy];
            if (!lastSeen) {
                return;
            }
            TTTTimeIntervalFormatter *tf = [[TTTTimeIntervalFormatter alloc] init];
            tf.presentTimeIntervalMargin = 60;
            tf.usesAbbreviatedCalendarUnits = YES;
            NSTimeInterval lastSeenInterval = [lastSeen timeIntervalSinceDate:[NSDate date]];
            NSString *labelString = nil;
            if (status == OTRThreadStatusAvailable) {
                labelString = nil;
            } else {
                labelString = [NSString stringWithFormat:@"%@ %@", ACTIVE_STRING(), [tf stringForTimeInterval:lastSeenInterval]];
            }
            
            if (!self.showConnStatus) {
                titleView.subtitleLabel.text = labelString;
            }
        };
        
        // Set the username if nothing else is set.
        // This should be cleared out when buddy is changed
        if (!titleView.subtitleLabel.text) {
            //
        }
        
        // Show an "Last seen 11 min ago" in title bar after brief delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            refreshTimeBlock();
        });
    } else if ([thread isGroupThread]) {
        titleView.titleLabel.text = [NSString stringWithFormat: @"#%@", titleView.titleLabel.text];
    } else {
        titleView.subtitleLabel.text = nil;
    }
    
    titleView.titleImageView.image = statusImage;

}

- (nullable NSString *)getThreadName {
    return self.titleView.titleLabel.text;
}

/**
 This generates a UIAlertAction where the handler fetches the outgoing message (optionaly duplicates). Then if media message resend media message. If not update messageSecurityInfo and date and create new sending action.
 */
- (UIAlertAction *)resendOutgoingMessageActionForMessageKey:(NSString *)messageKey
                                          messageCollection:(NSString *)messageCollection
                                writeConnection:(YapDatabaseConnection*)databaseConnection
                                                      title:(NSString *)title
{
    UIAlertAction *action = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            id object = [[transaction objectForKey:messageKey inCollection:messageCollection] copy];
            id<OTRMessageProtocol> message = nil;
            if ([object conformsToProtocol:@protocol(OTRMessageProtocol)]) {
                message = (id<OTRMessageProtocol>)object;
            } else {
                return;
            }
            // Messages that never sent properly don't need to be duplicated client-side
            NSError *messageError = message.messageError;
            message = [message duplicateMessage];
            message.messageError = nil;
            message.messageSecurity = self.state.messageSecurity;
            message.messageDate = [NSDate date];
            [message saveWithTransaction:transaction];
            
            // We only need to re-upload failed media messages
            // otherwise just resend the URL directly
            if (message.messageMediaItemKey.length &&
                (!message.messageText.length || messageError)) {
                OTRMediaItem *mediaItem = [OTRMediaItem fetchObjectWithUniqueID:message.messageMediaItemKey transaction:transaction];
                [self sendMediaItem:mediaItem data:nil message:message transaction:transaction];
            } else {
                OTRYapMessageSendAction *sendingAction = [OTRYapMessageSendAction sendActionForMessage:message date:message.messageDate];
                [sendingAction saveWithTransaction:transaction];
            }
        }];
    }];
    return action;
}

- (nonnull UIAlertAction *)viewProfileAction {
    return [UIAlertAction actionWithTitle:VIEW_PROFILE_STRING() style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self infoButtonPressed:action];
    }];
}

- (nonnull UIAlertAction *)cancleAction {
    return [UIAlertAction actionWithTitle:CANCEL_STRING()
                                    style:UIAlertActionStyleCancel
                                  handler:nil];
}

- (nullable UIAlertAction *)cancelDownloadActionForMessage:(id<OTRMessageProtocol>)message {
    __block OTRMediaItem *mediaItem = nil;
    __block OTRXMPPManager *xmpp = nil;
    
    //Get the media item
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        mediaItem = [OTRMediaItem fetchObjectWithUniqueID:[message messageMediaItemKey] transaction:transaction];
        xmpp = [self xmppManagerWithTransaction:transaction];
    }];
    UIAlertAction *action = nil;
    
    // Only show "Cancel" for messages that are not fully downloaded
    if (mediaItem && mediaItem.isIncoming && mediaItem.transferProgress < 1) {
        action = [UIAlertAction actionWithTitle:CANCEL_STRING() style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [xmpp.fileTransferManager cancelDownloadWithMediaItem:mediaItem];
        }];
    }
    return action;
}

- (NSArray <UIAlertAction *>*)actionForMessage:(id<OTRMessageProtocol>)message {
    NSMutableArray <UIAlertAction *>*actions = [[NSMutableArray alloc] init];
    
    if (!message.isMessageIncoming) {
        // This is an outgoing message so we can offer to resend
        UIAlertAction *resendAction = [self resendOutgoingMessageActionForMessageKey:message.messageKey messageCollection:message.messageCollection writeConnection:self.connections.write  title:RESEND_STRING()];
        [actions addObject:resendAction];
    }
    
    // If we are currently downloading, allow us to cancel
    if([[message messageMediaItemKey] length] > 0 && [message conformsToProtocol:@protocol(OTRDownloadMessage)] && message.messageError == nil) {
        UIAlertAction *cancelDownloadAction = [self cancelDownloadActionForMessage:message];
        if (cancelDownloadAction) {
            [actions addObject:cancelDownloadAction];
        }
    }
    
    if (![message isKindOfClass:[OTRXMPPRoomMessage class]]) {
        //
    }
    
    NSArray<UIAlertAction*> *mediaActions = [UIAlertAction actionsForMediaMessage:message sourceView:self.view viewController:self];
    [actions addObjectsFromArray:mediaActions];
    
    [actions addObject:[self cancleAction]];
    return actions;
}

#pragma mark - JSQMessagesComposerTextViewPasteDelegate method
- (BOOL)composerTextView:(JSQMessagesComposerTextView *)textView shouldPasteWithSender:(id)sender
{
    if ([UIPasteboard generalPasteboard].image) {
        [self sendPhoto:[UIPasteboard generalPasteboard].image asJPEG:YES shouldResize:YES];
        
        return NO;
    } else {
        //trying to send file should be same as sending image without compression
        DDLogError(@"%@", [UIPasteboard generalPasteboard].pasteboardTypes);
        NSData *moreData = [[UIPasteboard generalPasteboard]dataForPasteboardType:@"com.adobe.pdf"];
        if (moreData) {
            //get first 4 bytes and run hexString() on it
            NSRange range = {0, 4};
            NSData *testdata = [moreData subdataWithRange:range];
            if (testdata) {
                NSString *teststring = [testdata hexString];
                NSString *testString2 = [[NSString alloc] initWithData:testdata encoding:NSUTF8StringEncoding];
                DDLogError(@"testing string %@ and %@", teststring, testString2);
                //if teststring 2 = %PDF, create PDF filename to use for upload
                if ([testString2 isEqualToString:@"%PDF"]) {
                    //create OTRFileItem with name
                    NSString *pdfname = @"test.pdf";
                    
                }
            }
            DDLogError(@"testing with length %lu", (unsigned long)[moreData length]);
        }
    }
    return YES;
}

- (void)didTapAvatar:(id<OTRMessageProtocol>)message sender:(id)sender {
    NSError *error =  [message messageError];
    NSString *title = nil;
    NSString *alertMessage = nil;
    
    NSString * sendingType = UNENCRYPTED_STRING();
    switch (self.state.messageSecurity) {
        case OTRMessageTransportSecurityOTR:
            sendingType = @"OTR";
            break;
        case OTRMessageTransportSecurityOMEMO:
            sendingType = @"OMEMO";
            break;
            
        default:
            break;
    }
    
    if ([message isKindOfClass:[OTROutgoingMessage class]]) {
        title = RESEND_MESSAGE_TITLE();
        alertMessage = [NSString stringWithFormat:RESEND_DESCRIPTION_STRING(),sendingType];
    }
    
    if (error && !error.isUserCanceledError) {
        NSUInteger otrFingerprintError = 32872;
        title = ERROR_STRING();
        alertMessage = error.localizedDescription;
        
        if (error.code == otrFingerprintError) {
            alertMessage = NO_DEVICES_BUDDY_ERROR_STRING();
        }
        
        if([message isKindOfClass:[OTROutgoingMessage class]]) {
            //If it's an outgoing message the error title should be that we were unable to send the message.
            title = UNABLE_TO_SEND_STRING();
            
            
            
            NSString *resendDescription = [NSString stringWithFormat:RESEND_DESCRIPTION_STRING(),sendingType];
            alertMessage = [alertMessage stringByAppendingString:[NSString stringWithFormat:@"\n%@",resendDescription]];
            
            //If this is an error about not having a trusted identity then we should offer to connect to the
            if (error.code == OTROMEMOErrorNoDevicesForBuddy ||
                error.code == OTROMEMOErrorNoDevices ||
                error.code == otrFingerprintError) {
                
                alertMessage = [alertMessage stringByAppendingString:[NSString stringWithFormat:@"\n%@",VIEW_PROFILE_DESCRIPTION_STRING()]];
            }
        }
    }
    
    
    if (![self isMessageTrusted:message]) {
        title = UNTRUSTED_DEVICE_STRING();
        if ([message isMessageIncoming]) {
            alertMessage = UNTRUSTED_DEVICE_REVEIVED_STRING();
        } else {
            alertMessage = UNTRUSTED_DEVICE_SENT_STRING();
        }
        alertMessage = [alertMessage stringByAppendingString:[NSString stringWithFormat:@"\n%@",VIEW_PROFILE_DESCRIPTION_STRING()]];
    }
    
    alertMessage = nil;
    NSArray <UIAlertAction*>*actions = [self actionForMessage:message];
    if ([actions count] > 1) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:alertMessage preferredStyle:UIAlertControllerStyleActionSheet];
        [actions enumerateObjectsUsingBlock:^(UIAlertAction * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [alertController addAction:obj];
        }];
        if ([sender isKindOfClass:[UIView class]]) {
            UIView *sourceView = sender;
            alertController.popoverPresentationController.sourceView = sourceView;
            alertController.popoverPresentationController.sourceRect = sourceView.bounds;
        }
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

- (BOOL)isMessageTrusted:(id <OTRMessageProtocol>)message {
    BOOL trusted = YES;
    if (![message isKindOfClass:[OTRBaseMessage class]]) {
        return trusted;
    }
    
    OTRBaseMessage *baseMessage = (OTRBaseMessage *)message;
    
    
    if (baseMessage.messageSecurityInfo.messageSecurity == OTRMessageTransportSecurityOTR) {
        NSData *otrFingerprintData = baseMessage.messageSecurityInfo.otrFingerprint;
        if ([otrFingerprintData length]) {
            trusted = [[OTRProtocolManager.encryptionManager otrFingerprintForKey:self.threadKey collection:self.threadCollection fingerprint:otrFingerprintData] isTrusted];
        }
    } else if (baseMessage.messageSecurityInfo.messageSecurity == OTRMessageTransportSecurityOMEMO) {
        NSString *omemoDeviceYapKey = baseMessage.messageSecurityInfo.omemoDeviceYapKey;
        NSString *omemoDeviceYapCollection = baseMessage.messageSecurityInfo.omemoDeviceYapCollection;
        __block OMEMODevice *device = nil;
        [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            device = [transaction objectForKey:omemoDeviceYapKey inCollection:omemoDeviceYapCollection];
        }];
        if(device != nil) {
            trusted = [device isTrusted];
        }
    }
    return trusted;
}

- (BOOL) isGroupChat {
    return [self.threadCollection isEqualToString:OTRXMPPRoom.collection];
}

#pragma - mark Profile Button Methods

- (void)setupInfoButton {
    if ([self isGroupChat]) {
        UIButton *pinButton = [UIButton buttonWithType:UIButtonTypeCustom];
        pinButton.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 4);
        pinButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 4);
        pinButton.translatesAutoresizingMaskIntoConstraints = NO;
        pinButton.frame = CGRectMake(0, 0, 48, 36);
        pinButton.titleLabel.font = [UIFont fontWithName:kFontAwesomeFont size:26];
        pinButton.titleLabel.textAlignment = NSTextAlignmentCenter;
        [pinButton setTintColor:[UIColor blackColor]];
        [pinButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [pinButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateHighlighted];
        [pinButton setTitle:[NSString fa_stringForFontAwesomeIcon:FAIconThumbTack] forState:UIControlStateNormal];
        [pinButton addTarget:self action:@selector(didSelectPushpinButton:) forControlEvents:UIControlEventTouchUpInside];
        UIBarButtonItem *pinItem = [[UIBarButtonItem alloc] initWithCustomView:pinButton];
        
        UIButton *groupButton = [UIButton buttonWithType:UIButtonTypeCustom];
        groupButton.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 0);
        groupButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 0);
        groupButton.translatesAutoresizingMaskIntoConstraints = NO;
        groupButton.frame = CGRectMake(0, 0, 64, 42);
        //[groupButton setTintColor:[UIColor blackColor]];
        //[groupButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        
        UIImage *origImage = [UIImage imageNamed:@"112-group" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil];
        UIImage *normalImage = [origImage jsq_imageMaskedWithColor:[UIColor blackColor]];
        UIImage *highlightedImage = [origImage jsq_imageMaskedWithColor:[UIColor lightGrayColor]];
        [groupButton setImage:normalImage forState:UIControlStateNormal];
        [groupButton setImage:highlightedImage forState:UIControlStateHighlighted];
        
        //[groupButton setImage:[UIImage imageNamed:@"112-group" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
        [groupButton addTarget:self action:@selector(didSelectOccupantsButton:) forControlEvents:UIControlEventTouchUpInside];
        UIBarButtonItem *groupItem = [[UIBarButtonItem alloc] initWithCustomView:groupButton];
        [groupItem setStyle:UIBarButtonItemStylePlain];
        
        //UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"112-group" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(didSelectOccupantsButton:)];
        //self.navigationItem.rightBarButtonItem = barButtonItem;
        
        //UIBarButtonItem *pinItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"pushpin" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(didSelectPushpinButton:)];
        
        NSArray *items = [NSArray arrayWithObjects:groupItem, pinItem, nil];
        self.navigationItem.rightBarButtonItems = items;
    } else {
        self.navigationItem.rightBarButtonItem = nil;
        self.navigationItem.rightBarButtonItems = nil;
    }
}

- (void) infoButtonPressed:(id)sender {
    __block OTRXMPPAccount *account = nil;
    __block OTRXMPPBuddy *buddy = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        account = [self accountWithTransaction:transaction];
        buddy = [self buddyWithTransaction:transaction];
    }];
    if (!account || !buddy) {
        return;
    }
    
    // Hack to manually re-fetch OMEMO devicelist because PEP sucks
    // TODO: Ideally this should be moved to some sort of manual refresh in the Profile view
    [self fetchOMEMODeviceList];
    
    KeyManagementViewController *verify = [GlobalTheme.shared keyManagementViewControllerForBuddy:buddy];
    if ([verify isKindOfClass:KeyManagementViewController.class]) {
        verify.completionBlock = ^{
            [self updateEncryptionState];
        };
    }
    UINavigationController *verifyNav = [[UINavigationController alloc] initWithRootViewController:verify];
    verifyNav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:verifyNav animated:YES completion:nil];
}

- (void)didSelectOccupantsButton:(id)sender {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"OTRRoomOccupants" bundle:[OTRAssets resourcesBundle]];
    OTRRoomOccupantsViewController *occupantsVC = [storyboard instantiateViewControllerWithIdentifier:@"roomOccupants"];
    occupantsVC.delegate = self;
    [occupantsVC setupViewHandlerWithDatabaseConnection:[OTRDatabaseManager sharedInstance].longLivedReadOnlyConnection roomKey:self.threadKey];
    [self.navigationController pushViewController:occupantsVC animated:YES];
}

- (void)didSelectPushpinButton:(id)sender {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"RoomAttachments" bundle:[OTRAssets resourcesBundle]];
    RoomAttachmentsViewController *attachmentsVC = [storyboard instantiateViewControllerWithIdentifier:@"roomAttachments"];
    [attachmentsVC setupRoomWithRoomKey:self.threadKey pinned:self.pins];
    [self.navigationController pushViewController:attachmentsVC animated:YES];
}

-(void) getPins {
    self.pins = nil;
    __block OTRXMPPManager *xmpp = nil;
    __block OTRXMPPRoom *room = nil;
    [self.connections.read asyncReadWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        xmpp = [self xmppManagerWithTransaction:transaction];
        room = [self roomWithTransaction:transaction];
    }completionBlock:^{
        if (xmpp != nil && room != nil) {
            [xmpp.fileTransferManager getAttachmentsWithMuc:room.roomJID userjid:xmpp.account.bareJID completion:^(XMPPPinned * _Nullable pinned, NSError * _Nullable error) {
                if (pinned == nil) {
                    if (error) {
                    DDLogError(@"Error getting pinned files: %@",error);
                    } else {
                        DDLogError(@"Error getting pinned files");
                    }
                    return;
                }
                self.pins = pinned;
            }];
        }
    }];
}

// Hack to manually re-fetch OMEMO devicelist because PEP sucks
// TODO: Ideally this should be moved to some sort of manual refresh in the Profile view
-(void) fetchOMEMODeviceList {
    __block OTRAccount *account = nil;
    __block OTRBuddy *buddy = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        account = [self accountWithTransaction:transaction];
        buddy = [self buddyWithTransaction:transaction];
    }]; 
    if (!account || !buddy || ([buddy isKindOfClass:[OTRXMPPBuddy class]] && [(OTRXMPPBuddy *)buddy pendingApproval])) {
        return;
    }
    id manager = [[OTRProtocolManager sharedInstance] protocolForAccount:account];
    if ([manager isKindOfClass:[OTRXMPPManager class]]) {
        XMPPJID *jid = [XMPPJID jidWithString:buddy.username];
        OTRXMPPManager *xmpp = manager;
        [xmpp.omemoSignalCoordinator.omemoModule fetchDeviceIdsForJID:jid elementId:nil];
    }
}

- (UIBarButtonItem *)rightBarButtonItem
{
    if (!self.lockBarButtonItem) {
        self.lockBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.lockButton];
    }
    return self.lockBarButtonItem;
}

-(void)updateEncryptionState
{
    if ([self isGroupChat]) {
        __block OTRXMPPManager *xmpp = nil;
        __block OTRMessageTransportSecurity messageSecurity = OTRMessageTransportSecurityInvalid;
        [self.connections.read asyncReadWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            xmpp = [self xmppManagerWithTransaction:transaction];
            OTRXMPPRoom *room = [self roomWithTransaction:transaction];
            messageSecurity = [room preferredTransportSecurityWithTransaction:transaction];
        } completionBlock:^{
            BOOL canSendMedia = YES;
            // Check for XEP-0363 HTTP upload
            // TODO: move this check elsewhere so it isnt dependent on refreshing crypto state
            if (xmpp != nil && xmpp.fileTransferManager.canUploadFiles) {
                canSendMedia = YES;
            }
            self.state.canSendMedia = canSendMedia;
            self.state.messageSecurity = messageSecurity;
            [self didUpdateState];
        }];
    } else {
        __block OTRBuddy *buddy = nil;
        __block OTRAccount *account = nil;
        __block OTRXMPPManager *xmpp = nil;
        __block OTRMessageTransportSecurity messageSecurity = OTRMessageTransportSecurityInvalid;
        
        [self.connections.read asyncReadWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            buddy = [self buddyWithTransaction:transaction];
            account = [buddy accountWithTransaction:transaction];
            xmpp = [self xmppManagerWithTransaction:transaction];
            messageSecurity = [buddy preferredTransportSecurityWithTransaction:transaction];
        } completionBlock:^{
            BOOL canSendMedia = YES;
            // Check for XEP-0363 HTTP upload
            // TODO: move this check elsewhere so it isnt dependent on refreshing crypto state
            if (xmpp != nil && xmpp.fileTransferManager.canUploadFiles) {
                canSendMedia = YES;
            }
            if (!buddy || !account || !xmpp || (messageSecurity == OTRMessageTransportSecurityInvalid)) {
                DDLogError(@"updateEncryptionState error: missing parameters");
            } else {
                OTRKitMessageState messageState = [OTRProtocolManager.encryptionManager.otrKit messageStateForUsername:buddy.username accountName:account.username protocol:account.protocolTypeString];
                if (messageState == OTRKitMessageStateEncrypted &&
                    buddy.status != OTRThreadStatusOffline) {
                    // If other side supports OTR, assume OTRDATA is possible
                    canSendMedia = YES;
                }
            }
            self.state.canSendMedia = canSendMedia;
            self.state.messageSecurity = messageSecurity;
            [self didUpdateState];
        }];
    }
}

- (void)setupAccessoryButtonsWithMessageState:(OTRKitMessageState)messageState buddyStatus:(OTRThreadStatus)status textViewHasText:(BOOL)hasText
{
    self.inputToolbar.contentView.rightBarButtonItem = self.sendButton;
    self.inputToolbar.sendButtonLocation = JSQMessagesInputSendButtonLocationRight;
    //self.inputToolbar.contentView.leftBarButtonItem = nil;
    self.inputToolbar.contentView.leftBarButtonItem = self.moreOptionsButton;
}

- (void)connectButtonPressed:(id)sender
{
    [self hideDropdownAnimated:YES completion:nil];
    __block OTRAccount *account = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        account = [self accountWithTransaction:transaction];
    }];
    
    if (account == nil) {
        return;
    }
    
    //If we have the password then we can login with that password otherwise show login UI to enter password
    if ([account.password length]) {
        [[OTRProtocolManager sharedInstance] loginAccount:account userInitiated:YES];
        
    } else {
        OTRBaseLoginViewController *loginViewController = [[OTRBaseLoginViewController alloc] initWithAccount:account];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:loginViewController];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:nav animated:YES completion:nil];
    }
    
    
}

#pragma - mark  dropDown Methods

- (void)showDropdownWithTitle:(NSString *)title buttons:(NSArray *)buttons animated:(BOOL)animated tag:(NSInteger)tag
{
    NSTimeInterval duration = 0.3;
    if (!animated) {
        duration = 0.0;
    }
    
    self.buttonDropdownView = [[OTRButtonView alloc] initWithTitle:title buttons:buttons];
    self.buttonDropdownView.tag = tag;
    
    CGFloat height = [OTRButtonView heightForTitle:title width:self.view.bounds.size.width buttons:buttons];
    
    [self.view addSubview:self.buttonDropdownView];
    
    [self.buttonDropdownView autoSetDimension:ALDimensionHeight toSize:height];
    [self.buttonDropdownView autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [self.buttonDropdownView autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    self.buttonDropdownView.topLayoutConstraint = [self.buttonDropdownView autoPinToTopLayoutGuideOfViewController:self withInset:height*-1];
    
    [self.buttonDropdownView layoutIfNeeded];
    
    [UIView animateWithDuration:duration animations:^{
        self.buttonDropdownView.topLayoutConstraint.constant = 0.0;
        [self.buttonDropdownView layoutIfNeeded];
    } completion:nil];
    
}

- (void)hideDropdownAnimated:(BOOL)animated completion:(void (^)(void))completion
{
    if (!self.buttonDropdownView) {
        if (completion) {
            completion();
        }
    }
    else {
        NSTimeInterval duration = 0.3;
        if (!animated) {
            duration = 0.0;
        }
        
        [UIView animateWithDuration:duration animations:^{
            CGFloat height = self.buttonDropdownView.frame.size.height;
            self.buttonDropdownView.topLayoutConstraint.constant = height*-1;
            [self.buttonDropdownView layoutIfNeeded];
            
        } completion:^(BOOL finished) {
            if (finished) {
                [self.buttonDropdownView removeFromSuperview];
                self.buttonDropdownView = nil;
            }
            
            if (completion) {
                completion();
            }
        }];
    }
}

- (void)saveCurrentMessageText:(NSString *)text threadKey:(NSString *)key colleciton:(NSString *)collection
{
    if (![key length] || ![collection length]) {
        return;
    }
    
    [self.connections.write asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        id <OTRThreadOwner> thread = [[transaction objectForKey:key inCollection:collection] copy];
        if (thread == nil) {
            // this can happen when we've just approved a contact, then the thread key
            // might have changed.
            return;
        }
        [thread setCurrentMessageText:text];
        [transaction setObject:thread forKey:key inCollection:collection];
        
        //Send inactive chat State
        OTRAccount *account = [OTRAccount fetchObjectWithUniqueID:[thread threadAccountIdentifier] transaction:transaction];
        OTRXMPPManager *xmppManager = (OTRXMPPManager *)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
        if (![text length]) {
            [xmppManager sendChatState:OTRChatStateInactive withBuddyID:[thread threadIdentifier]];
        }
    }];
}

//* Takes the current value out of the thread object and sets it to the text view and nils out result*/
- (void)moveLastComposingTextForThreadKey:(NSString *)key colleciton:(NSString *)collection toTextView:(UITextView *)textView {
    if (![key length] || ![collection length] || !textView) {
        return;
    }
    __block id <OTRThreadOwner> thread = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        thread = [[transaction objectForKey:key inCollection:collection] copy];
    }];
    // Don't remove text you're already composing
    NSString *oldThreadText = [thread currentMessageText];
    if (!textView.text.length && oldThreadText.length) {
        textView.text = oldThreadText;
        [self receivedTextViewChanged:textView];
    }
    if (oldThreadText.length) {
        [thread setCurrentMessageText:nil];
        [self.connections.write asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            [transaction setObject:thread forKey:key inCollection:collection];
        }];
        
        self.state.hasText = YES;
    }
}

- (id <OTRMessageProtocol,JSQMessageData>)messageAtIndexPath:(NSIndexPath *)indexPath
{
    // Multiple invocations with the same indexPath tend to come in groups, no need to hit the DB each time.
    // Even though the object is cached, the row ID calculation still takes time
    if (![indexPath isEqual:self.currentIndexPath]) {
        self.currentIndexPath = indexPath;
        self.currentMessage = [self.viewHandler object:indexPath];
    }
    return self.currentMessage;
}

/**
 * Updates the flexible range of the DB connection.
 * @param reset When NO, adds kOTRMessagePageSize to the range length, when YES resets the length to the kOTRMessagePageSize
 */
- (void)updateRangeOptions:(BOOL)reset
{
    YapDatabaseViewRangeOptions *options = [self.viewHandler.mappings rangeOptionsForGroup:self.threadKey];
    if (reset) {
        if (options != nil && !self.messageRangeExtended) {
            return;
        }
        options = [YapDatabaseViewRangeOptions flexibleRangeWithLength:kOTRMessagePageSize
                                                                offset:0
                                                                  from:YapDatabaseViewEnd];
        self.messageSizeCache.countLimit = kOTRMessagePageSize;
        self.messageRangeExtended = NO;
    } else {
        options = [options copyWithNewLength:options.length + kOTRMessagePageSize];
        self.messageSizeCache.countLimit += kOTRMessagePageSize;
        self.messageRangeExtended = YES;
    }
    [self.viewHandler.mappings setRangeOptions:options forGroup:self.threadKey];
    
    self.loadingMessages = YES;
    
    CGFloat distanceToBottom = self.collectionView.contentSize.height - self.collectionView.contentOffset.y;
    
    [self.collectionView reloadData];
    
    __block NSUInteger shownCount;
    __block NSUInteger totalCount;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        shownCount = [self.viewHandler.mappings numberOfItemsInGroup:self.threadKey];
        totalCount = [[transaction ext:OTRFilteredChatDatabaseViewExtensionName] numberOfItemsInGroup:self.threadKey];
    }];
    [self setShowLoadEarlierMessagesHeader:shownCount < totalCount];
    
    if (!reset) {
        // see https://github.com/ChatSecure/ChatSecure-iOS/issues/817
        //[self.collectionView.collectionViewLayout invalidateLayout];
        [self.collectionView layoutSubviews];
        self.collectionView.contentOffset = CGPointMake(0, self.collectionView.contentSize.height - distanceToBottom);
    }
    
    self.loadingMessages = NO;
}

- (BOOL)showDateAtIndexPath:(NSIndexPath *)indexPath
{
    BOOL showDate = NO;
    id <OTRMessageProtocol> currentMessage = [self messageAtIndexPath:indexPath];
    if (indexPath.row == 0) {
        showDate = YES;
    }
    else {
        id <OTRMessageProtocol> previousMessage = [self messageAtIndexPath:[NSIndexPath indexPathForItem:indexPath.row-1 inSection:indexPath.section]];
        
        NSTimeInterval timeDifference = [[currentMessage messageDate] timeIntervalSinceDate:[previousMessage messageDate]];
        if (timeDifference > kOTRMessageSentDateShowTimeInterval) {
            showDate = YES;
        }
    }
    
    if ([currentMessage isKindOfClass:[OTRXMPPRoomMessage class]]) {
        return showDate;
    }
    
    return NO;
}

- (BOOL)showSenderDisplayNameAtIndexPath:(NSIndexPath *)indexPath {
    id<OTRMessageProtocol,JSQMessageData> message = [self messageAtIndexPath:indexPath];
    
    if(![self.threadCollection isEqualToString:[OTRXMPPRoom collection]]) {
        return NO;
    }
    
    if ([self isOutgoingMessage:message]) {
        return NO;
    }
    
    if ([self isMemberUpdateMessageAtIndexPath:indexPath]) {
        return NO;
    }
    
    return YES;
}

- (BOOL)isPushMessageAtIndexPath:(NSIndexPath *)indexPath {
    id message = [self messageAtIndexPath:indexPath];
    return [message isKindOfClass:[PushMessage class]];
}

- (BOOL)isMemberUpdateMessageAtIndexPath:(NSIndexPath *)indexPath {
    id message = [self messageAtIndexPath:indexPath];
    return [self isMemberUpdateMessage:message];
}

- (BOOL)isMemberUpdateMessage:(id <OTRMessageProtocol>)message {
    if ([message isKindOfClass:[OTRXMPPRoomMessage class]]) {
        OTRXMPPRoomMessage *xmessage = (OTRXMPPRoomMessage *)message;
        return xmessage.memberUpdate;
    }
    return NO;
}

- (BOOL)isFailedDecryptAtIndexPath:(NSIndexPath *)indexPath {
    id message = [self messageAtIndexPath:indexPath];
    return [self isFailedDecryptMessage:message];
}

- (BOOL)isFailedDecryptMessage:(id <OTRMessageProtocol>)message {
    if ([[message messageText] hasPrefix:@"Couldn't decrypt"]) {
        return YES;
    }
    return NO;
}

- (void) resetOptionsButton {
    [self.hourglassButton removeFromSuperview];
    [self.microphoneButton removeFromSuperview];
    [self.attachButton removeFromSuperview];
    self.inputToolbar.contentView.leftBarButtonItem = self.moreOptionsButton;
}

- (void)receivedTextViewChangedNotification:(NSNotification *)notification
{
    [self resetOptionsButton];
    
    //Check if the text state changes from having some text to some or vice versa
    UITextView *textView = notification.object;
    [self receivedTextViewChanged:textView];
}

- (void)receivedTextViewChanged:(UITextView *)textView {
    BOOL hasText = [textView.text length] > 0;
    if(hasText != self.state.hasText) {
        self.state.hasText = hasText;
        [self didUpdateState];
    } else {
        [self disableButtonsIfUnconnected];
        //Need to make sure this doesn't slow down the GUI, checking every keystroke
    }
    
    //Everytime the textview has text and a notification comes through we are 'typing' otherwise we are done typing
    if (hasText) {
        [self isTyping];
    } else {
        [self didFinishTyping];
    }
    
    return;

}

// if not connected, disable right and left buttons
- (void) disableButtonsIfUnconnected {
    __block OTRAccount *account = nil;
    [self.connections.read readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        account =  [self accountWithTransaction:transaction];
    }];
    if (account != nil) {
        if ([[OTRProtocolManager sharedInstance] existsProtocolForAccount:account]) {
            if (![[OTRProtocolManager sharedInstance] isAccountConnected:account]) {
                self.inputToolbar.contentView.leftBarButtonItem.enabled = NO;
                self.inputToolbar.contentView.rightBarButtonItem.enabled = NO;
            }
        } else {
            self.inputToolbar.contentView.leftBarButtonItem.enabled = NO;
            self.inputToolbar.contentView.rightBarButtonItem.enabled = NO;
        }
    }
}

#pragma - mark Update UI

- (void)didUpdateState {
    
}

- (void)isTyping {
    
}

- (void)didFinishTyping {
    
}

#pragma - mark Sending Media Items

- (void)sendMediaItem:(OTRMediaItem *)mediaItem data:(NSData *)data message:(id<OTRMessageProtocol>)message transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    id<OTRThreadOwner> thread = [self threadObjectWithTransaction:transaction];
    OTRXMPPManager *xmpp = [self xmppManagerWithTransaction:transaction];
    if (!message || !thread || !xmpp) {
        DDLogError(@"Error sending file due to bad paramters");
        return;
    }
    if (data) {
        thread.lastMessageIdentifier = message.messageKey;
        [thread saveWithTransaction:transaction];
    }
    // XEP-0363
    [xmpp.fileTransferManager sendWithMediaItem:mediaItem prefetchedData:data message:message];
    
    [mediaItem touchParentMessageWithTransaction:transaction];
}

/**
 Called when the image viewer detects a long press.
 */
- (void)imageViewerDidLongPress:(JTSImageViewController *)imageViewer atRect:(CGRect)rect {
    // implemented in JTSImageViewController, this just lets it know Save is allowed
}

#pragma - mark Media Display Methods

- (void)showImage:(OTRImageItem *)imageItem fromCollectionView:(JSQMessagesCollectionView *)collectionView atIndexPath:(NSIndexPath *)indexPath
{
    //FIXME: Possible for image to not be in cache?
    UIImage *image = [OTRImages imageWithIdentifier:imageItem.uniqueId];
    JTSImageInfo *imageInfo = [[JTSImageInfo alloc] init];
    imageInfo.image = image;
    
    UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
    if ([cell isKindOfClass:[JSQMessagesCollectionViewCell class]]) {
        UIView *cellContainterView = ((JSQMessagesCollectionViewCell *)cell).messageBubbleContainerView;
        imageInfo.referenceRect = cellContainterView.bounds;
        imageInfo.referenceView = cellContainterView;
        imageInfo.referenceCornerRadius = 10;
    }
    
    JTSImageViewController *imageViewer = [[JTSImageViewController alloc]
                                           initWithImageInfo:imageInfo
                                           mode:JTSImageViewControllerMode_Image
                                           backgroundStyle:JTSImageViewControllerBackgroundOption_Blurred];
    imageViewer.interactionsDelegate = self;
    
    [imageViewer showFromViewController:self transition:JTSImageViewControllerTransition_FromOriginalPosition];
}

- (void)showVideo:(OTRVideoItem *)videoItem fromCollectionView:(JSQMessagesCollectionView *)collectionView atIndexPath:(NSIndexPath *)indexPath
{
    if (videoItem.filename) {
        NSURL *videoURL = [[OTRMediaServer sharedInstance] urlForMediaItem:videoItem buddyUniqueId:self.threadKey];
        AVPlayer *player = [[AVPlayer alloc] initWithURL:videoURL];
        AVPlayerViewController *moviePlayerViewController = [[AVPlayerViewController alloc] init];
        moviePlayerViewController.player = player;
        [self presentViewController:moviePlayerViewController animated:YES completion:nil];
    }
}

- (void)showFile:(OTRFileItem *)fileItem fromCollectionView:(JSQMessagesCollectionView *)collectionView atIndexPath:(NSIndexPath *)indexPath
{
    if (fileItem.filename) {
        NSURL *fileURL = [[OTRMediaServer sharedInstance] urlForMediaItem:fileItem buddyUniqueId:self.threadKey];

        RoomAttachmentWebViewController *webview = [[RoomAttachmentWebViewController alloc] initWithUrl:fileURL data:nil baseurl:fileURL.URLByDeletingPathExtension];
        
        if (webview != nil) {
            [self.navigationController pushViewController:webview animated:YES];
        }
    }
}

- (void)playOrPauseAudio:(OTRAudioItem *)audioItem fromCollectionView:(JSQMessagesCollectionView *)collectionView atIndexPath:(NSIndexPath *)indexPath
{
    NSError *error = nil;
    if  ([audioItem.uniqueId isEqualToString:self.audioPlaybackController.currentAudioItem.uniqueId]) {
        if  ([self.audioPlaybackController isPlaying]) {
            [self.audioPlaybackController pauseCurrentlyPlaying];
        }
        else {
            [self.audioPlaybackController resumeCurrentlyPlaying];
        }
    }
    else {
        [self.audioPlaybackController stopCurrentlyPlaying];
        OTRAudioControlsView *audioControls = [self audioControllsfromCollectionView:collectionView atIndexPath:indexPath];
        [self.audioPlaybackController attachAudioControlsView:audioControls];
        [self.audioPlaybackController playAudioItem:audioItem buddyUniqueId:self.threadKey error:&error];
    }
    
    if (error) {
         DDLogError(@"Audio Playback Error: %@",error);
    }
   
}

- (OTRAudioControlsView *)audioControllsfromCollectionView:(JSQMessagesCollectionView *)collectionView atIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
    if ([cell isKindOfClass:[JSQMessagesCollectionViewCell class]]) {
        UIView *mediaView = ((JSQMessagesCollectionViewCell *)cell).mediaView;
        UIView *view = [mediaView viewWithTag:kOTRAudioControlsViewTag];
        if ([view isKindOfClass:[OTRAudioControlsView class]]) {
            return (OTRAudioControlsView *)view;
        }
    }
    
    return nil;
}

#pragma MARK - OTRMessagesCollectionViewFlowLayoutSizeProtocol methods

- (BOOL)hasBubbleSizeForCellAtIndexPath:(NSIndexPath *)indexPath {
    BOOL hasBubble = YES;
    if ([self isPushMessageAtIndexPath:indexPath] || [self isMemberUpdateMessageAtIndexPath:indexPath]) {
        hasBubble = NO;
    }
    return hasBubble;
}

#pragma mark - JSQMessagesViewController method overrides

- (BOOL)isOutgoingMessage:(id<JSQMessageData>)messageItem
{
    __block BOOL outgoing = [super isOutgoingMessage:messageItem];
    if (messageItem.isMediaMessage) {
        NSString *displayOut = messageItem.senderDisplayName;
        if (displayOut == nil) {
            return outgoing;
        }
        
        [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            OTRXMPPAccount *account = [self accountWithTransaction:transaction];
            id<OTRThreadOwner> thread = [self threadObjectWithTransaction:transaction];
            if (!thread.isGroupThread) {
                if ([messageItem.text hasPrefix:@"https"] || [messageItem.text hasPrefix:@"aesgcm"]) {
                    NSURL* url = [NSURL URLWithString:messageItem.text];
                    NSString* name = url.pathComponents[1];
                    if (account != nil && name != nil &&
                        ([account.displayName isEqualToString:name] ||
                         [account.bareJID.user isEqualToString:name])) {
                            outgoing = YES;
                    }
                }
            } else if (account != nil &&
                ([account.displayName isEqualToString:displayOut] ||
                 [account.bareJID.user isEqualToString:displayOut])) {
                    outgoing = YES;
            }
        }];
    }
    
    return outgoing;
}

- (UICollectionViewCell *)collectionView:(JSQMessagesCollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *)[super collectionView:collectionView cellForItemAtIndexPath:indexPath];
    
    if ([self isFailedDecryptAtIndexPath:indexPath]) {
        cell.textView.attributedText = [[NSAttributedString alloc] initWithString:cell.textView.text attributes:@{ NSFontAttributeName : collectionView.collectionViewLayout.italicMessageBubbleFont }];
    }
    
    //Fixes times when there needs to be two lines (date & knock sent) and doesn't seem to affect one line instances
    cell.cellTopLabel.numberOfLines = 0;
    
    id <OTRMessageProtocol>message = [self messageAtIndexPath:indexPath];
    
    __block OTRXMPPAccount *account = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        account = (OTRXMPPAccount*)[self accountWithTransaction:transaction];
    }];
    
    UIColor *textColor = nil;
    if ([message isMessageIncoming]) {
        textColor = [UIColor blackColor];
    }
    else {
        textColor = [UIColor whiteColor];
    }
    if (cell.textView != nil)
        cell.textView.textColor = textColor;

	// Do not allow clickable links for Tor accounts to prevent information leakage
    // Could be better to move this information to the message object to not need to do a database read.
    if ([account isKindOfClass:[OTRXMPPTorAccount class]]) {
        cell.textView.dataDetectorTypes = UIDataDetectorTypeNone;
    }
    else {
        cell.textView.dataDetectorTypes = UIDataDetectorTypeLink;
        cell.textView.linkTextAttributes = @{ NSForegroundColorAttributeName : textColor,
                                              NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid) };
    }
    
    if ([[message messageMediaItemKey] isEqualToString:self.audioPlaybackController.currentAudioItem.uniqueId]) {
        UIView *view = [cell.mediaView viewWithTag:kOTRAudioControlsViewTag];
        if ([view isKindOfClass:[OTRAudioControlsView class]]) {
            [self.audioPlaybackController attachAudioControlsView:(OTRAudioControlsView *)view];
        }
    }
    
    // Needed for link interaction
    cell.textView.delegate = self;
    return cell;
}

- (BOOL)collectionView:(UICollectionView *)collectionView canPerformAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    if (action == @selector(delete:)) {
        return YES;
    }
    
    return [super collectionView:collectionView canPerformAction:action forItemAtIndexPath:indexPath withSender:sender];
}

- (void)didPressSendButton:(UIButton *)button withMessageText:(NSString *)text senderId:(NSString *)senderId senderDisplayName:(NSString *)senderDisplayName date:(NSDate *)date
{
    if(!text.length) {
        return;
    }
    
    self.navigationController.providesPresentationContextTransitionStyle = YES;
    self.navigationController.definesPresentationContext = YES;
    
    //0. Clear out message text immediately
    //   This is to prevent the scenario where multiple messages get sent because the message text isn't cleared out
    //   due to aggregated touch events during UI pauses.
    //   A side effect is that sent messages may not appear in the UI immediately
    [self finishSendingMessage];
    
    __block id<OTRMessageProtocol> message = nil;
    __block OTRXMPPManager *xmpp = nil;
    __block OTROutgoingMessage *outgoingMessage = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        id<OTRThreadOwner> thread = [self threadObjectWithTransaction:transaction];
        message = [thread outgoingMessageWithText:text transaction:transaction];
        
        if ([message isKindOfClass:[OTROutgoingMessage class]]) {
            outgoingMessage = (OTROutgoingMessage *)message;
            if (thread.expiresIn) {
                outgoingMessage.expires = thread.expiresIn;
            } else {
                NSString *gtime = [OTRSettingsManager stringForOTRSettingKey:@"globalTimer"];
                if (gtime != nil && ![gtime isEqualToString:@"Off"]) {
                    outgoingMessage.expires = gtime;
                }
            }
        }
        
        xmpp = [self xmppManagerWithTransaction:transaction];
    }];
    if (!message || !xmpp) { return; }
    
    if (outgoingMessage) {
        [xmpp enqueueMessage:outgoingMessage];
    } else {
        [xmpp enqueueMessage:message];
    }
}

- (void)didPressAccessoryButton:(UIButton *)sender
{
    if ([sender isEqual:self.cameraButton]) {
        [self.attachmentPicker showAlertControllerFromSourceView:sender withCompletion:nil];
    } else if ([sender isEqual:self.attachButton]) {
        [self.attachmentPicker showAlertControllerFromSourceView:sender withCompletion:nil];
    }
}

- (void)collectionView:(UICollectionView *)collectionView performAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    if (action == @selector(delete:)) {
        [self deleteMessageAtIndexPath:indexPath];
    }
    else {
        [super collectionView:collectionView performAction:action forItemAtIndexPath:indexPath withSender:sender];
    }
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    id <OTRMessageProtocol, JSQMessageData> message = [self messageAtIndexPath:indexPath];

    NSNumber *key = @(message.messageHash);
    NSValue *sizeValue = [self.messageSizeCache objectForKey:key];
    if (sizeValue != nil) {
        return [sizeValue CGSizeValue];
    }

    // Although JSQMessagesBubblesSizeCalculator has its own cache, its size is fixed and quite small, so it quickly chokes on scrolling into the past
    CGSize size = [super collectionView:collectionView layout:collectionViewLayout sizeForItemAtIndexPath:indexPath];
    // The height of the first cell might change: on loading additional messages the date label most likely will disappear
    if (indexPath.row > 0) {
        [self.messageSizeCache setObject:[NSValue valueWithCGSize:size] forKey:key];
    }
    return size;
}

#pragma - mark UIPopoverPresentationControllerDelegate Methods

- (void)prepareForPopoverPresentation:(UIPopoverPresentationController *)popoverPresentationController {
    // Without setting this, there will be a crash on iPad
    // This delegate is set in the OTRAttachmentPicker
    popoverPresentationController.sourceView = self.attachButton;
}

- (void)sendPhoto:(UIImage *)photo asJPEG:(BOOL)asJPEG shouldResize:(BOOL)shouldResize {
    NSParameterAssert(photo);
    if (!photo) { return; }
    
    __block OTRXMPPManager *xmpp = nil;
    __block id<OTRThreadOwner> thread = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        xmpp = [self xmppManagerWithTransaction:transaction];
        thread = [self threadObjectWithTransaction:transaction];
    }];
    NSParameterAssert(xmpp);
    NSParameterAssert(thread);
    if (!xmpp || !thread) { return; }

    [xmpp.fileTransferManager sendWithImage:photo thread:thread];
}

#pragma - mark OTRAttachmentPickerDelegate Methods

- (void)attachmentPicker:(OTRAttachmentPicker *)attachmentPicker gotPhoto:(UIImage *)photo withInfo:(NSDictionary *)info
{
    [self sendPhoto:photo asJPEG:YES shouldResize:YES];
}

- (void)attachmentPicker:(OTRAttachmentPicker *)attachmentPicker gotVideoURL:(NSURL *)videoURL
{
    if (!videoURL) { return; }
    __block OTRXMPPManager *xmpp = nil;
    __block id<OTRThreadOwner> thread = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        xmpp = [self xmppManagerWithTransaction:transaction];
        thread = [self threadObjectWithTransaction:transaction];
    }];
    NSParameterAssert(xmpp);
    NSParameterAssert(thread);
    if (!xmpp || !thread) { return; }

    [xmpp.fileTransferManager sendWithVideoURL:videoURL thread:thread];
}

- (NSArray <NSString *>*)attachmentPicker:(OTRAttachmentPicker *)attachmentPicker preferredMediaTypesForSource:(UIImagePickerControllerSourceType)source
{
    return @[(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie];
}

- (void)sendAudioFileURL:(NSURL *)url
{
    if (!url) { return; }
    __block OTRXMPPManager *xmpp = nil;
    __block id<OTRThreadOwner> thread = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        xmpp = [self xmppManagerWithTransaction:transaction];
        thread = [self threadObjectWithTransaction:transaction];
    }];
    NSParameterAssert(xmpp);
    NSParameterAssert(thread);
    if (!xmpp || !thread) { return; }
    
    [xmpp.fileTransferManager sendWithAudioURL:url thread:thread];
}

- (void)sendImageFilePath:(NSString *)filePath asJPEG:(BOOL)asJPEG shouldResize:(BOOL)shouldResize
{
    [self sendPhoto:[UIImage imageWithContentsOfFile:filePath] asJPEG:asJPEG shouldResize:shouldResize];
}

- (void)attachmentPicker:(OTRAttachmentPicker *)attachmentPicker gotFileURL:(NSURL *)fileURL
{
    if (!fileURL) { return; }
    __block OTRXMPPManager *xmpp = nil;
    __block id<OTRThreadOwner> thread = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        xmpp = [self xmppManagerWithTransaction:transaction];
        thread = [self threadObjectWithTransaction:transaction];
    }];
    NSParameterAssert(xmpp);
    NSParameterAssert(thread);
    if (!xmpp || !thread) { return; }
    
    [xmpp.fileTransferManager sendWithFileURL:fileURL thread:thread];
}


#pragma - mark UIScrollViewDelegate Methods

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [self hideDropdownAnimated:YES completion:nil];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (!self.loadingMessages && ![scrollView isMemberOfClass:[JSQMessagesComposerTextView class]]) {
        UIEdgeInsets insets = scrollView.contentInset;
        CGFloat highestOffset = -insets.top;
        CGFloat lowestOffset = scrollView.contentSize.height - scrollView.frame.size.height + insets.bottom;
        CGFloat pos = scrollView.contentOffset.y;

        if (self.showLoadEarlierMessagesHeader && (pos == highestOffset || (pos < 0 && (scrollView.isDecelerating || scrollView.isDragging)))) {
            [self updateRangeOptions:NO];
        } else if (pos == lowestOffset) {
            [self updateRangeOptions:YES];
        }
    }
}

#pragma mark - UICollectionView DataSource
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    NSInteger numberOfMessages = [self.viewHandler.mappings numberOfItemsInSection:section];
    return numberOfMessages;
}

#pragma - mark JSQMessagesCollectionViewDataSource Methods

- (NSString *)senderDisplayName
{
    __block OTRAccount *account = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        account = [self accountWithTransaction:transaction];
    }];
    
    NSString *senderDisplayName = @"";
    if (account) {
        if ([account.displayName length]) {
            senderDisplayName = account.displayName;
        } else {
            senderDisplayName = account.username;
        }
    }
    
    return senderDisplayName;
}

- (id<JSQMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView messageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return (id <JSQMessageData>)[self messageAtIndexPath:indexPath];
}

- (id<JSQMessageBubbleImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView messageBubbleImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    id <OTRMessageProtocol> message = [self messageAtIndexPath:indexPath];
    JSQMessagesBubbleImage *image = nil;
    if ([message isMessageIncoming]) {
        image = self.incomingBubbleImage;
    }
    else {
        image = self.outgoingBubbleImage;
    }
    return image;
}

- (id <JSQMessageAvatarImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView avatarImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    id <OTRMessageProtocol,JSQMessageData> message = [self messageAtIndexPath:indexPath];
    if ([message isKindOfClass:[PushMessage class]] || [self isMemberUpdateMessage:message]) {
        return nil;
    }
    
    NSError *messageError = [message messageError];
    if ((messageError && !messageError.isAutomaticDownloadError && !messageError.isUserCanceledError) ||
        ![self isMessageTrusted:message]) {
        return [self warningAvatarImage];
    }
    
    if ([self isOutgoingMessage:message]) {
        return [self accountAvatarImage];
    }
    
    if ([message isKindOfClass:[OTRXMPPRoomMessage class]]) {
        OTRXMPPRoomMessage *roomMessage = (OTRXMPPRoomMessage *)message;
        __block OTRXMPPRoomOccupant *roomOccupant = nil;
        __block OTRXMPPBuddy *roomOccupantBuddy = nil;
        [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
            if (roomMessage.buddyUniqueId) {
                roomOccupantBuddy = [OTRXMPPBuddy fetchObjectWithUniqueID:roomMessage.buddyUniqueId transaction:transaction];
            }
            if (!roomOccupantBuddy) {
                roomOccupant = [OTRXMPPRoomOccupant occupantWithJid:[XMPPJID jidWithString:roomMessage.senderJID] realJID:nil roomJID:[XMPPJID jidWithString:roomMessage.roomJID] accountId:[self accountWithTransaction:transaction].uniqueId createIfNeeded:NO transaction:transaction];
                if (roomOccupant != nil) {
                    roomOccupantBuddy = [roomOccupant buddyWith:transaction];
                }
            }
        }];
        UIImage *avatarImage = nil;
        if (roomOccupantBuddy != nil) {
            avatarImage = [roomOccupantBuddy avatarImage];
        }
        if (!avatarImage && roomOccupant) {
            avatarImage = [roomOccupant avatarImage];
        }
        if (!avatarImage && roomMessage.senderJID) {
            XMPPJID *jid = [XMPPJID jidWithString:roomMessage.senderJID];
            NSString *resource = jid.resource;
            if (resource.length > 0) {
                avatarImage = [OTRImages avatarImageWithUsername:resource];
            } else {
                // this message probably came from the room itself
                return nil;
            }
        }
        if (avatarImage) {
            NSUInteger diameter = MIN(avatarImage.size.width, avatarImage.size.height);
            return [JSQMessagesAvatarImageFactory avatarImageWithImage:avatarImage diameter:diameter];
        }
        return nil;
    }
    
    /// For 1:1 buddy
    if ([message isMessageIncoming]) {
        return [self buddyAvatarImage];
    }

    return [self accountAvatarImage];
}

- (JSQMessagesAvatarImage *)createAvatarImage:(UIImage *(^)(YapDatabaseReadTransaction *))getImage
{
    __block UIImage *avatarImage;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        avatarImage = getImage(transaction);
    }];
    if (avatarImage != nil) {
        NSUInteger diameter = (NSUInteger) MIN(avatarImage.size.width, avatarImage.size.height);
        return [JSQMessagesAvatarImageFactory avatarImageWithImage:avatarImage diameter:diameter];
    }
    return nil;
}

- (JSQMessagesAvatarImage *)warningAvatarImage
{
    if (_warningAvatarImage == nil) {
        _warningAvatarImage = [self createAvatarImage:^(YapDatabaseReadTransaction *transaction) {
            return [OTRImages circleWarningWithColor:[OTRColors warnColor]];
        }];
    }
    return _warningAvatarImage;
}

- (JSQMessagesAvatarImage *)accountAvatarImage
{
    if (_accountAvatarImage == nil) {
        _accountAvatarImage = [self createAvatarImage:^(YapDatabaseReadTransaction *transaction) {
            return [[self accountWithTransaction:transaction] avatarImage];
        }];
    }
    return _accountAvatarImage;
}

- (JSQMessagesAvatarImage *)buddyAvatarImage
{
    if (_buddyAvatarImage == nil) {
        _buddyAvatarImage = [self createAvatarImage:^(YapDatabaseReadTransaction *transaction) {
            return [[self buddyWithTransaction:transaction] avatarImage];
        }];
    }
    return _buddyAvatarImage;
}

////// Optional //////

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
    
    if ([self showDateAtIndexPath:indexPath]) {
        id <OTRMessageProtocol> message = [self messageAtIndexPath:indexPath];
        NSDate *date = [message messageDate];
        if (date != nil) {
            [text appendAttributedString: [[JSQMessagesTimestampFormatter sharedFormatter] attributedTimestampForDate:date]];
        }
    }
    
    if ([self isPushMessageAtIndexPath:indexPath]) {
        JSQMessagesTimestampFormatter *formatter = [JSQMessagesTimestampFormatter sharedFormatter];
        NSString *knockString = KNOCK_SENT_STRING();
        //Add new line if there is already a date string
        if ([text length] > 0) {
            knockString = [@"\n" stringByAppendingString:knockString];
        }
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:knockString attributes:formatter.dateTextAttributes]];
    }
    
    if ([self isMemberUpdateMessageAtIndexPath:indexPath]) {
        id <OTRMessageProtocol> message = [self messageAtIndexPath:indexPath];
        NSString *updateString = message.messageOriginalText;
        if (updateString != nil) {
            updateString = [self getFormattedMemberUpdate:updateString];
            if ([text length] > 0 && updateString != nil) {
                updateString = [@"\n" stringByAppendingString:updateString];
            }
            [text appendAttributedString:[[NSAttributedString alloc] initWithString:updateString attributes:[JSQMessagesTimestampFormatter sharedFormatter].dateTextAttributes]];
        }
    }
    
    return text;
}

- (NSString *) getFormattedMemberUpdate:(NSString *)updateString {
    if ([updateString length] < 50) {
        return updateString;
    }
    
    NSMutableString *resultString = [[NSMutableString alloc] init];
    NSMutableString *currentLine = [[NSMutableString alloc] init];
    NSScanner *scanner = [NSScanner scannerWithString:updateString];
    NSString *scannedString = nil;
    while ([scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &scannedString]) {
        if ([currentLine length] + [scannedString length] <= 45) {
            [currentLine appendFormat:@"%@ ", scannedString];
        } else { // Need to break line and start new one
            [resultString appendFormat:@"%@\n", currentLine];
            [currentLine setString:[NSString stringWithFormat:@"%@ ", scannedString]];
        }
        [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
    }
    if ([currentLine length] > 0) {
        [resultString appendFormat:@"%@", currentLine];
    }
    return resultString;
}


- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    return  nil;
}

/** Currently uses clock for queued, and checkmark for delivered. */
- (nullable NSAttributedString*) deliveryStatusStringForMessage:(nonnull id<OTRMessageProtocol>)message {
    if (!message) { return nil; }
    // Only applies to outgoing messages
    if ([message isMessageIncoming]) {
        return nil;
    }
    NSString *deliveryStatusString = nil;
    if(message.isMessageSent == NO && ![message messageMediaItemKey]) {
        // Waiting to send message. This message is in the queue.
        deliveryStatusString = [NSString fa_stringForFontAwesomeIcon:FAIconClockO];
    } else if (message.isMessageDelivered){
        deliveryStatusString = [NSString stringWithFormat:@"%@ ",[NSString fa_stringForFontAwesomeIcon:FAIconCheck]];
    }
    if (deliveryStatusString != nil) {
        UIFont *font = [UIFont fontWithName:kFontAwesomeFont size:12];
        if (!font) {
            font = [UIFont systemFontOfSize:12];
        }
        return [[NSAttributedString alloc] initWithString:deliveryStatusString attributes:@{NSFontAttributeName: font}];
    }
    return nil;
}

- (nullable NSAttributedString *) encryptionStatusStringForMessage:(nonnull id<OTRMessageProtocol>)message {
    NSString *lockString = nil;
    if (message.messageSecurity == OTRMessageTransportSecurityOTR) {
        lockString = [NSString stringWithFormat:@"%@ OTR ",[NSString fa_stringForFontAwesomeIcon:FAIconLock]];
    } else if (message.messageSecurity == OTRMessageTransportSecurityOMEMO) {
        lockString = [NSString stringWithFormat:@"%@ ",[NSString fa_stringForFontAwesomeIcon:FAIconLock]];
    }
    else {
        lockString = [NSString stringWithFormat:@"%@ ",[NSString fa_stringForFontAwesomeIcon:FAIconLock]];
    }
    UIFont *font = [UIFont fontWithName:kFontAwesomeFont size:12];
    if (!font) {
        font = [UIFont systemFontOfSize:12];
    }
    return [[NSAttributedString alloc] initWithString:lockString attributes:@{NSFontAttributeName: font}];
}


- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    id <OTRMessageProtocol> message = [self messageAtIndexPath:indexPath];
    if (!message) {
        return [[NSAttributedString alloc] initWithString:@""];
    }
    
    UIFont *font = [UIFont fontWithName:kFontAwesomeFont size:12];
    if (!font) {
        font = [UIFont systemFontOfSize:12];
    }
    NSDictionary *iconAttributes = @{NSFontAttributeName: font};
    NSDictionary *lockAttributes = [iconAttributes copy];
    
    NSMutableAttributedString *attributedString = [[[NSAttributedString alloc] initWithString:@""] mutableCopy];
    if ([message isKindOfClass:[OTROutgoingMessage class]]) {
        NSDate *date = [message messageDate];
        if (date != nil) {
            [attributedString appendAttributedString: [[JSQMessagesTimestampFormatter sharedFormatter] attributedTimestampForDateRight:date]];
            [attributedString appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
        }
        
        if (message.messageExpires) {
            NSString *test = message.messageExpires;
            if (test) {
                [attributedString appendAttributedString: [self getAttributedStringForExpiring:message]];
                [attributedString appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
            }
        }
    }
    
    ////// Lock Icon //////
    NSAttributedString *lockString = [self encryptionStatusStringForMessage:message];
    if (!lockString) {
        lockString = [[NSAttributedString alloc] initWithString:@""];
    }
    
    BOOL trusted = YES;
    if([message isKindOfClass:[OTRBaseMessage class]]) {
        trusted = [self isMessageTrusted:message];
    };
    
    if (!trusted) {
        NSMutableDictionary *mutableCopy = [lockAttributes mutableCopy];
        [mutableCopy setObject:[UIColor redColor] forKey:NSForegroundColorAttributeName];
        lockAttributes = mutableCopy;
    }
    
    if ([message isKindOfClass:[OTROutgoingMessage class]]) {
        OTROutgoingMessage *outgoingMessage = (OTROutgoingMessage *)message;
        NSAttributedString *deliveryString = [self deliveryStatusStringForMessage:message];
        if (deliveryString) {
            [attributedString appendAttributedString:deliveryString];
        }
    } else {
        NSDate *date = [message messageDate];
        if (date != nil) {
            [attributedString appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
            [attributedString appendAttributedString: [[JSQMessagesTimestampFormatter sharedFormatter] attributedTimestampForDateLeft:date]];
        }
        
        if (message.messageExpires) {
            NSString *test = message.messageExpires;
            if (test) {
                [attributedString appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
                [attributedString appendAttributedString: [self getAttributedStringForExpiring:message]];
            }
        }
        
        if ([self showSenderDisplayNameAtIndexPath:indexPath]) {
            id<OTRMessageProtocol,JSQMessageData> message = [self messageAtIndexPath:indexPath];
            
            __block NSString *displayName = nil;
            if ([message isKindOfClass:[OTRXMPPRoomMessage class]]) {
                OTRXMPPRoomMessage *roomMessage = (OTRXMPPRoomMessage *)message;
                [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
                    if (roomMessage.buddyUniqueId) {
                        OTRXMPPBuddy *buddy = [OTRXMPPBuddy fetchObjectWithUniqueID:roomMessage.buddyUniqueId transaction:transaction];
                        displayName = [buddy displayName];
                    }
                    if (!displayName) {
                        OTRXMPPRoomOccupant *occupant = [OTRXMPPRoomOccupant occupantWithJid:[XMPPJID jidWithString:roomMessage.senderJID] realJID:[XMPPJID jidWithString:roomMessage.senderJID] roomJID:[XMPPJID jidWithString:roomMessage.roomJID] accountId:[self accountWithTransaction:transaction].uniqueId createIfNeeded:NO transaction:transaction];
                        if (occupant) {
                            OTRXMPPBuddy *buddy = [occupant buddyWith:transaction];
                            if (buddy) {
                                displayName = [buddy displayName];
                            } else if (occupant.roomName) {
                                displayName = occupant.roomName;
                            }
                        }
                    }
                }];
            }
            if (!displayName) {
                displayName = [message senderDisplayName];
            }
            
            NSArray *namecomponents = [displayName componentsSeparatedByString:@"@"];
            if (namecomponents.count == 2) {
                displayName = [namecomponents firstObject];
            }
            
            [attributedString appendAttributedString:[[NSAttributedString alloc] initWithString:@" - "]];
            [attributedString appendAttributedString: [[NSAttributedString alloc] initWithString:displayName]];
        }
    }
    
    if([[message messageMediaItemKey] length] > 0) {
        
        __block OTRMediaItem *mediaItem = nil;
        //Get the media item
        [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            mediaItem = [OTRMediaItem fetchObjectWithUniqueID:[message messageMediaItemKey] transaction:transaction];
        }];
        if (!mediaItem) {
            return attributedString;
        }
        
        float percentProgress = mediaItem.transferProgress * 100;
        
        NSString *progressString = nil;
        NSUInteger insertIndex = 0;
        
        if (mediaItem.isIncoming && mediaItem.transferProgress < 1) {
            if (message.messageError) {
                if (!message.messageError.isUserCanceledError) {
                    progressString = [NSString stringWithFormat:@"%@ ",WAITING_STRING()];
                }
            } else {
                progressString = [NSString stringWithFormat:@" %@ %.0f%%",INCOMING_STRING(),percentProgress];
            }
            insertIndex = [attributedString length];
        } else if (!mediaItem.isIncoming && mediaItem.transferProgress < 1) {
            if(percentProgress > 0) {
                progressString = [NSString stringWithFormat:@"%@ %.0f%% ",SENDING_STRING(),percentProgress];
            } else {
                progressString = [NSString stringWithFormat:@"%@ ",WAITING_STRING()];
            }
        }
        
        if ([progressString length]) {
            UIFont *font = [UIFont systemFontOfSize:12];
            [attributedString insertAttributedString:[[NSAttributedString alloc] initWithString:progressString attributes:@{NSFontAttributeName: font}] atIndex:insertIndex];
        }
    }
    
    return attributedString;
}

- (NSAttributedString *) getAttributedStringForExpiring:(nonnull id<OTRMessageProtocol>)message {
    if (message.messageExpires) {
        NSTimeInterval timeLeft = [self getTimeUntilExpires:message];
        if (timeLeft > 0) {
            NSString *secLeft = [_exptf stringForTimeInterval:timeLeft];
            return [[NSAttributedString alloc] initWithString:secLeft];
        }
    }
    
    return [[NSAttributedString alloc] initWithString:@""];
}

- (NSTimeInterval) getTimeUntilExpires:(nonnull id<OTRMessageProtocol>)message {
    if (message.messageReadDate == nil) {
        [message setMessageReadDate:[NSDate date]];
        [self.connections.write readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            [transaction setObject:message forKey:[message messageKey] inCollection:[message messageCollection]];
        }];
    }
    
    if (message.messageExpires && message.messageReadDate != nil) {
        NSDate *expDate = [[message messageReadDate] dateByAddingTimeInterval:[message.messageExpires intValue]];
        return [expDate timeIntervalSinceNow];
    }
    
    NSDate *expDate = [[NSDate date] dateByAddingTimeInterval:[message.messageExpires intValue]];
    return [expDate timeIntervalSinceNow];
}

- (void) updateForExpiringMessages:(NSTimer*)timer {
    //add index paths to dynamic array? Or just reload all if one exists?
    BOOL expiring = NO;
    NSMutableArray *expiringList = [NSMutableArray new];
    NSIndexPath *expiredpath = nil;
    for (NSIndexPath *ipath in [self.collectionView indexPathsForVisibleItems]) {
        id <OTRMessageProtocol> message = [self messageAtIndexPath:ipath];
        if (message.messageExpires) {
            [expiringList addObject:ipath];
            expiring = YES;
            
            if ([self getTimeUntilExpires:message] <= 0) {
                expiredpath = ipath;
            }
        }
    }
    
    if (expiredpath) {
        [self deleteMessageAtIndexPath:expiredpath];
    } else if (expiring) {
        [self.collectionView reloadItemsAtIndexPaths:expiringList];
    }
}


#pragma - mark  JSQMessagesCollectionViewDelegateFlowLayout Methods

- (UICollectionReusableView*)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    UICollectionReusableView *supplement = [self.supplementaryViewHandler collectionView:collectionView viewForSupplementaryElementOfKind:kind at:indexPath];
    if (supplement) {
        return supplement;
    }
    return [super collectionView:collectionView viewForSupplementaryElementOfKind:kind atIndexPath:indexPath];
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout
heightForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat height = 0.0f;
    if ([self showDateAtIndexPath:indexPath]) {
        height += kJSQMessagesCollectionViewCellLabelHeightDefault;
    }
    
    if ([self isPushMessageAtIndexPath:indexPath]) {
        height += kJSQMessagesCollectionViewCellLabelHeightDefault;
    }
    
    if ([self isMemberUpdateMessageAtIndexPath:indexPath]) {
        id <OTRMessageProtocol> message = [self messageAtIndexPath:indexPath];
        NSString *updateString = message.messageOriginalText;
        NSUInteger linecnt = 1;
        if (updateString != nil) {
            updateString = [self getFormattedMemberUpdate:updateString];
            linecnt = [updateString componentsSeparatedByString:@"\n"].count;
        }
        height += (kJSQMessagesCollectionViewCellLabelHeightDefault * linecnt);
    }
    return height;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout
heightForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self showSenderDisplayNameAtIndexPath:indexPath]) {
        return kJSQMessagesCollectionViewCellLabelHeightDefault;
    }
    return 0.0f;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout
heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat height = kJSQMessagesCollectionViewCellLabelHeightDefault;
    if ([self isPushMessageAtIndexPath:indexPath] || [self isMemberUpdateMessageAtIndexPath:indexPath]) {
        height = 0.0f;
    }
    return height;
}

- (void)deleteMessageAtIndexPath:(NSIndexPath *)indexPath
{
    __block id <OTRMessageProtocol,JSQMessageData> message = [self messageAtIndexPath:indexPath];
    __weak __typeof__(self) weakSelf = self;
    [self.connections.write asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        __typeof__(self) strongSelf = weakSelf;
        [transaction removeObjectForKey:[message messageKey] inCollection:[message messageCollection]];
        //Update Last message date for sorting and grouping
        OTRBuddy *buddy = [[strongSelf buddyWithTransaction:transaction] copy];
        buddy.lastMessageId = nil;
        [buddy saveWithTransaction:transaction];
    }];
}

- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapAvatarImageView:(UIImageView *)avatarImageView atIndexPath:(NSIndexPath *)indexPath
{
    id <OTRMessageProtocol,JSQMessageData> message = [self messageAtIndexPath:indexPath];
    [self didTapAvatar:message sender:avatarImageView];
}

- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapMessageBubbleAtIndexPath:(NSIndexPath *)indexPath
{
    id <OTRMessageProtocol,JSQMessageData> message = [self messageAtIndexPath:indexPath];
    if (!message.isMediaMessage) {
        return;
    }
    __block OTRMediaItem *item = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction *transaction) {
         item = [OTRMediaItem mediaItemForMessage:message transaction:transaction];
    }];
    if (!item) { return; }
    if (item.transferProgress != 1 && item.isIncoming) {
        return;
    }
    
    if ([item isKindOfClass:[OTRImageItem class]]) {
        [self showImage:(OTRImageItem *)item fromCollectionView:collectionView atIndexPath:indexPath];
    }
    else if ([item isKindOfClass:[OTRVideoItem class]]) {
        [self showVideo:(OTRVideoItem *)item fromCollectionView:collectionView atIndexPath:indexPath];
    }
    else if ([item isKindOfClass:[OTRFileItem class]]) {
        [self showFile:(OTRFileItem *)item fromCollectionView:collectionView atIndexPath:indexPath];
    }
    else if ([item isKindOfClass:[OTRAudioItem class]]) {
        [self playOrPauseAudio:(OTRAudioItem *)item fromCollectionView:collectionView atIndexPath:indexPath];
    } else if ([message conformsToProtocol:@protocol(OTRDownloadMessage)]) {
        id<OTRDownloadMessage> download = (id<OTRDownloadMessage>)message;
        // Janky hack to open URL for now
        NSArray<UIAlertAction*> *actions = [UIAlertAction actionsForMediaMessage:download sourceView:self.view viewController:self];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:message.text message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [actions enumerateObjectsUsingBlock:^(UIAlertAction * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [alert addAction:obj];
        }];
        [alert addAction:[self cancleAction]];
        
        // Get the anchor
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = self.view.bounds;
        UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
        if ([cell isKindOfClass:[JSQMessagesCollectionViewCell class]]) {
            UIView *cellContainterView = ((JSQMessagesCollectionViewCell *)cell).messageBubbleContainerView;
            alert.popoverPresentationController.sourceRect = cellContainterView.bounds;
            alert.popoverPresentationController.sourceView = cellContainterView;
        }

        [self presentViewController:alert animated:YES completion:nil];
    }
}

#pragma - mark database view delegate

- (void)didSetupMappings:(OTRYapViewHandler *)handler
{
    // The databse view is setup now so refresh from there
    [self updateViewWithKey:self.threadKey collection:self.threadCollection];
    [self updateRangeOptions:YES];
    [self.collectionView reloadData];
    
    __block OTRBuddy *buddy = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        buddy = [self buddyWithTransaction:transaction];
    }];
    [self checkForDeviceListUpdateWithBuddy:(OTRXMPPBuddy*)buddy];
}

- (void)didReceiveChanges:(OTRYapViewHandler *)handler key:(NSString *)key collection:(NSString *)collection
{
    [self updateViewWithKey:key collection:collection];
}

- (void)didReceiveChanges:(OTRYapViewHandler *)handler sectionChanges:(NSArray<YapDatabaseViewSectionChange *> *)sectionChanges rowChanges:(NSArray<YapDatabaseViewRowChange *> *)rowChanges
{
    if (!rowChanges.count) {
        return;
    }
    
    // Important to clear our "one message cache" here, since things may have changed.
    self.currentIndexPath = nil;
    
    NSUInteger collectionViewNumberOfItems = [self.collectionView numberOfItemsInSection:0];
    NSUInteger numberMappingsItems = [self.viewHandler.mappings numberOfItemsInSection:0];
    
    // Collection view has a bug which makes it call numberOfSections if it is not visible, ending up with an inconsistency exception at the end of the batch updates below. Work around: If we are not visible, just call reloadData.
    if (self.collectionView.window == nil) {
        [self.collectionView reloadData];
        return;
    }
    
    [self.collectionView performBatchUpdates:^{
        
        for (YapDatabaseViewRowChange *rowChange in rowChanges)
        {
            switch (rowChange.type)
            {
                case YapDatabaseViewChangeDelete :
                {
                    [self.collectionView deleteItemsAtIndexPaths:@[rowChange.indexPath]];
                    break;
                }
                case YapDatabaseViewChangeInsert :
                {
                    [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath ]];
                    break;
                }
                case YapDatabaseViewChangeMove :
                {
                    [self.collectionView moveItemAtIndexPath:rowChange.indexPath toIndexPath:rowChange.newIndexPath];
                    break;
                }
                case YapDatabaseViewChangeUpdate :
                {
                    // Update could be e.g. when we are done auto-loading a link. We
                    // need to reset the stored size of this item, so the image/message
                    // will get the correct bubble height.
                    id <JSQMessageData> message = [self messageAtIndexPath:rowChange.indexPath];
                    [self.collectionView.collectionViewLayout.bubbleSizeCalculator resetBubbleSizeCacheForMessageData:message];
                    [self.messageSizeCache removeObjectForKey:@(message.messageHash)];
                    [self.collectionView reloadItemsAtIndexPaths:@[ rowChange.indexPath]];
                    break;
                }
            }
        }
    } completion:^(BOOL finished){
        if(numberMappingsItems > collectionViewNumberOfItems && numberMappingsItems > 0) {
            //Inserted new item, probably at the end
            //Get last message and test if isIncoming
            id <OTRMessageProtocol>lastMessage = [self lastMessage];
            if ([lastMessage isMessageIncoming]) {
                [self finishReceivingMessage];
            } else {
                // We can't use finishSendingMessage here because it might
                // accidentally clear out unsent message text
                [self scrollToBottomAnimated:YES];
            }
        }
    }];
}

- (id<OTRMessageProtocol>) lastMessage {
    NSUInteger numberMappingsItems = [self.viewHandler.mappings numberOfItemsInSection:0];
    NSIndexPath *lastMessageIndexPath = [NSIndexPath indexPathForRow:numberMappingsItems - 1 inSection:0];
    return [self messageAtIndexPath:lastMessageIndexPath];
}

#pragma - mark UITextViewDelegateMethods

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange
{
    if ([URL otr_isInviteLink]) {
        NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
        activity.webpageURL = URL;
        [[OTRAppDelegate appDelegate] application:[UIApplication sharedApplication] continueUserActivity:activity restorationHandler:^(NSArray * _Nullable restorableObjects) {
            // TODO: restore stuff
        }];
        return NO;
    }
    
    UIActivityViewController *activityViewController = [UIActivityViewController otr_linkActivityViewControllerWithURLs:@[URL]];
    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"8.0")) {
        activityViewController.popoverPresentationController.sourceView = textView;
        activityViewController.popoverPresentationController.sourceRect = textView.bounds;
    }
    
    [self presentViewController:activityViewController animated:YES completion:nil];
    return NO;
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    
    if([text isEqualToString:@"\n"]) {
        if ([OTRSettingsManager boolForOTRSettingKey:@"kOTREnterToSendKey"]) {
            [self didPressSendButton:self.sendButton
                     withMessageText:textView.text
                            senderId:self.senderId
                   senderDisplayName:self.senderDisplayName
                                date:[NSDate date]];
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField{
    return NO;
}

- (void)viewWillLayoutSubviews {
    self.currentIndexPath = nil;
    [super viewWillLayoutSubviews];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutJIDForwardingHeader];
}

- (void) networkConnectionStatusChange:(NSNotification*)notification {
    [self setConnectionStatus];
}

- (void) setConnectionStatus {
    __block OTRAccount *account = nil;
    [self.connections.read readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        account =  [self accountWithTransaction:transaction];
    }];
    
    if (account != nil) {
        [self addStatusGestures:NO];
        if ([[OTRProtocolManager sharedInstance] existsProtocolForAccount:account]) {
            if ([[OTRProtocolManager sharedInstance] isAccountConnected:account]) {
                self.showConnStatus = NO;
                self.navigationItem.titleView = self.titleSubView;
                self.titleView.subtitleLabel.text = nil;
                self.titleView.subtitleLabel.textColor = [UIColor blackColor];
                [self refreshTitleView:[self titleView]];
                [self.titleView.dynConnectingView stopAnimating];
                self.titleView.dynConnectingView.hidden = YES;
            }
            else {
                [self handleConnectingStatus:YES];
            }
        } else {
            // this occurs when in process of trying to create new account
            // shouldn't happen in this class but just in case
            [self handleConnectingStatus:NO];
        }
    }
}

- (void) handleConnectingStatus:(BOOL)protocolExists {
    //DDLogWarn(@"*** handleConnectingStatus with statusCtr %d", _statusCtr);
    self.showConnStatus = YES;
    if (_statusCtr < 3) {
        self.titleView.subtitleLabel.text = nil;
        self.titleView.dynConnectingView.hidden = NO;
        [self.titleView.dynConnectingView startAnimating];
    } else {
        [self.titleView.dynConnectingView stopAnimating];
        self.titleView.dynConnectingView.hidden = YES;
        self.navigationItem.titleView = self.titleSubView;
        self.titleView.subtitleLabel.textColor = [UIColor blackColor];
        [self refreshTitleView:[self titleView]];
        
        OTRNetworkConnectionStatus networkStatus = [[OTRAppDelegate appDelegate] getCurrentNetworkStatus];
        if (networkStatus == OTRNetworkConnectionStatusConnected) { // logging in
            if (protocolExists) {
                if (_statusCtr < 6) {
                    self.titleView.subtitleLabel.text = @"Connecting";
                } else if (_statusCtr < 9) {
                    self.titleView.subtitleLabel.text = @"Still trying to log in";
                } else {
                    self.titleView.subtitleLabel.text = @"Offline - Tap to login";
                    [self addStatusGestures:YES];
                }
            } else { // don't think this should be possible, but just in case
                self.titleView.subtitleLabel.text = @"Problems initializing account";
            }
        } else if (_statusCtr < 6) {
            self.titleView.subtitleLabel.text = @"Connecting";
        } else if (_statusCtr < 9) {
            self.titleView.subtitleLabel.text = @"Waiting for VPN Connectivity";
            if (_accountType != nil && [_accountType isEqualToString:@"none"]) {
                self.titleView.subtitleLabel.text = @"Waiting for Connectivity";
            }
        } else {
            [self handleOfflineNetworkMessage];
        }
    }
}

- (void) handleOfflineNetworkMessage {
    //DDLogWarn(@"*** handleOfflineNetworkMessage with statusCtr %d", _statusCtr);
    if (_accountType != nil) {
        if ([_accountType isEqualToString:@"ipsec"]) {
            self.titleView.subtitleLabel.text = @"Offline - Enable VPN in iOS Settings";
        } else if ([_accountType isEqualToString:@"none"]) {
            self.titleView.subtitleLabel.text = @"Offline - Tap to try again";
            [self addStatusGestures:YES];
        } else {
            self.titleView.subtitleLabel.text = @"Offline - Tap for OpenVPN";
            [self addStatusGestures:YES];
        }
    } else {
        self.titleView.subtitleLabel.text = @"Offline - Tap for OpenVPN";
        [self addStatusGestures:YES];
    }
}

- (void) addStatusGestures:(BOOL)turnon {
    if (turnon) {
        [self.titleView addGestureRecognizer:self.statusTapGestureRecognizer];
        self.titleView.userInteractionEnabled = YES;
    } else {
        [self.titleView removeGestureRecognizer:self.statusTapGestureRecognizer];
        self.titleView.userInteractionEnabled = NO;
    }
}

- (void) handleStatusGesture {
    NSString *statusString = self.titleView.subtitleLabel.text;
    if ([statusString hasSuffix:@"OpenVPN"]) {
        [self openOpenVPN];
    } else if ([statusString hasSuffix:@"login"]) {
        if (self.statusTimer) [self.statusTimer invalidate];
        _statusCtr = 0;
        _statusTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateStatusTimer:) userInfo:nil repeats:YES];
        
        [self retryLogin];
    } else if ([statusString hasSuffix:@"again"]) { // retry network
        [self retryNetworkConnection];
    }
}

- (void)updateStatusTimer:(id)sender
{
    //DDLogWarn(@"*** statusCtr %d", _statusCtr);
    if (_statusCtr < 15) {
        _statusCtr++;
    } else {
        [self.statusTimer invalidate];
        self.statusTimer = nil;
    }
    
    if (_statusCtr % 3 == 0) {
        [self setConnectionStatus];
    }
}

- (void) retryNetworkConnection {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OTRAppDelegate appDelegate] checkConnectionOrTryLogin];
    });
}

- (void) retryLogin {
    OTRNetworkConnectionStatus currentStatus = [[OTRAppDelegate appDelegate] getCurrentNetworkStatus];
    NSMutableDictionary *userInfo = [@{NewNetworkStatusKey: @(currentStatus)} mutableCopy];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:NetworkStatusNotificationName object:self userInfo:userInfo];
    });
}

- (void) openOpenVPN {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OTRAppDelegate appDelegate] gotoOpenVPN];
    });
}

#pragma - mark Buddy Migration methods

- (nullable XMPPJID *)getForwardingJIDForBuddy:(OTRXMPPBuddy *)xmppBuddy {
    XMPPJID *ret = nil;
    if (xmppBuddy != nil && xmppBuddy.vCardTemp != nil) {
        ret = xmppBuddy.vCardTemp.jid;
    }
    return ret;
}

- (void)layoutJIDForwardingHeader {
    if (self.jidForwardingHeaderView != nil) {
        [self.jidForwardingHeaderView setNeedsLayout];
        [self.jidForwardingHeaderView layoutIfNeeded];
        int height = [self.jidForwardingHeaderView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height + 1;
        self.jidForwardingHeaderView.frame = CGRectMake(0, self.topLayoutGuide.length, self.view.frame.size.width, height);
        [self.view bringSubviewToFront:self.jidForwardingHeaderView];
        self.additionalContentInset = UIEdgeInsetsMake(height, 0, 0, 0);
    }
}

- (void)updateJIDForwardingHeader {
    
    __block id<OTRThreadOwner> thread = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        thread = [self threadObjectWithTransaction:transaction];
    }];
    OTRXMPPBuddy *buddy = nil;
    if ([thread isKindOfClass:[OTRXMPPBuddy class]]) {
        buddy = (OTRXMPPBuddy*)thread;
    }
    
    // If we have a buddy with vcard JID set to something else than the username, show a
    // "buddy has moved" warning to allow the user to start a chat with that JID instead.
    BOOL showHeader = NO;
    XMPPJID *forwardingJid = [self getForwardingJIDForBuddy:buddy];
    if (forwardingJid != nil && ![forwardingJid isEqualToJID:buddy.bareJID options:XMPPJIDCompareBare]) {
        showHeader = YES;
    }
    
    if (showHeader) {
        [self showJIDForwardingHeaderWithNewJID:forwardingJid];
    } else if (!showHeader && self.jidForwardingHeaderView != nil) {
        self.additionalContentInset = UIEdgeInsetsZero;
        [self.jidForwardingHeaderView removeFromSuperview];
        self.jidForwardingHeaderView = nil;
    }
}

- (void)showJIDForwardingHeaderWithNewJID:(XMPPJID *)newJid {
    if (self.jidForwardingHeaderView == nil) {
        UINib *nib = [UINib nibWithNibName:@"MigratedBuddyHeaderView" bundle:OTRAssets.resourcesBundle];
        MigratedBuddyHeaderView *header = (MigratedBuddyHeaderView*)[nib instantiateWithOwner:self options:nil][0];
        [header setForwardingJID:newJid];
        [header.titleLabel setText:MIGRATED_BUDDY_STRING()];
        [header.descriptionLabel setText:MIGRATED_BUDDY_INFO_STRING()];
        [header.switchButton setTitle:MIGRATED_BUDDY_SWITCH() forState:UIControlStateNormal];
        [header.ignoreButton setTitle:MIGRATED_BUDDY_IGNORE() forState:UIControlStateNormal];
        [header setBackgroundColor:UIColor.whiteColor];
        [self.view addSubview:header];
        [self.view bringSubviewToFront:header];
        self.jidForwardingHeaderView = header;
        [self.view setNeedsLayout];
    }
}

- (IBAction)didPressMigratedIgnore {
    if (self.jidForwardingHeaderView != nil) {
        self.jidForwardingHeaderView.hidden = YES;
        self.additionalContentInset = UIEdgeInsetsZero;
    }
}

- (IBAction)didPressMigratedSwitch {
    if (self.jidForwardingHeaderView != nil) {
        self.jidForwardingHeaderView.hidden = YES;
        self.additionalContentInset = UIEdgeInsetsZero;
    }
    
    __block OTRXMPPBuddy *buddy = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        buddy = (OTRXMPPBuddy*)[self buddyWithTransaction:transaction];
    }];
    
    XMPPJID *forwardingJid = [self getForwardingJIDForBuddy:buddy];
    if (forwardingJid != nil) {
        // Try to find buddy
        //
        [[OTRDatabaseManager sharedInstance].connections.write readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            OTRAccount *account = [self accountWithTransaction:transaction];
            OTRXMPPBuddy *buddy = [OTRXMPPBuddy fetchBuddyWithJid:forwardingJid accountUniqueId:account.uniqueId transaction:transaction];
            if (!buddy) {
                buddy = [[OTRXMPPBuddy alloc] init];
                buddy.accountUniqueId = account.uniqueId;
                buddy.username = forwardingJid.bare;
                [buddy saveWithTransaction:transaction];
                id<OTRProtocol> proto = [[OTRProtocolManager sharedInstance] protocolForAccount:account];
                if (proto != nil) {
                    [proto addBuddy:buddy];
                }
            }
            [self setThreadKey:buddy.uniqueId collection:[OTRBuddy collection]];
        }];
    }
}

#pragma - mark Group chat support

- (void)setupWithBuddies:(NSArray<NSString *> *)buddies accountId:(NSString *)accountId name:(NSString *)name
{
    __block OTRXMPPAccount *account = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        account = [OTRXMPPAccount fetchObjectWithUniqueID:accountId transaction:transaction];
    }];
    OTRXMPPManager *xmppManager = (OTRXMPPManager *)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
    NSString *service = [xmppManager.roomManager.conferenceServicesJID firstObject];
    if (service.length > 0) {
        NSString *jidName = [name stringByReplacingOccurrencesOfString:@" " withString:@"-"];
        XMPPJID *roomJID = [XMPPJID jidWithString:[NSString stringWithFormat:@"%@@%@",jidName,service]];
        self.threadKey = [xmppManager.roomManager startGroupChatWithBuddies:buddies roomJID:roomJID nickname:account.displayName subject:name isPublic:NO];
        [self setThreadKey:self.threadKey collection:[OTRXMPPRoom collection]];
    } else {
        DDLogError(@"No conference server for account: %@", account.username);
    }
}

- (void)setupPublicGroupWithName:(NSString *)name
{
    __block OTRAccount *account = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        account = [self accountWithTransaction:transaction];
        if (account == nil) {
            NSArray<OTRAccount*> *accounts = [OTRAccount allAccountsWithTransaction:transaction];
            if (accounts) {
                account = accounts.firstObject;
            }
        }
    }];
    
    if (account == nil) return;
    
    OTRXMPPManager *xmppManager = (OTRXMPPManager *)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
    NSString *service = [xmppManager.roomManager.conferenceServicesJID firstObject];
    if (service.length > 0) {
        NSString *jidName = [name stringByReplacingOccurrencesOfString:@" " withString:@"-"];
        XMPPJID *roomJID = [XMPPJID jidWithString:[NSString stringWithFormat:@"%@@%@",jidName,service]];
        self.threadKey = [xmppManager.roomManager startGroupChatWithBuddies:[NSArray array] roomJID:roomJID nickname:account.displayName subject:name isPublic:YES];
        [self setThreadKey:self.threadKey collection:[OTRXMPPRoom collection]];
        [xmppManager.roomManager publishJoinedRoom:roomJID withName:account.displayName];
    } else {
        DDLogError(@"No conference server for account: %@", account.username);
    }
}

#pragma - mark OTRRoomOccupantsViewControllerDelegate

- (void)didLeaveRoom:(OTRRoomOccupantsViewController *)roomOccupantsViewController {
    __block OTRXMPPRoom *room = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        room = [self roomWithTransaction:transaction];
    }];
    if (room) {
        [self setThreadKey:nil collection:nil];
        [self.connections.write readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            [room removeWithTransaction:transaction];
        }];
    }
    [self.navigationController popViewControllerAnimated:NO];
    if ([[self.navigationController viewControllers] count] > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self.navigationController.navigationController popViewControllerAnimated:YES];
    }
    
}

- (void)didArchiveRoom:(OTRRoomOccupantsViewController *)roomOccupantsViewController {
    __block OTRXMPPRoom *room = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        room = [self roomWithTransaction:transaction];
    }];
    if (room) {
        [self setThreadKey:nil collection:nil];
        [self.connections.write readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            room.isArchived = YES;
            [room saveWithTransaction:transaction];
        }];
    }
    [self.navigationController popViewControllerAnimated:NO];
    if ([[self.navigationController viewControllers] count] > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self.navigationController.navigationController popViewControllerAnimated:YES];
    }
}

- (void)newDeviceButtonPressed:(NSString *)buddyUniqueId {
    __block OTRXMPPAccount *account = nil;
    __block OTRXMPPBuddy *buddy = nil;
    [self.connections.ui readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        account = [self accountWithTransaction:transaction];
        buddy = [OTRXMPPBuddy fetchObjectWithUniqueID:buddyUniqueId transaction:transaction];
    }];
    if (account && buddy) {
        UIViewController *vc = [GlobalTheme.shared newUntrustedKeyViewControllerForBuddies:@[buddy]];
        UINavigationController *keyNav = [[UINavigationController alloc] initWithRootViewController:vc];
        [self presentViewController:keyNav animated:YES completion:nil];
    }
}

@end
