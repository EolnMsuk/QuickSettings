// QuickSettings — EolnMsuk. See LICENSE.
#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, QSPaneState) {
    QSPaneStateAvailable, QSPaneStateAbsent, QSPaneStateUnresolved
};

@interface QSPaneResolution : NSObject
@property (nonatomic, readonly) QSPaneState state;
@property (nonatomic, readonly, copy) NSURL *URL;
@property (nonatomic, readonly, copy) NSString *reason;
@end

FOUNDATION_EXPORT void QSDiagnostic(NSString *code, NSString *detail);
FOUNDATION_EXPORT BOOL QSValidBundleIdentifier(id value);

@interface QSPaneResolver : NSObject
+ (instancetype)sharedResolver;
- (void)setEnabled:(BOOL)enabled;
// Memory-only lookup. A cold/stale/unresolved result schedules serial work.
- (QSPaneResolution *)cachedResolutionForBundleIdentifier:(NSString *)bundleID;
// Asynchronous fresh model + installed-state validation; opens on the main queue.
- (void)openSettingsForBundleIdentifier:(NSString *)bundleID;
@end
