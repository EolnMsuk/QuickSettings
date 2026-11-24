// QuickSettings — EolnMsuk. See LICENSE.
#pragma once
#import <Foundation/Foundation.h>

#define QS_PREFS_DOMAIN CFSTR("com.eolnmsuk.quicksettings")
#define QS_ENABLED_KEY CFSTR("enabled")
#define QS_RELOAD_NOTIFICATION CFSTR("com.eolnmsuk.quicksettings/ReloadPrefs")
static NSString *const QSShortcutType = @"com.eolnmsuk.quicksettings.open-settings";
static NSString *const QSTargetBundleKey = @"com.eolnmsuk.quicksettings.target-bundle-id";
static NSString *const QSTargetRevisionKey = @"com.eolnmsuk.quicksettings.target-record-revision";
static NSString *const QSSettingsBundleID = @"com.apple.Preferences";
static const BOOL QSDefaultEnabled = NO;

#ifndef QS_BUILD_ENVIRONMENT
#error Build through the aggregate Makefile to select the installed environment.
#endif

static inline NSString *QSInstalledEnvironment(void) {
#if QS_BUILD_ENVIRONMENT == 2
    return @"RootHide";
#elif QS_BUILD_ENVIRONMENT == 1
    return @"rootless";
#elif QS_BUILD_ENVIRONMENT == 0
    return @"rootful";
#else
#error Unsupported QuickSettings build environment.
#endif
}
