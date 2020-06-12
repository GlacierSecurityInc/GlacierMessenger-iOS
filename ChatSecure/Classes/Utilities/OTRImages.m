//
//  OTRstatusImage.m
//  Off the Record
//
//  Created by David on 3/19/13.
//  Copyright (c) 2013 Chris Ballinger. All rights reserved.
//

#import "OTRImages.h"
#import "OTRUtilities.h"
#import "OTRColors.h"
@import BBlock;
@import JSQMessagesViewController;
#import "OTRComposingImageView.h"
#import "NSString+ChatSecure.h"
@import OTRAssets;

NSString *const OTRWarningImageKey = @"OTRWarningImageKey";
NSString *const OTRWarningCircleImageKey = @"OTRWarningCircleImageKey";
NSString *const OTRCheckmarkImageKey = @"OTRCeckmarkImageKey";
NSString *const OTRErrorImageKey = @"OTRErrorImageKey";
NSString *const OTRWifiImageKey = @"OTRWifiImageKey";
NSString *const OTRMicrophoneImageKey = @"OTRMicrophoneImageKey";

@implementation OTRImages

+ (NSCache *)imageCache{
    static NSCache *imageCache = nil;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        imageCache = [[NSCache alloc] init];
    });
    return imageCache;
}

+ (UIImage *)mirrorImage:(UIImage *)image {
    return [UIImage imageWithCGImage:image.CGImage
                               scale:image.scale
                         orientation:UIImageOrientationUpMirrored];
}

+ (UIImage *)image:(UIImage *)image maskWithColor:(UIColor *)maskColor
{
    CGRect imageRect = CGRectMake(0.0f, 0.0f, image.size.width, image.size.height);
    
    UIGraphicsBeginImageContextWithOptions(imageRect.size, NO, image.scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGContextScaleCTM(ctx, 1.0f, -1.0f);
    CGContextTranslateCTM(ctx, 0.0f, -(imageRect.size.height));
    
    CGContextClipToMask(ctx, imageRect, image.CGImage);
    CGContextSetFillColorWithColor(ctx, maskColor.CGColor);
    CGContextFillRect(ctx, imageRect);
    
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return newImage;
}

+ (UIImage *)circleWithRadius:(CGFloat)radius
{
    return [self circleWithRadius:radius lineWidth:0 lineColor:nil fillColor:nil];
}

+ (UIImage *)circleWithRadius:(CGFloat)radius lineWidth:(CGFloat)lineWidth lineColor:(UIColor *)lineColor fillColor:(UIColor *)fillColor
{
    if (!fillColor) {
        fillColor = [UIColor blackColor];
    }
    
    if (!lineColor) {
        lineColor = [UIColor blackColor];
    }
    
    return [UIImage imageForSize:CGSizeMake(radius*2+lineWidth, radius*2+lineWidth) opaque:NO withDrawingBlock:^{
        UIBezierPath* ovalPath = [UIBezierPath bezierPathWithOvalInRect: CGRectMake(lineWidth/2.0, lineWidth/2.0, radius*2.0, radius*2.0)];
        [fillColor setFill];
        [ovalPath fill];
        [lineColor setStroke];
        ovalPath.lineWidth = lineWidth;
        [ovalPath stroke];
        
    }];
    
}

+ (UIView *)typingBubbleView
{
    UIImageView * bubbleImageView = nil;
    UIImage * bubbleImage = nil;
    bubbleImage = [UIImage imageNamed:@"bubble-min-tailless" inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil];
    
    bubbleImage = [self image:bubbleImage maskWithColor:[OTRColors bubbleLightGrayColor]];
    bubbleImage = [self mirrorImage:bubbleImage];
    
    CGPoint center = CGPointMake((bubbleImage.size.width / 2.0f), bubbleImage.size.height / 2.0f);
    UIEdgeInsets capInsets = UIEdgeInsetsMake(center.y, center.x, center.y, center.x);
    
    bubbleImage = [bubbleImage resizableImageWithCapInsets:capInsets
                                                resizingMode:UIImageResizingModeStretch];
    
    bubbleImageView = [[OTRComposingImageView alloc] initWithImage:bubbleImage];
    CGRect rect = bubbleImageView.frame;
    rect.size.width = 60;
    bubbleImageView.frame = rect;
    
    return bubbleImageView;
}

+ (UIImage *)xmppServerImageWithName:(NSString *)name
{
    return [UIImage imageNamed:name inBundle:[OTRAssets resourcesBundle] compatibleWithTraitCollection:nil];
}

+(UIImage *)warningImage
{
    return [self warningImageWithColor:[OTRColors warnColor]];
}

+ (UIImage *)warningImageWithColor:(UIColor *)color;
{
    if (!color) {
        color = [UIColor blackColor];
    }
    
    NSString *identifier = [NSString stringWithFormat:@"%@-%@",OTRWarningImageKey,[color description]];
    
    return [UIImage imageWithIdentifier:identifier forSize:CGSizeMake(92.0, 92.0) andDrawingBlock:^{
        //// Bezier Drawing
        UIBezierPath* bezierPath = [UIBezierPath bezierPath];
        [bezierPath moveToPoint: CGPointMake(76.52, 86.78)];
        [bezierPath addLineToPoint: CGPointMake(15.48, 86.78)];
        [bezierPath addCurveToPoint: CGPointMake(2.43, 80.68) controlPoint1: CGPointMake(9.34, 86.78) controlPoint2: CGPointMake(4.71, 84.61)];
        [bezierPath addCurveToPoint: CGPointMake(3.67, 66.32) controlPoint1: CGPointMake(0.16, 76.74) controlPoint2: CGPointMake(0.6, 71.64)];
        [bezierPath addLineToPoint: CGPointMake(34.19, 13.47)];
        [bezierPath addCurveToPoint: CGPointMake(46, 5.22) controlPoint1: CGPointMake(37.26, 8.15) controlPoint2: CGPointMake(41.45, 5.22)];
        [bezierPath addCurveToPoint: CGPointMake(57.81, 13.47) controlPoint1: CGPointMake(50.54, 5.22) controlPoint2: CGPointMake(54.74, 8.15)];
        [bezierPath addLineToPoint: CGPointMake(88.33, 66.32)];
        [bezierPath addCurveToPoint: CGPointMake(89.56, 80.68) controlPoint1: CGPointMake(91.4, 71.64) controlPoint2: CGPointMake(91.84, 76.74)];
        [bezierPath addCurveToPoint: CGPointMake(76.52, 86.78) controlPoint1: CGPointMake(87.29, 84.61) controlPoint2: CGPointMake(82.66, 86.78)];
        [bezierPath closePath];
        [bezierPath moveToPoint: CGPointMake(52.23, 68.18)];
        [bezierPath addCurveToPoint: CGPointMake(46.48, 62.44) controlPoint1: CGPointMake(52.23, 65.01) controlPoint2: CGPointMake(49.65, 62.44)];
        [bezierPath addCurveToPoint: CGPointMake(40.74, 68.18) controlPoint1: CGPointMake(43.31, 62.44) controlPoint2: CGPointMake(40.74, 65.01)];
        [bezierPath addCurveToPoint: CGPointMake(46.48, 73.92) controlPoint1: CGPointMake(40.74, 71.35) controlPoint2: CGPointMake(43.31, 73.92)];
        [bezierPath addCurveToPoint: CGPointMake(52.23, 68.18) controlPoint1: CGPointMake(49.65, 73.92) controlPoint2: CGPointMake(52.23, 71.35)];
        [bezierPath closePath];
        [bezierPath moveToPoint: CGPointMake(52.38, 33.61)];
        [bezierPath addCurveToPoint: CGPointMake(46.48, 27.72) controlPoint1: CGPointMake(52.38, 30.36) controlPoint2: CGPointMake(49.74, 27.72)];
        [bezierPath addCurveToPoint: CGPointMake(40.59, 33.61) controlPoint1: CGPointMake(43.23, 27.72) controlPoint2: CGPointMake(40.59, 30.36)];
        [bezierPath addLineToPoint: CGPointMake(41.98, 54.55)];
        [bezierPath addLineToPoint: CGPointMake(42, 54.55)];
        [bezierPath addCurveToPoint: CGPointMake(46.48, 58.68) controlPoint1: CGPointMake(42.2, 56.86) controlPoint2: CGPointMake(44.12, 58.68)];
        [bezierPath addCurveToPoint: CGPointMake(50.92, 55.06) controlPoint1: CGPointMake(48.67, 58.68) controlPoint2: CGPointMake(50.5, 57.13)];
        [bezierPath addCurveToPoint: CGPointMake(50.97, 54.55) controlPoint1: CGPointMake(50.95, 54.9) controlPoint2: CGPointMake(50.95, 54.72)];
        [bezierPath addLineToPoint: CGPointMake(51.01, 54.55)];
        [bezierPath addLineToPoint: CGPointMake(52.38, 33.61)];
        [bezierPath closePath];
        bezierPath.miterLimit = 4;
        
        [color setFill];
        [bezierPath fill];

    }];
}

+ (UIImage *)circleWarningWithColor:(UIColor *)color
{
    if (!color) {
        color = [UIColor blackColor];
    }
    
    NSString *identifier = [NSString stringWithFormat:@"%@-%@",OTRWarningCircleImageKey,color.description];
    
    return [UIImage imageWithIdentifier:identifier forSize:CGSizeMake(60, 60) andDrawingBlock:^{
        //// Color Declarations
        
        //// Bezier Drawing
        UIBezierPath* bezierPath = [UIBezierPath bezierPath];
        [bezierPath moveToPoint: CGPointMake(30, 1)];
        [bezierPath addCurveToPoint: CGPointMake(1, 30) controlPoint1: CGPointMake(13.98, 1) controlPoint2: CGPointMake(1, 13.98)];
        [bezierPath addCurveToPoint: CGPointMake(30, 59) controlPoint1: CGPointMake(1, 46.02) controlPoint2: CGPointMake(13.98, 59)];
        [bezierPath addCurveToPoint: CGPointMake(59, 30) controlPoint1: CGPointMake(46.02, 59) controlPoint2: CGPointMake(59, 46.02)];
        [bezierPath addCurveToPoint: CGPointMake(30, 1) controlPoint1: CGPointMake(59, 13.98) controlPoint2: CGPointMake(46.02, 1)];
        [bezierPath closePath];
        [bezierPath moveToPoint: CGPointMake(29.36, 6.59)];
        [bezierPath addCurveToPoint: CGPointMake(30, 6.59) controlPoint1: CGPointMake(29.57, 6.57) controlPoint2: CGPointMake(29.78, 6.59)];
        [bezierPath addCurveToPoint: CGPointMake(36.32, 12.56) controlPoint1: CGPointMake(33.49, 6.59) controlPoint2: CGPointMake(36.32, 9.26)];
        [bezierPath addLineToPoint: CGPointMake(34.82, 33.8)];
        [bezierPath addLineToPoint: CGPointMake(34.79, 33.8)];
        [bezierPath addCurveToPoint: CGPointMake(34.73, 34.31) controlPoint1: CGPointMake(34.77, 33.98) controlPoint2: CGPointMake(34.76, 34.14)];
        [bezierPath addCurveToPoint: CGPointMake(30, 37.98) controlPoint1: CGPointMake(34.28, 36.4) controlPoint2: CGPointMake(32.34, 37.98)];
        [bezierPath addCurveToPoint: CGPointMake(25.21, 33.8) controlPoint1: CGPointMake(27.47, 37.98) controlPoint2: CGPointMake(25.43, 36.15)];
        [bezierPath addLineToPoint: CGPointMake(25.18, 33.8)];
        [bezierPath addLineToPoint: CGPointMake(23.68, 12.56)];
        [bezierPath addCurveToPoint: CGPointMake(29.36, 6.59) controlPoint1: CGPointMake(23.68, 9.46) controlPoint2: CGPointMake(26.18, 6.9)];
        [bezierPath closePath];
        [bezierPath moveToPoint: CGPointMake(30, 41.79)];
        [bezierPath addCurveToPoint: CGPointMake(36.13, 47.6) controlPoint1: CGPointMake(33.4, 41.79) controlPoint2: CGPointMake(36.13, 44.38)];
        [bezierPath addCurveToPoint: CGPointMake(30, 53.41) controlPoint1: CGPointMake(36.13, 50.82) controlPoint2: CGPointMake(33.4, 53.41)];
        [bezierPath addCurveToPoint: CGPointMake(23.87, 47.6) controlPoint1: CGPointMake(26.6, 53.41) controlPoint2: CGPointMake(23.87, 50.82)];
        [bezierPath addCurveToPoint: CGPointMake(30, 41.79) controlPoint1: CGPointMake(23.87, 44.38) controlPoint2: CGPointMake(26.6, 41.79)];
        [bezierPath closePath];
        bezierPath.miterLimit = 4;
        
        bezierPath.usesEvenOddFillRule = YES;
        
        [color setFill];
        [bezierPath fill];
    }];
}

+ (UIImage *)checkmarkWithColor:(UIColor *)color
{
    if (!color) {
        color = [UIColor blackColor];
    }
    
    NSString *identifier = [NSString stringWithFormat:@"%@-%@",OTRCheckmarkImageKey,[color description]];
    
    return [UIImage imageWithIdentifier:identifier forSize:CGSizeMake(100, 100) andDrawingBlock:^{
        UIBezierPath* bezierPath = [UIBezierPath bezierPath];
        [bezierPath moveToPoint: CGPointMake(50, 0)];
        [bezierPath addCurveToPoint: CGPointMake(0, 50) controlPoint1: CGPointMake(22.33, 0) controlPoint2: CGPointMake(0, 22.33)];
        [bezierPath addCurveToPoint: CGPointMake(50, 100) controlPoint1: CGPointMake(0, 77.67) controlPoint2: CGPointMake(22.33, 100)];
        [bezierPath addCurveToPoint: CGPointMake(100, 50) controlPoint1: CGPointMake(77.67, 100) controlPoint2: CGPointMake(100, 77.67)];
        [bezierPath addCurveToPoint: CGPointMake(50, 0) controlPoint1: CGPointMake(100, 22.33) controlPoint2: CGPointMake(77.67, 0)];
        [bezierPath closePath];
        [bezierPath moveToPoint: CGPointMake(79.89, 33.33)];
        [bezierPath addLineToPoint: CGPointMake(47.78, 73.44)];
        [bezierPath addCurveToPoint: CGPointMake(43.89, 75.44) controlPoint1: CGPointMake(46.78, 74.67) controlPoint2: CGPointMake(45.44, 75.33)];
        [bezierPath addCurveToPoint: CGPointMake(43.56, 75.44) controlPoint1: CGPointMake(43.78, 75.44) controlPoint2: CGPointMake(43.67, 75.44)];
        [bezierPath addCurveToPoint: CGPointMake(39.78, 73.89) controlPoint1: CGPointMake(42.11, 75.44) controlPoint2: CGPointMake(40.78, 74.89)];
        [bezierPath addLineToPoint: CGPointMake(20.56, 55)];
        [bezierPath addCurveToPoint: CGPointMake(20.56, 47.33) controlPoint1: CGPointMake(18.44, 52.89) controlPoint2: CGPointMake(18.44, 49.44)];
        [bezierPath addCurveToPoint: CGPointMake(28.22, 47.33) controlPoint1: CGPointMake(22.67, 45.22) controlPoint2: CGPointMake(26.11, 45.22)];
        [bezierPath addLineToPoint: CGPointMake(43.11, 62)];
        [bezierPath addLineToPoint: CGPointMake(71.44, 26.56)];
        [bezierPath addCurveToPoint: CGPointMake(79.11, 25.67) controlPoint1: CGPointMake(73.33, 24.22) controlPoint2: CGPointMake(76.78, 23.78)];
        [bezierPath addCurveToPoint: CGPointMake(79.89, 33.33) controlPoint1: CGPointMake(81.33, 27.56) controlPoint2: CGPointMake(81.78, 31)];
        [bezierPath closePath];
        bezierPath.miterLimit = 4;
        
        [color setFill];
        [bezierPath fill];
    }];
}

+ (UIImage *)errorWithColor:(UIColor *)color
{
    if (!color) {
        color = [UIColor blackColor];
    }
    
    NSString *identifier = [NSString stringWithFormat:@"%@-%@",OTRErrorImageKey,[color description]];
    
    return [UIImage imageWithIdentifier:identifier forSize:CGSizeMake(100, 100) andDrawingBlock:^{
        UIBezierPath* bezierPath = [UIBezierPath bezierPath];
        [bezierPath moveToPoint: CGPointMake(50, 0)];
        [bezierPath addCurveToPoint: CGPointMake(0, 50) controlPoint1: CGPointMake(22.33, 0) controlPoint2: CGPointMake(0, 22.33)];
        [bezierPath addCurveToPoint: CGPointMake(50, 100) controlPoint1: CGPointMake(0, 77.67) controlPoint2: CGPointMake(22.33, 100)];
        [bezierPath addCurveToPoint: CGPointMake(100, 50) controlPoint1: CGPointMake(77.67, 100) controlPoint2: CGPointMake(100, 77.67)];
        [bezierPath addCurveToPoint: CGPointMake(50, 0) controlPoint1: CGPointMake(100, 22.33) controlPoint2: CGPointMake(77.67, 0)];
        [bezierPath closePath];
        [bezierPath moveToPoint: CGPointMake(75.89, 69)];
        [bezierPath addCurveToPoint: CGPointMake(75.78, 76.67) controlPoint1: CGPointMake(78, 71.11) controlPoint2: CGPointMake(77.89, 74.56)];
        [bezierPath addCurveToPoint: CGPointMake(72, 78.22) controlPoint1: CGPointMake(74.78, 77.67) controlPoint2: CGPointMake(73.33, 78.22)];
        [bezierPath addCurveToPoint: CGPointMake(68.11, 76.56) controlPoint1: CGPointMake(70.56, 78.22) controlPoint2: CGPointMake(69.11, 77.67)];
        [bezierPath addLineToPoint: CGPointMake(50, 57.78)];
        [bezierPath addLineToPoint: CGPointMake(31.89, 76.56)];
        [bezierPath addCurveToPoint: CGPointMake(28, 78.22) controlPoint1: CGPointMake(30.78, 77.67) controlPoint2: CGPointMake(29.44, 78.22)];
        [bezierPath addCurveToPoint: CGPointMake(24.22, 76.67) controlPoint1: CGPointMake(26.67, 78.22) controlPoint2: CGPointMake(25.33, 77.67)];
        [bezierPath addCurveToPoint: CGPointMake(24.11, 69) controlPoint1: CGPointMake(22.11, 74.56) controlPoint2: CGPointMake(22, 71.11)];
        [bezierPath addLineToPoint: CGPointMake(42.44, 50)];
        [bezierPath addLineToPoint: CGPointMake(24.11, 31)];
        [bezierPath addCurveToPoint: CGPointMake(24.22, 23.33) controlPoint1: CGPointMake(22, 28.89) controlPoint2: CGPointMake(22.11, 25.44)];
        [bezierPath addCurveToPoint: CGPointMake(31.89, 23.44) controlPoint1: CGPointMake(26.33, 21.22) controlPoint2: CGPointMake(29.78, 21.33)];
        [bezierPath addLineToPoint: CGPointMake(50, 42.22)];
        [bezierPath addLineToPoint: CGPointMake(68.11, 23.56)];
        [bezierPath addCurveToPoint: CGPointMake(75.78, 23.44) controlPoint1: CGPointMake(70.22, 21.44) controlPoint2: CGPointMake(73.67, 21.33)];
        [bezierPath addCurveToPoint: CGPointMake(75.89, 31.11) controlPoint1: CGPointMake(77.89, 25.56) controlPoint2: CGPointMake(78, 29)];
        [bezierPath addLineToPoint: CGPointMake(57.56, 50)];
        [bezierPath addLineToPoint: CGPointMake(75.89, 69)];
        [bezierPath closePath];
        bezierPath.miterLimit = 4;
        
        [color setFill];
        [bezierPath fill];
    }];
}

+ (UIImage *)wifiWithColor:(UIColor *)color
{
    if (!color) {
        color = [UIColor blackColor];
    }
    
    NSString *identifier = [NSString stringWithFormat:@"%@-%@",OTRWifiImageKey,color];
    return [UIImage imageWithIdentifier:identifier forSize:CGSizeMake(100, 100) andDrawingBlock:^{
        UIBezierPath* bezierPath = [UIBezierPath bezierPath];
        [bezierPath moveToPoint: CGPointMake(50, 15.69)];
        [bezierPath addCurveToPoint: CGPointMake(0, 35.77) controlPoint1: CGPointMake(30.38, 15.69) controlPoint2: CGPointMake(12.72, 23.39)];
        [bezierPath addLineToPoint: CGPointMake(6.43, 42.4)];
        [bezierPath addCurveToPoint: CGPointMake(50, 25.05) controlPoint1: CGPointMake(17.42, 31.7) controlPoint2: CGPointMake(32.82, 25.05)];
        [bezierPath addCurveToPoint: CGPointMake(93.57, 42.4) controlPoint1: CGPointMake(67.18, 25.05) controlPoint2: CGPointMake(82.58, 31.7)];
        [bezierPath addLineToPoint: CGPointMake(100, 35.77)];
        [bezierPath addCurveToPoint: CGPointMake(50, 15.69) controlPoint1: CGPointMake(87.28, 23.39) controlPoint2: CGPointMake(69.62, 15.69)];
        [bezierPath addLineToPoint: CGPointMake(50, 15.69)];
        [bezierPath closePath];
        [bezierPath moveToPoint: CGPointMake(50, 34.4)];
        [bezierPath addCurveToPoint: CGPointMake(13.65, 49.22) controlPoint1: CGPointMake(36, 34.4) controlPoint2: CGPointMake(22.97, 39.9)];
        [bezierPath addLineToPoint: CGPointMake(20.28, 55.85)];
        [bezierPath addCurveToPoint: CGPointMake(50, 43.76) controlPoint1: CGPointMake(27.8, 48.32) controlPoint2: CGPointMake(38.43, 43.76)];
        [bezierPath addCurveToPoint: CGPointMake(79.83, 55.55) controlPoint1: CGPointMake(61.57, 43.76) controlPoint2: CGPointMake(72.3, 48.3)];
        [bezierPath addLineToPoint: CGPointMake(86.26, 48.83)];
        [bezierPath addCurveToPoint: CGPointMake(50.01, 34.4) controlPoint1: CGPointMake(76.95, 39.86) controlPoint2: CGPointMake(64.01, 34.4)];
        [bezierPath addLineToPoint: CGPointMake(50, 34.4)];
        [bezierPath closePath];
        [bezierPath moveToPoint: CGPointMake(50.01, 53.12)];
        [bezierPath addCurveToPoint: CGPointMake(27.98, 62.28) controlPoint1: CGPointMake(41.48, 53.12) controlPoint2: CGPointMake(33.54, 56.72)];
        [bezierPath addLineToPoint: CGPointMake(34.61, 68.91)];
        [bezierPath addCurveToPoint: CGPointMake(50.01, 62.47) controlPoint1: CGPointMake(38.4, 65.11) controlPoint2: CGPointMake(44.19, 62.47)];
        [bezierPath addCurveToPoint: CGPointMake(65.41, 68.91) controlPoint1: CGPointMake(55.82, 62.47) controlPoint2: CGPointMake(61.61, 65.11)];
        [bezierPath addLineToPoint: CGPointMake(72.03, 62.28)];
        [bezierPath addCurveToPoint: CGPointMake(50.01, 53.12) controlPoint1: CGPointMake(66.47, 56.72) controlPoint2: CGPointMake(58.54, 53.12)];
        [bezierPath closePath];
        [bezierPath moveToPoint: CGPointMake(50.01, 71.83)];
        [bezierPath addCurveToPoint: CGPointMake(41.23, 75.54) controlPoint1: CGPointMake(46.58, 71.83) controlPoint2: CGPointMake(43.42, 73.35)];
        [bezierPath addLineToPoint: CGPointMake(50.01, 84.31)];
        [bezierPath addLineToPoint: CGPointMake(58.78, 75.54)];
        [bezierPath addCurveToPoint: CGPointMake(50.01, 71.83) controlPoint1: CGPointMake(56.6, 73.04) controlPoint2: CGPointMake(53.44, 71.83)];
        [bezierPath closePath];
        bezierPath.miterLimit = 4;
        
        [color setFill];
        [bezierPath fill];
    }];
}

+ (UIImage *)microphoneWithColor:(UIColor *)color size:(CGSize)size
{
    if (!color) {
        color = [UIColor blackColor];
    }
    
    if (CGSizeEqualToSize(size, CGSizeZero)) {
        size = CGSizeMake(69.232, 100);
    } else {
        CGFloat normalRatio = 0.69232;
        CGFloat ratio = size.width / size.height;
        if (ratio < 0.69232 ) {
            size.height = size.width / normalRatio;
            
        } else {
            size.width = size.height * normalRatio;
        }
    }
    
    NSString *identifier = [NSString stringWithFormat:@"%@%@",OTRMicrophoneImageKey,[color description]];
    return [UIImage imageWithIdentifier:identifier forSize:size andDrawingBlock:^{
        
        CGRect group2 = CGRectMake(0, 0, size.width, size.height);
        
        
        //// Group 2
        {
            //// Bezier Drawing
            UIBezierPath* bezierPath = UIBezierPath.bezierPath;
            [bezierPath moveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.49999 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.69230 * CGRectGetHeight(group2))];
            [bezierPath addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.69616 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.63582 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.57639 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.69230 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.64177 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.67347 * CGRectGetHeight(group2))];
            [bezierPath addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.77775 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.50000 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.75055 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.59817 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.77775 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.55289 * CGRectGetHeight(group2))];
            [bezierPath addLineToPoint: CGPointMake(CGRectGetMinX(group2) + 0.77775 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.19231 * CGRectGetHeight(group2))];
            [bezierPath addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.69616 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.05649 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.77775 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.13942 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.75057 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.09416 * CGRectGetHeight(group2))];
            [bezierPath addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.49999 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.00000 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.64177 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.01884 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.57639 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.00000 * CGRectGetHeight(group2))];
            [bezierPath addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.30382 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.05649 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.42360 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.00000 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.35822 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.01884 * CGRectGetHeight(group2))];
            [bezierPath addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.22222 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.19231 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.24942 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.09415 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.22222 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.13942 * CGRectGetHeight(group2))];
            [bezierPath addLineToPoint: CGPointMake(CGRectGetMinX(group2) + 0.22222 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.50000 * CGRectGetHeight(group2))];
            [bezierPath addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.30382 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.63582 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.22222 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.55289 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.24943 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.59817 * CGRectGetHeight(group2))];
            [bezierPath addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.49999 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.69230 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.35821 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.67347 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.42360 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.69230 * CGRectGetHeight(group2))];
            [bezierPath closePath];
            bezierPath.miterLimit = 4;
            
            [color setFill];
            [bezierPath fill];
            
            
            //// Bezier 3 Drawing
            UIBezierPath* bezier3Path = UIBezierPath.bezierPath;
            [bezier3Path moveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.98349 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.39603 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.94443 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.38461 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.97251 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.38842 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.95947 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.38461 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.90537 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.39603 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.92938 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.38461 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.91636 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.38842 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.88888 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.42307 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.89437 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.40365 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.88888 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.41266 * CGRectGetHeight(group2))];
            [bezier3Path addLineToPoint: CGPointMake(CGRectGetMinX(group2) + 0.88888 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.50000 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.77473 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.69020 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.88888 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.57412 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.85082 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.63751 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.49999 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.76923 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.69864 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.74289 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.60706 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.76923 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.22525 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.69020 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.39293 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.76923 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.30136 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.74289 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.11111 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.50000 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.14916 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.63753 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.11111 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.57412 * CGRectGetHeight(group2))];
            [bezier3Path addLineToPoint: CGPointMake(CGRectGetMinX(group2) + 0.11111 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.42307 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.09462 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.39603 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.11111 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.41266 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.10562 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.40365 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.05556 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.38461 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.08363 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.38842 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.07062 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.38461 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.01649 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.39603 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.04051 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.38461 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.02749 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.38842 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.00000 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.42307 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.00550 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.40365 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.00000 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.41266 * CGRectGetHeight(group2))];
            [bezier3Path addLineToPoint: CGPointMake(CGRectGetMinX(group2) + 0.00000 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.50000 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.12803 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.73107 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.00000 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.58854 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.04268 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.66557 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.44443 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.84374 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.21338 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.79657 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.31885 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.83413 * CGRectGetHeight(group2))];
            [bezier3Path addLineToPoint: CGPointMake(CGRectGetMinX(group2) + 0.44443 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.92307 * CGRectGetHeight(group2))];
            [bezier3Path addLineToPoint: CGPointMake(CGRectGetMinX(group2) + 0.22222 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.92307 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.18316 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.93449 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.20717 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.92307 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.19415 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.92688 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.16666 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.96153 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.17216 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.94210 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.16666 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.95112 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.18316 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.98857 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.16666 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.97194 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.17216 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.98097 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.22222 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 1.00000 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.19415 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.99619 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.20717 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 1.00000 * CGRectGetHeight(group2))];
            [bezier3Path addLineToPoint: CGPointMake(CGRectGetMinX(group2) + 0.77775 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 1.00000 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.81681 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.98857 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.79280 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 1.00000 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.80584 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.99619 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.83332 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.96153 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.82782 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.98097 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.83332 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.97194 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.81681 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.93449 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.83332 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.95112 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.82782 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.94210 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.77775 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.92307 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.80584 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.92688 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.79280 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.92307 * CGRectGetHeight(group2))];
            [bezier3Path addLineToPoint: CGPointMake(CGRectGetMinX(group2) + 0.55556 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.92307 * CGRectGetHeight(group2))];
            [bezier3Path addLineToPoint: CGPointMake(CGRectGetMinX(group2) + 0.55556 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.84374 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.87195 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.73107 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.68112 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.83413 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.78658 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.79657 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 1.00000 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.50000 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 0.95731 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.66557 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 1.00000 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.58854 * CGRectGetHeight(group2))];
            [bezier3Path addLineToPoint: CGPointMake(CGRectGetMinX(group2) + 1.00000 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.42307 * CGRectGetHeight(group2))];
            [bezier3Path addCurveToPoint: CGPointMake(CGRectGetMinX(group2) + 0.98349 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.39603 * CGRectGetHeight(group2)) controlPoint1: CGPointMake(CGRectGetMinX(group2) + 1.00000 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.41266 * CGRectGetHeight(group2)) controlPoint2: CGPointMake(CGRectGetMinX(group2) + 0.99449 * CGRectGetWidth(group2), CGRectGetMinY(group2) + 0.40365 * CGRectGetHeight(group2))];
            [bezier3Path closePath];
            bezier3Path.miterLimit = 4;
            
            [color setFill];
            [bezier3Path fill];
        }

    }];
}

+ (UIImage *)imageWithIdentifier:(NSString *)identifier
{
    return [[self imageCache] objectForKey:identifier];
}

+ (void)removeImageWithIdentifier:(NSString *)identifier
{
    [[self imageCache] removeObjectForKey:identifier];
}

+ (void)setImage:(UIImage *)image forIdentifier:(NSString *)identifier
{
    if (![identifier length]) {
        return;
    }
    
    if (image && [image isKindOfClass:[UIImage class]]) {
        
        [[self imageCache] setObject:image forKey:identifier];
        
    } else if (!image) {
        [self removeImageWithIdentifier:identifier];
    }
}

+ (UIImage *)avatarImageWithUsername:(NSString *)username
{
    NSString *initials = [username otr_stringInitialsWithMaxCharacters:2];
    /*JSQMessagesAvatarImage *jsqImage = [JSQMessagesAvatarImageFactory avatarImageWithUserInitials:initials
                                                                                  backgroundColor:[UIColor colorWithWhite:0.85f alpha:1.0f]
                                                                                        textColor:[UIColor colorWithWhite:0.60f alpha:1.0f]
                                                                                             font:[UIFont systemFontOfSize:30.0f]
                                                                                         diameter:60];*/
    JSQMessagesAvatarImage *jsqImage = [JSQMessagesAvatarImageFactory avatarImageWithUserInitials:initials backgroundColor:[UIColor colorWithRed:41/255.0 green:54/255.0 blue:62/255.0 alpha:1] textColor:[UIColor colorWithWhite:0.60f alpha:1.0f] font:[UIFont systemFontOfSize:30.0f] diameter:60]; 
    return jsqImage.avatarImage;
}

+ (UIImage *)avatarImageWithUniqueIdentifier:(NSString *)identifier avatarData:(NSData *)data displayName:(NSString *)displayName username:(NSString *)username
{
    UIImage *image = [self imageWithIdentifier:identifier];
    if (!image) {
        if (data) {
            image = [UIImage imageWithData:data];
        }
        else {
            NSString *name  = displayName;
            if (![name length]) {
                name = [[username componentsSeparatedByString:@"@"] firstObject];
                if (![name length]) {
                    name = username;
                }
            }
            if (!name) {
                name = @"";
            }
            image = [self avatarImageWithUsername:name];
        }
        
        [self setImage:image forIdentifier:identifier];
    }
    
    return image;
}

@end
