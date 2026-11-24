// QuickSettings — EolnMsuk. See LICENSE.
#import "QSSettingsSupport.h"

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
