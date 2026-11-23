// QuickSettings — EolnMsuk. See LICENSE. Private API evidence: plan.md R7–R14.
#import "QSPaneResolver.h"
#import "QSPrivateInterfaces.h"
#import "QSPreferences.h"
#import "QSConstants.h"
#import <dlfcn.h>

static const NSTimeInterval QSFreshness = 30.0;
static const NSTimeInterval QSRetryDelay = 5.0;

void QSDiagnostic(NSString *code, NSString *detail) {
    static NSMutableDictionary<NSString *, NSNumber *> *last;
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ last = [NSMutableDictionary dictionary]; lock = [NSObject new]; });
    @synchronized (lock) {
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (last[code] && now - last[code].doubleValue < 60) return;
        if (last.count >= 48 && !last[code]) return;
        last[code] = @(now);
        NSLog(@"[QuickSettings] %@: %@", code, detail);
    }
}

BOOL QSValidBundleIdentifier(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] < 3 || [value length] > 512) return NO;
    static NSCharacterSet *invalid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        invalid = [[NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"] invertedSet];
    });
    return [value rangeOfString:@"."].location != NSNotFound
        && [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

@interface QSPaneResolution ()
- (instancetype)initWithState:(QSPaneState)state URL:(NSURL *)url reason:(NSString *)reason;
@end
@implementation QSPaneResolution
- (instancetype)initWithState:(QSPaneState)state URL:(NSURL *)url reason:(NSString *)reason {
    if ((self = [super init])) { _state = state; _URL = [url copy]; _reason = [reason copy]; }
    return self;
}
@end

static QSPaneResolution *QSResult(QSPaneState state, NSURL *url, NSString *reason) {
    return [[QSPaneResolution alloc] initWithState:state URL:url reason:reason];
}

static void QSLoadPreferencesModel(void) {
    static dispatch_once_t once;
    static void *handle;
    dispatch_once(&once, ^{
        // Apple framework path: never prepend a jailbreak prefix.
        handle = dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) QSDiagnostic(@"framework-unavailable", @"Could not load Apple's Preferences model.");
    });
}

static NSArray *QSContainerObjects(id native) {
    if ([native isKindOfClass:NSArray.class]) return native;
    if ([native isKindOfClass:NSSet.class]) return [native allObjects];
    if ([native isKindOfClass:NSDictionary.class]) return [native allValues];
    return nil;
}

// Absent is a real installed-state result. Missing/wrong interfaces are unresolved.
static QSPaneState QSProxyState(id<QSAppProxy> proxy, NSString *bundleID) {
    if (!proxy) return QSPaneStateAbsent;
    if (!QSCanCall(proxy, @selector(applicationIdentifier), "@", "")
        || !QSCanCall(proxy, @selector(isInstalled), "Bc", "")) return QSPaneStateUnresolved;
    @try {
        id actualID = [proxy applicationIdentifier];
        if (![actualID isKindOfClass:NSString.class] || ![actualID isEqualToString:bundleID]) {
            QSDiagnostic(@"proxy-id-mismatch", @"LaunchServices returned a different or invalid identifier.");
            return QSPaneStateUnresolved;
        }
        if (![proxy isInstalled]) return QSPaneStateAbsent;
        for (NSString *name in @[@"isPlaceholder", @"isRestricted"]) {
            SEL selector = NSSelectorFromString(name);
            if (![proxy respondsToSelector:selector]) continue; // Optional on the recorded versions.
            if (!QSCanCall(proxy, selector, "Bc", "")) return QSPaneStateUnresolved;
            BOOL blocked = [name isEqualToString:@"isPlaceholder"] ? [proxy isPlaceholder] : [proxy isRestricted];
            if (blocked) return QSPaneStateAbsent;
        }
        return QSPaneStateAvailable;
    } @catch (NSException *exception) {
        QSDiagnostic(@"proxy-exception", exception.name);
        return QSPaneStateUnresolved;
    }
}

static QSPaneState QSInstalledState(NSString *bundleID) {
    Class<QSAppProxy> cls = (Class<QSAppProxy>)NSClassFromString(@"LSApplicationProxy");
    if (!QSCanCall(cls, @selector(applicationProxyForIdentifier:), "@", "@")) {
        QSDiagnostic(@"proxy-interface", @"Installed-app lookup is unavailable or has an unexpected ABI.");
        return QSPaneStateUnresolved;
    }
    @try { return QSProxyState([cls applicationProxyForIdentifier:bundleID], bundleID); }
    @catch (NSException *exception) {
        QSDiagnostic(@"proxy-lookup-exception", exception.name);
        return QSPaneStateUnresolved;
    }
}

static NSDictionary<NSString *, NSArray<NSString *> *> *QSProviders(void) {
    static NSDictionary *providers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // The class association is the live evidence; root tokens only constrain
        // that class's returned URL. These tokens are never used to invent a URL.
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

static NSURL *QSValidatedProviderURL(id value, NSString *bundleID, NSString *expectedRoot) {
    NSURL *url = [value isKindOfClass:NSURL.class] ? value :
        ([value isKindOfClass:NSString.class] ? [NSURL URLWithString:value] : nil);
    if (!url || url.absoluteString.length > 2048) return nil;
    NSString *scheme = url.scheme.lowercaseString;
    if (![@[@"prefs", @"app-prefs"] containsObject:scheme] || url.host.length
        || url.user.length || url.password.length || url.fragment.length) return nil;
    NSString *resource = url.resourceSpecifier;
    NSString *root = nil;
    if ([resource hasPrefix:@"root="]) {
        NSArray *fields = [resource componentsSeparatedByString:@"&"];
        for (NSString *field in fields) {
            NSRange delimiter = [field rangeOfString:@"="];
            if (delimiter.location == NSNotFound) return nil;
            NSString *key = [field substringToIndex:delimiter.location];
            NSString *component = [[field substringFromIndex:delimiter.location + 1] stringByRemovingPercentEncoding];
            if (!component.length) return nil;
            if ([key isEqualToString:@"root"]) {
                if (root) return nil;
                root = component;
            } else if (![key isEqualToString:@"path"]) {
                return nil;
            }
        }
    } else {
        root = resource.stringByRemovingPercentEncoding;
    }
    if (!root.length || (![root isEqualToString:bundleID]
        && [root caseInsensitiveCompare:expectedRoot] != NSOrderedSame)) return nil;
    return url; // Retain the provider's URL, including its app-specific path.
}

static void QSAddNativeProviders(NSMutableDictionary *routes) {
    [QSProviders() enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, NSArray *provider, BOOL *stop) {
        QSPaneResolution *existing = routes[bundleID];
        if (existing && existing.state == QSPaneStateAvailable) return;
        QSPaneState installed = QSInstalledState(bundleID);
        if (installed != QSPaneStateAvailable) {
            routes[bundleID] = QSResult(installed, nil, @"native-app-installed-state");
            return;
        }
        Class<QSDetailProvider> cls = (Class<QSDetailProvider>)NSClassFromString(provider[0]);
        if (!QSCanCall(cls, @selector(preferencesURL), "@", "")) {
            QSDiagnostic(@"provider-interface", [NSString stringWithFormat:
                @"%@ for %@ is missing or has an unexpected ABI.", provider[0], bundleID]);
            routes[bundleID] = QSResult(QSPaneStateUnresolved, nil, @"native-provider-interface");
            return;
        }
        @try {
            NSURL *url = QSValidatedProviderURL([cls preferencesURL], bundleID, provider[1]);
            routes[bundleID] = QSResult(url ? QSPaneStateAvailable : QSPaneStateUnresolved, url,
                                        url ? @"native-provider" : @"native-provider-url");
            if (!url) QSDiagnostic(@"provider-url", [NSString stringWithFormat:@"%@ returned no validated app-specific URL.", provider[0]]);
        } @catch (NSException *exception) {
            routes[bundleID] = QSResult(QSPaneStateUnresolved, nil, @"native-provider-exception");
            QSDiagnostic(@"provider-exception", exception.name);
        }
    }];
}

static NSDictionary<NSString *, QSPaneResolution *> *QSBuildSnapshot(BOOL *complete) {
    QSLoadPreferencesModel();
    NSMutableDictionary *routes = [NSMutableDictionary dictionary];
    *complete = NO;
    @try {
        Class<QSSystemPolicy> policy = (Class<QSSystemPolicy>)NSClassFromString(@"PSSystemPolicyManager");
        Class appClass = NSClassFromString(@"PSThirdPartyApp");
        Class specifierClass = NSClassFromString(@"PSSpecifier");
        if (!appClass || !specifierClass
            || !QSCanCall(policy, @selector(thirdPartyApplications), "@", "")
            || !QSCanCall(policy, @selector(specifiersForThirdPartyApps:), "@", "@")) {
            QSDiagnostic(@"model-interface", @"Preferences app-model classes/selectors are unavailable or ABI-incompatible.");
        } else {
            id applications = [policy thirdPartyApplications];
            NSArray *apps = QSContainerObjects(applications);
            // Preserve the exact native container for the companion API.
            id nativeSpecifiers = apps ? [policy specifiersForThirdPartyApps:applications] : nil;
            NSArray *specifiers = QSContainerObjects(nativeSpecifiers);
            if (!apps || !specifiers || apps.count > 10000 || specifiers.count > 10000) {
                QSDiagnostic(@"model-container", [NSString stringWithFormat:@"Unexpected app/specifier types: %@ / %@.",
                    NSStringFromClass([applications class]), NSStringFromClass([nativeSpecifiers class])]);
            } else {
                BOOL reliable = apps.count > 0 && specifiers.count > 0;
                NSMutableSet<NSString *> *identifiers = [NSMutableSet set];
                for (id<QSNativeApp> app in apps) {
                    if (![app isKindOfClass:appClass] || !QSCanCall(app, @selector(proxy), "@", "")) {
                        reliable = NO;
                        QSDiagnostic(@"model-app-type", @"A native app entry is not a supported PSThirdPartyApp.");
                        continue;
                    }
                    id<QSAppProxy> proxy = [app proxy];
                    if (!QSCanCall(proxy, @selector(applicationIdentifier), "@", "")) {
                        reliable = NO;
                        QSDiagnostic(@"model-proxy-type", @"A native app has no supported proxy identifier.");
                        continue;
                    }
                    id bundleID = [proxy applicationIdentifier];
                    if (!QSValidBundleIdentifier(bundleID)) {
                        reliable = NO;
                        QSDiagnostic(@"model-app-id", @"A native app has an invalid identifier.");
                        continue;
                    }
                    [identifiers addObject:bundleID];
                    QSPaneState installed = QSProxyState(proxy, bundleID);
                    routes[bundleID] = QSResult(installed == QSPaneStateAvailable ? QSPaneStateAbsent : installed,
                                                nil, @"no-generated-app-destination");
                }
                NSUInteger matches = 0;
                for (id<QSNativeSpecifier> specifier in specifiers) {
                    if (![specifier isKindOfClass:specifierClass]
                        || !QSCanCall(specifier, @selector(cellType), "q", "")
                        || !QSCanCall(specifier, @selector(identifier), "@", "")) {
                        reliable = NO;
                        QSDiagnostic(@"model-specifier-type", @"Unexpected Settings specifier object or ABI.");
                        continue;
                    }
                    long long cell = [specifier cellType];
                    if (cell == 0) continue; // PSGroupCell is never a destination.
                    id rootID = [specifier identifier];
                    if (!QSValidBundleIdentifier(rootID) || ![identifiers containsObject:rootID]) {
                        reliable = NO;
                        QSDiagnostic(@"model-id-mismatch", QSValidBundleIdentifier(rootID)
                            ? [NSString stringWithFormat:@"Specifier %@ has no matching native app proxy identifier.", rootID]
                            : @"An app destination has no valid bundle identifier.");
                        continue;
                    }
                    if (cell != 1) { // PSLinkCell: do not navigate arbitrary controls.
                        routes[rootID] = QSResult(QSPaneStateUnresolved, nil, @"unsupported-destination-cell");
                        QSDiagnostic(@"model-cell", @"A matching app specifier is not a PSLinkCell.");
                        continue;
                    }
                    QSPaneState currentState = QSInstalledState(rootID);
                    if (currentState != QSPaneStateAvailable) {
                        routes[rootID] = QSResult(currentState, nil, @"destination-installed-state");
                        continue;
                    }
                    NSCharacterSet *componentCharacters = [NSCharacterSet characterSetWithCharactersInString:
                        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
                    NSString *encoded = [rootID stringByAddingPercentEncodingWithAllowedCharacters:componentCharacters];
                    NSURL *url = [NSURL URLWithString:[@"prefs:root=" stringByAppendingString:encoded]];
                    if (url) { routes[rootID] = QSResult(QSPaneStateAvailable, url, @"generated-app-specifier"); matches++; }
                }
                if (!reliable) {
                    for (NSString *bundleID in identifiers) {
                        QSPaneResolution *result = routes[bundleID];
                        if (result.state == QSPaneStateAbsent && [result.reason isEqualToString:@"no-generated-app-destination"]
                            && QSInstalledState(bundleID) == QSPaneStateAvailable) {
                            routes[bundleID] = QSResult(QSPaneStateUnresolved, nil, @"incomplete-native-model");
                        }
                    }
                }
                *complete = reliable;
                QSDiagnostic(@"model-snapshot", [NSString stringWithFormat:
                    @"apps=%lu (%@), specifiers=%lu (%@), matched=%lu, complete=%@; worker queue.",
                    (unsigned long)apps.count, NSStringFromClass([applications class]),
                    (unsigned long)specifiers.count, NSStringFromClass([nativeSpecifiers class]),
                    (unsigned long)matches, reliable ? @"yes" : @"no"]);
            }
        }
    } @catch (NSException *exception) {
        // Do not publish partially inspected private-model objects after failure.
        [routes removeAllObjects];
        *complete = NO;
        QSDiagnostic(@"model-exception", exception.name);
    }
    QSAddNativeProviders(routes);
    // Historical roots alone do not prove live destinations. These app IDs
    // remain explicit coverage gaps unless a generated specifier resolved them.
    for (NSString *bundleID in @[@"com.apple.mobilemail", @"com.apple.MobileAddressBook",
        @"com.apple.mobilecal", @"com.apple.camera", @"com.apple.VoiceMemos",
        @"com.apple.Translate", @"com.apple.measure", @"com.apple.iBooks",
        @"com.apple.Health", @"com.apple.Passbook"]) {
        QSPaneResolution *existing = routes[bundleID];
        if (existing && existing.state == QSPaneStateAvailable) continue;
        QSPaneState installed = QSInstalledState(bundleID);
        routes[bundleID] = QSResult(installed == QSPaneStateAbsent ? QSPaneStateAbsent : QSPaneStateUnresolved,
                                    nil, @"builtin-adapter-not-implemented");
    }
    return [routes copy];
}

@implementation QSPaneResolver {
    dispatch_queue_t _workQueue;
    dispatch_source_t _timer;
    NSDictionary<NSString *, QSPaneResolution *> *_snapshot;
    NSTimeInterval _snapshotTime;
    NSTimeInterval _lastAttempt;
    BOOL _modelComplete;
    BOOL _enabled;
    BOOL _refreshPending;
    NSUInteger _generation;
    id<QSWorkspace> _observedWorkspace; // Retained for SpringBoard's lifetime.
}

+ (instancetype)sharedResolver {
    static QSPaneResolver *resolver;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ resolver = [self new]; });
    return resolver;
}

- (instancetype)init {
    if ((self = [super init])) {
        _snapshot = @{};
        _workQueue = dispatch_queue_create("com.eolnmsuk.quicksettings.panes", DISPATCH_QUEUE_SERIAL);
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _workQueue);
        dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
                                 30 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(_timer, ^{ [self requestRefresh:NO]; });
        dispatch_resume(_timer);
    }
    return self;
}

- (void)observeApplicationChanges {
    // Confirmed in the versioned iOS 16 workspace/observer headers (see overview).
    if (_observedWorkspace) return;
    Class<QSWorkspace> cls = (Class<QSWorkspace>)NSClassFromString(@"LSApplicationWorkspace");
    if (!QSCanCall(cls, @selector(defaultWorkspace), "@", "")) return;
    @try {
        id<QSWorkspace> workspace = [cls defaultWorkspace];
        if (QSCanCall(workspace, @selector(addObserver:), "v", "@")) {
            [workspace addObserver:self];
            _observedWorkspace = workspace;
        } else {
            QSDiagnostic(@"app-observer", @"App-change observer unavailable; using the 30-second freshness interval.");
        }
    } @catch (NSException *exception) { QSDiagnostic(@"observer-exception", exception.name); }
}

- (void)setEnabled:(BOOL)enabled {
    @synchronized (self) {
        if (_enabled == enabled) return;
        _enabled = enabled;
        _generation++;
        _snapshot = @{};
        _snapshotTime = 0;
        _modelComplete = NO;
    }
    if (enabled) [self requestRefresh:YES];
}

- (void)requestRefresh:(BOOL)force {
    @synchronized (self) {
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (!_enabled || _refreshPending || (!force && now - _lastAttempt < QSRetryDelay)) return;
        _refreshPending = YES;
        _lastAttempt = now;
    }
    dispatch_async(_workQueue, ^{
        @autoreleasepool {
            [self observeApplicationChanges];
            [self refreshOnWorker];
            @synchronized (self) { self->_refreshPending = NO; }
        }
    });
}

- (void)refreshOnWorker {
    NSUInteger generation;
    @synchronized (self) { if (!_enabled) return; generation = _generation; }
    BOOL complete = NO;
    NSDictionary *snapshot = QSBuildSnapshot(&complete);
    @synchronized (self) {
        if (!_enabled || generation != _generation) return;
        _snapshot = snapshot;
        _modelComplete = complete;
        _snapshotTime = NSProcessInfo.processInfo.systemUptime;
    }
}

- (QSPaneResolution *)cachedResolutionForBundleIdentifier:(NSString *)bundleID {
    if (!QSValidBundleIdentifier(bundleID)) return QSResult(QSPaneStateAbsent, nil, @"non-app-icon");
    QSPaneResolution *result;
    @synchronized (self) {
        if (!_enabled) return QSResult(QSPaneStateAbsent, nil, @"disabled");
        BOOL fresh = _snapshotTime > 0 && NSProcessInfo.processInfo.systemUptime - _snapshotTime < QSFreshness;
        result = fresh ? _snapshot[bundleID] : nil;
        if (!result) result = QSResult(fresh && _modelComplete ? QSPaneStateAbsent : QSPaneStateUnresolved,
                                       nil, fresh ? @"not-in-native-pane-model" : @"snapshot-cold-or-stale");
    }
    if (result.state == QSPaneStateUnresolved) [self requestRefresh:NO];
    return result;
}

- (void)applicationModelChanged {
    @synchronized (self) {
        _generation++;
        _snapshotTime = 0;
        _snapshot = @{};
        _modelComplete = NO;
    }
    // Serialize behind any invalidated work, then request an unsuppressed refresh.
    dispatch_async(_workQueue, ^{ [self requestRefresh:YES]; });
}
- (void)applicationsDidInstall:(NSArray *)apps { [self applicationModelChanged]; }
- (void)applicationsDidUninstall:(NSArray *)apps { [self applicationModelChanged]; }
- (void)applicationStateDidChange:(NSArray *)apps { [self applicationModelChanged]; }

- (void)openSettingsForBundleIdentifier:(NSString *)bundleID {
    if (!QSValidBundleIdentifier(bundleID) || !QSReadEnabled()) return;
    NSString *target = [bundleID copy];
    dispatch_async(_workQueue, ^{
        @autoreleasepool {
            // Capture before validation. Capturing after the lookup could bless
            // an old route with a newer app-change generation.
            NSUInteger generation;
            @synchronized (self) {
                if (!self->_enabled) return;
                generation = self->_generation;
            }
            // Rebuild even a fresh menu snapshot: permissions/app state can change
            // while a menu is visible. Never trust a URL supplied in the item.
            [self refreshOnWorker];
            @synchronized (self) {
                if (!self->_enabled || generation != self->_generation) return;
            }
            QSPaneResolution *result = [self cachedResolutionForBundleIdentifier:target];
            if (result.state != QSPaneStateAvailable || QSInstalledState(target) != QSPaneStateAvailable) {
                QSDiagnostic(@"activation-unresolved", [NSString stringWithFormat:@"%@: %@", target, result.reason]);
                [self applicationModelChanged];
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                @synchronized (self) { if (!self->_enabled || generation != self->_generation) return; }
                if (!QSReadEnabled()) return;
                Class<QSWorkspace> cls = (Class<QSWorkspace>)NSClassFromString(@"LSApplicationWorkspace");
                BOOL accepted = NO;
                @try {
                    id<QSWorkspace> workspace = QSCanCall(cls, @selector(defaultWorkspace), "@", "")
                        ? [cls defaultWorkspace] : nil;
                    if (QSCanCall(workspace, @selector(openSensitiveURL:withOptions:), "Bc", "@@")) {
                        accepted = [workspace openSensitiveURL:result.URL withOptions:@{}];
                    } else {
                        QSDiagnostic(@"open-interface", @"Sensitive URL opening is unavailable or ABI-incompatible.");
                    }
                } @catch (NSException *exception) { QSDiagnostic(@"open-exception", exception.name); }
                if (!accepted) {
                    QSDiagnostic(@"open-rejected", [NSString stringWithFormat:@"Settings request rejected for %@.", target]);
                    [self applicationModelChanged];
                }
                // An accepted request is not proof of the final visible page.
            });
        }
    });
}
@end
