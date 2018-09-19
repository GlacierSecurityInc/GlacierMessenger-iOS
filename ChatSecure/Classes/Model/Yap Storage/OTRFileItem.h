//
//  OTRFileItem.h
//  ChatSecure
//
//  Created by Chris Ballinger on 5/19/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

#import "OTRMediaItem.h"

/** This is a catch-all item for unknown file types */
@interface OTRFileItem : OTRMediaItem

//@property (nonatomic, readwrite) CGSize size;

/** If mimeType is not provided, it will be guessed from filename */
/*- (instancetype _Nullable ) initWithFileData:(NSData*_Nullable)data
                       isIncoming:(BOOL)isIncoming NS_DESIGNATED_INITIALIZER;


- (instancetype) initWithFilename:(NSString *)filename mimeType:(nullable NSString *)mimeType isIncoming:(BOOL)isIncoming NS_UNAVAILABLE;*/

@end
