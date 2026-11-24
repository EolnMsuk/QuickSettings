// QuickSettings — EolnMsuk. See LICENSE.
#pragma once
#import <Foundation/Foundation.h>

// SpringBoard's immutable index facade. Only Settings can establish a positive.
@interface QSSettingsEligibility : NSObject
+ (instancetype)sharedEligibility;
@property (nonatomic, copy) void (^changeHandler)(void);
- (void)setEnabled:(BOOL)enabled preferenceGeneration:(NSUInteger)generation;
// Memory-only result; any demand refresh is queued, never awaited by the menu.
- (NSDictionary *)recordForBundleIdentifier:(NSString *)bundleID;
- (void)reloadIndex;
@end
