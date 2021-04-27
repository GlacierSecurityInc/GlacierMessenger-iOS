//
//  GlacierShareDataInterface.h
//  Glacier
//
//  Created by Andy Friedman on 12/15/20.
//  Copyright © 2020 Glacier. All rights reserved.
//
@import Foundation;
#import "OTRThreadOwner.h"

@protocol ShareExtensionDelegate <NSObject>
@required
- (void)doneSending:(BOOL)success;
@end

@protocol ShareMessageDelegate <NSObject>
@required
- (void)doShare:(id<OTRMessageProtocol>_Nullable)message;
@end

@interface GlacierShareDataInterface : NSObject
- (instancetype _Nonnull)initWithDelegate:(id<ShareExtensionDelegate>_Nonnull)delegate;
- (NSArray * _Nonnull) getAllConversations;
- (void) doShare:(NSString * _Nonnull)text withOwner:(id<OTRThreadOwner>)owner;
- (void) doShare:(NSURL * _Nonnull)url withOwner:(id<OTRThreadOwner>)owner withType:(NSInteger)mediaType;
- (void) setupMediaManager;
- (void)teardownStream; 
@end
