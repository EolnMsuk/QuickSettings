// QuickSettings — EolnMsuk. See LICENSE.
#import "QSSettingsEligibility.h"
#import "QSSettingsIPC.h"
#import "QSPrivateInterfaces.h"
#import "QSSettingsSupport.h"

// Installation is used only to invalidate an indexed positive, never to create one.
static BOOL QSProvenUnavailable(NSString *appID) {
    Class<QSAppProxy> cls = (Class<QSAppProxy>)NSClassFromString(@"LSApplicationProxy");
    if (!QSCanCall(cls, @selector(applicationProxyForIdentifier:), "@", "@")) return NO;
    id<QSAppProxy> proxy = [cls applicationProxyForIdentifier:appID];
    if (!QSCanCall(proxy, @selector(applicationIdentifier), "@", "")
        || ![[proxy applicationIdentifier] isEqual:appID] || !QSCanCall(proxy, @selector(isInstalled), "Bc", "")) return NO;
    if (![proxy isInstalled]) return YES;
    if (QSCanCall(proxy, @selector(isPlaceholder), "Bc", "") && [proxy isPlaceholder]) return YES;
    return QSCanCall(proxy, @selector(isRestricted), "Bc", "") && [proxy isRestricted];
}

static void QSIndexHint(CFNotificationCenterRef center, void *observer, CFStringRef name,
                        const void *object, CFDictionaryRef info) {
    [QSSettingsEligibility.sharedEligibility reloadIndex];
}
static NSSet *QSChangedAppIDs(id applications) {
    if (![applications isKindOfClass:NSArray.class] || [applications count] > QSIPCMaximumRecords) {
        QSDiagnostic(@"app-change-container-unsupported", @"App-change identities could not be bounded; native index refresh is still requested."); return [NSSet set];
    }
    NSMutableSet *identifiers = [NSMutableSet set];
    for (id app in applications) {
        id identifier = QSValidBundleIdentifier(app) ? app :
            (QSCanCall(app, @selector(applicationIdentifier), "@", "") ? [(id<QSAppProxy>)app applicationIdentifier] : nil);
        if (QSValidBundleIdentifier(identifier)) [identifiers addObject:[identifier copy]];
        else QSDiagnostic(@"app-change-identity-unresolved", @"An app-change target has no supported exact identity; native index refresh is still requested.");
    }
    return [identifiers copy];
}

@implementation QSSettingsEligibility {
    dispatch_queue_t _queue;
    NSDictionary *_records;
    BOOL _enabled;
    BOOL _refreshPending;
    BOOL _refreshAgain;
    NSUInteger _preferenceGeneration;
    NSTimeInterval _lastAttempt;
    id<QSWorkspace> _workspace;
    NSMutableDictionary *_changedTargets; // queue-confined; only indexed targets, <=1024
}
+ (instancetype)sharedEligibility {
    static QSSettingsEligibility *value; static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [self new]; }); return value;
}
- (instancetype)init {
    if ((self = [super init])) {
        _records = @{};
        _changedTargets = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("com.eolnmsuk.quicksettings.index-reader", DISPATCH_QUEUE_SERIAL);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            QSIndexHint, QS_INDEX_HINT, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}
- (void)setEnabled:(BOOL)enabled preferenceGeneration:(NSUInteger)generation {
    @synchronized (self) {
        if (generation < _preferenceGeneration) return;
        _enabled = enabled; _preferenceGeneration = generation;
    }
    if (enabled) [self reloadIndex];
}
- (NSDictionary *)recordForBundleIdentifier:(NSString *)bundleID {
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 16) return nil;
    NSDictionary *record; BOOL refresh;
    @synchronized (self) {
        record = _enabled && QSValidBundleIdentifier(bundleID) ? _records[bundleID] : nil;
        refresh = _enabled && !_refreshPending && QSIPCUptime() - _lastAttempt >= 5;
    }
    if (refresh) [self reloadIndex];
    return record;
}
- (void)reloadIndex {
    @synchronized (self) {
        if (_refreshPending) { _refreshAgain = YES; return; }
        _refreshPending = YES;
    }
    dispatch_async(_queue, ^{
        @autoreleasepool {
            @try {
                if (!self->_workspace) {
                    Class<QSWorkspace> cls = (Class<QSWorkspace>)NSClassFromString(@"LSApplicationWorkspace");
                    id<QSWorkspace> workspace = QSCanCall(cls, @selector(defaultWorkspace), "@", "") ? [cls defaultWorkspace] : nil;
                    if (QSCanCall(workspace, @selector(addObserver:), "v", "@")) {
                        [workspace addObserver:self]; self->_workspace = workspace;
                    } else QSDiagnostic(@"index-app-observer-unsupported", @"Application change callbacks are unavailable.");
                }
                BOOL ok = NO;
                NSDictionary *inventory = QSIPCRead(QSIPCInventoryKey, &ok);
                NSDictionary *records = nil;
                BOOL validInventory = ok && QSIPCValidInventory(inventory);
                if (validInventory) records = inventory[@"records"];
                else if (ok && !inventory) QSDiagnostic(@"index-not-ready", @"No native Settings inventory yet. Enable or revisit QuickSettings in Settings.");
                else QSDiagnostic(@"index-read-invalid", @"Native index is incompatible or unreadable; it cannot establish eligibility.");
                NSMutableDictionary *next;
                if (records) for (NSString *appID in [self->_changedTargets.allKeys copy])
                    if (!records[appID]) [self->_changedTargets removeObjectForKey:appID];
                @synchronized (self) { next = [(records ?: self->_records) mutableCopy]; }
                NSSet *observed = validInventory ? [NSSet setWithArray:inventory[@"observed"]] : [NSSet set];
                for (NSString *appID in [next.allKeys copy]) {
                    NSNumber *changed = self->_changedTargets[appID];
                    BOOL observedAfterChange = changed && validInventory
                        && [inventory[@"boot"] isEqual:QSBootIdentity()]
                        && [inventory[@"uptime"] doubleValue] >= changed.doubleValue
                        && [observed containsObject:appID];
                    if (observedAfterChange) [self->_changedTargets removeObjectForKey:appID];
                    if ((changed && !observedAfterChange) || QSProvenUnavailable(appID)) [next removeObjectForKey:appID];
                }
                BOOL changed;
                @synchronized (self) { changed = ![self->_records isEqual:next]; self->_records = [next copy]; }
                if (changed && self.changeHandler) self.changeHandler();
            } @catch (NSException *exception) { QSDiagnostic(@"index-read-exception", exception.name); }
            BOOL again;
            @synchronized (self) {
                self->_lastAttempt = QSIPCUptime();
                self->_refreshPending = NO; again = self->_refreshAgain; self->_refreshAgain = NO;
            }
            if (again) [self reloadIndex];
        }
    });
}
- (void)applicationModelChanged {
    [self reloadIndex];
    // A live Settings process may refresh. This cannot awaken a terminated or
    // suspended Settings process and never silently launches it during discovery.
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), QS_REFRESH_HINT, NULL, NULL, YES);
    QSDiagnostic(@"index-app-change-refresh-gap", @"App change observed; new-page discovery requires a runnable Settings model. Background refresh is unproven.");
}
- (void)invalidateChangedTargets:(NSArray *)apps {
    NSSet *identifiers = QSChangedAppIDs(apps);
    dispatch_async(_queue, ^{
        BOOL changed = NO;
        @synchronized (self) {
            NSMutableDictionary *records = [self->_records mutableCopy];
            for (NSString *appID in identifiers) if (records[appID] || self->_changedTargets[appID]) {
                self->_changedTargets[appID] = @(QSIPCUptime());
                [records removeObjectForKey:appID]; changed = YES;
            }
            self->_records = [records copy];
        }
        if (changed && self.changeHandler) self.changeHandler();
        [self applicationModelChanged];
    });
}
- (void)applicationsDidInstall:(NSArray *)apps { [self invalidateChangedTargets:apps]; }
- (void)applicationsDidUninstall:(NSArray *)apps { [self invalidateChangedTargets:apps]; }
- (void)applicationStateDidChange:(NSArray *)apps { [self applicationModelChanged]; }
@end
