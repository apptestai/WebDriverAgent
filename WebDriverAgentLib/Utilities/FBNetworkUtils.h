//
//  FBNetworkUtils.h
//  WebDriverAgentLib
//
//  Created by MO on 11/03/2020.
//  Copyright © 2020 Facebook. All rights reserved.
//

#ifndef FBNetworkUtils_h
#define FBNetworkUtils_h

#import <Foundation/Foundation.h>

@interface FBNetworkUtils : NSObject

/**
 Use this method to get your device local ip address in connected wifi network
 @return local ip address in string format
 */
+ (NSString *)ipaddress;

@end
#endif /* FBNetworkUtils_h */
