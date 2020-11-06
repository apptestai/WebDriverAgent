/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

@class XCAccessibilityElement;

NS_ASSUME_NONNULL_BEGIN

@interface FBActiveAppDetectionPoint : NSObject

@property (nonatomic) CGPoint coordinates;
// ADDED BY MO
@property (nonatomic, copy, nullable) NSString *platform;
// END
/**
 * Retrieves singleton representation of the current class
 */
+ (instancetype)sharedInstance;

/**
 * Calculates the accessbility element which is located at the given screen coordinates
 *
 * @param point The screen coordinates
 * @returns The retrieved accessbility element or nil if it cannot be detected
 */
+ (nullable XCAccessibilityElement *)axElementWithPoint:(CGPoint)point;

/**
 * Retrieves the accessbility element for the current screen point
 *
 * @returns The retrieved accessbility element or nil if it cannot be detected
 */
- (nullable XCAccessibilityElement *)axElement;

/**
 * Sets the coordinates for the current screen point
 *
 * @param coordinatesStr The coordinates string in `x,y` format. x and y can be any float numbers
 * @param error Is assigned to the actual error object if coordinates cannot be set
 * @returns YES if the coordinates were successfully set
 */
- (BOOL)setCoordinatesWithString:(NSString *)coordinatesStr error:(NSError **)error;

/**
 * Retrieves the coordinates of the current screen point in string representation
 *
 * @returns Point coordinates as `x,y` string
 */
- (NSString *)stringCoordinates;

// ADDED BY MO: extends setCoordinatesWithString method by reserved types such as left-top, top, right-top, center, left-bottom, bottom, right-bottom
/**
  parse coordinate with reserved keywords such as left-top, top, right-top, center, left-bottom, bottom, right-bottom
  @param coordinatesType reserved keywords such as left-top, top, right-top, center, left-bottom, bottom, right-bottom
                        left-top    : MIN(w, h)*0.2, MIN(w, h)*0.2
                        top         : w/2, MIN(w, h)*0.2
                        right-top   : w-MIN(w, h)*0.2, MIN(w, h)*0.2
                        center      : w/2, h/2
                        left-bottom : MIN(w, h)*0.2, h-MIN(w, h)*0.2
                        bottom      : w/2, h-MIN(w, h)*0.2
                        right-bottom: w-MIN(w, h)*0.2, h-MIN(w, h)*0.2
  @return CGPoint. Can return CGPointZero if error occured
 */
- (CGPoint)parseCoordinatesWithReservedType:(NSString *)coordinatesType;
//END

@end

NS_ASSUME_NONNULL_END
