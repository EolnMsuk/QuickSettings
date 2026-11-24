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
// Memory-only lookups; com.apple. targets are always ineligible without discovery.
// Other targets retain cold/stale asynchronous recovery; generation is always populated when supplied.
- (QSSettingsEligibilityState)stateForBundleIdentifier:(NSString *)bundleID
                                          generation:(NSUInteger *)generation;
- (BOOL)isEligibleBundleIdentifier:(NSString *)bundleID generation:(NSUInteger)generation;
@end
