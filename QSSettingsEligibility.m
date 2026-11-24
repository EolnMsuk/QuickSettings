// QuickSettings — EolnMsuk. See LICENSE. Restored adapter provenance: plan.md.
#import "QSSettingsEligibility.h"
#import "QSPrivateInterfaces.h"
#import "QSPaneResolver.h"
#import <dlfcn.h>

static const NSTimeInterval QSEligibilityFreshness = 30.0;
static const NSTimeInterval QSEligibilityRetryDelay = 5.0;
static const NSUInteger QSEligibilityAutomaticRetries = 2;
static const NSUInteger QSMaximumNativeEntries = 10000;

// Installation is only a prerequisite, never positive Settings-page evidence.
typedef NS_ENUM(NSUInteger, QSNativeInstallState) {
    QSNativeInstallUnknown, QSNativeInstallAbsent, QSNativeInstallPresent
};

static QSNativeInstallState QSProxyState(id<QSAppProxy> proxy, NSString *bundleID) {
    if (!proxy) return QSNativeInstallUnknown;
    if (!QSCanCall(proxy, @selector(applicationIdentifier), "@", "")
        || !QSCanCall(proxy, @selector(isInstalled), "Bc", "")) return QSNativeInstallUnknown;
    id actualID = [proxy applicationIdentifier];
    if (![actualID isKindOfClass:NSString.class] || ![actualID isEqualToString:bundleID]) {
        return QSNativeInstallUnknown;
    }
    if (![proxy isInstalled]) return QSNativeInstallAbsent;
    for (NSString *name in @[@"isPlaceholder", @"isRestricted"]) {
        SEL selector = NSSelectorFromString(name);
        if (![proxy respondsToSelector:selector]) continue; // Optional in the recovered adapter.
        if (!QSCanCall(proxy, selector, "Bc", "")) return QSNativeInstallUnknown;
        BOOL blocked = [name isEqualToString:@"isPlaceholder"] ? [proxy isPlaceholder] : [proxy isRestricted];
        if (blocked) return QSNativeInstallAbsent;
    }
    return QSNativeInstallPresent;
}

static QSNativeInstallState QSInstalledState(NSString *bundleID) {
    Class<QSAppProxy> cls = (Class<QSAppProxy>)NSClassFromString(@"LSApplicationProxy");
    if (!QSCanCall(cls, @selector(applicationProxyForIdentifier:), "@", "@")) return QSNativeInstallUnknown;
    return QSProxyState([cls applicationProxyForIdentifier:bundleID], bundleID);
}

static NSArray *QSContainerObjects(id native) {
    if ([native isKindOfClass:NSArray.class]) return [native count] <= QSMaximumNativeEntries ? native : nil;
    if ([native isKindOfClass:NSSet.class]) return [native count] <= QSMaximumNativeEntries ? [native allObjects] : nil;
    if ([native isKindOfClass:NSDictionary.class]) return [native count] <= QSMaximumNativeEntries ? [native allValues] : nil;
    return nil;
}

static NSDictionary<NSString *, NSArray<NSString *> *> *QSNativeProviders(void) {
    static NSDictionary *providers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Recovered class associations, not a route-table eligibility allowlist.
        // A provider must exist and return its own validated app-specific URL.
        providers = @{
            @"com.apple.mobilesafari": @[@"PSSafariSettingsDetail", @"SAFARI"],
            @"com.apple.mobilephone": @[@"PSPhoneSettingsDetail", @"Phone"],
            @"com.apple.MobileSMS": @[@"PSMessagesSettingsDetail", @"MESSAGES"],
            @"com.apple.facetime": @[@"PSFaceTimeSettingsDetail", @"FACETIME"],
            @"com.apple.Maps": @[@"PSMapsSettingsDetail", @"MAPS"],
            @"com.apple.Music": @[@"PSMusicSettingsDetail", @"MUSIC"],
            @"com.apple.mobilenotes": @[@"PSNotesSettingsDetail", @"NOTES"],
            @"com.apple.reminders": @[@"PSRemindersSettingsDetail", @"REMINDERS"],
            @"com.apple.compass": @[@"PSCompassSettingsDetail", @"COMPASS"],
            @"com.apple.mobileslideshow": @[@"PSPhotosAndCameraSettingsDetail", @"Photos"],
            @"com.apple.AppStore": @[@"PSStoreSettingsDetail", @"STORE"]
        };
    });
    return providers;
}

static BOOL QSProviderURLMatches(id value, NSString *bundleID, NSString *expectedRoot) {
    NSURL *url = [value isKindOfClass:NSURL.class] ? value :
        ([value isKindOfClass:NSString.class] ? [NSURL URLWithString:value] : nil);
    if (!url || url.absoluteString.length > 2048) return NO;
    if (![@[@"prefs", @"app-prefs"] containsObject:url.scheme.lowercaseString]
        || url.host.length || url.user.length || url.password.length || url.fragment.length) return NO;
    NSString *resource = url.resourceSpecifier;
    NSString *root = nil;
    if ([resource hasPrefix:@"root="]) {
        for (NSString *field in [resource componentsSeparatedByString:@"&"]) {
            NSRange delimiter = [field rangeOfString:@"="];
            if (delimiter.location == NSNotFound) return NO;
            NSString *key = [field substringToIndex:delimiter.location];
            NSString *component = [[field substringFromIndex:delimiter.location + 1] stringByRemovingPercentEncoding];
            if (!component.length) return NO;
            if ([key isEqualToString:@"root"]) {
                if (root) return NO;
                root = component;
            } else if (![key isEqualToString:@"path"]) return NO;
        }
    } else root = resource.stringByRemovingPercentEncoding;
    return root.length && ([root isEqualToString:bundleID] || [root isEqualToString:expectedRoot]);
}

static void QSAddNativeProviders(NSMutableDictionary<NSString *, NSNumber *> *states, NSSet<NSString *> *malformedTargets) {
    [QSNativeProviders() enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, NSArray *provider, BOOL *stop) {
        NSNumber *existing = states[bundleID];
        if ([malformedTargets containsObject:bundleID]) return;
        if (existing && existing.unsignedIntegerValue != QSSettingsEligibilityUnknown) return;
        @try {
            QSNativeInstallState installed = QSInstalledState(bundleID);
            if (installed != QSNativeInstallPresent) {
                states[bundleID] = @(installed == QSNativeInstallAbsent
                    ? QSSettingsEligibilityIneligible : QSSettingsEligibilityUnknown);
                return;
            }
            Class<QSDetailProvider> cls = (Class<QSDetailProvider>)NSClassFromString(provider[0]);
            if (!QSCanCall(cls, @selector(preferencesURL), "@", "")) {
                states[bundleID] = @(QSSettingsEligibilityUnknown);
                QSDiagnostic(@"eligibility-provider-interface", @"A restored built-in provider is unavailable or ABI-incompatible.");
                return;
            }
            BOOL matches = QSProviderURLMatches([cls preferencesURL], bundleID, provider[1]);
            states[bundleID] = @(matches ? QSSettingsEligibilityEligible : QSSettingsEligibilityUnknown);
        } @catch (NSException *exception) {
            states[bundleID] = @(QSSettingsEligibilityUnknown);
            QSDiagnostic(@"eligibility-provider-exception", exception.name);
        }
    }];
}

// Only the discovery queue calls this adapter. No Preferences controller is used.
// The recovered non-UI model's background-thread affinity and SpringBoard access
// remain unverified; see ProjectOverview.md before interpreting device results.
static NSDictionary<NSString *, NSNumber *> *QSNativeSnapshot(BOOL *complete) {
    static void *handle; // Accessed only on the serial discovery queue; retry failed loads.
    NSMutableDictionary<NSString *, NSNumber *> *states = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *malformedTargets = [NSMutableSet set];
    *complete = NO;
    @try {
        if (!handle) handle = dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_LAZY | RTLD_LOCAL);
        Class<QSSystemPolicy> policy = (Class<QSSystemPolicy>)NSClassFromString(@"PSSystemPolicyManager");
        Class appClass = NSClassFromString(@"PSThirdPartyApp");
        Class specifierClass = NSClassFromString(@"PSSpecifier");
        if (!appClass || !specifierClass
            || !QSCanCall(policy, @selector(thirdPartyApplications), "@", "")
            || !QSCanCall(policy, @selector(specifiersForThirdPartyApps:), "@", "@")) {
            QSDiagnostic(@"eligibility-model-interface", @"Restored Preferences model unavailable or ABI-incompatible; retrying with bounded recovery.");
        } else {
            id applications = [policy thirdPartyApplications];
            NSArray *apps = QSContainerObjects(applications);
            // Preserve the original native container for its companion API.
            NSArray *specifiers = apps ? QSContainerObjects([policy specifiersForThirdPartyApps:applications]) : nil;
            if (!apps || !specifiers) {
                QSDiagnostic(@"eligibility-model-container", @"Unexpected or oversized native app/specifier container.");
            } else {
                BOOL reliable = apps.count > 0 && specifiers.count > 0;
                NSUInteger matchedDestinations = 0;
                NSMutableDictionary<NSString *, NSNumber *> *installedStates = [NSMutableDictionary dictionary];
                NSMutableSet<NSString *> *destinations = [NSMutableSet set];
                for (id<QSNativeApp> app in apps) {
                    if (![app isKindOfClass:appClass] || !QSCanCall(app, @selector(proxy), "@", "")) {
                        reliable = NO;
                        continue;
                    }
                    id<QSAppProxy> proxy = [app proxy];
                    id value = QSCanCall(proxy, @selector(applicationIdentifier), "@", "") ? [proxy applicationIdentifier] : nil;
                    if (!QSValidBundleIdentifier(value)) {
                        reliable = NO;
                        continue;
                    }
                    if (installedStates[value]) {
                        reliable = NO;
                        installedStates[value] = @(QSNativeInstallUnknown);
                        states[value] = @(QSSettingsEligibilityUnknown);
                        [malformedTargets addObject:value];
                        continue;
                    }
                    NSString *bundleID = [value copy];
                    QSNativeInstallState installed = QSProxyState(proxy, bundleID);
                    installedStates[bundleID] = @(installed);
                    states[bundleID] = @(installed == QSNativeInstallAbsent
                        ? QSSettingsEligibilityIneligible : QSSettingsEligibilityUnknown);
                    if (installed == QSNativeInstallUnknown) reliable = NO;
                }
                for (id<QSNativeSpecifier> specifier in specifiers) {
                    if (![specifier isKindOfClass:specifierClass]
                        || !QSCanCall(specifier, @selector(cellType), "q", "")
                        || !QSCanCall(specifier, @selector(identifier), "@", "")) {
                        reliable = NO;
                        continue;
                    }
                    long long cell = [specifier cellType];
                    if (cell == 0) continue; // PSGroupCell is not a destination.
                    id rootID = [specifier identifier];
                    if (!QSValidBundleIdentifier(rootID) || !installedStates[rootID]) {
                        reliable = NO;
                        continue;
                    }
                    if ([destinations containsObject:rootID] || cell != 1) {
                        states[rootID] = @(QSSettingsEligibilityUnknown);
                        [malformedTargets addObject:rootID];
                        reliable = NO;
                    } else if ([installedStates[rootID] unsignedIntegerValue] == QSNativeInstallPresent) {
                        states[rootID] = @(QSSettingsEligibilityEligible); // Matching native PSLinkCell.
                        matchedDestinations++;
                    }
                    [destinations addObject:rootID];
                }
                // Group-only startup output is not a complete negative inventory.
                reliable = reliable && matchedDestinations > 0;
                if (reliable) {
                    for (NSString *bundleID in installedStates) {
                        // This third-party model cannot prove a missing built-in has no page.
                        if (![bundleID hasPrefix:@"com.apple."] && ![destinations containsObject:bundleID]
                            && [installedStates[bundleID] unsignedIntegerValue] == QSNativeInstallPresent) {
                            states[bundleID] = @(QSSettingsEligibilityIneligible);
                        }
                    }
                }
                *complete = reliable;
                QSDiagnostic(@"eligibility-snapshot", [NSString stringWithFormat:
                    @"apps=%lu specifiers=%lu matched=%lu complete=%@; separate discovery queue (thread affinity unverified).",
                    (unsigned long)apps.count, (unsigned long)specifiers.count, (unsigned long)matchedDestinations,
                    reliable ? @"yes" : @"no"]);
            }
        }
    } @catch (NSException *exception) {
        [states removeAllObjects];
        *complete = NO;
        QSDiagnostic(@"eligibility-model-exception", exception.name);
    }
    QSAddNativeProviders(states, malformedTargets);
    // Unrepresented apps, including unmapped built-ins, remain unknown.
    return [states copy];
}

@interface QSSettingsEligibility ()
- (void)requestRefresh;
- (void)observeApplicationChanges;
- (void)applicationModelChanged;
@end

@implementation QSSettingsEligibility {
    dispatch_queue_t _discoveryQueue;
    NSDictionary<NSString *, NSNumber *> *_snapshot;
    NSTimeInterval _snapshotTime;
    NSTimeInterval _lastAttempt;
    BOOL _hasSnapshot;
    BOOL _enabled;
    BOOL _refreshPending;
    BOOL _refreshAgain;
    NSUInteger _generation;
    NSUInteger _preferenceGeneration;
    NSUInteger _pendingGeneration;
    NSUInteger _automaticRetries;
    id<QSWorkspace> _observedWorkspace;
}

+ (instancetype)sharedEligibility {
    static QSSettingsEligibility *eligibility;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ eligibility = [self new]; });
    return eligibility;
}

- (instancetype)init {
    if ((self = [super init])) {
        _snapshot = @{};
        _discoveryQueue = dispatch_queue_create("com.eolnmsuk.quicksettings.eligibility", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

// Caller holds the memory monitor. No native calls, dispatch, or IPC here.
- (void)retireSnapshot {
    _generation++;
    _snapshot = @{};
    _hasSnapshot = NO;
    _snapshotTime = 0;
}

- (void)setEnabled:(BOOL)enabled preferenceGeneration:(NSUInteger)generation {
    @synchronized (self) {
        if (generation < _preferenceGeneration || (generation == _preferenceGeneration && enabled == _enabled)) return;
        _preferenceGeneration = generation;
        _enabled = enabled;
        [self retireSnapshot];
        _automaticRetries = enabled ? QSEligibilityAutomaticRetries : 0;
        _refreshAgain = enabled && _refreshPending;
    }
    if (enabled) [self requestRefresh];
}

- (QSSettingsEligibilityState)stateForBundleIdentifier:(NSString *)bundleID generation:(NSUInteger *)generation {
    BOOL refresh = NO;
    QSSettingsEligibilityState state = QSSettingsEligibilityUnknown;
    @synchronized (self) {
        if (_hasSnapshot && NSProcessInfo.processInfo.systemUptime - _snapshotTime >= QSEligibilityFreshness) {
            [self retireSnapshot];
            _automaticRetries = QSEligibilityAutomaticRetries;
        }
        if (generation) *generation = _generation;
        if (_enabled && QSValidBundleIdentifier(bundleID)) {
            NSNumber *value = _snapshot[bundleID];
            if (_hasSnapshot && value) state = (QSSettingsEligibilityState)value.unsignedIntegerValue;
            refresh = !_hasSnapshot;
        }
    }
    if (refresh) [self requestRefresh];
    return state;
}

- (BOOL)isEligibleBundleIdentifier:(NSString *)bundleID generation:(NSUInteger)generation {
    NSUInteger currentGeneration;
    QSSettingsEligibilityState state = [self stateForBundleIdentifier:bundleID generation:&currentGeneration];
    return generation == currentGeneration && state == QSSettingsEligibilityEligible;
}

- (void)requestRefresh {
    NSUInteger generation;
    NSTimeInterval delay;
    @synchronized (self) {
        if (!_enabled) return;
        if (_refreshPending) {
            if (_pendingGeneration != _generation) _refreshAgain = YES;
            return;
        }
        _refreshPending = YES;
        _pendingGeneration = generation = _generation; // Capture before queuing, not after invalidation.
        delay = _lastAttempt > 0 ? MAX(0, _lastAttempt + QSEligibilityRetryDelay - NSProcessInfo.processInfo.systemUptime) : 0;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _discoveryQueue, ^{
        @autoreleasepool {
            BOOL current;
            @synchronized (self) {
                current = self->_enabled && generation == self->_generation;
                if (current) self->_lastAttempt = NSProcessInfo.processInfo.systemUptime;
            }
            BOOL complete = NO;
            NSDictionary *snapshot = nil;
            if (current) {
                [self observeApplicationChanges];
                snapshot = QSNativeSnapshot(&complete);
            }
            BOOL retry = NO;
            @synchronized (self) {
                if (snapshot && self->_enabled && generation == self->_generation) {
                    self->_snapshot = snapshot;
                    self->_snapshotTime = NSProcessInfo.processInfo.systemUptime;
                    self->_hasSnapshot = YES;
                    if (!complete && self->_automaticRetries > 0) {
                        self->_automaticRetries--;
                        retry = YES;
                    }
                }
                self->_refreshPending = NO;
                retry = self->_enabled && (retry || self->_refreshAgain || generation != self->_generation);
                self->_refreshAgain = NO;
            }
            if (retry) [self requestRefresh];
        }
    });
}

- (void)observeApplicationChanges {
    if (_observedWorkspace) return; // Only this serial discovery queue registers.
    @try {
        Class<QSWorkspace> cls = (Class<QSWorkspace>)NSClassFromString(@"LSApplicationWorkspace");
        id<QSWorkspace> workspace = QSCanCall(cls, @selector(defaultWorkspace), "@", "") ? [cls defaultWorkspace] : nil;
        if (QSCanCall(workspace, @selector(addObserver:), "v", "@")) {
            [workspace addObserver:self];
            _observedWorkspace = workspace; // Singleton lifetime; no Preferences controller retained.
        } else QSDiagnostic(@"eligibility-observer", @"App observer unavailable; using bounded demand-driven freshness recovery.");
    } @catch (NSException *exception) { QSDiagnostic(@"eligibility-observer-exception", exception.name); }
}

- (void)applicationModelChanged {
    @synchronized (self) {
        [self retireSnapshot];
        _automaticRetries = _enabled ? QSEligibilityAutomaticRetries : 0;
    }
    [self requestRefresh];
}
- (void)applicationsDidInstall:(NSArray *)apps { [self applicationModelChanged]; }
- (void)applicationsDidUninstall:(NSArray *)apps { [self applicationModelChanged]; }
- (void)applicationStateDidChange:(NSArray *)apps { [self applicationModelChanged]; }
@end
