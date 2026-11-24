// QuickSettings — EolnMsuk. See LICENSE.
#pragma once
#import <Foundation/Foundation.h>

@interface QSPaneResolver : NSObject
+ (instancetype)sharedResolver;
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
// Memory-only target and native record are captured together for the menu.
- (NSDictionary *)recordForBundleIdentifier:(NSString *)bundleID;
- (void)reloadPreferences;
- (void)openSettingsForBundleIdentifier:(NSString *)bundleID recordRevision:(NSString *)revision;
@end
