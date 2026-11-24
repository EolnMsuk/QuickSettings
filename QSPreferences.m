// QuickSettings — EolnMsuk. See LICENSE.
#import "QSPreferences.h"
#import "QSConstants.h"

BOOL QSReadEnabled(void) {
    BOOL enabled = QSDefaultEnabled;
    QSReadEnabledWithStatus(&enabled);
    return enabled;
}

BOOL QSReadEnabledWithStatus(BOOL *enabled) {
    if (enabled) *enabled = QSDefaultEnabled;
    if (!CFPreferencesAppSynchronize(QS_PREFS_DOMAIN)) return NO;
    CFPropertyListRef value = CFPreferencesCopyAppValue(QS_ENABLED_KEY, QS_PREFS_DOMAIN);
    BOOL valid = !value || CFGetTypeID(value) == CFBooleanGetTypeID();
    if (value && valid && enabled) *enabled = CFBooleanGetValue((CFBooleanRef)value);
    if (value) CFRelease(value);
    return valid;
}

BOOL QSWriteEnabled(BOOL enabled) {
    CFPreferencesAppSynchronize(QS_PREFS_DOMAIN);
    CFPropertyListRef previous = CFPreferencesCopyAppValue(QS_ENABLED_KEY, QS_PREFS_DOMAIN);
    CFPreferencesSetAppValue(QS_ENABLED_KEY, enabled ? kCFBooleanTrue : kCFBooleanFalse, QS_PREFS_DOMAIN);
    BOOL committed = CFPreferencesAppSynchronize(QS_PREFS_DOMAIN);
    if (!committed) {
        CFPreferencesSetAppValue(QS_ENABLED_KEY, previous, QS_PREFS_DOMAIN);
        CFPreferencesAppSynchronize(QS_PREFS_DOMAIN);
    }
    if (previous) CFRelease(previous);
    if (committed) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             QS_RELOAD_NOTIFICATION, NULL, NULL, YES);
    }
    return committed;
}
