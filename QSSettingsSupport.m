// QuickSettings — EolnMsuk. See LICENSE.
#import "QSSettingsSupport.h"
#import "QSSettingsIPC.h"
#import <UIKit/UIKit.h>

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

void QSNavigationTrace(NSDictionary *request, NSString *stage, NSString *reason) {
#if QS_VERBOSE_DIAGNOSTICS
    static NSMutableDictionary<NSString *, NSNumber *> *counts;
    static NSTimeInterval window;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ counts = [NSMutableDictionary dictionary]; });
    @synchronized (counts) {
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (now - window >= 60) { [counts removeAllObjects]; window = now; }
        NSString *identifier = request[@"request"];
        if (!identifier || (!counts[identifier] && counts.count >= 24) || [counts[identifier] unsignedIntegerValue] >= 16) return;
        counts[identifier] = @([counts[identifier] unsignedIntegerValue] + 1);
        NSLog(@"[QuickSettings] marker=%@ session=%@ request=%@ target=%@ revision=%@ generation=%@ stage=%@ reason=%@ elapsed=%.1fms",
            request[@"marker"], request[@"session"], identifier, request[@"target"], request[@"revision"],
            request[@"preferenceGeneration"], stage, reason, (QSIPCUptime() - [request[@"created"] doubleValue]) * 1000);
    }
#endif
}

void QSNavigationFailureFeedback(void) {
    NSCAssert(NSThread.isMainThread, @"Navigation feedback must run on the main thread.");
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) [windows addObject:window];
    }
    if (windows.count != 1) return;
    UIViewController *presenter = windows.firstObject.rootViewController;
    for (NSUInteger depth = 0; presenter && depth < 16; depth++) {
        if (presenter.presentedViewController) return;
        UIViewController *next = [presenter isKindOfClass:UINavigationController.class]
            ? ((UINavigationController *)presenter).visibleViewController :
            ([presenter isKindOfClass:UITabBarController.class] ? ((UITabBarController *)presenter).selectedViewController : nil);
        if (!next || next == presenter) break;
        presenter = next;
    }
    if (!presenter.viewIfLoaded.window || presenter.transitionCoordinator || presenter.isBeingDismissed) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"App Settings Unavailable"
        message:@"QuickSettings could not confirm this app’s Settings page. Let Settings finish loading, then try the app’s menu again."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
