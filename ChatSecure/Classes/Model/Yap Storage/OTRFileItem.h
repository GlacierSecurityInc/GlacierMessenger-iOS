//
//  OTRFileItem.h
//  ChatSecure
//
//  Created by Chris Ballinger on 5/19/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

#import "OTRMediaItem.h"

/** This is a catch-all item for unknown file types */
NS_ASSUME_NONNULL_BEGIN
@interface OTRFileItem : OTRMediaItem

@property (nonatomic, readwrite) CGSize size;

/** If mimeType is not provided, it will be guessed from filename */
- (instancetype) initWithFileURL:(NSURL*)url
                       isIncoming:(BOOL)isIncoming NS_DESIGNATED_INITIALIZER;


- (instancetype) initWithFilename:(NSString *)filename mimeType:(nullable NSString *)mimeType isIncoming:(BOOL)isIncoming NS_UNAVAILABLE;

@end
NS_ASSUME_NONNULL_END
