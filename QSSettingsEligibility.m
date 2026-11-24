// QuickSettings — EolnMsuk. See LICENSE.
#import "QSSettingsEligibility.h"
#import "QSPrivateInterfaces.h"
#import "QSSettingsSupport.h"
#import <dlfcn.h>

static const NSTimeInterval QSEligibilityFreshness = 30.0;
static const NSTimeInterval QSEligibilityStaleAllowance = 300.0;
static const NSTimeInterval QSEligibilityRetryDelay = 5.0;
static const NSUInteger QSEligibilityAutomaticRetries = 2;
static const NSUInteger QSMaximumNativeEntries = 10000;
static const NSUInteger QSMaximumPlistBytes = 4 * 1024 * 1024;

typedef NS_ENUM(NSUInteger, QSNativeInstallState) {
    QSNativeInstallUnknown, QSNativeInstallAbsent, QSNativeInstallPresent
};
typedef NS_ENUM(NSUInteger, QSSettingsCheck) {
    QSSettingsCheckUnknown, QSSettingsCheckNo, QSSettingsCheckYes
};

@interface QSSettingsDestination ()
@property (nonatomic, readonly) NSTimeInterval validatedAt;
@property (nonatomic, readonly) NSUInteger generation;
- (instancetype)initWithBundleIdentifier:(NSString *)bundleID state:(QSSettingsEligibilityState)state
    URL:(NSURL *)URL evidence:(QSSettingsEvidence)evidence validatedAt:(NSTimeInterval)time
    generation:(NSUInteger)generation;
@end
@implementation QSSettingsDestination
- (instancetype)initWithBundleIdentifier:(NSString *)bundleID state:(QSSettingsEligibilityState)state
    URL:(NSURL *)URL evidence:(QSSettingsEvidence)evidence validatedAt:(NSTimeInterval)time
    generation:(NSUInteger)generation {
    if ((self = [super init])) {
        if (state == QSSettingsEligibilityEligible && !URL) state = QSSettingsEligibilityUnknown;
        _bundleIdentifier = [bundleID copy];
        _state = state;
        _URL = state == QSSettingsEligibilityEligible ? [URL copy] : nil;
        _evidence = state == QSSettingsEligibilityEligible ? evidence : QSSettingsEvidenceNone;
        _validatedAt = time;
        _generation = generation;
    }
    return self;
}
@end

@interface QSBuiltinPage : NSObject
@property (nonatomic, copy) NSString *root;
@property (nonatomic) NSOperatingSystemVersion minimumVersion;
@property (nonatomic) BOOL requiresManifest;
@end
@implementation QSBuiltinPage
@end
static QSBuiltinPage *QSPage(NSString *root, NSInteger major, NSInteger minor, BOOL requiresManifest) {
    QSBuiltinPage *page = [QSBuiltinPage new];
    page.root = root;
    page.minimumVersion = (NSOperatingSystemVersion){major, minor, 0};
    page.requiresManifest = requiresManifest;
    return page;
}

static NSDictionary<NSString *, QSBuiltinPage *> *QSBuiltinCatalog(void) {
    static NSDictionary *catalog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Exact app IDs: https://support.apple.com/en-lamr/guide/deployment/depece748c41/web
        // Empirical roots, not a private-API compatibility contract:
        // https://raw.githubusercontent.com/FifiTheBulldog/ios-settings-urls/d3b5c3b5bf98a65698a917d7137a1df23b048789/versions/16.2/en/prefs.md
        // Applying that export across iOS 15–17 needs device verification.
        catalog = @{
            @"com.apple.stocks": QSPage(@"STOCKS", 15, 0, NO),
            @"com.apple.VoiceMemos": QSPage(@"VOICE_MEMOS", 15, 0, NO),
            @"com.apple.mobilesafari": QSPage(@"SAFARI", 15, 0, NO),
            @"com.apple.mobilephone": QSPage(@"Phone", 15, 0, NO),
            @"com.apple.MobileSMS": QSPage(@"MESSAGES", 15, 0, NO),
            @"com.apple.facetime": QSPage(@"FACETIME", 15, 0, NO),
            @"com.apple.Maps": QSPage(@"MAPS", 15, 0, NO),
            @"com.apple.Music": QSPage(@"MUSIC", 15, 0, NO),
            @"com.apple.mobilenotes": QSPage(@"NOTES", 15, 0, NO),
            @"com.apple.reminders": QSPage(@"REMINDERS", 15, 0, NO),
            @"com.apple.compass": QSPage(@"COMPASS", 15, 0, NO),
            @"com.apple.mobileslideshow": QSPage(@"Photos", 15, 0, NO),
            @"com.apple.AppStore": QSPage(@"STORE", 15, 0, NO),
            @"com.apple.mobilemail": QSPage(@"MAIL", 15, 0, NO),
            @"com.apple.MobileAddressBook": QSPage(@"CONTACTS", 15, 0, NO),
            @"com.apple.mobilecal": QSPage(@"CALENDAR", 15, 0, NO),
            @"com.apple.camera": QSPage(@"CAMERA", 15, 0, NO),
            @"com.apple.Translate": QSPage(@"TRANSLATE", 15, 0, NO),
            @"com.apple.measure": QSPage(@"MEASURE", 15, 0, NO),
            @"com.apple.iBooks": QSPage(@"IBOOKS", 15, 0, NO),
            @"com.apple.Health": QSPage(@"HEALTH", 15, 0, NO),
            @"com.apple.Passbook": QSPage(@"PASSBOOK", 15, 0, NO),
            @"com.apple.shortcuts": QSPage(@"SHORTCUTS", 15, 0, NO),
            @"com.apple.podcasts": QSPage(@"PODCASTS", 15, 0, NO),
            @"com.apple.news": QSPage(@"NEWS", 15, 0, NO),
            @"com.apple.weather": QSPage(@"WEATHER", 15, 0, NO),
            @"com.apple.tv": QSPage(@"TVAPP", 15, 0, NO),
            // FREEFORM appears in a later export, not the inspected 16.2 export:
            // https://raw.githubusercontent.com/FifiTheBulldog/ios-settings-urls/d3b5c3b5bf98a65698a917d7137a1df23b048789/versions/18.7.1/en/prefs.md
            @"com.apple.freeform": QSPage(@"FREEFORM", 16, 2, YES),
            // HOMEKIT is only a candidate; never substitute Privacy/HomeKit.
            @"com.apple.Home": QSPage(@"HOMEKIT", 15, 0, YES)
        };
    });
    return catalog;
}

static QSBuiltinPage *QSAvailableBuiltin(NSString *bundleID) {
    QSBuiltinPage *page = QSBuiltinCatalog()[bundleID];
    return page && [NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:page.minimumVersion] ? page : nil;
}

static NSCharacterSet *QSComponentCharacters(void) {
    static NSCharacterSet *characters;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ characters = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"]; });
    return characters;
}
// A Settings root is not necessarily a bundle ID (STOCKS and Phone are valid).
static BOOL QSValidRoot(NSString *root) {
    return [root isKindOfClass:NSString.class] && root.length > 0 && root.length <= 512
        && [root rangeOfCharacterFromSet:QSComponentCharacters().invertedSet].location == NSNotFound;
}

static NSString *QSManifestRoot(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] > 2048) return nil;
    NSURL *URL = [NSURL URLWithString:value];
    if (!URL || ![@[@"prefs", @"app-prefs"] containsObject:URL.scheme.lowercaseString]
        || URL.host.length || URL.user.length || URL.password.length || URL.port) return nil;
    // Fragments/subpaths may corroborate a root but are never executable destinations.
    NSString *resource = [[URL.resourceSpecifier componentsSeparatedByString:@"#"] firstObject];
    NSArray<NSString *> *fields = [resource componentsSeparatedByString:@"&"];
    NSString *root = nil;
    NSMutableSet *keys = [NSMutableSet set];
    for (NSUInteger index = 0; index < fields.count; index++) {
        NSString *field = fields[index];
        NSRange equal = [field rangeOfString:@"="];
        if (equal.location == NSNotFound) {
            if (index != 0 || root) return nil;
            root = field.stringByRemovingPercentEncoding;
            continue;
        }
        NSString *key = [[field substringToIndex:equal.location] stringByRemovingPercentEncoding];
        NSString *component = [[field substringFromIndex:equal.location + 1] stringByRemovingPercentEncoding];
        if (!key.length || !component.length || [keys containsObject:key]) return nil;
        [keys addObject:key];
        if ([key isEqualToString:@"root"]) {
            if (root) return nil; // Includes encoded/duplicate/conflicting root fields.
            root = component;
        } else if (![key isEqualToString:@"path"]) return nil;
    }
    return QSValidRoot(root) ? root : nil; // Decoded exactly once; placeholders are rejected.
}

static id QSReadBoundedPlist(NSURL *URL, BOOL *missing) {
    if (missing) *missing = NO;
    if (![URL isKindOfClass:NSURL.class] || !URL.isFileURL) return nil;
    NSError *error = nil;
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:URL.path error:&error];
    if (!attributes) {
        if (missing) *missing = [error.domain isEqualToString:NSCocoaErrorDomain]
            && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError);
        return nil;
    }
    if (![attributes[NSFileType] isEqual:NSFileTypeRegular]
        || [attributes[NSFileSize] unsignedLongLongValue] > QSMaximumPlistBytes) return nil;
    NSData *data = [NSData dataWithContentsOfURL:URL options:NSDataReadingMappedIfSafe error:nil];
    if (!data || data.length > QSMaximumPlistBytes) return nil;
    return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil];
}

static NSSet<NSString *> *QSScanManifestRoots(BOOL *complete) {
    NSMutableSet<NSString *> *roots = [NSMutableSet set];
    __block BOOL reliable = YES;
    NSUInteger files = 0, itemsSeen = 0, visited = 0;
    // Apple system resources stay at system paths, independently of jailbreak relocation.
    // Manifest layout/locations: https://raw.githubusercontent.com/FifiTheBulldog/ios-settings-urls/d3b5c3b5bf98a65698a917d7137a1df23b048789/generate.py
    for (NSString *path in @[@"/System/Library/PreferenceBundles", @"/System/Library/PreferenceManifests",
                              @"/System/Library/PreferenceManifestsInternal"]) {
        NSURL *directory = [NSURL fileURLWithPath:path isDirectory:YES];
        NSError *directoryError = nil;
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:&directoryError];
        if (!attributes) {
            // Some OS builds omit a directory; an unreadable one is incomplete.
            BOOL missing = [directoryError.domain isEqualToString:NSCocoaErrorDomain]
                && (directoryError.code == NSFileReadNoSuchFileError || directoryError.code == NSFileNoSuchFileError);
            if (!missing) reliable = NO;
            continue;
        }
        if (![attributes[NSFileType] isEqual:NSFileTypeDirectory]) { reliable = NO; continue; }
        NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtURL:directory
            includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsSymbolicLinkKey]
            options:0 errorHandler:^BOOL(NSURL *URL, NSError *error) { reliable = NO; return YES; }];
        if (!enumerator) { reliable = NO; continue; }
        for (NSURL *URL in enumerator) {
            if (++visited > 20000) { reliable = NO; break; }
            NSNumber *isDirectory = nil, *symlink = nil;
            if (![URL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil]
                || ![URL getResourceValue:&symlink forKey:NSURLIsSymbolicLinkKey error:nil]) {
                reliable = NO;
                [enumerator skipDescendants];
                continue;
            }
            NSString *name = URL.lastPathComponent;
            if ([name rangeOfString:@"Bridge" options:NSCaseInsensitiveSearch].location != NSNotFound
                || [name rangeOfString:@"Nano" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [enumerator skipDescendants];
                continue;
            }
            if (symlink.boolValue) {
                reliable = NO; // Do not follow resources outside the bounded system tree.
                [enumerator skipDescendants];
                continue;
            }
            if (URL.pathComponents.count - directory.pathComponents.count > 6) {
                reliable = NO;
                [enumerator skipDescendants];
                continue;
            }
            if (isDirectory.boolValue || ![name hasPrefix:@"SettingsSearchManifest"] || ![name hasSuffix:@".plist"]) continue;
            if (++files > 2048) { reliable = NO; break; }
            id plist = QSReadBoundedPlist(URL, NULL);
            id items = [plist isKindOfClass:NSDictionary.class] ? plist[@"items"] : nil;
            if (![items isKindOfClass:NSArray.class]) { reliable = NO; continue; }
            if ([items count] > 50000 - itemsSeen) { reliable = NO; itemsSeen = 50001; break; }
            itemsSeen += [items count];
            for (id item in items) {
                if (![item isKindOfClass:NSDictionary.class]) { reliable = NO; continue; }
                id value = item[@"searchURL"];
                if (!value) continue;
                if (![value isKindOfClass:NSString.class]) { reliable = NO; continue; }
                NSString *root = QSManifestRoot(value);
                if (root) [roots addObject:root];
            }
        }
        if (visited > 20000 || files > 2048 || itemsSeen > 50000) { reliable = NO; break; }
    }
    // Unavailable, malformed, or empty scans never become a permanent empty inventory.
    *complete = reliable && files > 0 && roots.count > 0;
    if (!*complete) QSDiagnostic(@"manifest-incomplete", @"System Settings manifests unavailable or incomplete; retaining positives and using bounded recovery.");
    QSVerboseDiagnostic(@"manifest-snapshot", ([NSString stringWithFormat:@"files=%lu roots=%lu complete=%@",
        (unsigned long)files, (unsigned long)roots.count, *complete ? @"yes" : @"no"]));
    return [roots copy];
}

static QSNativeInstallState QSProxyState(id<QSAppProxy> proxy, NSString *bundleID) {
    if (!QSCanCall(proxy, @selector(applicationIdentifier), "@", "")
        || !QSCanCall(proxy, @selector(isInstalled), "Bc", "")) return QSNativeInstallUnknown;
    id actualID = [proxy applicationIdentifier];
    if (![actualID isKindOfClass:NSString.class] || ![actualID isEqualToString:bundleID]) return QSNativeInstallUnknown;
    if (![proxy isInstalled]) return QSNativeInstallAbsent;
    BOOL reliable = YES;
    if (!QSCanCall(proxy, @selector(isPlaceholder), "Bc", "")) reliable = NO;
    else if ([proxy isPlaceholder]) return QSNativeInstallAbsent;
    if (!QSCanCall(proxy, @selector(isRestricted), "Bc", "")) reliable = NO;
    else if ([proxy isRestricted]) return QSNativeInstallAbsent;
    // A proven absence/block wins even if another optional getter was unavailable.
    return reliable ? QSNativeInstallPresent : QSNativeInstallUnknown;
}

static id<QSAppProxy> QSProxyForIdentifier(NSString *bundleID) {
    Class<QSAppProxy> cls = (Class<QSAppProxy>)NSClassFromString(@"LSApplicationProxy");
    return QSCanCall(cls, @selector(applicationProxyForIdentifier:), "@", "@")
        ? [cls applicationProxyForIdentifier:bundleID] : nil;
}

static NSArray *QSContainerObjects(id native) {
    if ([native isKindOfClass:NSArray.class]) return [native count] <= QSMaximumNativeEntries ? native : nil;
    if ([native isKindOfClass:NSSet.class]) return [native count] <= QSMaximumNativeEntries ? [native allObjects] : nil;
    if ([native isKindOfClass:NSDictionary.class]) return [native count] <= QSMaximumNativeEntries ? [native allValues] : nil;
    return nil;
}

static Class<QSSystemPolicy> QSLoadSettingsModel(void) {
    static void *handle; // Serial discovery queue only; retry failed loads.
    if (!handle) handle = dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_LAZY | RTLD_LOCAL);
    if (!handle) QSDiagnostic(@"eligibility-framework", @"Preferences model could not be loaded; retaining independent evidence.");
    return (Class<QSSystemPolicy>)NSClassFromString(@"PSSystemPolicyManager");
}

@interface QSNativeInventory : NSObject
@property (nonatomic, copy) NSSet<NSString *> *candidates;
@property (nonatomic, copy) NSSet<NSString *> *links;
@property (nonatomic) BOOL complete;
@end
@implementation QSNativeInventory
@end

// Only non-UI models are queried; never instantiate Settings controllers in SpringBoard.
static QSNativeInventory *QSReadNativeInventory(void) {
    QSNativeInventory *inventory = [QSNativeInventory new];
    NSMutableDictionary<NSString *, NSNumber *> *installed = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *links = [NSMutableSet set], *seen = [NSMutableSet set], *malformed = [NSMutableSet set];
    BOOL reliable = NO;
    @try {
        Class<QSSystemPolicy> policy = QSLoadSettingsModel();
        Class appClass = NSClassFromString(@"PSThirdPartyApp"), specifierClass = NSClassFromString(@"PSSpecifier");
        if (!appClass || !specifierClass || !QSCanCall(policy, @selector(thirdPartyApplications), "@", "")
            || !QSCanCall(policy, @selector(specifiersForThirdPartyApps:), "@", "@")) {
            QSDiagnostic(@"eligibility-model-interface", @"Native app/link model unavailable or ABI-incompatible; using independent evidence and bounded recovery.");
        } else {
            id applications = [policy thirdPartyApplications];
            NSArray *apps = QSContainerObjects(applications);
            // Keep the original native container for its companion API.
            NSArray *specifiers = apps ? QSContainerObjects([policy specifiersForThirdPartyApps:applications]) : nil;
            if (!apps || !specifiers) {
                QSDiagnostic(@"eligibility-model-container", @"Unexpected or oversized native app/specifier container.");
            } else {
                reliable = apps.count > 0 && specifiers.count > 0;
                for (id<QSNativeApp> app in apps) {
                    if (![app isKindOfClass:appClass] || !QSCanCall(app, @selector(proxy), "@", "")) { reliable = NO; continue; }
                    id<QSAppProxy> proxy = [app proxy];
                    id value = QSCanCall(proxy, @selector(applicationIdentifier), "@", "") ? [proxy applicationIdentifier] : nil;
                    if (!QSValidBundleIdentifier(value)) { reliable = NO; continue; }
                    NSString *bundleID = [value copy];
                    if (installed[bundleID]) {
                        [malformed addObject:bundleID];
                        reliable = NO;
                        continue;
                    }
                    QSNativeInstallState state = QSProxyState(proxy, bundleID);
                    installed[bundleID] = @(state);
                    if (state == QSNativeInstallUnknown) reliable = NO;
                }
                for (id<QSNativeSpecifier> specifier in specifiers) {
                    if (![specifier isKindOfClass:specifierClass] || !QSCanCall(specifier, @selector(cellType), "q", "")
                        || !QSCanCall(specifier, @selector(identifier), "@", "")) { reliable = NO; continue; }
                    NSInteger cell = [specifier cellType];
                    if (cell == 0) continue; // PSGroupCell is not a destination.
                    id rootID = [specifier identifier];
                    if (!QSValidBundleIdentifier(rootID) || !installed[rootID]) { reliable = NO; continue; }
                    if (cell != 1 || [seen containsObject:rootID]) {
                        [malformed addObject:rootID];
                        reliable = NO;
                    } else if ([installed[rootID] unsignedIntegerValue] == QSNativeInstallPresent) {
                        [links addObject:[rootID copy]]; // Matching app and native PSLinkCell.
                    }
                    [seen addObject:[rootID copy]];
                }
            }
        }
    } @catch (NSException *exception) {
        reliable = NO;
        QSDiagnostic(@"eligibility-model-exception", exception.name);
    }
    [links minusSet:malformed];
    inventory.candidates = [NSSet setWithArray:installed.allKeys];
    inventory.links = links;
    inventory.complete = reliable && links.count > 0; // Group-only startup output is incomplete.
    if (!inventory.complete) QSDiagnostic(@"eligibility-model-incomplete", @"Native app/link inventory is incomplete; omissions remain unknown and independent evidence is retained.");
    QSVerboseDiagnostic(@"eligibility-snapshot", ([NSString stringWithFormat:@"apps=%lu links=%lu complete=%@; model thread affinity unverified",
        (unsigned long)installed.count, (unsigned long)links.count, inventory.complete ? @"yes" : @"no"]));
    return inventory;
}

static NSDictionary<NSString *, id<QSAppProxy>> *QSWorkspaceProxies(BOOL *complete) {
    NSMutableDictionary *proxies = [NSMutableDictionary dictionary];
    *complete = NO;
    @try {
        Class<QSWorkspace> cls = (Class<QSWorkspace>)NSClassFromString(@"LSApplicationWorkspace");
        id<QSWorkspace> workspace = QSCanCall(cls, @selector(defaultWorkspace), "@", "") ? [cls defaultWorkspace] : nil;
        id values = QSCanCall(workspace, @selector(allInstalledApplications), "@", "") ? [workspace allInstalledApplications] : nil;
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        if (![values isKindOfClass:NSArray.class] || [values count] > QSMaximumNativeEntries || !proxyClass) {
            QSDiagnostic(@"eligibility-workspace-interface", @"Installed-app candidates unavailable or incompatible; enumeration is not Settings evidence.");
        } else {
            BOOL reliable = [values count] > 0;
            NSMutableSet *seen = [NSMutableSet set];
            for (id<QSAppProxy> proxy in values) {
                if (![proxy isKindOfClass:proxyClass] || !QSCanCall(proxy, @selector(applicationIdentifier), "@", "")) { reliable = NO; continue; }
                id bundleID = [proxy applicationIdentifier];
                if (!QSValidBundleIdentifier(bundleID)) { reliable = NO; continue; }
                if ([seen containsObject:bundleID]) {
                    [proxies removeObjectForKey:bundleID]; // Independent lookup can still establish this target.
                    reliable = NO;
                } else proxies[[bundleID copy]] = proxy;
                [seen addObject:[bundleID copy]];
            }
            *complete = reliable;
        }
    } @catch (NSException *exception) { QSDiagnostic(@"eligibility-workspace-exception", exception.name); }
    return [proxies copy];
}

static QSSettingsCheck QSPerAppNativeLink(NSString *bundleID) {
    @try {
        Class<QSSystemPolicy> policy = QSLoadSettingsModel();
        if (!QSCanCall(policy, @selector(thirdPartyApplicationForBundleID:), "@", "@")
            || !QSCanCall(policy, @selector(specifiersForThirdPartyApps:), "@", "@")) {
            QSDiagnostic(@"eligibility-app-model-interface", @"Per-app native link lookup unavailable or ABI-incompatible.");
            return QSSettingsCheckUnknown;
        }
        id<QSNativeApp> app = [policy thirdPartyApplicationForBundleID:bundleID];
        if (!app) return QSSettingsCheckNo; // Only absence from this model, not a final eligibility veto.
        if (![app isKindOfClass:NSClassFromString(@"PSThirdPartyApp")]
            || !QSCanCall(app, @selector(proxy), "@", "")
            || QSProxyState([app proxy], bundleID) != QSNativeInstallPresent) return QSSettingsCheckUnknown;
        NSArray *specifiers = QSContainerObjects([policy specifiersForThirdPartyApps:@[app]]);
        if (!specifiers.count) return QSSettingsCheckUnknown;
        NSUInteger matches = 0;
        for (id<QSNativeSpecifier> specifier in specifiers) {
            if (![specifier isKindOfClass:NSClassFromString(@"PSSpecifier")]
                || !QSCanCall(specifier, @selector(cellType), "q", "")
                || !QSCanCall(specifier, @selector(identifier), "@", "")) return QSSettingsCheckUnknown;
            NSInteger cell = [specifier cellType];
            if (cell == 0) continue;
            id identifier = [specifier identifier];
            if (![identifier isKindOfClass:NSString.class] || ![identifier isEqualToString:bundleID] || cell != 1) return QSSettingsCheckUnknown;
            matches++;
        }
        return matches == 1 ? QSSettingsCheckYes : QSSettingsCheckUnknown;
    } @catch (NSException *exception) {
        QSDiagnostic(@"eligibility-app-model-exception", exception.name);
        return QSSettingsCheckUnknown;
    }
}

static QSSettingsCheck QSCustomBundleCheck(id<QSAppProxy> proxy) {
    @try {
        if (QSCanCall(proxy, @selector(hasSettingsBundle), "Bc", "")) {
            return [proxy hasSettingsBundle] ? QSSettingsCheckYes : QSSettingsCheckNo;
        }
        // Resource fallback uses this app's real bundle URL, never container scans.
        if (!QSCanCall(proxy, @selector(bundleURL), "@", "")) {
            QSDiagnostic(@"eligibility-custom-interface", @"Neither Settings-bundle metadata nor its resource fallback is available.");
            return QSSettingsCheckUnknown;
        }
        id bundleURL = [proxy bundleURL];
        if (![bundleURL isKindOfClass:NSURL.class] || ![bundleURL isFileURL]) return QSSettingsCheckUnknown;
        NSURL *root = [[bundleURL URLByAppendingPathComponent:@"Settings.bundle" isDirectory:YES]
            URLByAppendingPathComponent:@"Root.plist"];
        BOOL missing = NO;
        id plist = QSReadBoundedPlist(root, &missing);
        if (!plist) return missing ? QSSettingsCheckNo : QSSettingsCheckUnknown;
        id specifiers = [plist isKindOfClass:NSDictionary.class] ? plist[@"PreferenceSpecifiers"] : nil;
        if (![specifiers isKindOfClass:NSArray.class] || [specifiers count] > QSMaximumNativeEntries) return QSSettingsCheckUnknown;
        // Public Settings bundle schema, distinct from internal manifest 'items':
        // https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UserDefaults/Preferences/Preferences.html
        for (id specifier in specifiers) {
            if (![specifier isKindOfClass:NSDictionary.class]) continue;
            id type = specifier[@"Type"], key = specifier[@"Key"], file = specifier[@"File"];
            if ([type isEqual:@"PSChildPaneSpecifier"] && [file isKindOfClass:NSString.class]
                && [file length] > 0 && [file length] <= 512 && [file isEqual:[file lastPathComponent]]) return QSSettingsCheckYes;
            if ([@[@"PSToggleSwitchSpecifier", @"PSMultiValueSpecifier", @"PSTitleValueSpecifier",
                   @"PSTextFieldSpecifier", @"PSSliderSpecifier", @"PSRadioGroupSpecifier"] containsObject:type ?: NSNull.null]
                && [key isKindOfClass:NSString.class] && [key length] > 0 && [key length] <= 512) return QSSettingsCheckYes;
        }
        return QSSettingsCheckNo; // Empty, group-only, or unsupported declarations are not evidence.
    } @catch (NSException *exception) {
        QSDiagnostic(@"eligibility-custom-bundle-exception", exception.name);
        return QSSettingsCheckUnknown;
    }
}

static QSSettingsCheck QSSystemSettingsCheck(id<QSAppProxy> proxy) {
    @try {
        Class<QSSystemPolicy> policy = QSLoadSettingsModel();
        if (!QSCanCall(policy, @selector(_systemSettingsNeededForProxy:), "Bc", "@")) {
            QSDiagnostic(@"eligibility-system-interface", @"Native aggregate Settings predicate unavailable or ABI-incompatible; result remains unknown.");
            return QSSettingsCheckUnknown;
        }
        // Engineering inference from the inspected declarations; needs device verification.
        // Never a dependency or veto for an independently established native/custom page.
        return [policy _systemSettingsNeededForProxy:proxy] ? QSSettingsCheckYes : QSSettingsCheckNo;
    } @catch (NSException *exception) {
        QSDiagnostic(@"eligibility-system-exception", exception.name);
        return QSSettingsCheckUnknown;
    }
}

static BOOL QSManifestSupportsApp(NSString *bundleID, NSSet<NSString *> *roots) {
    QSBuiltinPage *page = QSAvailableBuiltin(bundleID);
    // Never map a localized title, file basename, or preference-bundle identifier.
    return [roots containsObject:bundleID] || (page && [roots containsObject:page.root]);
}

static QSSettingsDestination *QSResult(NSString *bundleID, QSSettingsEligibilityState state, NSURL *URL,
                                       QSSettingsEvidence evidence) {
    return [[QSSettingsDestination alloc] initWithBundleIdentifier:bundleID state:state URL:URL evidence:evidence
        validatedAt:state == QSSettingsEligibilityUnknown ? 0 : NSProcessInfo.processInfo.systemUptime generation:0];
}

static QSSettingsDestination *QSDiscoverApp(NSString *bundleID, id<QSAppProxy> candidate,
    QSNativeInventory *inventory, NSSet<NSString *> *roots, BOOL manifestsComplete) {
    @try {
        id<QSAppProxy> proxy = candidate ?: QSProxyForIdentifier(bundleID);
        QSNativeInstallState installed = QSProxyState(proxy, bundleID);
        if (installed != QSNativeInstallPresent) {
            if (installed == QSNativeInstallUnknown) QSDiagnostic(@"eligibility-install-unknown", @"Cannot reliably validate app identity, installation, placeholder, and restriction state.");
            return QSResult(bundleID, installed == QSNativeInstallAbsent ? QSSettingsEligibilityIneligible : QSSettingsEligibilityUnknown,
                nil, QSSettingsEvidenceNone);
        }
        NSInteger major = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
        if (major < 15) return QSResult(bundleID, QSSettingsEligibilityUnknown, nil, QSSettingsEvidenceNone);
        BOOL legacy = major < 18;
        QSBuiltinPage *page = QSAvailableBuiltin(bundleID);
        BOOL catalogRoot = legacy && page && (!page.requiresManifest || [roots containsObject:page.root]);
        QSSettingsEvidence evidence = catalogRoot ? QSSettingsEvidenceBuiltinCatalog : QSSettingsEvidenceNone;
        if (QSManifestSupportsApp(bundleID, roots)) evidence |= QSSettingsEvidenceManifest;
        QSSettingsCheck native = [inventory.links containsObject:bundleID] ? QSSettingsCheckYes :
            (inventory.complete && [inventory.candidates containsObject:bundleID] ? QSSettingsCheckNo : QSSettingsCheckUnknown);
        if (native == QSSettingsCheckYes) evidence |= QSSettingsEvidenceNativeLink;
        QSSettingsCheck custom = QSSettingsCheckUnknown, system = QSSettingsCheckUnknown;
        if (!evidence) {
            QSSettingsCheck perApp = QSPerAppNativeLink(bundleID);
            if (perApp != QSSettingsCheckUnknown) native = perApp;
            if (native == QSSettingsCheckYes) evidence |= QSSettingsEvidenceNativeLink;
            custom = QSCustomBundleCheck(proxy);
            if (custom == QSSettingsCheckYes) evidence |= QSSettingsEvidenceCustomBundle;
            if (!evidence) {
                system = QSSystemSettingsCheck(proxy);
                if (system == QSSettingsCheckYes) evidence |= QSSettingsEvidenceSystemPolicy;
            }
        }
        if (!evidence) {
            // Omissions, missing APIs, and partial scans are unknown, never a fabricated negative.
            BOOL negative = native == QSSettingsCheckNo && custom == QSSettingsCheckNo
                && system == QSSettingsCheckNo && manifestsComplete;
            return QSResult(bundleID, negative ? QSSettingsEligibilityIneligible : QSSettingsEligibilityUnknown,
                nil, QSSettingsEvidenceNone);
        }
        NSString *root = catalogRoot ? page.root : bundleID;
        if (legacy && [bundleID isEqualToString:@"com.apple.podcasts"]
            && ![roots containsObject:page.root] && [roots containsObject:bundleID]) root = bundleID;
        // iOS 15–17 generic roots and the existing 18+ branch remain separate.
        // The 18+ URL is retained, not a claim of compatibility on future releases.
        NSString *component = [(legacy ? root : bundleID) stringByAddingPercentEncodingWithAllowedCharacters:QSComponentCharacters()];
        NSURL *URL = component.length ? [NSURL URLWithString:[(legacy ? @"prefs:root=" : @"App-prefs:") stringByAppendingString:component]] : nil;
        if (!URL) {
            QSDiagnostic(@"route-invalid", @"Could not construct one component for an evidenced Settings destination.");
            return QSResult(bundleID, QSSettingsEligibilityUnknown, nil, QSSettingsEvidenceNone);
        }
        return QSResult(bundleID, QSSettingsEligibilityEligible, URL, evidence);
    } @catch (NSException *exception) {
        QSDiagnostic(@"eligibility-target-exception", exception.name);
        return QSResult(bundleID, QSSettingsEligibilityUnknown, nil, QSSettingsEvidenceNone);
    }
}

@interface QSTargetRecovery : NSObject
@property (nonatomic) NSUInteger attempts;
@property (nonatomic) NSTimeInterval cycleStarted;
@property (nonatomic) NSTimeInterval lastAttempt;
@property (nonatomic) BOOL pending;
@end
@implementation QSTargetRecovery
@end

@interface QSSettingsEligibility ()
- (void)requestRefreshAutomatically:(BOOL)automatic;
- (void)requestTarget:(NSString *)bundleID automatically:(BOOL)automatic;
- (void)requestManifestRefresh;
- (void)observeApplicationChanges;
- (void)applicationModelChanged;
- (BOOL)publishResults:(NSDictionary<NSString *, QSSettingsDestination *> *)results epoch:(NSUInteger)epoch;
@end

@implementation QSSettingsEligibility {
    dispatch_queue_t _discoveryQueue;
    NSDictionary<NSString *, QSSettingsDestination *> *_snapshot;
    NSMutableDictionary<NSString *, QSTargetRecovery *> *_targetRecoveries;
    BOOL _enabled;
    BOOL _refreshPending;
    BOOL _refreshAgain;
    BOOL _hasFullCycle;
    NSTimeInterval _fullCycleStarted;
    NSTimeInterval _lastFullAttempt;
    NSUInteger _automaticRetries;
    NSUInteger _invalidationEpoch;
    NSUInteger _pendingEpoch;
    NSUInteger _nextDestinationGeneration;
    NSUInteger _preferenceGeneration;
    id<QSWorkspace> _observedWorkspace;
    // OS resources are cached separately, only on the serial discovery queue.
    NSSet<NSString *> *_manifestRoots;
    BOOL _manifestsComplete;
    BOOL _manifestPending;
    NSUInteger _manifestAttempts;
    NSTimeInterval _lastManifestAttempt;
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
        _targetRecoveries = [NSMutableDictionary dictionary];
        _manifestRoots = [NSSet set];
        _discoveryQueue = dispatch_queue_create("com.eolnmsuk.quicksettings.eligibility", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

// Caller holds the memory monitor. No native work, filesystem access, or IPC.
- (void)retireSnapshot {
    _invalidationEpoch++;
    _snapshot = @{};
    [_targetRecoveries removeAllObjects];
    _hasFullCycle = NO;
    _automaticRetries = QSEligibilityAutomaticRetries;
    _refreshAgain = _enabled && _refreshPending;
}

- (void)setEnabled:(BOOL)enabled preferenceGeneration:(NSUInteger)generation {
    @synchronized (self) {
        if (generation < _preferenceGeneration || (generation == _preferenceGeneration && enabled == _enabled)) return;
        _preferenceGeneration = generation;
        _enabled = enabled;
        [self retireSnapshot];
    }
    if (enabled) [self requestRefreshAutomatically:NO];
}

- (QSSettingsDestination *)destinationForBundleIdentifier:(NSString *)bundleID generation:(NSUInteger *)generation {
    QSSettingsDestination *destination = nil;
    BOOL refresh = NO, target = NO;
    @synchronized (self) {
        if (_enabled && QSValidBundleIdentifier(bundleID)) {
            NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
            QSSettingsDestination *record = _snapshot[bundleID];
            NSTimeInterval age = record ? now - record.validatedAt : QSEligibilityStaleAllowance;
            refresh = !_hasFullCycle || now - _fullCycleStarted >= QSEligibilityFreshness;
            target = !record || record.state == QSSettingsEligibilityUnknown || age >= QSEligibilityStaleAllowance;
            if (record.state == QSSettingsEligibilityEligible && record.URL && age < QSEligibilityStaleAllowance) {
                destination = record;
                refresh |= age >= QSEligibilityFreshness;
            } else if (record && age < QSEligibilityFreshness) destination = record;
        }
        if (generation) *generation = destination ? destination.generation : 0;
    }
    // These only enqueue work; the hook performs no filesystem or LaunchServices calls.
    if (refresh) [self requestRefreshAutomatically:NO];
    if (target) [self requestTarget:[bundleID copy] automatically:NO];
    return destination;
}

- (BOOL)isCurrentDestination:(QSSettingsDestination *)destination generation:(NSUInteger)generation {
    if (destination.state != QSSettingsEligibilityEligible || !destination.URL) return NO;
    NSUInteger currentGeneration = 0;
    QSSettingsDestination *current = [self destinationForBundleIdentifier:destination.bundleIdentifier generation:&currentGeneration];
    return current.state == QSSettingsEligibilityEligible && currentGeneration == generation
        && [current.URL isEqual:destination.URL];
}

- (BOOL)validateDestinationForOpening:(QSSettingsDestination *)destination generation:(NSUInteger)generation {
    if (![self isCurrentDestination:destination generation:generation]) return NO;
    QSSettingsDestination *current;
    @synchronized (self) { current = _snapshot[destination.bundleIdentifier]; }
    if (NSProcessInfo.processInfo.systemUptime - current.validatedAt < QSEligibilityFreshness) {
        return [self isCurrentDestination:destination generation:generation];
    }
    __block QSNativeInstallState installed = QSNativeInstallUnknown;
    // Only the resolver's worker calls this method. Never hold either memory
    // monitor while waiting for the discovery queue or making LaunchServices IPC.
    dispatch_sync(_discoveryQueue, ^{
        @autoreleasepool {
            @try { installed = QSProxyState(QSProxyForIdentifier(destination.bundleIdentifier), destination.bundleIdentifier); }
            @catch (NSException *exception) { QSDiagnostic(@"eligibility-recheck-exception", exception.name); }
        }
    });
    if (installed == QSNativeInstallAbsent) [self applicationModelChanged];
    if (installed == QSNativeInstallUnknown) [self requestTarget:destination.bundleIdentifier automatically:NO];
    if (installed != QSNativeInstallPresent) {
        QSDiagnostic(@"stale-target-cancelled", @"Stale destination failed installation/restriction revalidation; this tap was cancelled.");
        return NO;
    }
    // An installation-only recheck must not extend the age of Settings evidence.
    return [self isCurrentDestination:destination generation:generation];
}

- (BOOL)publishResults:(NSDictionary<NSString *, QSSettingsDestination *> *)results epoch:(NSUInteger)epoch {
    @synchronized (self) {
        if (!_enabled || epoch != _invalidationEpoch) return NO;
        NSMutableDictionary *snapshot = [_snapshot mutableCopy];
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        for (NSString *bundleID in results) {
            QSSettingsDestination *result = results[bundleID], *previous = snapshot[bundleID];
            if (!previous && snapshot.count >= QSMaximumNativeEntries) continue;
            BOOL previousLive = previous && now - previous.validatedAt < QSEligibilityStaleAllowance;
            if (result.state == QSSettingsEligibilityUnknown && previous.state == QSSettingsEligibilityEligible && previousLive) {
                continue; // Transient failure retains the last positive without refreshing its timestamp.
            }
            BOOL same = previous && previous.state == result.state
                && (previous.URL == result.URL || [previous.URL isEqual:result.URL]);
            NSUInteger generation = same && (previous.state != QSSettingsEligibilityEligible || previousLive)
                ? previous.generation : ++_nextDestinationGeneration;
            snapshot[bundleID] = [[QSSettingsDestination alloc] initWithBundleIdentifier:bundleID state:result.state
                URL:result.URL evidence:result.evidence validatedAt:result.validatedAt generation:generation];
        }
        _snapshot = [snapshot copy]; // One immutable publication, including URLs and generations.
        return YES;
    }
}

- (void)requestRefreshAutomatically:(BOOL)automatic {
    NSUInteger epoch;
    NSTimeInterval delay;
    @synchronized (self) {
        if (!_enabled) return;
        if (_refreshPending) {
            if (_pendingEpoch != _invalidationEpoch) _refreshAgain = YES;
            return;
        }
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (automatic) {
            if (!_automaticRetries) return;
            _automaticRetries--;
        } else {
            if (_hasFullCycle && now - _fullCycleStarted < QSEligibilityFreshness) return;
            _fullCycleStarted = now;
            _hasFullCycle = YES;
            _automaticRetries = QSEligibilityAutomaticRetries;
        }
        _refreshPending = YES;
        _pendingEpoch = epoch = _invalidationEpoch; // Capture before enqueueing.
        delay = _lastFullAttempt > 0 ? MAX(0, _lastFullAttempt + QSEligibilityRetryDelay - now) : 0;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _discoveryQueue, ^{
        @autoreleasepool {
            NSArray<NSString *> *knownIDs = nil;
            @synchronized (self) {
                if (self->_enabled && epoch == self->_invalidationEpoch) {
                    knownIDs = self->_snapshot.allKeys;
                    self->_lastFullAttempt = NSProcessInfo.processInfo.systemUptime;
                }
            }
            BOOL complete = NO;
            if (knownIDs) {
                [self observeApplicationChanges];
                QSNativeInventory *inventory = QSReadNativeInventory();
                BOOL workspaceComplete = NO;
                NSDictionary *proxies = QSWorkspaceProxies(&workspaceComplete);
                NSMutableSet<NSString *> *candidates = [NSMutableSet set];
                complete = inventory.complete && workspaceComplete;
                for (NSArray *source in @[QSBuiltinCatalog().allKeys, knownIDs, inventory.candidates.allObjects, proxies.allKeys]) {
                    for (NSString *bundleID in source) {
                        if (candidates.count >= QSMaximumNativeEntries && ![candidates containsObject:bundleID]) { complete = NO; continue; }
                        [candidates addObject:bundleID];
                    }
                }
                NSMutableDictionary *results = [NSMutableDictionary dictionary];
                for (NSString *bundleID in candidates) {
                    QSSettingsDestination *result = QSDiscoverApp(bundleID, proxies[bundleID], inventory,
                        self->_manifestRoots, self->_manifestsComplete);
                    results[bundleID] = result;
                    if (result.state == QSSettingsEligibilityUnknown) complete = NO;
                }
                // Establish native/catalog/custom destinations before optional manifest work.
                [self publishResults:results epoch:epoch];
            }
            BOOL again, retry;
            @synchronized (self) {
                self->_refreshPending = NO;
                again = self->_enabled && (self->_refreshAgain || epoch != self->_invalidationEpoch);
                retry = self->_enabled && !complete && !again;
                self->_refreshAgain = NO;
            }
            if (knownIDs) [self requestManifestRefresh];
            if (again) [self requestRefreshAutomatically:NO];
            else if (retry) [self requestRefreshAutomatically:YES];
        }
    });
}

- (void)requestTarget:(NSString *)bundleID automatically:(BOOL)automatic {
    if (!QSValidBundleIdentifier(bundleID)) return;
    NSUInteger epoch;
    NSTimeInterval delay;
    QSTargetRecovery *recovery;
    @synchronized (self) {
        if (!_enabled) return;
        recovery = _targetRecoveries[bundleID];
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (!recovery) {
            if (_targetRecoveries.count >= QSMaximumNativeEntries) return;
            recovery = [QSTargetRecovery new];
            recovery.cycleStarted = now;
            _targetRecoveries[bundleID] = recovery;
        }
        if (recovery.pending) return;
        if (!automatic && now - recovery.cycleStarted >= QSEligibilityFreshness) {
            recovery.cycleStarted = now;
            recovery.attempts = 0;
        }
        if (recovery.attempts >= 1 + QSEligibilityAutomaticRetries) return;
        recovery.attempts++;
        recovery.pending = YES;
        epoch = _invalidationEpoch;
        delay = recovery.lastAttempt > 0 ? MAX(0, recovery.lastAttempt + QSEligibilityRetryDelay - now) : 0;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _discoveryQueue, ^{
        @autoreleasepool {
            BOOL current;
            @synchronized (self) {
                current = self->_enabled && epoch == self->_invalidationEpoch && self->_targetRecoveries[bundleID] == recovery;
                if (current) recovery.lastAttempt = NSProcessInfo.processInfo.systemUptime;
            }
            QSSettingsDestination *result = nil;
            if (current) {
                [self observeApplicationChanges];
                result = QSDiscoverApp(bundleID, nil, nil, self->_manifestRoots, self->_manifestsComplete);
                [self publishResults:@{bundleID: result} epoch:epoch];
                [self requestManifestRefresh];
            }
            BOOL retry;
            @synchronized (self) {
                recovery.pending = NO;
                retry = self->_enabled && epoch == self->_invalidationEpoch
                    && result.state == QSSettingsEligibilityUnknown && recovery.attempts < 1 + QSEligibilityAutomaticRetries;
            }
            if (retry) [self requestTarget:bundleID automatically:YES];
        }
    });
}

// Discovery queue only. Process/OS-build cache survives ordinary app-state refreshes.
- (void)requestManifestRefresh {
    if (_manifestsComplete || _manifestPending || _manifestAttempts >= 1 + QSEligibilityAutomaticRetries) return;
    _manifestPending = YES;
    NSTimeInterval delay = _lastManifestAttempt > 0
        ? MAX(0, _lastManifestAttempt + QSEligibilityRetryDelay - NSProcessInfo.processInfo.systemUptime) : 0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _discoveryQueue, ^{
        @autoreleasepool {
            BOOL enabled;
            @synchronized (self) { enabled = self->_enabled; }
            self->_manifestPending = NO;
            if (!enabled) return;
            self->_manifestAttempts++;
            self->_lastManifestAttempt = NSProcessInfo.processInfo.systemUptime;
            BOOL complete = NO;
            NSSet *roots = nil;
            @try { roots = QSScanManifestRoots(&complete); }
            @catch (NSException *exception) { QSDiagnostic(@"manifest-exception", exception.name); }
            NSMutableSet *merged = [self->_manifestRoots mutableCopy];
            if (roots) [merged unionSet:roots];
            self->_manifestRoots = [merged copy];
            self->_manifestsComplete = complete;
            NSUInteger epoch;
            NSMutableSet<NSString *> *candidates;
            @synchronized (self) {
                epoch = self->_invalidationEpoch;
                candidates = [NSMutableSet setWithArray:self->_snapshot.allKeys];
            }
            [candidates addObjectsFromArray:QSBuiltinCatalog().allKeys];
            for (NSString *root in self->_manifestRoots) {
                if (candidates.count < QSMaximumNativeEntries && QSValidBundleIdentifier(root)) [candidates addObject:root];
            }
            NSMutableDictionary *results = [NSMutableDictionary dictionary];
            for (NSString *bundleID in candidates) {
                if (QSManifestSupportsApp(bundleID, self->_manifestRoots)) {
                    results[bundleID] = QSDiscoverApp(bundleID, nil, nil, self->_manifestRoots, self->_manifestsComplete);
                }
            }
            [self publishResults:results epoch:epoch];
            if (!complete) [self requestManifestRefresh]; // At most two retries, at five-second spacing.
        }
    });
}

- (void)observeApplicationChanges {
    if (_observedWorkspace) return;
    @try {
        Class<QSWorkspace> cls = (Class<QSWorkspace>)NSClassFromString(@"LSApplicationWorkspace");
        id<QSWorkspace> workspace = QSCanCall(cls, @selector(defaultWorkspace), "@", "") ? [cls defaultWorkspace] : nil;
        if (QSCanCall(workspace, @selector(addObserver:), "v", "@")) {
            [workspace addObserver:self];
            _observedWorkspace = workspace;
        } else QSDiagnostic(@"eligibility-observer", @"App observer unavailable; using bounded demand-driven recovery and stale-open rechecks.");
    } @catch (NSException *exception) { QSDiagnostic(@"eligibility-observer-exception", exception.name); }
}

- (void)applicationModelChanged {
    @synchronized (self) { [self retireSnapshot]; }
    [self requestRefreshAutomatically:NO];
}
// Callback payloads are not assumed to have a stable per-app schema. Conservatively
// retire all app records immediately; the independent system-manifest cache survives.
- (void)applicationsDidInstall:(NSArray *)apps { [self applicationModelChanged]; }
- (void)applicationsDidUninstall:(NSArray *)apps { [self applicationModelChanged]; }
- (void)applicationStateDidChange:(NSArray *)apps { [self applicationModelChanged]; }
@end
