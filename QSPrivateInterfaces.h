// Narrow shortcut/model declarations; every private call is ABI-guarded.
// Matching a signature does not establish runtime compatibility on every iOS.
#pragma once
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

@interface SBIconView : UIView
- (id)icon;
- (id)applicationShortcutItems;
- (id)applicationBundleIdentifierForShortcuts;
- (id)applicationBundleIdentifier;
+ (void)activateShortcut:(id)item withBundleIdentifier:(id)bundleID forIconView:(id)iconView;
@end

// Optional icon predicates supplement the required application-icon check.
@protocol QSHomeIcon <NSObject>
- (BOOL)isApplicationIcon;
- (BOOL)isFolderIcon;
- (BOOL)isBookmarkIcon;
@end

@protocol QSShortcutItem <NSObject>
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *localizedTitle;
@property (nonatomic, strong) id icon;
@property (nonatomic, copy) NSString *bundleIdentifierToLaunch;
@property (nonatomic, copy) NSDictionary *userInfo;
@end
@protocol QSShortcutSystemIcon <NSObject>
- (id)initWithSystemImageName:(NSString *)name;
@end

// Non-UI declarations inspected in iOS 15/16.5/17/18.2 headers, for example:
// https://raw.githubusercontent.com/donato-fiore/iOS-Runtime-Headers/031ec3a8b25d1751646143551d2ea630bbb04cf9/16.5/PrivateFrameworks/Preferences.framework/Headers/PSSystemPolicyManager.h
// The aggregate predicate's use for arbitrary apps is an engineering inference;
// signatures do not verify SpringBoard access or background-thread affinity.
@protocol QSSystemPolicy <NSObject>
+ (id)thirdPartyApplications;
+ (id)specifiersForThirdPartyApps:(id)applications;
+ (id)thirdPartyApplicationForBundleID:(NSString *)bundleID;
+ (BOOL)_systemSettingsNeededForProxy:(id)proxy;
@end
@protocol QSNativeApp <NSObject>
- (id)proxy;
@end
@protocol QSNativeSpecifier <NSObject>
- (id)identifier;
- (NSInteger)cellType;
@end
@protocol QSAppProxy <NSObject>
// https://raw.githubusercontent.com/donato-fiore/iOS-Runtime-Headers/031ec3a8b25d1751646143551d2ea630bbb04cf9/16.5/Frameworks/CoreServices.framework/Headers/LSApplicationProxy.h
// bundleURL is inherited from LSBundleProxy; app resources follow this URL.
+ (id)applicationProxyForIdentifier:(NSString *)identifier;
- (id)applicationIdentifier;
- (BOOL)isInstalled;
- (BOOL)isPlaceholder;
- (BOOL)isRestricted;
- (BOOL)hasSettingsBundle;
- (id)bundleURL;
@end
@protocol QSWorkspace <NSObject>
+ (id)defaultWorkspace;
- (void)addObserver:(id)observer;
- (id)allInstalledApplications;
@end

// expectedReturn is a set of accepted encodings; args describes explicit args.
// BOOL is B on the intended ABI; c is accepted for older Objective-C metadata.
static inline BOOL QSMethodSignature(Method method, const char *expectedReturn, const char *args) {
    if (!method || method_getNumberOfArguments(method) != strlen(args) + 2) return NO;
    char *type = method_copyReturnType(method);
    const char *base = type;
    while (base && *base && strchr("rnNoORV", *base)) base++;
    BOOL valid = base && *base && strchr(expectedReturn, *base);
    free(type);
    for (unsigned i = 0; valid && i < strlen(args); i++) {
        type = method_copyArgumentType(method, i + 2);
        base = type;
        while (base && *base && strchr("rnNoORV", *base)) base++;
        valid = base && (*base == args[i] || (args[i] == 'B' && *base == 'c'));
        free(type);
    }
    return valid;
}

static inline BOOL QSCanCall(id receiver, SEL selector, const char *returnType, const char *args) {
    return receiver && QSMethodSignature(class_getInstanceMethod(object_getClass(receiver), selector), returnType, args);
}
