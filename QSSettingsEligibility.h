// QuickSettings — EolnMsuk. See LICENSE.
#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, QSSettingsEligibilityState) {
    QSSettingsEligibilityUnknown,
    QSSettingsEligibilityIneligible,
    QSSettingsEligibilityEligible
};

@interface QSSettingsEligibility : NSObject
+ (instancetype)sharedEligibility;
// Older preference publications cannot re-enable discovery after a newer reload.
- (void)setEnabled:(BOOL)enabled preferenceGeneration:(NSUInteger)generation;
// Memory-only lookups; cold/stale data coalesces asynchronous recovery.
- (QSSettingsEligibilityState)stateForBundleIdentifier:(NSString *)bundleID
                                          generation:(NSUInteger *)generation;
- (BOOL)isEligibleBundleIdentifier:(NSString *)bundleID generation:(NSUInteger)generation;
@end
