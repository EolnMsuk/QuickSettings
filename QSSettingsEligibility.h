// QuickSettings — EolnMsuk. See LICENSE.
#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, QSSettingsEligibilityState) {
    QSSettingsEligibilityUnknown,
    QSSettingsEligibilityIneligible,
    QSSettingsEligibilityEligible
};

typedef NS_OPTIONS(NSUInteger, QSSettingsEvidence) {
    QSSettingsEvidenceNone = 0,
    QSSettingsEvidenceNativeLink = 1 << 0,
    QSSettingsEvidenceCustomBundle = 1 << 1,
    QSSettingsEvidenceSystemPolicy = 1 << 2,
    QSSettingsEvidenceBuiltinCatalog = 1 << 3,
    QSSettingsEvidenceManifest = 1 << 4
};

// Immutable, internally constructed result. Only eligible results carry a URL.
@interface QSSettingsDestination : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) QSSettingsEligibilityState state;
@property (nonatomic, copy, readonly) NSURL *URL;
@property (nonatomic, readonly) QSSettingsEvidence evidence;
@end

@interface QSSettingsEligibility : NSObject
+ (instancetype)sharedEligibility;
// Older preference publications cannot re-enable discovery after a newer reload.
- (void)setEnabled:(BOOL)enabled preferenceGeneration:(NSUInteger)generation;
// One memory-only read captures the destination and its generation together.
// Soft expiry retains positives during refresh; hard expiry returns unknown/nil.
- (QSSettingsDestination *)destinationForBundleIdentifier:(NSString *)bundleID
                                              generation:(NSUInteger *)generation;
- (BOOL)isCurrentDestination:(QSSettingsDestination *)destination generation:(NSUInteger)generation;
// Request-worker only. Stale positives must pass a fresh installation check on
// the discovery queue. Failure cancels this tap; recovery never opens later.
- (BOOL)validateDestinationForOpening:(QSSettingsDestination *)destination generation:(NSUInteger)generation;
@end
