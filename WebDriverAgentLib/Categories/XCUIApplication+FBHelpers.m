/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "XCUIApplication+FBHelpers.h"

#import "FBSpringboardApplication.h"
#import "XCElementSnapshot.h"
#import "FBElementTypeTransformer.h"
#import "FBMacros.h"
#import "FBMathUtils.h"
#import "FBXCodeCompatibility.h"
#import "FBXPath.h"
#import "XCElementSnapshot+FBHelpers.h"
#import "XCUIDevice+FBHelpers.h"
#import "XCUIElement+FBIsVisible.h"
#import "XCUIElement+FBUtilities.h"
#import "XCUIElement+FBWebDriverAttributes.h"

const static NSTimeInterval FBMinimumAppSwitchWait = 3.0;

@implementation XCUIApplication (FBHelpers)

- (BOOL)fb_deactivateWithDuration:(NSTimeInterval)duration error:(NSError **)error
{
  if(![[XCUIDevice sharedDevice] fb_goToHomescreenWithError:error]) {
    return NO;
  }
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:MAX(duration, FBMinimumAppSwitchWait)]];
  [self fb_activate];
  return YES;
}

- (NSDictionary *)fb_tree
{
  if ([FBConfiguration shouldUseTestManagerForVisibilityDetection]) {
    [self fb_waitUntilSnapshotIsStable];
  }

  // If getting the snapshot with attributes fails we use the snapshot with lazily initialized attributes
  XCElementSnapshot *snapshot = self.fb_snapshotWithAttributes ?: self.fb_lastSnapshot;

  NSMutableDictionary *snapshotTree = [[self.class dictionaryForElement:snapshot recursive:NO] mutableCopy];

  NSArray<XCUIElement *> *children = [self fb_filterDescendantsWithSnapshots:snapshot.children];
  NSMutableArray<NSDictionary *> *childrenTree = [NSMutableArray arrayWithCapacity:children.count];

  for (XCUIElement* child in children) {
    XCElementSnapshot *childSnapshot = child.fb_snapshotWithAttributes ?: child.fb_lastSnapshot;
    if (nil == childSnapshot) {
      continue;
    }
    [childrenTree addObject:[self.class dictionaryForElement:childSnapshot recursive:YES]];
  }

  if (childrenTree.count > 0) {
    [snapshotTree setObject:childrenTree.copy forKey:@"children"];
  }

  return snapshotTree.copy;
}

- (NSDictionary *)fb_accessibilityTree
{
  [self fb_waitUntilSnapshotIsStable];
  // We ignore all elements except for the main window for accessibility tree
  return [self.class accessibilityInfoForElement:(self.fb_snapshotWithAttributes ?: self.fb_lastSnapshot)];
}

+ (NSDictionary *)dictionaryForElement:(XCElementSnapshot *)snapshot recursive:(BOOL)recursive
{
  NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
  info[@"type"] = [FBElementTypeTransformer shortStringWithElementType:snapshot.elementType];
  info[@"rawIdentifier"] = FBValueOrNull([snapshot.identifier isEqual:@""] ? nil : snapshot.identifier);
  info[@"name"] = FBValueOrNull(snapshot.wdName);
  info[@"value"] = FBValueOrNull(snapshot.wdValue);
  info[@"label"] = FBValueOrNull(snapshot.wdLabel);
  // It is mandatory to replace all Infinity values with zeroes to avoid JSON parsing
  // exceptions like https://github.com/facebook/WebDriverAgent/issues/639#issuecomment-314421206
  // caused by broken element dimensions returned by XCTest
  info[@"rect"] = FBwdRectNoInf(snapshot.wdRect);
  info[@"frame"] = NSStringFromCGRect(snapshot.wdFrame);
  info[@"isEnabled"] = [@([snapshot isWDEnabled]) stringValue];
  info[@"isVisible"] = [@([snapshot isWDVisible]) stringValue];
#if TARGET_OS_TV
  info[@"isFocused"] = [@([snapshot isWDFocused]) stringValue];
#endif

  if (!recursive) {
    return info.copy;
  }

  NSArray *childElements = snapshot.children;
  if ([childElements count]) {
    info[@"children"] = [[NSMutableArray alloc] init];
    for (XCElementSnapshot *childSnapshot in childElements) {
      [info[@"children"] addObject:[self dictionaryForElement:childSnapshot recursive:YES]];
    }
  }
  return info;
}

+ (NSDictionary *)accessibilityInfoForElement:(XCElementSnapshot *)snapshot
{
  BOOL isAccessible = [snapshot isWDAccessible];
  BOOL isVisible = [snapshot isWDVisible];

  NSMutableDictionary *info = [[NSMutableDictionary alloc] init];

  if (isAccessible) {
    if (isVisible) {
      info[@"value"] = FBValueOrNull(snapshot.wdValue);
      info[@"label"] = FBValueOrNull(snapshot.wdLabel);
    }
  } else {
    NSMutableArray *children = [[NSMutableArray alloc] init];
    for (XCElementSnapshot *childSnapshot in snapshot.children) {
      NSDictionary *childInfo = [self accessibilityInfoForElement:childSnapshot];
      if ([childInfo count]) {
        [children addObject: childInfo];
      }
    }
    if ([children count]) {
      info[@"children"] = [children copy];
    }
  }
  if ([info count]) {
    info[@"type"] = [FBElementTypeTransformer shortStringWithElementType:snapshot.elementType];
    info[@"rawIdentifier"] = FBValueOrNull([snapshot.identifier isEqual:@""] ? nil : snapshot.identifier);
    info[@"name"] = FBValueOrNull(snapshot.wdName);
  } else {
    return nil;
  }
  return info;
}

- (NSString *)fb_xmlRepresentation
{
  return [FBXPath xmlStringWithRootElement:self];
}

- (NSString *)fb_descriptionRepresentation
{
  NSMutableArray<NSString *> *childrenDescriptions = [NSMutableArray array];
  for (XCUIElement *child in [self childrenMatchingType:XCUIElementTypeAny].allElementsBoundByAccessibilityElement) {
    [childrenDescriptions addObject:child.debugDescription];
  }
  // debugDescription property of XCUIApplication instance shows descendants addresses in memory
  // instead of the actual information about them, however the representation works properly
  // for all descendant elements
  return (0 == childrenDescriptions.count) ? self.debugDescription : [childrenDescriptions componentsJoinedByString:@"\n\n"];
}

- (XCUIElement *)fb_activeElement
{
  return [[[self descendantsMatchingType:XCUIElementTypeAny]
           matchingPredicate:[NSPredicate predicateWithFormat:@"hasKeyboardFocus == YES"]]
          fb_firstMatch];
}

#if TARGET_OS_TV
- (XCUIElement *)fb_focusedElement
{
  return [[[self descendantsMatchingType:XCUIElementTypeAny]
           matchingPredicate:[NSPredicate predicateWithFormat:@"hasFocus == true"]]
          fb_firstMatch];
}
#endif

// ADDED BY MO
static NSRegularExpression *pidRegex = nil;
-(void)findBundleIDs:(NSDictionary *)bundleIDs inAccessibilityDesc:(NSString *)desc {
  if (pidRegex == nil) {
    pidRegex = [NSRegularExpression regularExpressionWithPattern:@" pid: ([0-9]+), elementOrHash.elementID: " options:NSRegularExpressionCaseInsensitive error:nil];
  }
  
  NSArray *matches = [pidRegex matchesInString:desc options:0 range:NSMakeRange(0, [desc length])];
  for (NSTextCheckingResult *match in matches) {
    NSString *strPid = [desc substringWithRange:[match rangeAtIndex:1]];
    if (![bundleIDs objectForKey:strPid]) {
      FBApplication *app = [FBApplication fb_applicationWithPID:strPid.intValue];
      if (app && app.bundleID) {
        [bundleIDs setValue:app.bundleID forKey:strPid];
      } else {
        [bundleIDs setValue:@"" forKey:strPid];
      }
    }
  }
}

// ADDED BY MO
- (NSString *)fb_descriptionRepresentation_v2 {
  // bundleIDs
  NSString *pid = [NSString stringWithFormat:@"%ld", (long)self.processID];
  NSMutableDictionary<NSString *, NSString *> *bundleIDs = [NSMutableDictionary dictionary];
  [bundleIDs setValue:self.bundleID forKey:pid];
  
  // accessibility Description
  NSMutableArray<NSString *> *childrenDescriptions = [NSMutableArray array];
  for (XCUIElement *child in [self childrenMatchingType:XCUIElementTypeAny].allElementsBoundByAccessibilityElement) {
    NSString *desc = child.fb_lastSnapshot.recursiveDescriptionIncludingAccessibilityElement;
    [self findBundleIDs:bundleIDs inAccessibilityDesc:desc];
    [childrenDescriptions addObject:desc];
  }
  
  // Application Desc
  UIInterfaceOrientation orientation = self.interfaceOrientation;
  CGRect rect = self.frame;
  CGFloat x = rect.origin.x;
  CGFloat y = rect.origin.y;
  CGFloat width = rect.size.width;
  CGFloat height = rect.size.height;
  
  int rotation = 0;
  if (orientation == UIInterfaceOrientationLandscapeRight) {
    rotation = 1;
    width = rect.size.height;
    height = rect.size.width;
    
  } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
    rotation = 2;
    
  } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
    rotation = 3;
    width = rect.size.height;
    height = rect.size.width;
  }
  
  NSString *applicationDescription = nil;
  NSData *bundleIDsJson = [NSJSONSerialization dataWithJSONObject:bundleIDs options:0 error:nil];
  if (bundleIDsJson) {
    NSString *bundleIDsDesc = [[NSString alloc] initWithData:bundleIDsJson encoding:NSUTF8StringEncoding];
    applicationDescription = [NSString stringWithFormat:@"BundleIDs, %@\n\nApplication, bundle: %@, rotation: %d, {{%.1f, %.1f}, {%.1f, %.1f}}, pid: %@", bundleIDsDesc, self.bundleID, rotation, x, y, width, height, pid];
  } else {
    applicationDescription = [NSString stringWithFormat:@"Application, bundle: %@, rotation: %d, {{%.1f, %.1f}, {%.1f, %.1f}}, pid: %@", self.bundleID, rotation, x, y, width, height, pid];
  }
  
  if (0 == childrenDescriptions.count) {
    return applicationDescription;
  }
  
  [childrenDescriptions insertObject:applicationDescription atIndex:0];
  return [childrenDescriptions componentsJoinedByString:@"\n\n"];
}
@end
