// QuickSettings — EolnMsuk. See LICENSE.
#pragma once
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT void QSDiagnostic(NSString *code, NSString *detail);
FOUNDATION_EXPORT BOOL QSValidBundleIdentifier(id value);

@interface QSPaneResolver : NSObject
+ (instancetype)sharedResolver;
// Memory only; no preferences service or app-model work on the menu/tap path.
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
// Memory only; unknown/stale results hide the action and coalesce discovery.
- (BOOL)hasSettingsForBundleIdentifier:(NSString *)bundleID;
// Invalidates pending work immediately, then reads committed state on a worker.
- (void)reloadPreferences;
// One worker validation, then one asynchronous UIKit open after the hook returns.
- (void)openSettingsForBundleIdentifier:(NSString *)bundleID;
@end
