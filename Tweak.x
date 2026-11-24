// QuickSettings — EolnMsuk. See LICENSE. Private hook signatures are checked below.
#import "QSConstants.h"
#import "QSPrivateInterfaces.h"
#import "QSPaneResolver.h"

static BOOL QSIsOurItem(id item) {
    return QSCanCall(item, @selector(type), "@", "")
        && [[(id<QSShortcutItem>)item type] isEqual:QSShortcutType];
}

static NSString *QSBundleIDForIcon(id iconView) {
    if (!QSCanCall(iconView, @selector(icon), "@", "")) {
        QSDiagnostic(@"icon-interface", @"SBIconView has no compatible icon getter.");
        return nil;
    }
    id<QSHomeIcon> icon = [(SBIconView *)iconView icon];
    if (!QSCanCall(icon, @selector(isApplicationIcon), "Bc", "")) {
        QSDiagnostic(@"icon-kind-interface", @"The icon has no compatible application-icon predicate.");
        return nil;
    }
    if (![icon isApplicationIcon]) return nil;
    for (NSString *name in @[@"isFolderIcon", @"isBookmarkIcon"]) {
        SEL selector = NSSelectorFromString(name);
        if (![icon respondsToSelector:selector]) continue;
        if (!QSCanCall(icon, selector, "Bc", "")) return nil;
        if ([name isEqualToString:@"isFolderIcon"] ? [icon isFolderIcon] : [icon isBookmarkIcon]) return nil;
    }
    id value = nil;
    if (QSCanCall(iconView, @selector(applicationBundleIdentifierForShortcuts), "@", "")) {
        value = [(SBIconView *)iconView applicationBundleIdentifierForShortcuts];
    }
    if (!QSValidBundleIdentifier(value)
        && QSCanCall(iconView, @selector(applicationBundleIdentifier), "@", "")) {
        value = [(SBIconView *)iconView applicationBundleIdentifier];
    }
    return QSValidBundleIdentifier(value) ? [value copy] : nil;
}

static BOOL QSShortcutClassReady(Class cls) {
    if (!cls || !QSMethodSignature(class_getInstanceMethod(cls, @selector(init)), "@", "")) return NO;
    for (NSString *name in @[@"setType:", @"setLocalizedTitle:", @"setUserInfo:", @"setBundleIdentifierToLaunch:"]) {
        if (!QSMethodSignature(class_getInstanceMethod(cls, NSSelectorFromString(name)), "v", "@")) return NO;
    }
    return QSMethodSignature(class_getInstanceMethod(cls, @selector(type)), "@", "")
        && QSMethodSignature(class_getInstanceMethod(cls, @selector(userInfo)), "@", "");
}

%group QSHomeScreen
%hook SBIconView
- (id)applicationShortcutItems {
    id original = %orig;
    if (original && ![original isKindOfClass:NSArray.class]) {
        QSDiagnostic(@"shortcut-list-type", @"Stock getter did not return an array.");
        return original;
    }
    NSMutableArray *items = original ? [original mutableCopy] : [NSMutableArray array];
    // Remove only our own type, preserving every other item and its order.
    NSIndexSet *duplicates = [items indexesOfObjectsPassingTest:^BOOL(id item, NSUInteger index, BOOL *stop) {
        return QSIsOurItem(item);
    }];
    [items removeObjectsAtIndexes:duplicates];
    if (!QSPaneResolver.sharedResolver.isEnabled) return duplicates.count ? [items copy] : original;
    NSString *bundleID = QSBundleIDForIcon(self);
    if (!bundleID) {
        return duplicates.count ? [items copy] : original;
    }
    Class itemClass = NSClassFromString(@"SBSApplicationShortcutItem");
    if (!QSShortcutClassReady(itemClass)) {
        QSDiagnostic(@"shortcut-item-interface", @"Shortcut payload class/selectors are unavailable or ABI-incompatible.");
        return duplicates.count ? [items copy] : original;
    }
    id<QSShortcutItem> item = [[itemClass alloc] init];
    if (!item) return duplicates.count ? [items copy] : original;
    item.type = QSShortcutType;
    item.localizedTitle = @"App Settings";
    item.bundleIdentifierToLaunch = QSSettingsBundleID;
    item.userInfo = @{QSTargetBundleKey: bundleID};
    Class iconClass = NSClassFromString(@"SBSApplicationShortcutSystemIcon");
    if (QSCanCall(item, @selector(setIcon:), "v", "@")
        && QSMethodSignature(class_getInstanceMethod(iconClass, @selector(initWithSystemImageName:)), "@", "@")) {
        item.icon = [(id<QSShortcutSystemIcon>)[iconClass alloc] initWithSystemImageName:@"gearshape"];
    }
    [items insertObject:item atIndex:0];
    return [items copy];
}

+ (void)activateShortcut:(id)item withBundleIdentifier:(id)bundleID forIconView:(id)iconView {
    if (!QSIsOurItem(item)) { %orig; return; }
    // Always consume our action, including disabled or stale-menu failures.
    if (!QSPaneResolver.sharedResolver.isEnabled) return;
    id payload = QSCanCall(item, @selector(userInfo), "@", "") ? [(id<QSShortcutItem>)item userInfo] : nil;
    id target = [payload isKindOfClass:NSDictionary.class] ? payload[QSTargetBundleKey] : nil;
    if (!QSValidBundleIdentifier(target)) {
        QSDiagnostic(@"shortcut-target", @"QuickSettings action has no valid namespaced target.");
        return;
    }
    // bundleID can now be com.apple.Preferences. Only userInfo retains the target.
    [QSPaneResolver.sharedResolver openSettingsForBundleIdentifier:target];
}
%end
%end

static void QSReloadPreferences(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [QSPaneResolver.sharedResolver reloadPreferences];
}

%ctor {
    @autoreleasepool {
        Class cls = NSClassFromString(@"SBIconView");
        BOOL compatible = QSMethodSignature(class_getInstanceMethod(cls, @selector(applicationShortcutItems)), "@", "")
            && QSMethodSignature(class_getClassMethod(cls, @selector(activateShortcut:withBundleIdentifier:forIconView:)), "v", "@@@");
        if (!compatible) {
            QSDiagnostic(@"hook-interface", @"SBIconView getter/void class activation ABI unsupported; hooks were not installed.");
            return;
        }
        %init(QSHomeScreen);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            QSReloadPreferences, QS_RELOAD_NOTIFICATION, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        NSLog(@"[QuickSettings] Installed dormant hooks (%@).", QSInstalledEnvironment());
        // The callback only queues a committed read; no CFPreferences IPC here.
        QSReloadPreferences(NULL, NULL, NULL, NULL, NULL);
    }
}
