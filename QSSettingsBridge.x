// QuickSettings — EolnMsuk. See LICENSE.
// Settings owns discovery and navigation. No Settings controllers are constructed.
#import "QSSettingsNativeInterfaces.h"
#import "QSSettingsIPC.h"
#import "QSSettingsSupport.h"
#import "QSPreferences.h"
#import "QSConstants.h"
#import <substrate.h>
#import <dlfcn.h>

static NSString *QSClassName(id value) {
    NSString *name = value ? NSStringFromClass([value class]) : @"absent";
    return QSIPCValidLocator(name) ? name : @"opaque-class";
}
static NSString *QSSymbolKey(NSString *symbol) {
    // Read exported NSString constants, never guessed property-key literals.
    NSString * __unsafe_unretained *slot = (NSString * __unsafe_unretained *)dlsym(RTLD_DEFAULT, symbol.UTF8String);
    id key = slot ? *slot : nil;
    return [key isKindOfClass:NSString.class] && [key length] <= 128 ? [key copy] : nil;
}
static id QSRowProperty(id row, NSString *symbol) {
    NSString *key = QSSymbolKey(symbol);
    return key && QSCanCall(row, @selector(propertyForKey:), "@", "@")
        ? [(id<QSSettingsSpecifier>)row propertyForKey:key] : nil;
}
static NSString *QSRowID(id row) {
    id identifier = QSCanCall(row, @selector(identifier), "@", "") ? [(id<QSSettingsSpecifier>)row identifier] : nil;
    return QSIPCValidLocator(identifier) ? [identifier copy] : nil;
}
static BOOL QSNativeLink(id row) {
    return [row isKindOfClass:NSClassFromString(@"PSSpecifier")]
        && QSCanCall(row, @selector(cellType), "q", "") && [(id<QSSettingsSpecifier>)row cellType] == 1;
}
static id<QSAppProxy> QSProxy(NSString *appID, BOOL *unavailable) {
    if (unavailable) *unavailable = NO;
    if (!QSValidBundleIdentifier(appID)) return nil;
    Class<QSAppProxy> cls = (Class<QSAppProxy>)NSClassFromString(@"LSApplicationProxy");
    if (!QSCanCall(cls, @selector(applicationProxyForIdentifier:), "@", "@")) return nil;
    id<QSAppProxy> proxy = [cls applicationProxyForIdentifier:appID];
    if (!QSCanCall(proxy, @selector(applicationIdentifier), "@", "") || ![[proxy applicationIdentifier] isEqual:appID]
        || !QSCanCall(proxy, @selector(isInstalled), "Bc", "")
        || !QSCanCall(proxy, @selector(isPlaceholder), "Bc", "")
        || !QSCanCall(proxy, @selector(isRestricted), "Bc", "")) return nil;
    BOOL blocked = ![proxy isInstalled] || [proxy isPlaceholder] || [proxy isRestricted];
    if (unavailable) *unavailable = blocked;
    return blocked ? nil : proxy;
}
static NSString *QSAssociatedProxyID(id value) {
    Class app = NSClassFromString(@"PSThirdPartyApp");
    if (app && [value isKindOfClass:app] && QSCanCall(value, @selector(proxy), "@", "")) value = [(id<QSNativeApp>)value proxy];
    Class proxy = NSClassFromString(@"LSApplicationProxy");
    if (!proxy || ![value isKindOfClass:proxy] || !QSCanCall(value, @selector(applicationIdentifier), "@", "")) return nil;
    id appID = [(id<QSAppProxy>)value applicationIdentifier];
    return QSProxy(appID, NULL) ? [appID copy] : nil;
}
static BOOL QSNativeContains(NSHashTable *context, id object) {
    return [context containsObject:object];
}
static NSDictionary *QSSemanticRecord(NSDictionary *record) {
    NSMutableDictionary *value = [record mutableCopy];
    [value removeObjectForKey:@"revision"]; [value removeObjectForKey:@"evidence"];
    return [value copy];
}

// Independently establish the app-only context from the real root's native
// third-party array. Only exact installed application IDs calibrate the dedicated
// app-settings key. Icons, defaults domains and preference bundles never calibrate it.
static NSDictionary *QSKeySemantics(NSArray *specifiers, NSHashTable *thirdParty) {
    NSUInteger matches = 0, conflicts = 0;
    NSMutableSet *apps = [NSMutableSet set];
    for (id row in specifiers) {
        if (!QSNativeLink(row) || !QSNativeContains(thirdParty, row)) continue;
        NSString *appID = QSRowID(row);
        if (!QSProxy(appID, NULL)) continue;
        id value = QSRowProperty(row, @"PSAppSettingsBundleIDKey");
        if (!value) continue;
        if ([value isKindOfClass:NSString.class] && [value isEqual:appID]) {
            if (![apps containsObject:appID]) { matches++; [apps addObject:appID]; }
        } else conflicts++;
    }
    return @{@"key": QSSymbolKey(@"PSAppSettingsBundleIDKey") ?: @"symbol-unavailable", @"scope": @"native-third-party-array-only",
        @"independentAppMatches": @(matches), @"conflicts": @(conflicts), @"validated": @(matches >= 2 && !conflicts)};
}

static NSString *QSIdentity(id row, BOOL appContext, BOOL keyValidated, NSString **evidence, NSString **reason) {
    id user = QSCanCall(row, @selector(userInfo), "@", "") ? [(id<QSSettingsSpecifier>)row userInfo] : nil;
    id bundleValue = QSRowProperty(row, @"PSAppSettingsBundleKey");
    NSString *associated = QSAssociatedProxyID(user) ?: QSAssociatedProxyID(bundleValue);
    NSString *kind = associated ? @"native-app-proxy" : nil;
    // An NSBundle is evidence only for the very same installed .app URL. A
    // Preferences .bundle identifier/path is deliberately not an app association.
    if (!associated && [bundleValue isKindOfClass:NSBundle.class]) {
        NSBundle *bundle = bundleValue;
        id<QSAppProxy> proxy = QSProxy(bundle.bundleIdentifier, NULL);
        NSURL *url = QSCanCall(proxy, @selector(bundleURL), "@", "") ? [proxy bundleURL] : nil;
        if ([bundle.bundleURL.pathExtension isEqual:@"app"] && [url isKindOfClass:NSURL.class]
            && [bundle.bundleURL.standardizedFileURL isEqual:url.standardizedFileURL]) {
            associated = bundle.bundleIdentifier; kind = @"native-application-bundle";
        }
    }
    NSString *rowID = QSRowID(row);
    NSString *nativeID = appContext && QSProxy(rowID, NULL) ? rowID : nil;
    id keyValue = QSRowProperty(row, @"PSAppSettingsBundleIDKey");
    // Calibration in the third-party model cannot prove the same property's
    // meaning on a system/global row. Those require an independent native app
    // object or .app bundle association. Keep unresolved system rows as gaps.
    NSString *keyID = keyValidated && appContext && QSProxy(keyValue, NULL) ? keyValue : nil;
    NSMutableSet *identities = [NSMutableSet set];
    for (NSString *candidate in @[associated ?: @"", nativeID ?: @"", keyID ?: @""]) if (candidate.length) [identities addObject:candidate];
    if (identities.count > 1) { *reason = @"conflicting-native-app-identities"; return nil; }
    NSString *result = associated ?: nativeID ?: keyID;
    if (!result) {
        if (keyValue && keyValidated && !appContext) *reason = @"system-row-app-settings-key-semantics-unverified";
        else if (keyValue && !keyValidated) *reason = @"app-settings-key-semantics-unverified";
        else if (QSValidBundleIdentifier(rowID) && QSProxy(rowID, NULL)) *reason = @"app-page-context-unproven";
        else *reason = @"native-app-association-unresolved";
        return nil;
    }
    *evidence = kind ?: (nativeID ? @"native-third-party-row-id" : @"calibrated-app-settings-key");
    return [result copy];
}
static NSString *QSAvailabilityReason(id row) {
    for (NSString *name in @[@"buttonAction", @"confirmationAction", @"legacyAction"]) {
        SEL selector = NSSelectorFromString(name);
        if (!QSCanCall(row, selector, ":", "")) return @"row-action-abi-unsupported";
        SEL action = [name isEqual:@"buttonAction"] ? [(id<QSSettingsSpecifier>)row buttonAction] :
            ([name isEqual:@"confirmationAction"] ? [(id<QSSettingsSpecifier>)row confirmationAction] : [(id<QSSettingsSpecifier>)row legacyAction]);
        if (action) return @"action-row-excluded";
    }
    if (!QSCanCall(row, @selector(hasValidSetter), "Bc", "")) return @"row-setter-abi-unsupported";
    if ([(id<QSSettingsSpecifier>)row hasValidSetter]) return @"setter-row-excluded";
    if (QSRowProperty(row, @"PSConfirmationKey") || QSRowProperty(row, @"PSDeletionActionKey")) return @"confirmation-row-excluded";
    id destructive = QSRowProperty(row, @"PSConfirmationDestructiveKey");
    if (destructive && (![destructive isKindOfClass:NSNumber.class] || [destructive boolValue])) return @"destructive-row-excluded";
    id enabled = QSRowProperty(row, @"PSEnabledKey");
    if (enabled && ![enabled isKindOfClass:NSNumber.class]) return @"enabled-property-type-unsupported";
    if (enabled && ![enabled boolValue]) return @"native-row-disabled";
    return nil;
}
static NSArray *QSPropertyDiagnostics(id row) {
    NSMutableArray *properties = [NSMutableArray array];
    for (NSString *symbol in @[@"PSAppSettingsBundleIDKey", @"PSAppSettingsBundleKey", @"PSLazyIconAppID", @"PSDefaultsKey", @"PSBundlePathKey", @"PSIsTopLevelKey", @"PSEnabledKey"]) {
        NSString *key = QSSymbolKey(symbol); id value = key ? QSRowProperty(row, symbol) : nil;
        NSMutableDictionary *entry = [@{@"symbol": symbol, @"key": key ?: @"symbol-unavailable", @"type": QSClassName(value)} mutableCopy];
        // Syntactically bounded identifier hints only, never ownership evidence
        // or arbitrary preference values. A hint can also identify an unavailable app.
        if (([symbol isEqual:@"PSLazyIconAppID"] || [symbol isEqual:@"PSAppSettingsBundleIDKey"])
            && QSValidBundleIdentifier(value)) entry[@"identifierHint"] = [value copy];
        [properties addObject:[entry copy]];
    }
    return [properties copy];
}

// Main-thread scan of the real, already-owned root model. Returns scalar data;
// liveRows stays in Settings memory and is never passed to the IO worker.
static NSDictionary *QSScan(id owner, NSMutableDictionary *liveRows) {
    NSCAssert(NSThread.isMainThread, @"Native Settings metadata is main-thread only.");
    id native = QSCanCall(owner, @selector(specifiers), "@", "") ? [(id<QSSettingsList>)owner specifiers] : nil;
    BOOL thirdGetter = QSCanCall(owner, @selector(_thirdPartySpecifiers), "@", "");
    id third = thirdGetter ? [(id<QSSettingsList>)owner _thirdPartySpecifiers] : nil;
    if (![native isKindOfClass:NSArray.class]) return @{@"records": @{}, @"rows": @[], @"retired": @[], @"state": @"root-model-not-ready", @"overflow": @NO};
    BOOL overflow = [native count] > QSIPCMaximumRows || ([third isKindOfClass:NSArray.class] && [third count] > QSIPCMaximumRows);
    NSArray *specifiers = [native count] > QSIPCMaximumRows ? [native subarrayWithRange:NSMakeRange(0, QSIPCMaximumRows)] : [native copy];
    NSArray *thirdParty = [third isKindOfClass:NSArray.class] && [third count] <= QSIPCMaximumRows ? [third copy] : @[];
    NSHashTable *appContextRows = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for (id row in thirdParty) [appContextRows addObject:row];
    NSDictionary *semantics = QSKeySemantics(specifiers, appContextRows);
    NSMutableDictionary *ids = [NSMutableDictionary dictionary];
    for (id row in specifiers) { NSString *identifier = QSRowID(row); if (identifier) ids[identifier] = @([ids[identifier] unsignedIntegerValue] + 1); }
    NSMutableDictionary *records = [NSMutableDictionary dictionary];
    NSMutableArray *rows = [NSMutableArray array]; NSMutableSet *retired = [NSMutableSet set];
    NSString *group = @"unidentified-native-group";
    for (id row in specifiers) {
        BOOL nativeClass = [row isKindOfClass:NSClassFromString(@"PSSpecifier")];
        if (!nativeClass || !QSCanCall(row, @selector(cellType), "q", "")) {
            [rows addObject:@{@"row": QSRowID(row) ?: @"unavailable", @"parent": @"settings-root", @"group": group,
                @"cell": @"unsupported", @"controller": @"unavailable", @"context": @"unclassified-native-row",
                @"availability": nativeClass ? @"cell-type-abi-unsupported" : @"native-specifier-class-unsupported",
                @"identityProperties": QSPropertyDiagnostics(row)}];
            continue;
        }
        NSInteger cell = [(id<QSSettingsSpecifier>)row cellType];
        if (cell == 0) { group = QSRowID(row) ?: @"unidentified-native-group"; continue; }
        NSString *identifier = QSRowID(row);
        BOOL appContext = QSNativeContains(appContextRows, row);
        NSString *evidence = nil, *reason = nil;
        NSString *appID = QSIdentity(row, appContext, [semantics[@"validated"] boolValue], &evidence, &reason);
        NSString *unavailable = cell == 1 ? QSAvailabilityReason(row) : @"non-link-cell-excluded";
        if (unavailable) reason = unavailable;
        if (!identifier) reason = @"row-identifier-unavailable-or-private";
        else if ([ids[identifier] unsignedIntegerValue] != 1) reason = @"duplicate-native-row-identifier";
        if (appID && !reason && records[appID]) {
            reason = @"multiple-native-pages-for-app"; [retired addObject:appID];
            [records removeObjectForKey:appID]; [liveRows removeObjectForKey:appID];
        }
        if (appID && [retired containsObject:appID]) reason = @"multiple-native-pages-for-app";
        if (appID && !reason) {
            records[appID] = @{@"app": appID, @"owner": @"settings-root", @"row": identifier,
                @"group": group, @"evidence": evidence, @"available": @YES};
            liveRows[appID] = row;
        }
        Class detail = QSCanCall(row, @selector(detailControllerClass), "#", "") ? [(id<QSSettingsSpecifier>)row detailControllerClass] : Nil;
        NSMutableDictionary *diagnostic = [@{@"row": identifier ?: @"unavailable", @"parent": @"settings-root", @"group": group,
            @"cell": @(cell), @"controller": detail ? NSStringFromClass(detail) : @"lazy-or-unavailable",
            @"context": appContext ? @"native-third-party-array" : @"native-root-link",
            @"availability": reason ?: @"available", @"identityProperties": QSPropertyDiagnostics(row)} mutableCopy];
        if (appID) diagnostic[@"app"] = appID;
        if (evidence) diagnostic[@"identityEvidence"] = evidence;
        [rows addObject:[diagnostic copy]];
    }
    return @{@"records": [records copy], @"rows": [rows copy], @"retired": retired.allObjects,
        @"state": @"partial-native-model", @"overflow": @(overflow), @"keySemantics": semantics,
        @"thirdPartyState": !thirdGetter ? @"getter-abi-unsupported" : (![third isKindOfClass:NSArray.class]
            ? @"native-container-not-an-array" : ([third count] > QSIPCMaximumRows ? @"native-container-overflow" : @"observed-without-completion-proof")),
        @"nativeSpecifierCount": @([native count]), @"nativeThirdPartyCount": @(thirdParty.count)};
}

@interface QSSettingsBridge : NSObject
+ (instancetype)sharedBridge;
- (void)start;
- (void)hint;
- (void)observeRoot:(id)root;
- (void)modelChanged:(id)owner;
- (void)didAppear:(id)controller;
- (void)userInteraction;
- (void)becameInactive;
@end

static void QSBridgeHint(CFNotificationCenterRef center, void *observer, CFStringRef name,
                         const void *object, CFDictionaryRef info) {
    [QSSettingsBridge.sharedBridge hint];
}
static BOOL QSInstallNativeHooks(void);
static BOOL QSInstallSceneObserver(void);

@implementation QSSettingsBridge {
    dispatch_queue_t _queue;
    NSString *_publisher;
    NSUInteger _signal; // memory barrier for command/preference hints, never a notification payload
    BOOL _readPending;
    BOOL _readAgain;
    BOOL _supported;
    dispatch_source_t _pollTimer;
    NSString *_pollID;
    NSDictionary *_publishedRecords; // IO-queue only
    NSDictionary *_publishedInventory; // IO-queue only
    NSDictionary *_lastDiagnostics; // IO-queue only
    NSDictionary *_exportCommand; // IO-queue only, safe protocol objects only
    NSDictionary *_exportReply;
    NSURL *_exportURL;
    id<QSWorkspace> _workspace; // IO-queue only
    // Everything below is main-thread confined. No native object crosses into IPC.
    __weak UIViewController *_root;
    __weak UIViewController *_owner;
    NSString *_ownerState;
    BOOL _captureQueued;
    BOOL _capturing;
    NSUInteger _captureGeneration;
    NSDictionary *_liveRecords;
    NSDictionary *_request;
    NSDictionary *_terminalRequest;
    NSDictionary *_command;
    BOOL _enabled;
    BOOL _selectionCommitting;
    BOOL _dispatchCommitted;
    BOOL _selectionInvoked;
    BOOL _sawActiveScene;
    BOOL _rowResolvedReported;
    BOOL _requestRefreshAttempted;
    NSUInteger _interaction;
    NSUInteger _requestInteraction;
    NSUInteger _requestSignal;
    NSString *_waitReason;
    id _selectedRow;
    NSArray *_notificationTokens;
}
+ (instancetype)sharedBridge {
    static QSSettingsBridge *value; static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [self new]; }); return value;
}
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.eolnmsuk.quicksettings.settings-bridge", DISPATCH_QUEUE_SERIAL);
        _publisher = NSUUID.UUID.UUIDString; _liveRecords = @{};
    }
    return self;
}
- (NSUInteger)signal { @synchronized (self) { return _signal; } }
- (void)hint {
    @synchronized (self) { _signal++; }
    [self readPendingState];
}
- (void)readPendingState {
    @synchronized (self) {
        if (_readPending) { _readAgain = YES; return; } _readPending = YES;
    }
    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSUInteger signal = [self signal];
            BOOL read = NO, enabled = NO;
            NSDictionary *command = QSIPCRead(QSIPCCommandKey, &read);
            BOOL prefsRead = QSReadEnabledWithStatus(&enabled);
            BOOL replyRead = NO; NSDictionary *reply = QSIPCRead(QSIPCReplyKey, &replyRead);
            BOOL commandValid = QSIPCValidCommand(command);
            NSString *readFailure = !prefsRead ? @"preference-read-failed" : (!read ? @"command-read-failed" :
                (!command ? @"command-absent" : (!commandValid ? @"command-schema-incompatible" : nil)));
            if (!read || !prefsRead || !commandValid) {
                if (command || !read || !prefsRead) QSDiagnostic(@"settings-command-invalid", @"Bridge command or committed preferences are unreadable or incompatible.");
                command = nil;
            }
            if (!replyRead || !QSIPCValidReply(reply)) reply = nil;
            BOOL exportChanged = !(self->_exportCommand == command || [self->_exportCommand isEqual:command])
                || !(self->_exportReply == reply || [self->_exportReply isEqual:reply]);
            self->_exportCommand = command; self->_exportReply = reply;
            if (exportChanged) [self exportDiagnostics];
            [self configurePoll:command[@"request"] reply:reply];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (signal != [self signal]) return;
                [self acceptCommand:command enabled:prefsRead && enabled reply:reply failure:readFailure];
            });
            BOOL again;
            @synchronized (self) { self->_readPending = NO; again = self->_readAgain; self->_readAgain = NO; }
            if (again) [self readPendingState];
        }
    });
}
- (BOOL)reply:(NSDictionary *)reply matches:(NSDictionary *)request {
    if (!QSIPCValidReply(reply) || !QSIPCValidRequest(request)) return NO;
    for (NSString *key in @[@"session", @"request", @"target", @"revision", @"sequence", @"preferenceGeneration", @"boot"])
        if (![reply[key] isEqual:request[key]]) return NO;
    double uptime = [reply[@"uptime"] doubleValue];
    return uptime >= [request[@"created"] doubleValue] && uptime <= QSIPCUptime()
        && (![reply[@"stage"] isEqual:@"visible-target"] || uptime < [request[@"deadline"] doubleValue]);
}
- (void)configurePoll:(NSDictionary *)request reply:(NSDictionary *)reply {
    BOOL terminal = [self reply:reply matches:request] && [reply[@"terminal"] boolValue];
    if (!QSIPCRequestIsLive(request) || terminal) {
        if (_pollTimer) dispatch_source_cancel(_pollTimer); _pollTimer = nil; _pollID = nil; return;
    }
    if ([_pollID isEqual:request[@"request"]]) return;
    if (_pollTimer) dispatch_source_cancel(_pollTimer);
    _pollID = request[@"request"];
    _pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_pollTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), NSEC_PER_SEC / 4, NSEC_PER_SEC / 40);
    dispatch_source_set_event_handler(_pollTimer, ^{ [self readPendingState]; }); dispatch_resume(_pollTimer);
}
- (void)observeRoot:(id)root {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self observeRoot:root]; }); return;
    }
    if (![root isKindOfClass:UIViewController.class] || _root == root) return;
    _root = root; // model/lifecycle hooks schedule work outside this native getter
}
- (void)modelChanged:(id)owner {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self modelChanged:owner]; }); return;
    }
    if (![owner isKindOfClass:NSClassFromString(@"PSUIPrefsListController")]) return;
    _owner = owner;
    if (!_capturing) [self scheduleCapture];
}
- (void)didAppear:(id)controller {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_supported) self->_supported = QSInstallNativeHooks();
        [self scheduleCapture]; [self readPendingState];
    });
}
- (void)scheduleCapture {
    NSCAssert(NSThread.isMainThread, @"Capture scheduling is main-thread only.");
    if (_captureQueued || _capturing) return;
    _captureQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_captureQueued = NO; [self capture];
    });
}

// Walk only an existing scene's controller hierarchy, including native navigation
// stacks. Bounds apply even if another tweak has introduced a container cycle.
- (NSArray<UIViewController *> *)existingControllers {
    NSMutableArray *pending = [NSMutableArray array], *result = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.rootViewController) [pending addObject:window.rootViewController];
    }
    while (pending.count && result.count < 64) {
        UIViewController *controller = pending.lastObject; [pending removeLastObject];
        if ([result indexOfObjectIdenticalTo:controller] != NSNotFound) continue;
        [result addObject:controller];
        if ([controller isKindOfClass:UINavigationController.class]) [pending addObjectsFromArray:((UINavigationController *)controller).viewControllers];
        [pending addObjectsFromArray:controller.childViewControllers];
        if (controller.presentedViewController) [pending addObject:controller.presentedViewController];
        if (pending.count > 128) break;
    }
    return [result copy];
}
- (UIViewController *)nativeOwner {
    NSArray *controllers = [self existingControllers];
    NSMutableArray *owners = [NSMutableArray array];
    NSMutableArray *activeOwners = [NSMutableArray array];
    for (UIViewController *controller in controllers) {
        if ([controller isKindOfClass:NSClassFromString(@"PSUIPrefsRootController")]
            && QSCanCall(controller, @selector(rootListController), "@", "")) {
            id list = [(id<QSSettingsRoot>)controller rootListController];
            if ([list isKindOfClass:NSClassFromString(@"PSUIPrefsListController")]
                && [owners indexOfObjectIdenticalTo:list] == NSNotFound) {
                [owners addObject:list];
                UIWindow *window = controller.viewIfLoaded.window;
                if (window.isKeyWindow && window.windowScene.activationState == UISceneActivationStateForegroundActive)
                    [activeOwners addObject:list];
            }
        }
    }
    // Unattached list objects cannot establish accessible rows. Wait for the real
    // Settings window hierarchy even if a native getter was already observed.
    NSArray *candidates = activeOwners.count ? activeOwners : owners;
    if (candidates.count != 1) {
        _ownerState = candidates.count ? @"ambiguous-native-scene-owners" : @"native-root-owner-not-ready";
        return nil;
    }
    _ownerState = @"native-owner-observed";
    _owner = candidates.firstObject;
    if ([_owner.navigationController isKindOfClass:NSClassFromString(@"PSUIPrefsRootController")]) _root = _owner.navigationController;
    return _owner;
}
- (NSDictionary *)scanOwner:(UIViewController *)owner liveRows:(NSMutableDictionary *)liveRows {
    _capturing = YES; NSDictionary *scan;
    @try { scan = QSScan(owner, liveRows); }
    @catch (NSException *exception) {
        scan = @{@"records": @{}, @"rows": @[], @"retired": @[], @"state": @"native-model-exception", @"overflow": @NO};
        QSDiagnostic(@"native-model-exception", exception.name);
    } @finally { _capturing = NO; }
    return scan;
}
- (void)capture {
    NSUInteger generation = ++_captureGeneration;
    UIViewController *owner = _supported ? [self nativeOwner] : nil;
    NSDictionary *scan = _supported && _enabled && owner ? [self scanOwner:owner liveRows:[NSMutableDictionary dictionary]] :
        @{@"records": @{}, @"rows": @[], @"retired": @[], @"state": _enabled ? @"native-adapter-unsupported" : @"disabled-inventory-dormant", @"overflow": @NO};
    if (_supported && _enabled && !owner) scan = @{@"records": @{}, @"rows": @[], @"retired": @[], @"state": _ownerState ?: @"native-root-owner-not-ready", @"overflow": @NO};
    dispatch_async(_queue, ^{ [self publishScan:scan generation:generation]; });
}
- (void)publishScan:(NSDictionary *)scan generation:(NSUInteger)generation {
    if (!_publishedRecords) {
        BOOL ok = NO; NSDictionary *previous = QSIPCRead(QSIPCInventoryKey, &ok);
        BOOL valid = ok && QSIPCValidInventory(previous);
        _publishedRecords = valid ? previous[@"records"] : @{};
        _publishedInventory = valid ? previous : nil;
    }
    NSMutableDictionary *merged = [_publishedRecords mutableCopy];
    for (NSString *appID in scan[@"retired"]) [merged removeObjectForKey:appID];
    for (NSDictionary *row in scan[@"rows"]) {
        if (![@[@"native-row-disabled", @"duplicate-native-row-identifier", @"conflicting-native-app-identities",
            @"action-row-excluded", @"confirmation-row-excluded", @"destructive-row-excluded"] containsObject:row[@"availability"]]) continue;
        for (NSString *appID in [merged.allKeys copy])
            if ([merged[appID][@"row"] isEqual:row[@"row"]]) [merged removeObjectForKey:appID];
    }
    for (NSString *appID in [merged.allKeys copy]) {
        BOOL unavailable = NO; QSProxy(appID, &unavailable);
        if (unavailable) [merged removeObjectForKey:appID];
    }
    BOOL overflow = [scan[@"overflow"] boolValue];
    for (NSString *appID in scan[@"records"]) {
        NSDictionary *draft = scan[@"records"][appID];
        NSDictionary *prior = merged[appID];
        if (prior && [QSSemanticRecord(prior) isEqual:QSSemanticRecord(draft)]) {
            NSMutableDictionary *record = [draft mutableCopy]; record[@"revision"] = prior[@"revision"];
            merged[appID] = [record copy]; continue;
        }
        if (!prior && merged.count >= QSIPCMaximumRecords) { overflow = YES; continue; }
        NSMutableDictionary *record = [draft mutableCopy]; record[@"revision"] = NSUUID.UUID.UUIDString;
        merged[appID] = [record copy];
    }
    NSMutableDictionary *inventory = [QSIPCHeader() mutableCopy];
    NSMutableArray *observed = [NSMutableArray array];
    for (NSString *appID in scan[@"records"]) if (merged[appID]) [observed addObject:appID];
    [inventory addEntriesFromDictionary:@{@"publisher": _publisher, @"publication": NSUUID.UUID.UUIDString, @"boot": QSBootIdentity(), @"observed": [observed copy],
        @"uptime": @(QSIPCUptime()), @"complete": @NO,
        @"coverage": @"partial-native-model-background-refresh-unproven", @"records": [merged copy]}];
    BOOL committed = QSIPCValidInventory(inventory) && QSIPCWrite(QSIPCInventoryKey, inventory, QS_INDEX_HINT);
    if (committed) { _publishedRecords = [merged copy]; _publishedInventory = [inventory copy]; }
    NSMutableDictionary *diagnostics = [QSIPCHeader() mutableCopy];
    [diagnostics addEntriesFromDictionary:scan];
    [diagnostics removeObjectForKey:@"records"]; [diagnostics removeObjectForKey:@"retired"];
    diagnostics[@"publisher"] = _publisher; diagnostics[@"overflow"] = @(overflow);
    diagnostics[@"indexedApps"] = @(merged.count); diagnostics[@"liveResolvedApps"] = @([scan[@"records"] count]);
    diagnostics[@"indexCommitted"] = @(committed);
    diagnostics[@"asyncCompletion"] = @"unproven-partial-publications-never-retire-omissions";
    diagnostics[@"lifecycle"] = @"settings-must-run-for-discovery-no-background-activation-adapter";
    diagnostics[@"limits"] = @{@"records": @(QSIPCMaximumRecords), @"rows": @(QSIPCMaximumRows), @"bytesPerInventoryOrDiagnostics": @(1024 * 1024)};
    NSMutableArray *exportRows = [diagnostics[@"rows"] mutableCopy];
    NSUInteger originalCount = exportRows.count;
    diagnostics[@"droppedRows"] = @0;
    while ([[NSPropertyListSerialization dataWithPropertyList:diagnostics format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL] length] > 1024 * 1024 && exportRows.count) {
        [exportRows removeObjectsInRange:NSMakeRange(exportRows.count / 2, exportRows.count - exportRows.count / 2)];
        diagnostics[@"rows"] = [exportRows copy]; diagnostics[@"overflow"] = @YES;
        diagnostics[@"droppedRows"] = @(originalCount - exportRows.count);
    }
    if (![_lastDiagnostics isEqual:diagnostics]) {
        if (QSIPCWrite(QSIPCDiagnosticsKey, diagnostics, NULL)) _lastDiagnostics = [diagnostics copy];
        [self exportDiagnostics];
        QSVerboseDiagnostic(@"native-inventory", ([NSString stringWithFormat:@"marker=%@ live=%lu indexed=%lu overflow=%@ complete=no state=%@",
            QSNavigationMarker, (unsigned long)[scan[@"records"] count], (unsigned long)merged.count, overflow ? @"yes" : @"no", scan[@"state"]]));
    }
    NSDictionary *published = committed ? [merged copy] : @{};
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self->_captureGeneration) return;
        NSMutableDictionary *live = [NSMutableDictionary dictionary];
        for (NSString *appID in scan[@"records"]) if (published[appID]) live[appID] = published[appID];
        self->_liveRecords = [live copy];
        [self readPendingState];
    });
}

- (void)exportDiagnostics {
#if QS_VERBOSE_DIAGNOSTICS
    // One bounded, atomically replaced, sanitized plist in Settings' own cache.
    // The runtime location is logged; no jailbreak/container path is assumed.
    if (!_lastDiagnostics) return;
    BOOL ok = NO; NSDictionary *command = QSIPCRead(QSIPCCommandKey, &ok);
    if (!ok || !QSIPCValidCommand(command)) command = nil;
    NSDictionary *reply = QSIPCRead(QSIPCReplyKey, &ok);
    if (!ok || !QSIPCValidReply(reply)) reply = nil;
    NSMutableDictionary *payload = [QSIPCHeader() mutableCopy];
    payload[@"diagnostics"] = _lastDiagnostics;
    if (_publishedInventory) payload[@"inventory"] = _publishedInventory;
    if (command) payload[@"command"] = command;
    if (reply) payload[@"reply"] = reply;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:payload format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    // XML is readable by the user's existing plist viewer. Its overhead is also bounded.
    if (!data || data.length > 8 * 1024 * 1024) { QSDiagnostic(@"diagnostic-export-overflow", @"Sanitized export exceeds its 8 MiB XML limit; bounded domain keys remain available."); return; }
    if (!_exportURL) {
        NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        if (cache.isFileURL) {
            [NSFileManager.defaultManager createDirectoryAtURL:cache withIntermediateDirectories:YES attributes:nil error:NULL];
            _exportURL = [cache URLByAppendingPathComponent:@"QuickSettings-native-bridge.plist" isDirectory:NO];
        }
    }
    if (!_exportURL || ![data writeToURL:_exportURL options:NSDataWritingAtomic error:NULL]) {
        QSDiagnostic(@"diagnostic-export-write", @"Could not write Settings' sanitized diagnostic export."); return;
    }
    QSDiagnostic(@"diagnostic-export", [NSString stringWithFormat:@"marker=%@ export=%@", QSNavigationMarker, _exportURL.path]);
#endif
}

- (NSString *)committedRequestFailure:(NSDictionary *)request requireLive:(BOOL)live {
    BOOL ok = NO, enabled = NO;
    NSDictionary *command = QSIPCRead(QSIPCCommandKey, &ok);
    if (!ok) return @"command-read-failed";
    if (!QSIPCValidCommand(command)) return @"command-schema-incompatible";
    if (![command[@"enabled"] boolValue]) return @"command-disabled";
    if (!QSIPCSameRequest(command[@"request"], request)) return @"request-replaced";
    if (live) {
        if (!QSReadEnabledWithStatus(&enabled)) return @"preference-read-failed";
        if (!enabled) return @"committed-disabled";
        if (!QSIPCRequestIsLive(request)) return @"deadline-expired";
    }
    return nil;
}
- (BOOL)committedRequest:(NSDictionary *)request requireLive:(BOOL)live {
    return ![self committedRequestFailure:request requireLive:live];
}
- (void)postStage:(NSString *)stage reason:(NSString *)reason request:(NSDictionary *)request {
    QSNavigationTrace(request, stage, reason);
    dispatch_async(_queue, ^{
        BOOL read = NO; NSDictionary *previous = QSIPCRead(QSIPCReplyKey, &read);
        if (read && [self reply:previous matches:request] && [previous[@"terminal"] boolValue]) return;
        if ([self committedRequest:request requireLive:YES]) {
            QSIPCWrite(QSIPCReplyKey, QSIPCReply(request, stage, reason, NO), QS_REPLY_HINT);
            [self exportDiagnostics];
        }
    });
}
- (void)finishStage:(NSString *)stage reason:(NSString *)reason feedback:(BOOL)feedback {
    NSCAssert(NSThread.isMainThread, @"Settings request state is main-thread only.");
    NSDictionary *request = _request;
    if (!request) return;
    _terminalRequest = request; _request = nil; _selectedRow = nil;
    _selectionCommitting = NO; _dispatchCommitted = NO; _selectionInvoked = NO;
    QSNavigationTrace(request, stage, reason);
    if (![stage isEqual:@"visible-target"]) QSDiagnostic(@"settings-navigation-result", [NSString stringWithFormat:
        @"request=%@ target=%@ stage=%@ reason=%@", request[@"request"], request[@"target"], stage, reason]);
    NSUInteger interaction = _interaction, signal = [self signal];
    dispatch_async(_queue, ^{
        if ([self committedRequest:request requireLive:NO]) {
            QSIPCWrite(QSIPCReplyKey, QSIPCReply(request, stage, reason, YES), QS_REPLY_HINT);
            [self exportDiagnostics];
        }
        if ([self->_pollID isEqual:request[@"request"]]) {
            if (self->_pollTimer) dispatch_source_cancel(self->_pollTimer);
            self->_pollTimer = nil; self->_pollID = nil;
        }
    });
    if (feedback) dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_request && self->_interaction == interaction && signal == [self signal]) QSNavigationFailureFeedback();
    });
}
- (void)acceptCommand:(NSDictionary *)command enabled:(BOOL)enabled reply:(NSDictionary *)reply failure:(NSString *)failure {
    if (!_supported) _supported = QSInstallNativeHooks(); // enable can follow late framework loading
    BOOL newlyEnabled = enabled && !_enabled;
    _enabled = enabled; _command = command;
    _requestSignal = [self signal];
    if (newlyEnabled) [self scheduleCapture]; // enabling in our pane seeds the actual root inventory
    NSDictionary *incoming = enabled && [command[@"enabled"] boolValue] ? command[@"request"] : nil;
    if (_request && !QSIPCSameRequest(_request, incoming)) {
        NSString *reason = failure ?: (!enabled ? @"committed-disabled" : (!command ? @"command-absent" :
            (!incoming ? command[@"state"] : @"replacement-request")));
        [self finishStage:@"cancelled" reason:reason feedback:NO];
    }
    if (!incoming || QSIPCSameRequest(_terminalRequest, incoming)) return;
    if (!_request) {
        _request = incoming; _requestInteraction = _interaction;
        _selectionCommitting = NO; _dispatchCommitted = NO; _selectionInvoked = NO;
        _sawActiveScene = NO; _rowResolvedReported = NO; _requestRefreshAttempted = NO; _selectedRow = nil; _waitReason = @"scene-or-model-not-ready";
        if ([self reply:reply matches:incoming]) {
            if ([reply[@"terminal"] boolValue]) { _terminalRequest = incoming; _request = nil; return; }
            if ([@[@"selection-dispatch-committed", @"selection-invoked"] containsObject:reply[@"stage"]]) {
                // The previous Settings process crossed the at-most-once boundary.
                // Replaying its row handler could double-push an already selected page.
                [self finishStage:@"failed" reason:@"selection-state-uncertain-after-settings-restart" feedback:YES]; return;
            }
        }
        [self postStage:@"request-received" reason:@"matching-command-and-committed-enable" request:incoming];
        [self scheduleCapture];
    }
    if (!QSIPCRequestIsLive(_request)) {
        [self finishStage:@"expired" reason:_waitReason ?: @"deadline-expired" feedback:YES]; return;
    }
    if (!_supported) { [self finishStage:@"failed" reason:@"native-adapter-unsupported" feedback:YES]; return; }
    if (_interaction != _requestInteraction) { [self finishStage:@"cancelled" reason:@"user-interaction" feedback:NO]; return; }
    [self tryNavigate];
}

- (UINavigationController *)activeNavigationForOwner:(UIViewController *)owner {
    if (!owner) { _waitReason = _ownerState ?: @"native-root-owner-not-ready"; return nil; }
    if ([[self existingControllers] indexOfObjectIdenticalTo:owner] == NSNotFound) { _waitReason = @"native-owner-not-in-scene"; return nil; }
    UINavigationController *navigation = owner.navigationController;
    if (![navigation isKindOfClass:UINavigationController.class]
        || [navigation.viewControllers indexOfObjectIdenticalTo:owner] == NSNotFound) {
        _waitReason = @"native-owner-container-unsupported"; return nil;
    }
    UIWindow *window = navigation.viewIfLoaded.window;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive || !window.isKeyWindow
        || window.windowScene.activationState != UISceneActivationStateForegroundActive) {
        _waitReason = @"settings-scene-inactive"; return nil;
    }
    _sawActiveScene = YES;
    if (navigation.presentedViewController || _root.presentedViewController) { _waitReason = @"modal-blocked"; return nil; }
    for (UIViewController *controller in navigation.viewControllers) {
        if (controller.presentedViewController) { _waitReason = @"modal-blocked"; return nil; }
    }
    if (navigation.transitionCoordinator || navigation.isBeingDismissed) { _waitReason = @"native-transition-in-progress"; return nil; }
    return navigation;
}
- (BOOL)visibleControllerMatches:(UINavigationController *)navigation row:(id)row owner:(UIViewController *)owner {
    UIViewController *visible = navigation.visibleViewController;
    if (!visible || visible == owner || visible != navigation.topViewController || navigation.transitionCoordinator
        || !visible.viewIfLoaded.window || visible.isBeingDismissed || visible.presentedViewController) return NO;
    // Require the target's own controller to be the visible root child, not an
    // unrelated descendant or a global privacy/notification subpage with a title.
    NSUInteger ownerIndex = [navigation.viewControllers indexOfObjectIdenticalTo:owner];
    if (ownerIndex == NSNotFound || ownerIndex + 2 != navigation.viewControllers.count) return NO;
    for (NSUInteger depth = 0; visible && depth < 8; depth++) {
        id origin = QSCanCall(visible, @selector(specifier), "@", "") ? [(id<QSSettingsPage>)visible specifier] : nil;
        if (origin == row || (_selectedRow && origin == _selectedRow)) return YES;
        NSMutableArray *children = [NSMutableArray array];
        for (UIViewController *child in visible.childViewControllers)
            if (child.viewIfLoaded.window == visible.viewIfLoaded.window && !child.viewIfLoaded.hidden) [children addObject:child];
        if (children.count != 1) return NO;
        visible = children.firstObject;
    }
    return NO;
}
- (void)commitSelectionBoundary {
    if (_selectionCommitting || _dispatchCommitted || !_request) return;
    _selectionCommitting = YES;
    NSDictionary *request = _request;
    NSUInteger signal = [self signal], interaction = _interaction;
    dispatch_async(_queue, ^{
        NSString *failure = [self committedRequestFailure:request requireLive:YES];
        BOOL written = !failure && QSIPCWrite(QSIPCReplyKey,
            QSIPCReply(request, @"selection-dispatch-committed", @"at-most-once-native-handler", NO), QS_REPLY_HINT);
        if (written) QSNavigationTrace(request, @"selection-dispatch-committed", @"at-most-once-native-handler");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!QSIPCSameRequest(self->_request, request)) return;
            self->_selectionCommitting = NO;
            if (self->_interaction != interaction) {
                [self finishStage:@"cancelled" reason:@"user-interaction" feedback:NO]; return;
            }
            if (!written) {
                BOOL cancelled = failure && [@[@"command-disabled", @"committed-disabled", @"request-replaced"] containsObject:failure];
                NSString *stage = [failure isEqual:@"deadline-expired"] ? @"expired" : (cancelled ? @"cancelled" : @"failed");
                [self finishStage:stage reason:failure ?: @"selection-marker-commit-failed" feedback:!cancelled]; return;
            }
            if (!QSIPCRequestIsLive(request)) { [self finishStage:@"expired" reason:@"deadline-before-native-selection" feedback:YES]; return; }
            self->_dispatchCommitted = YES;
            if (signal != [self signal]) { [self readPendingState]; return; } // a duplicate hint is not cancellation
            [self tryNavigate];
        });
    });
}
- (void)tryNavigate {
    if (!_request || _selectionCommitting) return;
    NSDictionary *activeRequest = _request;
    if (_requestSignal != [self signal]) { [self readPendingState]; return; }
    if (!QSIPCRequestIsLive(_request)) { [self finishStage:@"expired" reason:_waitReason ?: @"deadline-expired" feedback:YES]; return; }
    if (!_enabled || !QSIPCSameRequest(_command[@"request"], _request) || _interaction != _requestInteraction) {
        [self finishStage:@"cancelled" reason:@"state-changed-before-native-selection" feedback:NO]; return;
    }
    UIViewController *owner = [self nativeOwner];
    UINavigationController *navigation = [self activeNavigationForOwner:owner];
    if (!navigation) return; // lifecycle/model callbacks and bounded polling retry readiness
    if (!QSIPCSameRequest(_request, activeRequest)) return;
    NSDictionary *published = _liveRecords[activeRequest[@"target"]];
    if (!published) { _waitReason = _captureQueued ? @"inventory-publication-pending" : @"target-absent-from-live-resolved-index"; return; }
    if (![published[@"revision"] isEqual:_request[@"revision"]]) {
        [self finishStage:@"failed" reason:@"native-record-replaced" feedback:YES]; return;
    }
    NSMutableDictionary *liveRows = [NSMutableDictionary dictionary];
    NSDictionary *scan = [self scanOwner:owner liveRows:liveRows];
    if (!QSIPCSameRequest(_request, activeRequest)) return;
    if (_requestSignal != [self signal]) { [self readPendingState]; return; }
    if (!QSIPCRequestIsLive(activeRequest)) { [self finishStage:@"expired" reason:@"deadline-during-row-resolution" feedback:YES]; return; }
    NSDictionary *current = scan[@"records"][activeRequest[@"target"]];
    id row = liveRows[activeRequest[@"target"]];
    if (!row || ![QSSemanticRecord(published) isEqual:QSSemanticRecord(current)]) {
        _waitReason = @"native-row-not-in-current-model";
        for (NSDictionary *diagnostic in scan[@"rows"]) if ([diagnostic[@"row"] isEqual:published[@"row"]]) {
            _waitReason = [diagnostic[@"availability"] isEqual:@"available"] ? @"native-record-identity-changed" : diagnostic[@"availability"]; break;
        }
        if (!_requestRefreshAttempted) { _requestRefreshAttempted = YES; [self scheduleCapture]; }
        return;
    }
    if ([self visibleControllerMatches:navigation row:row owner:owner]) {
        [self finishStage:@"visible-target" reason:@"visible-controller-origin-is-native-row" feedback:NO]; return;
    }
    if (_selectionInvoked) {
        id visible = navigation.visibleViewController;
        _waitReason = QSCanCall(visible, @selector(specifier), "@", "") && [(id<QSSettingsPage>)visible specifier]
            ? @"visible-controller-origin-mismatch" : @"visible-controller-origin-unavailable";
        return;
    }
    if (!_rowResolvedReported) {
        _rowResolvedReported = YES; [self postStage:@"row-resolved" reason:published[@"evidence"] request:_request];
    }
    if (!_dispatchCommitted) { [self commitSelectionBoundary]; return; }
    @try {
        if (_requestSignal != [self signal] || !QSIPCSameRequest(_request, activeRequest)) { [self readPendingState]; return; }
        if (navigation.topViewController != owner) {
            // Use the existing hierarchy. Never instantiate a root or detail,
            // dismiss a modal, replace a delegate, or push a second controller.
            [navigation popToViewController:owner animated:NO];
            _waitReason = @"waiting-for-existing-owner-visibility";
            [self readPendingState]; return; // re-resolve after the pop's lifecycle/model work
        }
        id tableValue = QSCanCall(owner, @selector(table), "@", "") ? [(id<QSSettingsList>)owner table] : nil;
        if (![tableValue isKindOfClass:UITableView.class]) { _waitReason = @"native-table-not-ready"; return; }
        UITableView *table = tableValue;
        if (!table.window || !owner.viewIfLoaded.window) { _waitReason = @"native-owner-not-visible"; return; }
        if (table.delegate != (id)owner || !table.allowsSelection || table.editing) {
            [self finishStage:@"failed" reason:@"native-table-selection-owner-unsupported" feedback:YES]; return;
        }
        if (table.dragging || table.decelerating) { [self finishStage:@"cancelled" reason:@"native-table-user-scrolling" feedback:NO]; return; }
        if (!QSCanCall(owner, @selector(indexPathForSpecifier:), "@", "@")
            || !QSCanCall(owner, @selector(specifierAtIndexPath:), "@", "@")
            || !QSCanCall(owner, @selector(tableView:didSelectRowAtIndexPath:), "v", "@@")) {
            [self finishStage:@"failed" reason:@"native-selection-abi-unsupported" feedback:YES]; return;
        }
        id pathValue = [(id<QSSettingsList>)owner indexPathForSpecifier:row];
        if (![pathValue isKindOfClass:NSIndexPath.class] || [pathValue length] != 2) {
            [self finishStage:@"failed" reason:@"native-index-path-unavailable" feedback:YES]; return;
        }
        NSIndexPath *path = pathValue;
        if (path.section < 0 || path.row < 0 || path.section >= table.numberOfSections || path.row >= [table numberOfRowsInSection:path.section]
            || [(id<QSSettingsList>)owner specifierAtIndexPath:path] != row) {
            [self finishStage:@"failed" reason:@"native-row-index-path-mismatch" feedback:YES]; return;
        }
        if (!QSCanCall(owner, @selector(tableView:willSelectRowAtIndexPath:), "@", "@@")) {
            [self finishStage:@"failed" reason:@"native-selection-permission-abi-unsupported" feedback:YES]; return;
        }
        id allowed = [(id<QSSettingsList>)owner tableView:table willSelectRowAtIndexPath:path];
        if (![allowed isKindOfClass:NSIndexPath.class] || ![allowed isEqual:path]) {
            [self finishStage:@"failed" reason:@"native-row-selection-disallowed" feedback:YES]; return;
        }
        if (!QSIPCRequestIsLive(_request) || _interaction != _requestInteraction || _requestSignal != [self signal]
            || [(id<QSSettingsList>)owner specifierAtIndexPath:path] != row) {
            [self finishStage:@"cancelled" reason:@"state-changed-at-native-handler-boundary" feedback:NO]; return;
        }
        _selectionInvoked = YES; _selectedRow = row;
        NSDictionary *request = _request;
        [(id<QSSettingsList>)owner tableView:table didSelectRowAtIndexPath:path];
        [self postStage:@"selection-invoked" reason:@"native-table-row-handler" request:request];
        id<UIViewControllerTransitionCoordinator> transition = navigation.transitionCoordinator;
        if (transition) [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) { [self readPendingState]; }];
        [self readPendingState]; // visibility is checked again; handler return is not success
    } @catch (NSException *exception) {
        [self finishStage:@"failed" reason:@"native-selection-exception" feedback:YES];
    }
}
- (void)userInteraction {
    NSCAssert(NSThread.isMainThread, @"Touch observation is main-thread only.");
    _interaction++;
    if (_request) [self finishStage:@"cancelled" reason:@"user-interaction" feedback:NO];
}
- (void)becameInactive {
    if (_request && _sawActiveScene) [self finishStage:@"cancelled" reason:@"settings-left-active-scene" feedback:NO];
    [self hint];
}
- (void)applicationModelChanged {
    dispatch_async(dispatch_get_main_queue(), ^{ [self scheduleCapture]; [self hint]; });
}
- (void)applicationsDidInstall:(NSArray *)apps { [self applicationModelChanged]; }
- (void)applicationsDidUninstall:(NSArray *)apps { [self applicationModelChanged]; }
- (void)applicationStateDidChange:(NSArray *)apps { [self applicationModelChanged]; }
- (void)start {
    NSCAssert(NSThread.isMainThread, @"Settings bridge starts on the main thread.");
    QSInstallSceneObserver(); // also observes bootstrap before PreferencesUI classes exist
    _supported = QSInstallNativeHooks();
    for (id name in @[(__bridge NSString *)QS_COMMAND_HINT, (__bridge NSString *)QS_RELOAD_NOTIFICATION, (__bridge NSString *)QS_REFRESH_HINT])
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, QSBridgeHint,
            (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSNotificationName name in @[UIApplicationDidFinishLaunchingNotification, UIApplicationDidBecomeActiveNotification,
        UIApplicationWillEnterForegroundNotification, UISceneDidActivateNotification, NSCurrentLocaleDidChangeNotification]) {
        id token = [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *notification) {
                if (!self->_supported) self->_supported = QSInstallNativeHooks();
                [self scheduleCapture]; [self hint];
            }];
        [tokens addObject:token];
    }
    [tokens addObject:[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) { [self becameInactive]; }]];
    _notificationTokens = [tokens copy];
    dispatch_async(_queue, ^{
        @try {
            Class<QSWorkspace> cls = (Class<QSWorkspace>)NSClassFromString(@"LSApplicationWorkspace");
            id<QSWorkspace> workspace = QSCanCall(cls, @selector(defaultWorkspace), "@", "") ? [cls defaultWorkspace] : nil;
            if (QSCanCall(workspace, @selector(addObserver:), "v", "@")) { [workspace addObserver:self]; self->_workspace = workspace; }
            else QSDiagnostic(@"settings-app-observer-unsupported", @"Native app-change observation is unavailable; foreground/model events still refresh.");
        } @catch (NSException *exception) { QSDiagnostic(@"settings-app-observer-exception", exception.name); }
    });
    NSLog(@"[QuickSettings] Settings bridge marker=%@ adapter=%@ osBuild=%@ environment=%@. Discovery requires the Settings model; continuous background coverage is unverified.",
        QSNavigationMarker, QSNativeAdapter, QSOSBuild(), QSInstalledEnvironment());
    [self scheduleCapture]; [self hint];
}
@end

// Runtime-guarded observation hooks. Private async completion blocks are passed
// through by Settings itself; we neither invent their signature nor wrap them.
static id (*QSOriginalRootList)(id, SEL);
static id QSRootList(id self, SEL cmd) {
    id list = QSOriginalRootList(self, cmd);
    [QSSettingsBridge.sharedBridge observeRoot:self];
    return list;
}
static id (*QSOriginalSpecifiers)(id, SEL);
static id QSSpecifiers(id self, SEL cmd) {
    id rows = QSOriginalSpecifiers(self, cmd); [QSSettingsBridge.sharedBridge modelChanged:self]; return rows;
}
static void (*QSOriginalThirdPartySetter)(id, SEL, id);
static void QSThirdPartySetter(id self, SEL cmd, id rows) {
    QSOriginalThirdPartySetter(self, cmd, rows); [QSSettingsBridge.sharedBridge modelChanged:self];
}
static void (*QSOriginalSetSpecifiers)(id, SEL, id);
static void QSSetSpecifiers(id self, SEL cmd, id rows) {
    QSOriginalSetSpecifiers(self, cmd, rows); [QSSettingsBridge.sharedBridge modelChanged:self];
}
static void (*QSOriginalInsertSpecifiers)(id, SEL, id, NSInteger, BOOL);
static void QSInsertSpecifiers(id self, SEL cmd, id rows, NSInteger index, BOOL animated) {
    QSOriginalInsertSpecifiers(self, cmd, rows, index, animated); [QSSettingsBridge.sharedBridge modelChanged:self];
}
static void (*QSOriginalAddSpecifiers)(id, SEL, id, BOOL);
static void QSAddSpecifiers(id self, SEL cmd, id rows, BOOL animated) {
    QSOriginalAddSpecifiers(self, cmd, rows, animated); [QSSettingsBridge.sharedBridge modelChanged:self];
}
static void (*QSOriginalMovedSpecifiers)(id, SEL, BOOL);
static void QSMovedSpecifiers(id self, SEL cmd, BOOL animated) {
    QSOriginalMovedSpecifiers(self, cmd, animated); [QSSettingsBridge.sharedBridge modelChanged:self];
}
static void (*QSOriginalReload)(id, SEL);
static void QSReload(id self, SEL cmd) { QSOriginalReload(self, cmd); [QSSettingsBridge.sharedBridge modelChanged:self]; }
static void (*QSOriginalAsyncFirst)(id, SEL);
static void QSAsyncFirst(id self, SEL cmd) { QSOriginalAsyncFirst(self, cmd); [QSSettingsBridge.sharedBridge modelChanged:self]; }
static void (*QSOriginalDisplayChanged)(id, SEL);
static void QSDisplayChanged(id self, SEL cmd) { QSOriginalDisplayChanged(self, cmd); [QSSettingsBridge.sharedBridge modelChanged:self]; }
static void (*QSOriginalLayout)(id, SEL);
static void QSLayout(id self, SEL cmd) { QSOriginalLayout(self, cmd); [QSSettingsBridge.sharedBridge modelChanged:self]; }
static void (*QSOriginalAppeared)(id, SEL, BOOL);
static void QSAppeared(id self, SEL cmd, BOOL animated) { QSOriginalAppeared(self, cmd, animated); [QSSettingsBridge.sharedBridge didAppear:self]; }
static void (*QSOriginalEvent)(id, SEL, UIEvent *);
static void QSEvent(id self, SEL cmd, UIEvent *event) {
    if (event.type == UIEventTypeTouches) for (UITouch *touch in event.allTouches) {
        if (touch.phase == UITouchPhaseBegan) { [QSSettingsBridge.sharedBridge userInteraction]; break; }
    }
    if (event.type == UIEventTypePresses && [event isKindOfClass:UIPressesEvent.class])
        for (UIPress *press in ((UIPressesEvent *)event).allPresses) {
            if (press.phase == UIPressPhaseBegan) { [QSSettingsBridge.sharedBridge userInteraction]; break; }
        }
    QSOriginalEvent(self, cmd, event);
}
static BOOL QSHook(Class cls, NSString *name, const char *result, const char *args, IMP hook, IMP *original) {
    SEL selector = NSSelectorFromString(name);
    if (!QSMethodSignature(class_getInstanceMethod(cls, selector), result, args)) {
        QSDiagnostic(@"native-observer-abi", [NSString stringWithFormat:@"Not observing incompatible %@.%@", NSStringFromClass(cls) ?: @"missing-class", name]); return NO;
    }
    MSHookMessageEx(cls, selector, hook, original); return YES;
}
static BOOL QSInstallSceneObserver(void) {
    static BOOL installed;
    if (!installed) installed = QSHook(UIViewController.class, @"viewDidAppear:", "v", "B", (IMP)QSAppeared, (IMP *)&QSOriginalAppeared);
    return installed;
}
static BOOL QSInstallNativeHooks(void) {
    static BOOL installed;
    if (installed) return YES;
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 16) {
        QSDiagnostic(@"native-os-unsupported", @"This instrumented adapter is scoped to iOS 16. Other Settings layouts require separate verification."); return NO;
    }
    Class root = NSClassFromString(@"PSUIPrefsRootController"), list = NSClassFromString(@"PSUIPrefsListController");
    Class base = NSClassFromString(@"PSListController"), page = NSClassFromString(@"PSViewController");
    if (!QSMethodSignature(class_getInstanceMethod(root, @selector(rootListController)), "@", "")
        || !QSMethodSignature(class_getInstanceMethod(list, @selector(specifiers)), "@", "")
        || !QSMethodSignature(class_getInstanceMethod(list, @selector(table)), "@", "")
        || !QSMethodSignature(class_getInstanceMethod(list, @selector(indexPathForSpecifier:)), "@", "@")
        || !QSMethodSignature(class_getInstanceMethod(list, @selector(specifierAtIndexPath:)), "@", "@")
        || !QSMethodSignature(class_getInstanceMethod(list, @selector(tableView:didSelectRowAtIndexPath:)), "v", "@@")
        || !QSMethodSignature(class_getInstanceMethod(list, @selector(tableView:willSelectRowAtIndexPath:)), "@", "@@")
        || !QSMethodSignature(class_getInstanceMethod(UIApplication.class, @selector(sendEvent:)), "v", "@") || !page || !base) {
        QSDiagnostic(@"native-core-abi", @"Settings classes are not ready or the native root/list/selection ABI is unsupported."); return NO;
    }
    QSHook(root, @"rootListController", "@", "", (IMP)QSRootList, (IMP *)&QSOriginalRootList);
    QSHook(list, @"specifiers", "@", "", (IMP)QSSpecifiers, (IMP *)&QSOriginalSpecifiers);
    QSHook(list, @"set_thirdPartySpecifiers:", "v", "@", (IMP)QSThirdPartySetter, (IMP *)&QSOriginalThirdPartySetter);
    QSHook(base, @"setSpecifiers:", "v", "@", (IMP)QSSetSpecifiers, (IMP *)&QSOriginalSetSpecifiers);
    QSHook(base, @"insertContiguousSpecifiers:atIndex:animated:", "v", "@qB", (IMP)QSInsertSpecifiers, (IMP *)&QSOriginalInsertSpecifiers);
    QSHook(base, @"addSpecifiersFromArray:animated:", "v", "@B", (IMP)QSAddSpecifiers, (IMP *)&QSOriginalAddSpecifiers);
    QSHook(list, @"insertMovedThirdPartySpecifiersAnimated:", "v", "B", (IMP)QSMovedSpecifiers, (IMP *)&QSOriginalMovedSpecifiers);
    QSHook(list, @"reloadSpecifiers", "v", "", (IMP)QSReload, (IMP *)&QSOriginalReload);
    QSHook(list, @"asyncSpecifiersFirstLoad", "v", "", (IMP)QSAsyncFirst, (IMP *)&QSOriginalAsyncFirst);
    QSHook(list, @"displayIdentifiersChanged", "v", "", (IMP)QSDisplayChanged, (IMP *)&QSOriginalDisplayChanged);
    QSHook(list, @"viewDidLayoutSubviews", "v", "", (IMP)QSLayout, (IMP *)&QSOriginalLayout);
    QSHook(UIApplication.class, @"sendEvent:", "v", "@", (IMP)QSEvent, (IMP *)&QSOriginalEvent);
    installed = YES; return YES;
}

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqual:QSSettingsBundleID]) return;
        dispatch_async(dispatch_get_main_queue(), ^{ [QSSettingsBridge.sharedBridge start]; });
    }
}
