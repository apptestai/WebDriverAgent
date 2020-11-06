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
#import "FBLogger.h"
#import "FBMacros.h"
#import "FBMathUtils.h"
#import "FBActiveAppDetectionPoint.h"
#import "FBXCodeCompatibility.h"
#import "FBXPath.h"
#import "FBXCTestDaemonsProxy.h"
#import "FBXCAXClientProxy.h"
#import "XCAccessibilityElement.h"
#import "XCElementSnapshot+FBHelpers.h"
#import "XCUIDevice+FBHelpers.h"
#import "XCUIElement+FBIsVisible.h"
#import "XCUIElement+FBUtilities.h"
#import "XCUIElement+FBWebDriverAttributes.h"
#import "XCTestManager_ManagerInterface-Protocol.h"
#import "XCTestPrivateSymbols.h"
#import "XCTRunnerDaemonSession.h"

const static NSTimeInterval FBMinimumAppSwitchWait = 3.0;
static NSString* const FBUnknownBundleId = @"unknown";


@implementation XCUIApplication (FBHelpers)

- (BOOL)fb_waitForAppElement:(NSTimeInterval)timeout
{
  __block BOOL canDetectAxElement = YES;
  int currentProcessIdentifier = self.accessibilityElement.processIdentifier;
  BOOL result = [[[FBRunLoopSpinner new]
           timeout:timeout]
          spinUntilTrue:^BOOL{
    XCAccessibilityElement *currentAppElement = FBActiveAppDetectionPoint.sharedInstance.axElement;
    canDetectAxElement = nil != currentAppElement;
    if (!canDetectAxElement) {
      return YES;
    }
    return currentAppElement.processIdentifier == currentProcessIdentifier;
  }];
  return canDetectAxElement
    ? result
    : [self waitForExistenceWithTimeout:timeout];
}

+ (NSArray<NSDictionary<NSString *, id> *> *)fb_appsInfoWithAxElements:(NSArray<XCAccessibilityElement *> *)axElements
{
  NSMutableArray<NSDictionary<NSString *, id> *> *result = [NSMutableArray array];
  id<XCTestManager_ManagerInterface> proxy = [FBXCTestDaemonsProxy testRunnerProxy];
  for (XCAccessibilityElement *axElement in axElements) {
    NSMutableDictionary<NSString *, id> *appInfo = [NSMutableDictionary dictionary];
    pid_t pid = axElement.processIdentifier;
    appInfo[@"pid"] = @(pid);
    __block NSString *bundleId = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [proxy _XCT_requestBundleIDForPID:pid
                                reply:^(NSString *bundleID, NSError *error) {
                                  if (nil == error) {
                                    bundleId = bundleID;
                                  } else {
                                    [FBLogger logFmt:@"Cannot request the bundle ID for process ID %@: %@", @(pid), error.description];
                                  }
                                  dispatch_semaphore_signal(sem);
                                }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)));
    appInfo[@"bundleId"] = bundleId ?: FBUnknownBundleId;
    [result addObject:appInfo.copy];
  }
  return result.copy;
}

+ (NSArray<NSDictionary<NSString *, id> *> *)fb_activeAppsInfo
{
  return [self fb_appsInfoWithAxElements:[FBXCAXClientProxy.sharedClient activeApplications]];
}

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
  XCElementSnapshot *snapshot = self.fb_cachedSnapshot ?: self.fb_lastSnapshot;
  NSMutableDictionary *rootTree = [[self.class dictionaryForElement:snapshot recursive:NO] mutableCopy];
  NSArray<XCUIElement *> *children = [self fb_filterDescendantsWithSnapshots:snapshot.children
                                                                     selfUID:snapshot.wdUID
                                                                onlyChildren:YES];
  NSMutableArray<NSDictionary *> *childrenTrees = [NSMutableArray arrayWithCapacity:children.count];
  [self fb_waitUntilSnapshotIsStable];
  for (XCUIElement* child in children) {
    XCElementSnapshot *childSnapshot = child.fb_snapshotWithAllAttributes;
    if (nil == childSnapshot) {
      [FBLogger logFmt:@"Skipping source dump for '%@' because its snapshot cannot be resolved", child.description];
      continue;
    }
    [childrenTrees addObject:[self.class dictionaryForElement:childSnapshot recursive:YES]];
  }
  // This is necessary because web views are not visible in the native page source otherwise
  [rootTree setObject:childrenTrees.copy forKey:@"children"];

  return rootTree.copy;
}

- (NSDictionary *)fb_accessibilityTree
{
  [self fb_waitUntilSnapshotIsStable];
  // We ignore all elements except for the main window for accessibility tree
  return [self.class accessibilityInfoForElement:(self.fb_snapshotWithAllAttributes ?: self.fb_lastSnapshot)];
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
  return [FBXPath xmlStringWithRootElement:self excludingAttributes:nil];
}

- (NSString *)fb_xmlRepresentationWithoutAttributes:(NSArray<NSString *> *)excludedAttributes
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullable-to-nonnull-conversion"
  return [FBXPath xmlStringWithRootElement:self excludingAttributes:excludedAttributes];
#pragma clang diagnostic pop
}

- (NSString *)fb_descriptionRepresentation
{
  NSMutableArray<NSString *> *childrenDescriptions = [NSMutableArray array];
  for (XCUIElement *child in [self.fb_query childrenMatchingType:XCUIElementTypeAny].allElementsBoundByAccessibilityElement) {
    [childrenDescriptions addObject:child.debugDescription];
  }
  // debugDescription property of XCUIApplication instance shows descendants addresses in memory
  // instead of the actual information about them, however the representation works properly
  // for all descendant elements
  return (0 == childrenDescriptions.count) ? self.debugDescription : [childrenDescriptions componentsJoinedByString:@"\n\n"];
}

- (XCUIElement *)fb_activeElement
{
  return [[[self.fb_query descendantsMatchingType:XCUIElementTypeAny]
           matchingPredicate:[NSPredicate predicateWithFormat:@"hasKeyboardFocus == YES"]]
          fb_firstMatch];
}

#if TARGET_OS_TV
- (XCUIElement *)fb_focusedElement
{
  return [[[self.fb_query descendantsMatchingType:XCUIElementTypeAny]
           matchingPredicate:[NSPredicate predicateWithFormat:@"hasFocus == true"]]
          fb_firstMatch];
}
#endif

+ (NSInteger)fb_testmanagerdVersion
{
  static dispatch_once_t getTestmanagerdVersion;
  static NSInteger testmanagerdVersion;
  dispatch_once(&getTestmanagerdVersion, ^{
    id<XCTestManager_ManagerInterface> proxy = [FBXCTestDaemonsProxy testRunnerProxy];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [proxy _XCT_exchangeProtocolVersion:testmanagerdVersion reply:^(unsigned long long code) {
      testmanagerdVersion = (NSInteger) code;
      dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)));
  });
  return testmanagerdVersion;
}

- (BOOL)fb_resetAuthorizationStatusForResource:(long long)resourceId error:(NSError **)error
{
  SEL selector = NSSelectorFromString(@"resetAuthorizationStatusForResource:");
  if (![self respondsToSelector:selector]) {
    return [[[FBErrorBuilder builder]
             withDescription:@"'resetAuthorizationStatusForResource' API is only supported for Xcode SDK 11.4 and later"]
            buildError:error];
  }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  [self performSelector:selector withObject:@(resourceId)];
#pragma clang diagnostic pop
  return YES;
}

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
//END

// ADDED BY MO
- (NSString *)fb_descriptionRepresentation_v2 {
  // bundleIDs
  NSString *pid = [NSString stringWithFormat:@"%ld", (long)self.processID];
  NSMutableDictionary<NSString *, NSString *> *bundleIDs = [NSMutableDictionary dictionary];
  [bundleIDs setValue:self.bundleID forKey:pid];
  
  // accessibility Description
  NSMutableArray<NSString *> *childrenDescriptions = [NSMutableArray array];
  for (XCUIElement *child in [self.fb_query childrenMatchingType:XCUIElementTypeAny].allElementsBoundByAccessibilityElement) {
    NSString *desc = child.fb_lastSnapshot.recursiveDescriptionIncludingAccessibilityElement;
    if (desc != nil) {
      [self findBundleIDs:bundleIDs inAccessibilityDesc:desc];
      [childrenDescriptions addObject:desc];
    }
  }
  
  // Application Desc
  UIInterfaceOrientation orientation = self.interfaceOrientation;
  int rotation = 0;
  CGRect bounds = self.fb_screenBounds;
  if (orientation == UIInterfaceOrientationLandscapeRight) {
    rotation = 1;
  } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
    rotation = 2;
  } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
    rotation = 3;
  }
  
  NSString *applicationDescription = nil;
  NSData *bundleIDsJson = [NSJSONSerialization dataWithJSONObject:bundleIDs options:0 error:nil];
  if (bundleIDsJson) {
    NSString *bundleIDsDesc = [[NSString alloc] initWithData:bundleIDsJson encoding:NSUTF8StringEncoding];
    applicationDescription = [NSString stringWithFormat:@"BundleIDs, %@\n\nApplication, bundle: %@, rotation: %d, {{%.1f, %.1f}, {%.1f, %.1f}}, pid: %@",
                              bundleIDsDesc, self.bundleID, rotation, bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height, pid];
  } else {
    applicationDescription = [NSString stringWithFormat:@"Application, bundle: %@, rotation: %d, {{%.1f, %.1f}, {%.1f, %.1f}}, pid: %@",
                              self.bundleID, rotation, bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height, pid];
  }
  
  if (0 == childrenDescriptions.count) {
    return applicationDescription;
  }
  
  [childrenDescriptions insertObject:applicationDescription atIndex:0];
  return [childrenDescriptions componentsJoinedByString:@"\n\n"];
}
//END

// ADDED BY MO
- (CGRect)fb_screenBounds
{
  UIInterfaceOrientation orientation = self.interfaceOrientation;
  CGRect rect = self.frame;
  CGFloat x = rect.origin.x;
  CGFloat y = rect.origin.y;
  CGFloat width = rect.size.width;
  CGFloat height = rect.size.height;
  
  if (orientation == UIInterfaceOrientationLandscapeRight) {
    width = rect.size.height;
    height = rect.size.width;
  } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
  } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
    width = rect.size.height;
    height = rect.size.width;
  }
  return CGRectMake(x, y, width, height);
}
//END
@end
