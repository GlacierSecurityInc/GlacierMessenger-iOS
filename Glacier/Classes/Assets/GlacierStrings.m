//
//  GlacierStrings.m
//  Glacier
//
//  Created by Andy Friedman on 6/17/20.
//  Copyright © 2020 Glacier. All rights reserved.
//

#import "GlacierStrings.h"
#import "GlacierInfo.h"

@implementation GlacierStrings

+(NSString *)translatedString:(NSString *)englishString
{
    NSBundle *bundle = [GlacierInfo resourcesBundle];
    NSParameterAssert(bundle != nil);
    
    NSString *bundlePath = [bundle pathForResource:@"Localizable" ofType:@"strings" inDirectory:nil forLocalization:@"Base"];
    NSBundle *foreignBundle = [[NSBundle alloc] initWithPath:[bundlePath stringByDeletingLastPathComponent]];
    NSString * translatedString = NSLocalizedStringFromTableInBundle(englishString, nil, foreignBundle, nil);
    
    if (![translatedString length]) {
        translatedString = englishString;
    }
    return translatedString;
}

@end

