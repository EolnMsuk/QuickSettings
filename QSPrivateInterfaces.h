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

// Recovered pre-1.0.1 declarations; provenance and runtime limits: plan.md.
// These are non-controller model calls. Thread affinity is not device-verified.
@protocol QSSystemPolicy <NSObject>
+ (id)thirdPartyApplications;
+ (id)specifiersForThirdPartyApps:(id)applications;
@end
@protocol QSNativeApp <NSObject>
- (id)proxy;
@end
@protocol QSNativeSpecifier <NSObject>
- (id)identifier;
- (long long)cellType;
@end
@protocol QSAppProxy <NSObject>
+ (id)applicationProxyForIdentifier:(NSString *)identifier;
- (id)applicationIdentifier;
- (BOOL)isInstalled;
- (BOOL)isPlaceholder;
- (BOOL)isRestricted;
@end
@protocol QSWorkspace <NSObject>
+ (id)defaultWorkspace;
- (void)addObserver:(id)observer;
@end
@protocol QSDetailProvider <NSObject>
+ (id)preferencesURL;
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
