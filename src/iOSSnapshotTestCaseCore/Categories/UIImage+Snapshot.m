/*
 *  Copyright (c) 2017-2018, Uber Technologies, Inc.
 *  Copyright (c) 2015-2018, Facebook, Inc.
 *
 *  This source code is licensed under the MIT license found in the
 *  LICENSE file in the root directory of this source tree.
 *
 */

#import <math.h>

#if SWIFT_PACKAGE
#import "UIImage+Snapshot.h"
#import "UIApplication+KeyWindow.h"
#else
#import <FBSnapshotTestCase/UIImage+Snapshot.h>
#import <FBSnapshotTestCase/UIApplication+KeyWindow.h>
#endif

@implementation UIImage (Snapshot)

+ (UIImage *)fb_imageForLayer:(CALayer *)layer
{
    CGRect bounds = layer.bounds;
    NSAssert1(CGRectGetWidth(bounds), @"Zero width for layer %@", layer);
    NSAssert1(CGRectGetHeight(bounds), @"Zero height for layer %@", layer);

    UIGraphicsBeginImageContextWithOptions(bounds.size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    NSAssert1(context, @"Could not generate context for layer %@", layer);
    CGContextSaveGState(context);
    [layer layoutIfNeeded];
    [layer renderInContext:context];
    CGContextRestoreGState(context);

    UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return snapshot;
}

+ (UIImage *)fb_imageForViewLayer:(UIView *)view
{
    [view layoutIfNeeded];
    return [self fb_imageForLayer:view.layer];
}

+ (UIImage *)fb_imageForView:(UIView *)view
{
    // If the input view is already a UIWindow, then just use that. Otherwise wrap in a window.
    UIWindow *window = [view isKindOfClass:[UIWindow class]] ? (UIWindow *)view : view.window;
    BOOL removeFromSuperview = NO;
    if (!window) {
        window = [[UIApplication sharedApplication] ub_keyWindow];
    }

    if (!view.window && view != window) {
        [window addSubview:view];
        removeFromSuperview = YES;
    }

    [view layoutIfNeeded];

    CGRect bounds = view.bounds;
    NSAssert1(CGRectGetWidth(bounds), @"Zero width for view %@", view);
    NSAssert1(CGRectGetHeight(bounds), @"Zero height for view %@", view);

    // Render directly into a Display P3 bitmap context so the pixel values themselves are
    // computed in P3, rather than rendering in (extended) sRGB and re-tagging the color space
    // afterwards, which would leave the numeric pixel values wrong for the declared space.
    CGFloat scale = window.screen ? window.screen.scale : [UIScreen mainScreen].scale;
    size_t pixelWidth = (size_t)ceil(bounds.size.width * scale);
    size_t pixelHeight = (size_t)ceil(bounds.size.height * scale);

    CGColorSpaceRef p3ColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                  pixelWidth,
                                                  pixelHeight,
                                                  8,
                                                  0,
                                                  p3ColorSpace,
                                                  kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(p3ColorSpace);
    NSAssert1(context, @"Could not generate Display P3 context for view %@", view);

    // CGBitmapContextCreate uses a bottom-left origin, but UIKit drawing (and the rest of this
    // file, via UIGraphics*ImageContext) assumes a top-left origin. Flip vertically before
    // applying the points-to-pixels scale, otherwise the rendered snapshot comes out upside down.
    CGContextTranslateCTM(context, 0, pixelHeight);
    CGContextScaleCTM(context, scale, -scale);
    UIGraphicsPushContext(context);
    [view drawViewHierarchyInRect:bounds afterScreenUpdates:YES];
    UIGraphicsPopContext();

    if (removeFromSuperview) {
        [view removeFromSuperview];
    }

    CGImageRef p3CGImage = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    UIImage *snapshot = [UIImage imageWithCGImage:p3CGImage scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(p3CGImage);

    return snapshot;
}

@end
