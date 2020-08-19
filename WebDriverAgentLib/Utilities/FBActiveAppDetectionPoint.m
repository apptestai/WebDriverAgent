/**
* Copyright (c) 2015-present, Facebook, Inc.
* All rights reserved.
*
* This source code is licensed under the BSD-style license found in the
* LICENSE file in the root directory of this source tree. An additional grant
* of patent rights can be found in the PATENTS file in the same directory.
*/

#import "FBActiveAppDetectionPoint.h"

#import "FBErrorBuilder.h"
#import "FBLogger.h"
#import "FBXCTestDaemonsProxy.h"
#import "XCTestManager_ManagerInterface-Protocol.h"

//ADDED BY MO
#import "XCUIDevice+FBHelpers.h"
#import "FBConfiguration.h"
//END

@implementation FBActiveAppDetectionPoint

- (instancetype)init {
  if ((self = [super init])) {
    //MODIFIED BY MO: [UIScreen mainScreen].bounds is invalid
//    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    _platform = XCUIDevice.sharedDevice.fb_devicePlatform;
    CGSize screenSize = [self screenBounds].size;
    //END
    // Consider the element, which is located close to the top left corner of the screen the on-screen one.
    CGFloat pointDistance = MIN(screenSize.width, screenSize.height) * (CGFloat) 0.2;
    _coordinates = CGPointMake(pointDistance, pointDistance);
    
  }
  return self;
}

+ (instancetype)sharedInstance
{
  static FBActiveAppDetectionPoint *instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[self alloc] init];
  });
  return instance;
}

+ (XCAccessibilityElement *)axElementWithPoint:(CGPoint)point
{
  __block XCAccessibilityElement *onScreenElement = nil;
  id<XCTestManager_ManagerInterface> proxy = [FBXCTestDaemonsProxy testRunnerProxy];
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  [proxy _XCT_requestElementAtPoint:point
                              reply:^(XCAccessibilityElement *element, NSError *error) {
                                if (nil == error) {
                                  onScreenElement = element;
                                } else {
                                  [FBLogger logFmt:@"Cannot request the screen point at %@: %@", [NSValue valueWithCGPoint:point], error.description];
                                }
                                dispatch_semaphore_signal(sem);
                              }];
  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)));
  return onScreenElement;
}

- (XCAccessibilityElement *)axElement
{
  // ADDED BY MO: When the device rotates to landscape, the bounds(point) should be updated.
  NSString * coordinatesType = FBConfiguration.activeAppDetectionPoint;
  if (coordinatesType != nil && coordinatesType.length > 0 && [coordinatesType rangeOfString:@","].location == NSNotFound) {
    CGPoint point = [self parseCoordinatesWithReservedType:coordinatesType];
    if (!CGPointEqualToPoint(point, CGPointZero)) {
      self.coordinates = point;
    }
  }
  // END
  return [self.class axElementWithPoint:self.coordinates];
}

- (BOOL)setCoordinatesWithString:(NSString *)coordinatesStr error:(NSError **)error
{
//ADDED BY MO: extends setCoordinatesWithString method by reserved types such as left-top, top, right-top, center, left-bottom, bottom, right-bottom
  CGPoint point = [self parseCoordinatesWithReservedType:coordinatesStr];
  if (!CGPointEqualToPoint(point, CGPointZero)) {
    self.coordinates = point;
    return YES;
  }
//END
  
  NSArray<NSString *> *screenPointCoords = [coordinatesStr componentsSeparatedByString:@","];
  if (screenPointCoords.count != 2) {
    return [[[FBErrorBuilder builder]
             withDescriptionFormat:@"The screen point coordinates should be separated by a single comma character. Got '%@' instead", coordinatesStr]
            buildError:error];
  }
  NSString *strX = [screenPointCoords.firstObject stringByTrimmingCharactersInSet:
                    NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSString *strY = [screenPointCoords.lastObject stringByTrimmingCharactersInSet:
                    NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (0 == strX.length || 0 == strY.length) {
    return [[[FBErrorBuilder builder]
             withDescriptionFormat:@"Both screen point coordinates should be valid numbers. Got '%@' instead", coordinatesStr]
            buildError:error];
  }
  self.coordinates = CGPointMake((CGFloat) strX.doubleValue, (CGFloat) strY.doubleValue);
  return YES;
}

- (NSString *)stringCoordinates
{
  return [NSString stringWithFormat:@"%.2f,%.2f", self.coordinates.x, self.coordinates.y];
}

//  ADDED BY MO: extends setCoordinatesWithString method by reserved types such as left-top, top, right-top, center, left-bottom, bottom, right-bottom
- (CGPoint)parseCoordinatesWithReservedType:(NSString *)coordinatesType
{
  CGPoint point = CGPointZero;
  CGSize screenSize = [self screenBounds].size;
  // Consider the element, which is located close to the top left corner of the screen the on-screen one.
  CGFloat pointDistance = MIN(screenSize.width, screenSize.height) * (CGFloat) 0.2;
  CGPoint center = CGPointMake(screenSize.width / (CGFloat) 2.0, screenSize.height / (CGFloat) 2.0);
  
  //  left-top    : MIN(w, h)*0.2, MIN(w, h)*0.2
  if ([coordinatesType isEqualToString:@"left-top"]) {
    point = CGPointMake(pointDistance, pointDistance);
  }
  //  top         : w/2, MIN(w, h)*0.2
  else if ([coordinatesType isEqualToString:@"top"]) {
    point = CGPointMake(center.x, pointDistance);
  }
  //  right-top   : w-MIN(w, h)*0.2, MIN(w, h)*0.2
  else if ([coordinatesType isEqualToString:@"right-top"]) {
    point = CGPointMake(screenSize.width - pointDistance, pointDistance);
  }
  //  center      : w/2, h/2
  else if ([coordinatesType isEqualToString:@"center"]) {
    point = CGPointMake(center.x, center.y);
  }
  //  left-bottom : MIN(w, h)*0.2, h-MIN(w, h)*0.2
  else if ([coordinatesType isEqualToString:@"left-bottom"]) {
    point = CGPointMake(pointDistance, screenSize.height - pointDistance);
  }
  //  bottom      : w/2, h-MIN(w, h)*0.2
  else if ([coordinatesType isEqualToString:@"bottom"]) {
    point = CGPointMake(center.x, screenSize.height - pointDistance);
  }
  //  right-bottom: w-MIN(w, h)*0.2, h-MIN(w, h)*0.2
  else if ([coordinatesType isEqualToString:@"right-bottom"]) {
    point = CGPointMake(screenSize.width - pointDistance, screenSize.height - pointDistance);
  }
  
  return point;
}
//END

//ADDED BY MO: [UIScreen mainScreen].bounds is invalid(return value of iPhone7 => w:=320, h:=480), use static matching
- (CGRect)screenBounds
{
  CGRect bounds = [UIScreen mainScreen].bounds;
  if (self.platform == nil) {
    return bounds;
  }
  
  if (MAX(bounds.size.width, bounds.size.height) > (CGFloat) 480) {
    return bounds;
  }
  
//  https://www.paintcodeapp.com/news/ultimate-guide-to-iphone-resolutions
//  https://qastack.kr/programming/11197509/how-to-get-device-make-and-model-on-ios
//  iPhone 5, 5c, 5s, SE, SE 2nd
  if ([self.platform hasPrefix:@"iPhone5"] || [self.platform isEqualToString:@"iPhone8,4"] || [self.platform hasPrefix:@"iPhone5"] || [self.platform hasPrefix:@"iPhone6"] || [self.platform hasPrefix:@"iPhone12,8"])
    bounds = CGRectMake(0, 0, 320, 568);
  
  // iPhone X
  else if ([self.platform isEqualToString:@"iPhone10,3"] || [self.platform isEqualToString:@"iPhone10,6"])
    bounds = CGRectMake(0, 0, 375, 812);
  
  // iPhone Plus 6, 6s
  else if ([self.platform isEqualToString:@"iPhone7,1"] || [self.platform isEqualToString:@"iPhone8,2"])
    bounds = CGRectMake(0, 0, 414, 736);
  // iPhone 7 Plus CDMA, GSM
  else if ([self.platform isEqualToString:@"iPhone9,2"] || [self.platform isEqualToString:@"iPhone9,4"])
    bounds = CGRectMake(0, 0, 414, 736);
  // iPhone 8 Plus CDMA, GSM
  else if ([self.platform isEqualToString:@"iPhone10,2"] || [self.platform isEqualToString:@"iPhone10,5"])
    bounds = CGRectMake(0, 0, 414, 736);
  
  // iPhone 6, 6s, 7 CDMA, 7 GSM, 8 CDMA, 8 GSM
  else if ([self.platform hasPrefix:@"iPhone7"] || [self.platform hasPrefix:@"iPhone8"] || [self.platform hasPrefix:@"iPhone9"] || [self.platform hasPrefix:@"iPhone10"])
    bounds = CGRectMake(0, 0, 375, 667);
  
  // iPhone XS, 11 Pro
  else if ([self.platform isEqualToString:@"iPhone11,2"] || [self.platform isEqualToString:@"iPhone11,3"])
    bounds = CGRectMake(0, 0, 375, 812);
  
  // iPhone 11, XR, XS Max, XS Max China, 11 Pro Max
  else if ([self.platform hasPrefix:@"iPhone11"] || [self.platform hasPrefix:@"iPhone12"])
    bounds = CGRectMake(0, 0, 414, 896);
  
  if (MAX(bounds.size.width, bounds.size.height) > (CGFloat) 480) {
    UIDeviceOrientation orientation = XCUIDevice.sharedDevice.orientation;
    if (orientation == UIInterfaceOrientationLandscapeRight) {
      bounds = CGRectMake(0, 0, bounds.size.height, bounds.size.width);
    } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
      bounds = CGRectMake(0, 0, bounds.size.height, bounds.size.width);
    }
  }
  return bounds;
}
@end
