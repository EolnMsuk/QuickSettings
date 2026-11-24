// Adapted from HaptiX by EolnMsuk; GPL-3.0, see ../LICENSE.
// Adapted from ChoySee. See Resources/ChoySee-LICENSE.txt.
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#pragma once

static inline BOOL QSCanPresent(UIViewController *controller) {
    UIWindow *window = controller.viewIfLoaded.window;
    UINavigationController *navigation = controller.navigationController;
    if (!window || window.hidden || controller.presentedViewController
        || controller.isBeingDismissed || controller.isMovingFromParentViewController
        || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return NO;
    if (navigation && (navigation.topViewController != controller
        || navigation.presentedViewController || navigation.isBeingDismissed)) return NO;
    UIWindowScene *scene = window.windowScene;
    return !scene || scene.activationState == UISceneActivationStateForegroundActive;
}

static inline void QSShowMessage(UIViewController *controller, NSString *title, NSString *message) {
    if (!QSCanPresent(controller)) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

static inline void QSAfterAlertDismissal(UIAlertController *alert, dispatch_block_t action) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (alert.isBeingDismissed && [alert.transitionCoordinator animateAlongsideTransition:nil
            completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                if (!context.isCancelled) action();
            }]) return;
        if (alert.presentingViewController) [alert dismissViewControllerAnimated:YES completion:action];
        else action();
    });
}

static inline void QSOpenExternalURL(UIViewController *controller, NSURL *url) {
    if (!QSCanPresent(controller) || !url) return;
    __weak UIViewController *weakController = controller;
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
        if (!success) dispatch_async(dispatch_get_main_queue(), ^{
            QSShowMessage(weakController, @"Unable to Open Link", url.absoluteString);
        });
    }];
}
