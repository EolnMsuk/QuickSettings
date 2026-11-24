// QuickSettings — EolnMsuk. See LICENSE.
#pragma once
#import <Foundation/Foundation.h>

@interface QSPaneResolver : NSObject
+ (instancetype)sharedResolver;
// Memory only; no preferences service or app-model work on the menu/tap path.
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
// Memory only; cold or 30-second-expired snapshots hide the action and coalesce discovery.
- (BOOL)hasSettingsForBundleIdentifier:(NSString *)bundleID;
// Invalidates pending work immediately, then reads committed state on a worker.
- (void)reloadPreferences;
// One worker validation, then one asynchronous UIKit open after the hook returns.
- (void)openSettingsForBundleIdentifier:(NSString *)bundleID;
@end
