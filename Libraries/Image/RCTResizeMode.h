/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTConvert.h"
#import "AppKit/AppKit.h"


typedef NS_ENUM(NSInteger, RCTResizeMode) {
  RCTResizeModeCover = 1,
  RCTResizeModeContain = 2, // TODO: actual NSImageResizingMode
  RCTResizeModeStretch = 3,
};

@interface RCTConvert(RCTResizeMode)

+ (RCTResizeMode)RCTResizeMode:(id)json;

@end
