// QuickSettings — EolnMsuk. See LICENSE.
#import "QSSettingsIPC.h"
#import "QSSettingsSupport.h"
#import <CoreFoundation/CoreFoundation.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <mach/mach_time.h>
#include <math.h>

NSString *const QSNavigationMarker = @"native-row-v1-20261124a";
NSString *const QSNativeAdapter = @"prefs-root-ios16-v1";
NSString *const QSIPCCommandKey = @"command";
NSString *const QSIPCInventoryKey = @"inventory";
NSString *const QSIPCReplyKey = @"reply";
NSString *const QSIPCDiagnosticsKey = @"diagnostics";
const NSTimeInterval QSIPCRequestLifetime = 10.0;

NSTimeInterval QSIPCUptime(void) {
    static mach_timebase_info_data_t scale; static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&scale); });
    if (!scale.denom) { QSDiagnostic(@"bridge-clock-unavailable", @"Continuous monotonic clock is unavailable; navigation cannot be authorized."); return NAN; }
    return (double)mach_continuous_time() * (double)scale.numer / (double)scale.denom / 1e9;
}

NSString *QSOSBuild(void) {
    static NSString *build;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        char bytes[128] = {0}; size_t size = sizeof(bytes) - 1;
        if (sysctlbyname("kern.osversion", bytes, &size, NULL, 0) == 0)
            build = [[NSString alloc] initWithUTF8String:bytes];
        if (!build.length) build = @"unavailable";
    });
    return build;
}

NSString *QSBootIdentity(void) {
    static NSString *boot;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        struct timeval time = {0}; size_t size = sizeof(time);
        if (sysctlbyname("kern.boottime", &time, &size, NULL, 0) == 0 && time.tv_sec > 0)
            boot = [NSString stringWithFormat:@"%lld.%06d", (long long)time.tv_sec, (int)time.tv_usec];
        if (!boot.length) boot = @"unavailable";
    });
    return boot;
}

BOOL QSIPCValidUUID(id value) {
    return [value isKindOfClass:NSString.class] && [value length] == 36
        && [[NSUUID alloc] initWithUUIDString:value] != nil;
}

BOOL QSIPCValidLocator(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length] || [value length] > 512) return NO;
    static NSCharacterSet *invalid; static dispatch_once_t once;
    dispatch_once(&once, ^{
        invalid = [[NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-:"] invertedSet];
    });
    return [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

static BOOL QSKeys(NSDictionary *value, NSArray *required, NSArray *optional) {
    if (![value isKindOfClass:NSDictionary.class] || value.count > required.count + optional.count) return NO;
    for (id key in value) {
        if (![key isKindOfClass:NSString.class] || (![required containsObject:key] && ![optional containsObject:key])) return NO;
    }
    for (NSString *key in required) if (!value[key]) return NO;
    return YES;
}
static BOOL QSNumber(id value, BOOL positive) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    double n = [value doubleValue];
    return isfinite(n) && n >= (positive ? 1 : 0) && n <= 9007199254740991.0 && floor(n) == n;
}
static BOOL QSBool(id value) {
    return value && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}
static BOOL QSTime(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()
        && isfinite([value doubleValue]) && [value doubleValue] >= 0;
}

NSDictionary *QSIPCHeader(void) {
    return @{@"schema": @1, @"marker": QSNavigationMarker, @"adapter": QSNativeAdapter, @"osBuild": QSOSBuild(), @"clock": @"mach-continuous-seconds"};
}
BOOL QSIPCHeaderMatches(id value) {
    if (![value isKindOfClass:NSDictionary.class] || [QSOSBuild() isEqual:@"unavailable"]) return NO;
    for (NSString *key in QSIPCHeader()) if (![value[key] isEqual:QSIPCHeader()[key]]) return NO;
    return QSNumber(value[@"schema"], YES);
}
static NSArray *QSHeaderKeys(void) { return @[@"schema", @"marker", @"adapter", @"osBuild", @"clock"]; }
static NSArray *QSWithHeader(NSArray *fields) { return [QSHeaderKeys() arrayByAddingObjectsFromArray:fields]; }

static NSUInteger QSLimitForKey(NSString *key) {
    if ([key isEqual:QSIPCInventoryKey] || [key isEqual:QSIPCDiagnosticsKey]) return 1024 * 1024;
    if ([key isEqual:QSIPCCommandKey] || [key isEqual:QSIPCReplyKey]) return 16 * 1024;
    return 0;
}
static NSDictionary *QSImmutablePlist(id value, NSUInteger limit) {
    if (!limit || ![value isKindOfClass:NSDictionary.class]
        || ![NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListBinaryFormat_v1_0]) return nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    if (!data || data.length > limit) return nil;
    return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
}

id QSIPCRead(NSString *key, BOOL *success) {
    if (success) *success = NO;
    if (!QSLimitForKey(key) || !CFPreferencesAppSynchronize(QS_BRIDGE_DOMAIN)) {
        QSDiagnostic(@"bridge-read-sync", @"Bridge preferences could not be refreshed."); return nil;
    }
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, QS_BRIDGE_DOMAIN));
    if (!value) { if (success) *success = YES; return nil; }
    NSDictionary *copy = QSImmutablePlist(value, QSLimitForKey(key));
    if (!copy) { QSDiagnostic(@"bridge-read-bounds", @"Bridge key is malformed or exceeds its byte limit."); return nil; }
    if (success) *success = YES;
    return copy;
}

BOOL QSIPCWrite(NSString *key, NSDictionary *value, CFStringRef hint) {
    NSString *process = NSBundle.mainBundle.bundleIdentifier;
    BOOL springboard = [process isEqual:@"com.apple.springboard"];
    BOOL settings = [process isEqual:@"com.apple.Preferences"];
    BOOL owns = springboard ? [key isEqual:QSIPCCommandKey] : settings
        && [@[QSIPCInventoryKey, QSIPCReplyKey, QSIPCDiagnosticsKey] containsObject:key];
    NSDictionary *copy = QSImmutablePlist(value, QSLimitForKey(key));
    BOOL schema = [key isEqual:QSIPCCommandKey] ? QSIPCValidCommand(copy) :
        ([key isEqual:QSIPCInventoryKey] ? QSIPCValidInventory(copy) :
        ([key isEqual:QSIPCReplyKey] ? QSIPCValidReply(copy) : QSIPCHeaderMatches(copy)));
    if (!owns || !copy || !schema || !CFPreferencesAppSynchronize(QS_BRIDGE_DOMAIN)) {
        QSDiagnostic(@"bridge-write-precondition", @"Bridge writer, bounds, or synchronization check failed."); return NO;
    }
    CFPropertyListRef previous = CFPreferencesCopyAppValue((__bridge CFStringRef)key, QS_BRIDGE_DOMAIN);
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)copy, QS_BRIDGE_DOMAIN);
    BOOL committed = CFPreferencesAppSynchronize(QS_BRIDGE_DOMAIN);
    if (!committed) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, previous, QS_BRIDGE_DOMAIN);
        CFPreferencesAppSynchronize(QS_BRIDGE_DOMAIN);
        QSDiagnostic(@"bridge-write-sync", @"Bridge commit failed; no delivery hint was sent.");
    }
    if (previous) CFRelease(previous);
    if (committed && hint) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), hint, NULL, NULL, YES);
    return committed;
}

BOOL QSIPCValidRecord(id value, NSString *appID) {
    return QSKeys(value, @[@"app", @"owner", @"row", @"group", @"evidence", @"revision", @"available"], @[])
        && QSValidBundleIdentifier(appID) && [value[@"app"] isEqual:appID]
        && [value[@"owner"] isEqual:@"settings-root"] && QSIPCValidLocator(value[@"row"])
        && QSIPCValidLocator(value[@"group"]) && QSIPCValidUUID(value[@"revision"])
        && [@[@"native-third-party-row-id", @"native-app-proxy", @"native-application-bundle", @"calibrated-app-settings-key"] containsObject:value[@"evidence"]]
        && QSBool(value[@"available"]) && [value[@"available"] boolValue];
}
BOOL QSIPCValidInventory(id value) {
    if (!QSKeys(value, QSWithHeader(@[@"publisher", @"publication", @"complete", @"records", @"uptime", @"coverage", @"boot", @"observed"]), @[])
        || !QSIPCHeaderMatches(value) || !QSIPCValidUUID(value[@"publisher"]) || !QSIPCValidUUID(value[@"publication"])
        || !QSBool(value[@"complete"]) || !QSTime(value[@"uptime"])
        || !QSIPCValidLocator(value[@"boot"]) || ![value[@"observed"] isKindOfClass:NSArray.class]
        || [value[@"observed"] count] > QSIPCMaximumRecords
        || ![value[@"coverage"] isEqual:@"partial-native-model-background-refresh-unproven"]
        || [value[@"complete"] boolValue] || ![value[@"records"] isKindOfClass:NSDictionary.class]
        || [value[@"records"] count] > QSIPCMaximumRecords) return NO;
    for (id app in value[@"records"]) if (!QSIPCValidRecord(value[@"records"][app], app)) return NO;
    NSMutableSet *observed = [NSMutableSet set];
    for (id app in value[@"observed"]) {
        if (!QSValidBundleIdentifier(app) || !value[@"records"][app] || [observed containsObject:app]) return NO;
        [observed addObject:app];
    }
    return YES; // This adapter deliberately cannot claim an authoritative negative inventory.
}
BOOL QSIPCValidRequest(id value) {
    if (!QSKeys(value, QSWithHeader(@[@"session", @"request", @"sequence", @"target", @"revision", @"preferenceGeneration", @"created", @"deadline", @"boot", @"operation"]), @[])
        || !QSIPCHeaderMatches(value) || !QSIPCValidUUID(value[@"session"]) || !QSIPCValidUUID(value[@"request"])
        || !QSNumber(value[@"sequence"], YES) || !QSNumber(value[@"preferenceGeneration"], YES)
        || !QSValidBundleIdentifier(value[@"target"]) || !QSIPCValidUUID(value[@"revision"])
        || ![value[@"operation"] isEqual:@"select-native-row"] || [QSBootIdentity() isEqual:@"unavailable"]
        || ![value[@"boot"] isEqual:QSBootIdentity()] || !QSTime(value[@"created"]) || !QSTime(value[@"deadline"])) return NO;
    double lifetime = [value[@"deadline"] doubleValue] - [value[@"created"] doubleValue];
    return lifetime > 0 && lifetime <= QSIPCRequestLifetime;
}
BOOL QSIPCValidCommand(id value) {
    if (!QSKeys(value, QSWithHeader(@[@"session", @"preferenceGeneration", @"enabled", @"boot", @"state"]), @[@"request"])
        || !QSIPCHeaderMatches(value) || !QSIPCValidUUID(value[@"session"])
        || !QSNumber(value[@"preferenceGeneration"], YES) || !QSBool(value[@"enabled"])
        || ![value[@"boot"] isEqual:QSBootIdentity()] || [QSBootIdentity() isEqual:@"unavailable"]
        || !QSIPCValidLocator(value[@"state"])) return NO;
    NSDictionary *request = value[@"request"];
    return !request || (QSIPCValidRequest(request) && [value[@"enabled"] boolValue]
        && [request[@"session"] isEqual:value[@"session"]]
        && [request[@"preferenceGeneration"] isEqual:value[@"preferenceGeneration"]]);
}
BOOL QSIPCRequestIsLive(NSDictionary *request) {
    double now = QSIPCUptime();
    return QSIPCValidRequest(request) && [request[@"created"] doubleValue] <= now
        && now < [request[@"deadline"] doubleValue];
}
BOOL QSIPCSameRequest(NSDictionary *a, NSDictionary *b) {
    return QSIPCValidRequest(a) && QSIPCValidRequest(b) && [a isEqual:b];
}
NSDictionary *QSIPCReply(NSDictionary *request, NSString *stage, NSString *reason, BOOL terminal) {
    if (!QSIPCValidRequest(request) || !QSIPCValidLocator(reason) || !QSIPCValidLocator(stage)) return nil;
    NSMutableDictionary *reply = [QSIPCHeader() mutableCopy];
    for (NSString *key in @[@"session", @"request", @"target", @"revision", @"sequence", @"preferenceGeneration", @"boot"])
        reply[key] = request[key];
    reply[@"stage"] = stage; reply[@"reason"] = reason; reply[@"terminal"] = @(terminal);
    reply[@"uptime"] = @(QSIPCUptime());
    return [reply copy];
}
BOOL QSIPCValidReply(id value) {
    if (!QSKeys(value, QSWithHeader(@[@"session", @"request", @"target", @"revision", @"sequence", @"preferenceGeneration", @"boot", @"stage", @"reason", @"terminal", @"uptime"]), @[])
        || !QSIPCHeaderMatches(value) || !QSIPCValidUUID(value[@"session"]) || !QSIPCValidUUID(value[@"request"])
        || !QSValidBundleIdentifier(value[@"target"]) || !QSIPCValidUUID(value[@"revision"])
        || !QSNumber(value[@"sequence"], YES) || !QSNumber(value[@"preferenceGeneration"], YES)
        || ![value[@"boot"] isEqual:QSBootIdentity()] || !QSTime(value[@"uptime"])
        || !QSIPCValidLocator(value[@"reason"]) || !QSBool(value[@"terminal"])) return NO;
    NSArray *terminal = @[@"visible-target", @"failed", @"cancelled", @"expired"];
    NSArray *progress = @[@"request-received", @"row-resolved", @"selection-dispatch-committed", @"selection-invoked"];
    return [value[@"terminal"] boolValue] ? [terminal containsObject:value[@"stage"]] : [progress containsObject:value[@"stage"]];
}
