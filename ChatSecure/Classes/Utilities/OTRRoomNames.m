//
//  OTRRoomNames.m
//  ChatSecureCore
//
//  Created by Andy Friedman on 11/13/17.
//  Copyright © 2017 Glacier Security, Inc. All rights reserved.
//

#import "OTRRoomNames.h"
@import OTRAssets;

@implementation OTRRoomNames

static NSArray *firstWord;
static NSArray *secondWord;

+ (void)loadFirstWord {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        firstWord = [NSArray arrayWithObjects: @"snowy",
                                                @"restless",
                                                @"calm",
                                                @"ancient",
                                                @"summer",
                                                @"evening",
                                                @"guarded",
                                                @"lively",
                                                @"thawing",
                                                @"autumn",
                                                @"thriving",
                                                @"patient",
                                                @"winter",
                                                @"pleasant",
                                                @"thundering",
                                                @"spring",
                                                @"elegant",
                                                @"narrow",
                                                @"abundant", nil];
    });
}

+ (void)loadSecondWord {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        secondWord = [NSArray arrayWithObjects: @"waterfall",
                                                @"meadow",
                                                @"skies",
                                                @"waves",
                                                @"fields",
                                                @"stars",
                                                @"dreams",
                                                @"refuge",
                                                @"forest",
                                                @"plains",
                                                @"waters",
                                                @"plateau",
                                                @"thunder",
                                                @"volcano",
                                                @"glacier",
                                                @"wilderness",
                                                @"peaks",
                                                @"mountains",
                                                @"vineyards", nil];
    });
}

+(NSString *)getRoomName {
    if (!firstWord) {
        [self loadFirstWord];
        [self loadSecondWord];
    }
    
    NSString *wordOne = firstWord[arc4random_uniform((uint32_t)firstWord.count)];
    NSString *wordTwo = secondWord[arc4random_uniform((uint32_t)secondWord.count)];
    NSString *roomName = [NSString stringWithFormat:@"%@-%@-%u", wordOne, wordTwo, arc4random_uniform(99)+1];
    
    return roomName;
}

@end
