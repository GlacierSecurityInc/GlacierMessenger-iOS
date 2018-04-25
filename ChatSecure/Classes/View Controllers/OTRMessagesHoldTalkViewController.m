//
//  OTRMessagesHoldTalkViewController.m
//  ChatSecure
//
//  Created by David Chiles on 4/1/15.
//  Copyright (c) 2015 Chris Ballinger. All rights reserved.
//

#import "OTRMessagesHoldTalkViewController.h"
@import PureLayout;
#import "OTRHoldToTalkView.h"
#import "OTRAudioSessionManager.h"
#import "OTRAudioTrashView.h"
#import "OTRLog.h"
@import OTRKit;
#import "OTRBuddy.h"
#import "OTRXMPPManager.h"
#import "OTRXMPPAccount.h"

#import <ChatSecureCore/ChatSecureCore-Swift.h>
@import Mapbox;

static Float64 kOTRMessagesMinimumAudioTime = .5;

@import AVFoundation;
@import OTRAssets;

@interface OTRMessagesHoldTalkViewController () <OTRHoldToTalkViewStateDelegate, OTRAudioSessionManagerDelegate, MGLMapViewDelegate, UIPickerViewDataSource,UIPickerViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) OTRHoldToTalkView *hold2TalkButton;
@property (nonatomic, strong) OTRAudioTrashView *trashView;

@property (nonatomic, strong) NSLayoutConstraint *trashViewWidthConstraint;

@property (nonatomic, strong) UIButton *keyboardButton;

@property (nonatomic) BOOL holdTalkAddedConstraints;

@property (nonatomic, strong) OTRAudioSessionManager *audioSessionManager;

@property (nonatomic, strong) UIView *recordingBackgroundView;

// location sharing
@property (nonatomic, strong) UIToolbar *locbar;
@property (nonatomic, strong) MGLMapView *mapView;
@property (nonatomic, strong) UIBarButtonItem *btnMapShare;
@property (nonatomic) BOOL locReady;

// expiring messages
@property (nonatomic, strong) UIPickerView *timePickerView;
@property (strong, nonatomic) NSArray *pickerArray;
@property (nonatomic, strong) UITextField *timePickerTextField;
@property (nonatomic, strong) UITapGestureRecognizer *timeTapGesture;
@property (nonatomic, strong) UITapGestureRecognizer *timeTapGesture2;
@property (nonatomic, strong) UIButton *timeButton;
@property (nonatomic) BOOL timeOn;

@end

@implementation OTRMessagesHoldTalkViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.audioSessionManager = [[OTRAudioSessionManager alloc] init];
    self.audioSessionManager.delegate = self;
    
    self.keyboardButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.keyboardButton.frame = CGRectMake(0, 0, 22, 32);
    self.keyboardButton.titleLabel.font = [UIFont fontWithName:kFontAwesomeFont size:20];
    self.keyboardButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.keyboardButton setTitle:[NSString fa_stringForFontAwesomeIcon:FAIconKeyboardO]
                           forState:UIControlStateNormal];
    [self.keyboardButton setTintColor:[UIColor jsq_messageBubbleBlueColor]];
    
    // expiring messages
    [self.microphoneButton addTarget:self action:@selector(microphoneButtonTouched:) forControlEvents:UIControlEventTouchUpInside];
    self.pickerArray = @[@"Off", @"15 seconds", @"1 minute", @"5 minutes", @"1 day", @"1 week"];
    [self.hourglassButton addTarget:self action:@selector(hourglassButtonTouched:) forControlEvents:UIControlEventTouchUpInside];
    
    self.timeButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.timeButton.frame = CGRectMake(0, 0, 32, 32);
    self.timeButton.titleLabel.font = [UIFont fontWithName:kFontAwesomeFont size:16];
    self.timeButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.timeButton setTitle:[NSString fa_stringForFontAwesomeIcon:FAIconHourglass1] forState:UIControlStateNormal];
    [self.timeButton setTintColor:[UIColor jsq_messageBubbleBlueColor]];
    
    // share location
    self.locReady = false;
    self.btnMapShare = [[UIBarButtonItem alloc] initWithTitle:@"Locating..." style:UIBarButtonItemStylePlain target:self action:@selector(shareLocation)];
    self.mapView = [[MGLMapView alloc] initWithFrame:self.view.bounds styleURL:[MGLStyle darkStyleURLWithVersion:9]];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"MGLMapboxMetricsEnabled"];
    self.mapView.delegate = self;
    self.mapView.userTrackingMode = MGLUserTrackingModeFollow;
    self.mapView.showsUserLocation = true;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enteringForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:[UIApplication sharedApplication]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resigningActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:[UIApplication sharedApplication]];
    
    [self setupDefaultSendButton];
    [self.view setNeedsUpdateConstraints];
    [self updateTimeButton];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self updateEncryptionState];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self turnOnOffLocation:YES];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self turnOnOffLocation:NO];
}

// whether to track location. only tracks location when actively on conversation
- (void) turnOnOffLocation:(BOOL)locationOn {
    if (locationOn) {
        self.mapView.userTrackingMode = MGLUserTrackingModeFollow;
        self.mapView.showsUserLocation = true;
    } else {
        self.mapView.userTrackingMode = MGLUserTrackingModeNone;
        self.mapView.showsUserLocation = false;
        
        if (self.locbar) {
            [self cancelLocation];
        }
    }
}

- (void) enteringForeground:(NSNotification *)notification {
    [self turnOnOffLocation:YES];
}

- (void) resigningActive:(NSNotification *)notification {
    [self turnOnOffLocation:NO];
}

#pragma - mark AutoLayout

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.trashView.trashButton.buttonCornerRadius = @(CGRectGetWidth(self.trashView.trashButton.bounds));
}

#pragma - mark Utilities

- (CGFloat)distanceBetweenPoint1:(CGPoint)point1 point2:(CGPoint)point2
{
    return sqrt(pow(point2.x-point1.x,2)+pow(point2.y-point1.y,2));
}

- (CGPoint)centerOfview:(UIView *)view1 inView:(UIView *)view2
{
    CGPoint localCenter = CGPointMake(CGRectGetMidX(view1.bounds), CGRectGetMidY(view1.bounds));
    CGPoint trashButtonCenter = [view2 convertPoint:localCenter fromView:view1];
    return trashButtonCenter;
}

#pragma - mark Setup Recording

- (void)addPush2TalkButton
{
    if (self.hold2TalkButton) {
        [self removePush2TalkButton];
    }
    self.hold2TalkButton = [[OTRHoldToTalkView alloc] initForAutoLayout];
    [self setHold2TalkStatusWaiting];
    self.hold2TalkButton.delegate = self;
    [self.view addSubview:self.hold2TalkButton];
    
    UIView *textView = self.inputToolbar.contentView.textView;
    
    CGFloat offset = 1;
    
    [self.hold2TalkButton autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:textView withOffset:-offset];
    [self.hold2TalkButton autoPinEdge:ALEdgeTrailing toEdge:ALEdgeTrailing ofView:textView withOffset:offset];
    [self.hold2TalkButton autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:textView withOffset:-offset];
    [self.hold2TalkButton autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:textView withOffset:offset];
    
    
    [self.view setNeedsUpdateConstraints];
}

- (void)setHold2TalkStatusWaiting
{
    self.hold2TalkButton.textLabel.text = HOLD_TO_TALK_STRING();
    self.hold2TalkButton.textLabel.textColor = [UIColor whiteColor];
    self.hold2TalkButton.backgroundColor = [UIColor darkGrayColor];
}

- (void)setHold2TalkButtonRecording
{
    self.hold2TalkButton.textLabel.text = RELEASE_TO_SEND_STRING();
    self.hold2TalkButton.textLabel.textColor = [UIColor darkGrayColor];
    self.hold2TalkButton.backgroundColor = [UIColor whiteColor];
}

- (void)addTrashViewItems
{
    if (self.trashView) {
        [self removeTrashViewItems];
    }
    self.trashView = [[OTRAudioTrashView alloc] initForAutoLayout];
    [self.view addSubview:self.trashView];
    
    [self.trashView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.view withOffset:50];
    [self.trashView autoAlignAxisToSuperviewAxis:ALAxisVertical];
    self.trashViewWidthConstraint = [self.trashView autoSetDimension:ALDimensionHeight toSize:self.trashView.intrinsicContentSize.height];
    self.trashView.trashIconLabel.alpha = 0;
    self.trashView.microphoneIconLabel.alpha = 1;
    self.trashView.trashButton.highlighted = NO;
    self.trashView.trashLabel.textColor = [UIColor whiteColor];
}

- (void)addRecordingBackgroundView
{
    if (self.recordingBackgroundView) {
        [self removeRecordingBackgroundView];
    }
    self.recordingBackgroundView = [[UIView alloc] initForAutoLayout];
    self.recordingBackgroundView.backgroundColor = [UIColor grayColor];
    self.recordingBackgroundView.alpha = 0.7;
    [self.view insertSubview:self.recordingBackgroundView belowSubview:self.hold2TalkButton];
    
    [self.recordingBackgroundView autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsZero];
}

- (void)removeRecordingBackgroundView
{
    [self.recordingBackgroundView removeFromSuperview];
    self.recordingBackgroundView = nil;
}

- (void)removePush2TalkButton
{
    [self.hold2TalkButton removeFromSuperview];
    self.hold2TalkButton = nil;
}

- (void)removeTrashViewItems
{
    [self.trashView removeFromSuperview];
    self.trashView = nil;
    
}

#pragma - mark JSQMessageViewController

- (void)isTyping {
    __weak __typeof__(self) weakSelf = self;
    [self.connections.read asyncReadWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        __typeof__(self) strongSelf = weakSelf;
        OTRXMPPManager *xmppManager = [strongSelf xmppManagerWithTransaction:transaction];
        [xmppManager sendChatState:OTRChatStateComposing withBuddyID:[strongSelf threadKey]];
    }];
    
    
}

- (void)didFinishTyping {
    __weak __typeof__(self) weakSelf = self;
    [self.connections.read asyncReadWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        __typeof__(self) strongSelf = weakSelf;
        OTRXMPPManager *xmppManager = [strongSelf xmppManagerWithTransaction:transaction];
        [xmppManager sendChatState:OTRChatStateActive withBuddyID:[strongSelf threadKey]];
    }];
    
    
}

- (void)didUpdateState
{
    [self setupDefaultSendButton];
    if (self.state.hasText) {
        self.inputToolbar.contentView.rightBarButtonItem.enabled = YES;
    } else {
        self.inputToolbar.contentView.rightBarButtonItem.enabled = NO;
    }
    
    if (!self.inputToolbar.contentView.leftBarButtonItem) {
        self.inputToolbar.contentView.leftBarButtonItem = self.moreOptionsButton;
        self.inputToolbar.contentView.leftBarButtonItem.enabled = YES;
    }
    
    if (self.state.canSendMedia) {
        
        if (!self.state.hasText) {
            //No text then show microphone
            if ([self.hold2TalkButton superview]) {
                self.inputToolbar.contentView.rightBarButtonItem = self.keyboardButton;
                self.inputToolbar.contentView.rightBarButtonItem.enabled = YES;
            } else if (self.timeOn) { 
                self.inputToolbar.contentView.rightBarButtonItem = self.timeButton;
            }
            self.inputToolbar.sendButtonLocation = JSQMessagesInputSendButtonLocationNone;
        } else {
            //Default Send button
            [self setupDefaultSendButton];
            self.inputToolbar.contentView.rightBarButtonItem.enabled = YES;
        }
    } else {
        [self removeMediaButtons];
    }
}

- (void)removeMediaButtons {
    [self removePush2TalkButton];
    [self removeRecordingBackgroundView];
    [self removeTrashViewItems];
    self.inputToolbar.contentView.leftBarButtonItem = nil;
}

- (void)setupDefaultSendButton {
    //Default send button
    
    self.inputToolbar.contentView.rightBarButtonItem = self.sendButton;
    self.inputToolbar.sendButtonLocation = JSQMessagesInputSendButtonLocationRight;
}

#pragma - mark OTRHoldToTalkViewStateDelegate

- (void)didBeginTouch:(OTRHoldToTalkView *)view
{
    //start Recording
    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![view isInTouch]) {
                // Abort this, no longer in touch
            } else if (granted) {
                [self addRecordingBackgroundView];
                [self addTrashViewItems];
                NSString *temporaryPath = NSTemporaryDirectory();
                NSString *fileName = [NSString stringWithFormat:@"%@.m4a",[[NSUUID UUID] UUIDString]];
                NSURL *url = [NSURL fileURLWithPath:[temporaryPath stringByAppendingPathComponent:fileName]];
                
                [self.audioSessionManager recordAudioToURL:url error:nil];
                [self setHold2TalkButtonRecording];
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:Microphone_Disabled() message:Microphone_Reenable_Please() preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *fix = [UIAlertAction actionWithTitle:Enable_String() style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    NSURL *settings = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                    [[UIApplication sharedApplication] openURL:settings];
                }];
                UIAlertAction *cancel = [UIAlertAction actionWithTitle:CANCEL_STRING() style:UIAlertActionStyleCancel handler:nil];
                [alert addAction:fix];
                [alert addAction:cancel];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
    
}

- (void)view:(OTRHoldToTalkView *)view touchDidMoveToPointInWindow:(CGPoint)point
{
    UIWindow *mainWindow = [[UIApplication sharedApplication] keyWindow];
    CGPoint poinInView = [self.view convertPoint:point fromView:mainWindow];
    
    CGPoint trashButtonCenter = [self centerOfview:self.trashView.trashButton inView:self.view];
    CGPoint holdToTalkCenter = [self centerOfview:self.hold2TalkButton inView:self.view];
    
    CGFloat normalDistance = [self distanceBetweenPoint1:trashButtonCenter point2:holdToTalkCenter];
    
    CGFloat distance = [self distanceBetweenPoint1:poinInView point2:trashButtonCenter];
    
    CGFloat percentDistance = (normalDistance - distance)/normalDistance;
    CGFloat defaultHeight = self.trashView.intrinsicContentSize.height;
    self.trashViewWidthConstraint.constant = MAX(defaultHeight, defaultHeight+defaultHeight * percentDistance);
    
    CGPoint testPoint = [self.trashView.trashButton convertPoint:poinInView fromView:self.view];
    BOOL insideButton = CGRectContainsPoint(self.trashView.trashButton.bounds, testPoint);
    
    self.trashView.trashButton.highlighted = insideButton;
    
    if (insideButton) {
        self.trashView.trashIconLabel.alpha = 1;
        self.trashView.microphoneIconLabel.alpha = 0;
        self.hold2TalkButton.textLabel.text = RELEASE_TO_DELETE_STRING();
    } else {
        self.trashView.trashIconLabel.alpha = percentDistance;
        self.trashView.microphoneIconLabel.alpha = 1-percentDistance;
        self.hold2TalkButton.textLabel.text = RELEASE_TO_SEND_STRING();
    }
    
    [self.view setNeedsUpdateConstraints];
}

- (void)didReleaseTouch:(OTRHoldToTalkView *)view
{
    //stop recording and send
    NSURL *currentURL = [self.audioSessionManager currentRecorderURL];
    [self.audioSessionManager stopRecording];
    AVURLAsset *audioAsset = [AVURLAsset assetWithURL:currentURL];
    Float64 duration = CMTimeGetSeconds(audioAsset.duration);
    
    
    if (currentURL) {
        // Delete recording if the button trash button is slelected or the audio is less than the minimum time.
        // This prevents taps on the record button from sending audio with extremely little length
        if (self.trashView.trashButton.isHighlighted || duration < kOTRMessagesMinimumAudioTime) {
            if([[NSFileManager defaultManager] fileExistsAtPath:currentURL.path]) {
                [[NSFileManager defaultManager] removeItemAtPath:currentURL.path error:nil];
            }
        } else {
            [self sendAudioFileURL:currentURL];
        }
    }

    
    [self removeTrashViewItems];
    [self setHold2TalkStatusWaiting];
    [self removeRecordingBackgroundView];
}

- (void)touchCancelled:(OTRHoldToTalkView *)view
{
    //stop recording and delete
    NSURL *currentURL = [self.audioSessionManager currentRecorderURL];
    [self.audioSessionManager stopRecording];
    if([[NSFileManager defaultManager] fileExistsAtPath:currentURL.path]) {
        [[NSFileManager defaultManager] removeItemAtPath:currentURL.path error:nil];
    }
    [self removeTrashViewItems];
    [self setHold2TalkStatusWaiting];
    [self removeRecordingBackgroundView];
}

#pragma - mark AudioSeessionDelegate

- (void)audioSession:(OTRAudioSessionManager *)audioSessionManager didUpdateRecordingDecibel:(double)decibel
{
    double scale = 0;
    //Values for human speech range quiet to loud
    double mindB = -80;
    double maxdB = -10;
    if (decibel >= maxdB) {
        //too loud
        scale = 1;
    } else if (decibel >= mindB && decibel <= maxdB) {
        //normal voice
        double powerFactor = 20;
        double mindBScale = pow(10, mindB / powerFactor);
        double maxdBScale = pow(10, maxdB / powerFactor);
        double linearScale = pow (10, decibel / powerFactor);
        double scaleMin = 0;
        double scaleMax = 1;
        //Get a value between 0 and 1 for mindB & maxdB values
        scale = ( ((scaleMax - scaleMin) * (linearScale - mindBScale)) / (maxdBScale - mindBScale)) + scaleMin;
    }
    
    [self.trashView setAnimationChange:30 * scale];
}

// BEGIN share location fuctions
- (void)attachmentPicker:(OTRAttachmentPicker *)attachmentPicker shareLocationButtonPressed:(NSURL *)locationURL
{
    [self.view endEditing:YES];
    [self addLocationViewBtns:YES];
    [self.view insertSubview:self.mapView belowSubview:self.locbar];
    [self.mapView autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsZero];
    
    CLLocationDegrees latd = self.mapView.userLocation.coordinate.latitude;
    CLLocationDegrees lond = self.mapView.userLocation.coordinate.longitude;
    
    self.mapView.userLocation.title = [self senderDisplayName];
    // possibly use reverse geocoding to get address?
    
    [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(latd, lond)
                            zoomLevel:12
                             animated:NO];
}

- (void)addLocationViewBtns:(BOOL)shareable
{
    self.locbar = [[UIToolbar alloc] initForAutoLayout];
    [self.locbar sizeToFit];
    
    NSMutableArray *barItems = [[NSMutableArray alloc] init];
    
    UIBarButtonItem *btnCancel = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancelLocation)];
    if (!shareable) {
        [btnCancel setTitle:@"Close"];
    }
    [barItems addObject:btnCancel];
    
    UIBarButtonItem *btnFlex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    [barItems addObject:btnFlex];
    
    if (shareable) {
        [barItems addObject:self.btnMapShare];
    }
    
    [self.locbar setItems:barItems animated:YES];
    
    self.locbar.barTintColor = [UIColor colorWithRed:249/255.0 green:249/255.0 blue:249/255.0 alpha:1];
    self.locbar.tintColor = [UIColor blackColor];
    self.locbar.translucent = NO;
    
    
    [self.view addSubview:self.locbar];
    [self removeMediaButtons];
    
    [self.hourglassButton removeFromSuperview];
    [self.microphoneButton removeFromSuperview];
    [self.attachButton removeFromSuperview];
    self.inputToolbar.contentView.leftBarButtonItem = nil;
    
    UIView *textView = self.inputToolbar.contentView;
    
    CGFloat offset = 1;
    
    [self.locbar autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:textView withOffset:-offset];
    [self.locbar autoPinEdge:ALEdgeTrailing toEdge:ALEdgeTrailing ofView:textView withOffset:offset];
    [self.locbar autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:textView withOffset:-offset];
    [self.locbar autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:textView withOffset:offset];
    
    
    [self.view setNeedsUpdateConstraints];
}

- (void)cancelLocation {
    [self.locbar removeFromSuperview];
    self.locbar = nil;
    [self.mapView removeFromSuperview];
    
    [self didUpdateState];
}

- (void)shareLocation {
    MGLUserLocation *userloc = [self.mapView userLocation];
    NSString *userLocString = [@"geo:" stringByAppendingFormat:@"%f,%f", userloc.coordinate.latitude,userloc.coordinate.longitude];
    
    [self cancelLocation];
    [self.inputToolbar.contentView.textView setText:userLocString];
    [self didPressSendButton:self.sendButton
             withMessageText:userLocString
                    senderId:self.senderId
           senderDisplayName:self.senderDisplayName
                        date:[NSDate date]];
}

- (BOOL)mapView:(MGLMapView *)mapView annotationCanShowCallout:(id <MGLAnnotation>)annotation {
    // Always try to show a callout when an annotation is tapped.
    return YES;
}

- (void)mapView:(MGLMapView *)mapView didUpdateUserLocation:(MGLUserLocation *)userLocation {
    self.btnMapShare.title = @"Share Location";
}

- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapMessageBubbleAtIndexPath:(NSIndexPath *)indexPath
{
    id <OTRMessageProtocol,JSQMessageData> message = [self messageAtIndexPath:indexPath];
    if (!message.isMediaMessage) {
        return;
    }
    __block OTRMediaItem *item = nil;
    [self.connections.read readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        item = [OTRMediaItem mediaItemForMessage:message transaction:transaction];
    }];
    if (!item) { return; }
    if (item.transferProgress != 1 && item.isIncoming) {
        return;
    }
    
    if ([item isKindOfClass:[OTRImageItem class]]) {
        // looking for geo tag for location
        id<OTRDownloadMessage> otrd = [item downloadMessage];
        NSString *origtext = [otrd messageOriginalText];
        if (origtext && [origtext hasPrefix:@"geo"]) {
            [self findBuddyLocation:origtext];
        } else {
            [super collectionView:collectionView didTapMessageBubbleAtIndexPath:indexPath];
        }
    } else {
        [super collectionView:collectionView didTapMessageBubbleAtIndexPath:indexPath];
    }
}

- (void) findBuddyLocation:(NSString *)buddyloc {
    NSString *buddycomponents = [buddyloc stringByReplacingOccurrencesOfString:@"geo:" withString:@""];
    
    NSArray *loccomponents = [buddycomponents componentsSeparatedByString:@","];
    if (loccomponents.count != 2) {
        return;
    }
    
    CLLocationDegrees latd = [[loccomponents firstObject] doubleValue];
    CLLocationDegrees lond = [[loccomponents lastObject] doubleValue];
    
    [self.view endEditing:YES]; 
    [self addLocationViewBtns:NO];
    [self.view insertSubview:self.mapView belowSubview:self.locbar];
    [self.mapView autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsZero];
    self.mapView.userLocation.title = [self senderDisplayName];
    
    MGLPointAnnotation *friendloc = [[MGLPointAnnotation alloc] init];
    friendloc.coordinate = CLLocationCoordinate2DMake(latd, lond);
    
    if ([self getThreadName]) {
        friendloc.title = [self getThreadName];
    }
    
    [self.mapView addAnnotation:friendloc];
    
    [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(latd, lond)
                            zoomLevel:12
                             animated:NO];
}
// END share location functions

- (void) handleMoreOptionsClick {
    [self.view endEditing:YES];
    self.inputToolbar.contentView.leftBarButtonItem = self.attachButton;
    
    [self.inputToolbar.contentView.leftBarButtonContainerView addSubview:self.microphoneButton];
    [self.microphoneButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    
    __block id<OTRThreadOwner> thread = nil;
    [self.connections.read readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        thread = [self threadObjectWithTransaction:transaction];
    }];
    if (thread.isGroupThread) {
        NSArray *cvconstraints = [self.inputToolbar.contentView.leftBarButtonContainerView constraints];
        [self.inputToolbar.contentView.leftBarButtonContainerView removeConstraints:cvconstraints];
        self.inputToolbar.contentView.leftBarButtonItemWidth = 55;
        
        [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.attachButton toEdge:NSLayoutAttributeBottom];
        [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.attachButton toEdge:NSLayoutAttributeTop];
        [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.attachButton toEdge:NSLayoutAttributeLeading];
        
        [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.microphoneButton toEdge:NSLayoutAttributeBottom];
        [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.microphoneButton toEdge:NSLayoutAttributeTop];
        [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.microphoneButton toEdge:NSLayoutAttributeTrailing];
        
        [self.microphoneButton autoPinEdge:ALEdgeLeading toEdge:ALEdgeTrailing ofView:self.attachButton withOffset:5];
        
        [self.inputToolbar.contentView setNeedsUpdateConstraints];
        return;
    }
    
    [self.inputToolbar.contentView.leftBarButtonContainerView addSubview:self.hourglassButton];
    [self.hourglassButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    
    NSArray *cvconstraints = [self.inputToolbar.contentView.leftBarButtonContainerView constraints];
    [self.inputToolbar.contentView.leftBarButtonContainerView removeConstraints:cvconstraints];
    self.inputToolbar.contentView.leftBarButtonItemWidth = 80;
    
    [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.attachButton toEdge:NSLayoutAttributeBottom];
    [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.attachButton toEdge:NSLayoutAttributeTop];
    [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.attachButton toEdge:NSLayoutAttributeLeading];
    
    [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.microphoneButton toEdge:NSLayoutAttributeBottom];
    [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.microphoneButton toEdge:NSLayoutAttributeTop];
    
    [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.hourglassButton toEdge:NSLayoutAttributeBottom];
    [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.hourglassButton toEdge:NSLayoutAttributeTop];
    [self.inputToolbar.contentView.leftBarButtonContainerView jsq_pinSubview:self.hourglassButton toEdge:NSLayoutAttributeTrailing];
    
    [self.microphoneButton autoPinEdge:ALEdgeLeading toEdge:ALEdgeTrailing ofView:self.attachButton withOffset:5];
    [self.hourglassButton autoPinEdge:ALEdgeLeading toEdge:ALEdgeTrailing ofView:self.microphoneButton withOffset:5];
    
    [self.inputToolbar.contentView setNeedsUpdateConstraints];
}

- (void)microphoneButtonTouched:(id)sender {
    [self.view endEditing:YES];
    if (self.state.hasText) {
        self.inputToolbar.contentView.textView.text = nil;
        self.state.hasText = NO;
    }
    [self.hourglassButton removeFromSuperview];
    [self.microphoneButton removeFromSuperview];
    [self.attachButton removeFromSuperview];
    self.inputToolbar.contentView.leftBarButtonItem = self.moreOptionsButton;
    self.inputToolbar.contentView.leftBarButtonItem.enabled = NO;
    self.inputToolbar.sendButtonLocation = JSQMessagesInputSendButtonLocationNone;
    [self addPush2TalkButton];
    
    self.inputToolbar.contentView.rightBarButtonItem = self.keyboardButton;
    self.inputToolbar.contentView.rightBarButtonItem.enabled = YES;
}


#pragma - mark JSQMessagesDelegate

- (void)didPressAccessoryButton:(UIButton *)sender
{
    if ([sender isEqual:self.microphoneButton]) {
        [self.view endEditing:YES];
        [self addPush2TalkButton];
        
        self.inputToolbar.contentView.rightBarButtonItem = self.keyboardButton;
    } else if ([sender isEqual:self.keyboardButton]) {
        [self removeMediaButtons];
        [self.inputToolbar.contentView.textView becomeFirstResponder];
        self.inputToolbar.contentView.leftBarButtonItem = nil;
        [self didUpdateState];
    } else if ([sender isEqual:self.moreOptionsButton]) {
        [self handleMoreOptionsClick];
    } else {
        [super didPressAccessoryButton:sender];
    }
}

// expiring message related functions here to end
- (void)hourglassButtonTouched:(id)sender {
    self.timePickerView = [[UIPickerView alloc]init];
    self.timePickerView.dataSource = self;
    self.timePickerView.delegate = self;
    self.timePickerView.backgroundColor = [UIColor colorWithRed:41/255.0 green:54/255.0 blue:62/255.0 alpha:1];
    
    self.timeTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clearTimePicker:)];
    self.timeTapGesture.delegate = self;
    self.timeTapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:self.timeTapGesture];
    
    self.timeTapGesture2 = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clearTimePicker:)];
    self.timeTapGesture2.delegate = self;
    self.timeTapGesture2.cancelsTouchesInView = NO;
    [self.timePickerView addGestureRecognizer:self.timeTapGesture2];
    
    NSString *strHeader = @"Set a time for the message to disappear";
    float lblWidth = self.view.frame.size.width;
    float lblXposition = self.timePickerView.frame.origin.x;
    float lblYposition = (self.timePickerView.frame.origin.y);
    
    UILabel *lblHeader = [[UILabel alloc] initWithFrame:CGRectMake(lblXposition, lblYposition,
                                                                   lblWidth, 20)];
    [lblHeader setText:strHeader];
    [lblHeader setTextAlignment:NSTextAlignmentCenter];
    lblHeader.textColor = [UIColor whiteColor];
    lblHeader.font = [UIFont fontWithName:kFontAwesomeFont size:10];
    [self.timePickerView addSubview:lblHeader];
    
    self.inputToolbar.contentView.rightBarButtonItem = self.sendButton;
    
    self.timePickerTextField = [[UITextField alloc]initWithFrame:CGRectZero];
    [self.view addSubview:self.timePickerTextField];
    
    self.timePickerTextField.inputView = self.timePickerView;
    [self.timePickerTextField becomeFirstResponder];
    
    NSInteger selrow = [self currentTimeSelectedRow];
    [self.timePickerView selectRow:selrow inComponent:0 animated:YES];
}

- (NSInteger) currentTimeSelectedRow {
    __block id<OTRThreadOwner> thread = nil;
    [self.connections.read readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        thread = [self threadObjectWithTransaction:transaction];
    }];
    if (thread && thread.expiresIn) {
        self.timeOn = YES;
        NSString *etime = thread.expiresIn;
        if ([etime isEqualToString:@"604800"]) {
            return 5;
        } else if ([etime isEqualToString:@"86400"]) {
            return 4;
        } else if ([etime isEqualToString:@"300"]) {
            return 3;
        } else if ([etime isEqualToString:@"60"]) {
            return 2;
        } else if ([etime isEqualToString:@"15"]) {
            return 1;
        }
    }
    self.timeOn = NO;
    return 0;
}

- (void)setThreadKey:(NSString *)key collection:(NSString *)collection
{
    [super setThreadKey:key collection:collection];
    [self updateTimeButton];
}

// called when initializing view or reentering view (viewWillAppear)
- (void) updateTimeButton {
    
    switch ([self currentTimeSelectedRow])
    {
        case 1:
            [self.timeButton setImage:[UIImage imageNamed:@"timer_15s_blue" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            break;
        case 2:
            [self.timeButton setImage:[UIImage imageNamed:@"timer_1m_blue" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            break;
        case 3:
            [self.timeButton setImage:[UIImage imageNamed:@"timer_5m_blue" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            break;
        case 4:
            [self.timeButton setImage:[UIImage imageNamed:@"timer_1d_blue" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            break;
        case 5:
            [self.timeButton setImage:[UIImage imageNamed:@"timer_1w_blue" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            break;
        default:
            break;
    }
    [self didUpdateState];
}

#pragma - mark UIPickerViewDelegate
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    
    return 1;
}


-(NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{
    return self.pickerArray.count;
}

- (NSAttributedString *)pickerView:(UIPickerView *)pickerView attributedTitleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    NSString *title = self.pickerArray[row];
    NSAttributedString *attString =
    [[NSAttributedString alloc] initWithString:title attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    
    return attString;
}


-(NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    return self.pickerArray[row];
}


-(void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
    __block id<OTRThreadOwner> thread = nil;
    [self.connections.read readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        thread = [self threadObjectWithTransaction:transaction];
    }];
    NSParameterAssert(thread);
    if (!thread) { return; }
    
    self.timeOn = YES;
    switch (row)
    {
        case 1:
            [self.timeButton setImage:[UIImage imageNamed:@"timer_15s_blue" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            thread.expiresIn = @"15";
            break;
        case 2:
            [self.timeButton setImage:[UIImage imageNamed:@"timer_1m_blue" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            thread.expiresIn = @"60";
            break;
        case 3:
            [self.timeButton setImage:[UIImage imageNamed:@"timer_5m_blue" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            thread.expiresIn = @"300";
            break;
        case 4:
            [self.timeButton setImage:[UIImage imageNamed:@"timer_1d_blue" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            thread.expiresIn = @"86400";
            break;
        case 5:
            [self.timeButton setImage:[UIImage imageNamed:@"timer_1w_blue" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            thread.expiresIn = @"604800";
            break;
        default:
            self.timeOn = NO;
            thread.expiresIn = nil;
            break;
    }
    
    // try setting send button to expires image
    if (self.timeOn) {
        self.inputToolbar.contentView.rightBarButtonItem = self.timeButton;
    }
}

-(BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer{
    return true;
}

- (void)clearTimePicker:(UITapGestureRecognizer *)gesture {
    [self.timePickerTextField resignFirstResponder];
    [self.timePickerTextField removeFromSuperview];
    self.timePickerTextField = nil;
    [self.view removeGestureRecognizer:self.timeTapGesture];
    [self.timePickerView removeGestureRecognizer:self.timeTapGesture2];
    self.timeTapGesture = nil;
    self.timeTapGesture2 = nil;
    self.timePickerView = nil;
    [self didUpdateState];
}

@end
