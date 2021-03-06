/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTImageView.h"

#import "RCTBridge.h"
#import "RCTConvert.h"
#import "RCTEventDispatcher.h"
#import "UIImageUtils.h"
#import "RCTImageLoader.h"
#import "RCTImageSource.h"
#import "RCTImageUtils.h"
#import "RCTUtils.h"

#import "NSView+React.h"

/**
 * Determines whether an image of `currentSize` should be reloaded for display
 * at `idealSize`.
 */
static BOOL RCTShouldReloadImageForSizeChange(CGSize currentSize, CGSize idealSize)
{
  static const CGFloat upscaleThreshold = 1.2;
  static const CGFloat downscaleThreshold = 0.5;

  CGFloat widthMultiplier = idealSize.width / currentSize.width;
  CGFloat heightMultiplier = idealSize.height / currentSize.height;

  return widthMultiplier > upscaleThreshold || widthMultiplier < downscaleThreshold ||
    heightMultiplier > upscaleThreshold || heightMultiplier < downscaleThreshold;
}

@interface RCTImageView ()

@property (nonatomic, copy) RCTDirectEventBlock onLoadStart;
@property (nonatomic, copy) RCTDirectEventBlock onProgress;
@property (nonatomic, copy) RCTDirectEventBlock onError;
@property (nonatomic, copy) RCTDirectEventBlock onLoad;
@property (nonatomic, copy) RCTDirectEventBlock onLoadEnd;

@end

@implementation RCTImageView
{
  __weak RCTBridge *_bridge;
  CGSize _targetSize;

  /**
   * A block that can be invoked to cancel the most recent call to -reloadImage,
   * if any.
   */
  RCTImageLoaderCancellationBlock _reloadImageCancellationBlock;
}

- (instancetype)initWithBridge:(RCTBridge *)bridge
{
  if ((self = [super initWithFrame:NSZeroRect])) {
    _bridge = bridge;
    [self setWantsLayer:YES];
  }
  return self;
}

RCT_NOT_IMPLEMENTED(- (instancetype)init)
RCT_NOT_IMPLEMENTED(- (instancetype)initWithFrame:(NSRect)frameRect)
RCT_NOT_IMPLEMENTED(- (instancetype)initWithCoder:(NSCoder *)coder)

- (void)updateImage
{
  NSImage *image = self.image;
  if (!image) {
    return;
  }

  // Apply rendering mode
//  if (_renderingMode != image.renderingMode) {
//    image = [image imageWithRenderingMode:_renderingMode];
//  }

  // Applying capInsets of 0 will switch the "resizingMode" of the image to "tile" which is undesired
  // TODO:
//  if (!NSEdgeInsetsEqualToEdgeInsets(NSEdgeInsetsZero, _capInsets)) {
//    image = [image resizableImageWithCapInsets:_capInsets];
//  }

  // Apply trilinear filtering to smooth out mis-sized images
  self.layer.minificationFilter = kCAFilterTrilinear;
  self.layer.magnificationFilter = kCAFilterTrilinear;

  super.image = image;
}

- (void)setImage:(NSImage *)image
{
//  image = image ?: _defaultImage;
//  if (image != super.image) {
//    super.image = image;
//    [self updateImage];
//  }
  CGFloat desiredScaleFactor = [[RCTSharedApplication() mainWindow] backingScaleFactor];
  CGFloat actualScaleFactor = [image recommendedLayerContentsScale:desiredScaleFactor];

  id layerContents = [image layerContentsForContentsScale:actualScaleFactor];

  [self.layer setContents:layerContents];
  [self.layer setContentsScale:actualScaleFactor];
}

// TODO: Replace it with proper mechanism
static inline BOOL UIEdgeInsetsEqualToEdgeInsets(NSEdgeInsets insets1, NSEdgeInsets insets2) {
  return CGRectEqualToRect(CGRectMake(insets1.left, insets1.top, insets1.right, insets1.bottom),
                           CGRectMake(insets2.left, insets2.top, insets2.right, insets2.bottom));
}

- (void)setCapInsets:(NSEdgeInsets)capInsets
{
  if (!UIEdgeInsetsEqualToEdgeInsets(_capInsets, capInsets)) {
    if (UIEdgeInsetsEqualToEdgeInsets(_capInsets, NSEdgeInsetsZero) ||
        UIEdgeInsetsEqualToEdgeInsets(capInsets, NSEdgeInsetsZero)) {
      _capInsets = capInsets;
      // Need to reload image when enabling or disabling capInsets
      [self reloadImage];
    } else {
      _capInsets = capInsets;
      [self updateImage];
    }
  }
}

//- (void)setRenderingMode:(UIImageRenderingMode)renderingMode
//{
//  if (_renderingMode != renderingMode) {
//    _renderingMode = renderingMode;
//    [self updateImage];
//  }
//}

- (void)setSource:(RCTImageSource *)source
{
  if (![source isEqual:_source]) {
    _source = source;
    [self reloadImage];
  }
}

- (BOOL)sourceNeedsReload
{
  // If capInsets are set, image doesn't need reloading when resized
  return UIEdgeInsetsEqualToEdgeInsets(_capInsets, NSEdgeInsetsZero);
}

//- (void)setContentMode:(NSViewContentMode)mode
//{
//  if (self.contentMode != contentMode) {
//    super.contentMode = contentMode;
//    if ([self sourceNeedsReload]) {
//      [self reloadImage];
//    }
//}

- (void)cancelImageLoad
{
  RCTImageLoaderCancellationBlock previousCancellationBlock = _reloadImageCancellationBlock;
  if (previousCancellationBlock) {
    previousCancellationBlock();
    _reloadImageCancellationBlock = nil;
  }
}

- (void)clearImage
{
  [self cancelImageLoad];
  [self.layer removeAnimationForKey:@"contents"];
  self.image = nil;
}

- (void)reloadImage
{
  [self cancelImageLoad];

  if (_source && self.frame.size.width > 0 && self.frame.size.height > 0) {
    if (_onLoadStart) {
      _onLoadStart(nil);
    }

    RCTImageLoaderProgressBlock progressHandler = nil;
    if (_onProgress) {
      progressHandler = ^(int64_t loaded, int64_t total) {
        _onProgress(@{
          @"loaded": @((double)loaded),
          @"total": @((double)total),
        });
      };
    }

    CGSize imageSize = self.bounds.size;
    CGFloat imageScale = RCTScreenScale();
    if (!UIEdgeInsetsEqualToEdgeInsets(_capInsets, NSEdgeInsetsZero)) {
      // Don't resize images that use capInsets
      imageSize = CGSizeZero;
      imageScale = _source.scale;
    }

    RCTImageSource *source = _source;
    __weak RCTImageView *weakSelf = self;
    _reloadImageCancellationBlock = [_bridge.imageLoader loadImageWithoutClipping:_source.imageURL.absoluteString
                                                                             size:imageSize
                                                                            scale:imageScale
                                                                       resizeMode:(RCTResizeMode)self.contentMode
                                                                    progressBlock:progressHandler
                                                                  completionBlock:^(NSError *error, NSImage *image) {

      dispatch_async(dispatch_get_main_queue(), ^{
        RCTImageView *strongSelf = weakSelf;
        if (![source isEqual:strongSelf.source]) {
          // Bail out if source has changed since we started loading
          return;
        }
        if (image.reactKeyframeAnimation) {
          [strongSelf.layer addAnimation:image.reactKeyframeAnimation forKey:@"contents"];
        } else {
          [strongSelf.layer removeAnimationForKey:@"contents"];
          strongSelf.image = image;
        }
        if (error) {
          if (strongSelf->_onError) {
            strongSelf->_onError(@{ @"error": error.localizedDescription });
          }
        } else {
          if (strongSelf->_onLoad) {
            strongSelf->_onLoad(nil);
          }
        }
        if (strongSelf->_onLoadEnd) {
           strongSelf->_onLoadEnd(nil);
        }
      });
    }];
  } else {
    [self clearImage];
  }
}

- (void)reactSetFrame:(CGRect)frame
{
  [super reactSetFrame:frame];

  if (!self.image || self.image == _defaultImage) {
    _targetSize = frame.size;
    [self reloadImage];
  } else if ([self sourceNeedsReload]) {
    CGSize imageSize = self.image.size;

    // TODO: replace 1.0 with real scale
    CGSize idealSize = RCTTargetSize(imageSize, 1.0f, frame.size,
                                     RCTScreenScale(), (RCTResizeMode)self.contentMode, YES);

    if (RCTShouldReloadImageForSizeChange(imageSize, idealSize)) {
      if (RCTShouldReloadImageForSizeChange(_targetSize, idealSize)) {
        RCTLogInfo(@"[PERF IMAGEVIEW] Reloading image %@ as size %f x %f", _source.imageURL, idealSize.width, idealSize.height);

        // If the existing image or an image being loaded are not the right
        // size, reload the asset in case there is a better size available.
        _targetSize = idealSize;
        [self reloadImage];
      }
    } else {
      // Our existing image is good enough.
      [self cancelImageLoad];
      _targetSize = imageSize;
    }
  }
}

- (void)didMoveToWindow
{
  //[super didMoveToWindow];

  if (!self.window) {
    // Don't keep self alive through the asynchronous dispatch, if the intention
    // was to remove the view so it would deallocate.
    __weak typeof(self) weakSelf = self;

    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(self) strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }

      // If we haven't been re-added to a window by this run loop iteration,
      // clear out the image to save memory.
      if (!strongSelf.window) {
        [strongSelf clearImage];
      }
    });
  } else if (!self.image || self.image == _defaultImage) {
    [self reloadImage];
  }
}

@end
