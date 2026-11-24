// QuickSettings — EolnMsuk. See LICENSE. Routing references: plan.md E1, E3, E5.
#import "QSPaneResolver.h"
#import "QSPreferences.h"
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

static NSDictionary<NSString *, NSString *> *QSLegacyBuiltinRoots(void) {
    static NSDictionary *roots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Empirical iOS 15–17 roots, not live pane eligibility or a page guarantee.
        // Tokens: plan.md E5. Additional app IDs: Apple's deployment bundle-ID list
        // linked in ProjectOverview.md. Keep exact case for both IDs and roots.
        roots = @{
            @"com.apple.mobilesafari": @"SAFARI",
            @"com.apple.mobilephone": @"Phone",
            @"com.apple.MobileSMS": @"MESSAGES",
            @"com.apple.facetime": @"FACETIME",
            @"com.apple.Maps": @"MAPS",
            @"com.apple.Music": @"MUSIC",
            @"com.apple.mobilenotes": @"NOTES",
            @"com.apple.reminders": @"REMINDERS",
            @"com.apple.compass": @"COMPASS",
            @"com.apple.mobileslideshow": @"Photos",
            @"com.apple.AppStore": @"STORE",
            @"com.apple.mobilemail": @"MAIL",
            @"com.apple.MobileAddressBook": @"CONTACTS",
            @"com.apple.mobilecal": @"CALENDAR",
            @"com.apple.camera": @"CAMERA",
            @"com.apple.VoiceMemos": @"VOICE_MEMOS",
            @"com.apple.Translate": @"TRANSLATE",
            @"com.apple.measure": @"MEASURE",
            @"com.apple.iBooks": @"IBOOKS",
            @"com.apple.Health": @"HEALTH",
            @"com.apple.Passbook": @"PASSBOOK",
            @"com.apple.shortcuts": @"SHORTCUTS",
            @"com.apple.podcasts": @"com.apple.podcasts",
            @"com.apple.news": @"NEWS",
            @"com.apple.Home": @"HOMEKIT"
        };
    });
    return roots;
}

static NSURL *QSSettingsURL(NSString *bundleID, NSString **routeKind) {
    NSInteger major = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
    // The iOS 18+ Settings redesign is outside the legacy table's evidence.
    NSString *root = major >= 15 && major < 18 ? QSLegacyBuiltinRoots()[bundleID] : nil;
    *routeKind = root ? @"builtin-root" : @"app";
    NSCharacterSet *componentCharacters = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
    NSString *encoded = [(root ?: bundleID) stringByAddingPercentEncodingWithAllowedCharacters:componentCharacters];
    if (!encoded.length) return nil;
    return [NSURL URLWithString:[(root ? @"prefs:root=" : @"App-prefs:") stringByAppendingString:encoded]];
}

@interface QSOpenRequest : NSObject
@property (nonatomic) NSUInteger identifier;
@property (nonatomic) NSUInteger preferenceGeneration;
@property (nonatomic, copy) NSString *target;
@property (nonatomic) NSTimeInterval started;
@property (nonatomic) BOOL traceEnabled;
@end
@implementation QSOpenRequest
@end

static void QSRequestTrace(QSOpenRequest *request, NSString *routeKind, NSString *stage,
                           NSTimeInterval timestamp) {
    if (!request.traceEnabled) return;
    NSLog(@"[QuickSettings] request=%lu target=%@ route=%@ elapsed=%.1fms %@",
        (unsigned long)request.identifier, request.target, routeKind,
        (timestamp - request.started) * 1000.0, stage);
}

@implementation QSPaneResolver {
    dispatch_queue_t _workQueue;
    // Protect only memory. Never hold this monitor across CFPreferences or UIKit.
    BOOL _enabled;
    NSUInteger _preferenceGeneration;
    NSUInteger _nextRequestID;
    QSOpenRequest *_pendingRequest;
    NSTimeInterval _traceWindowStart;
    NSUInteger _tracedRequests;
}

+ (instancetype)sharedResolver {
    static QSPaneResolver *resolver;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ resolver = [self new]; });
    return resolver;
}

- (instancetype)init {
    if ((self = [super init])) {
        _workQueue = dispatch_queue_create("com.eolnmsuk.quicksettings.requests", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)isEnabled {
    @synchronized (self) { return _enabled; }
}

- (void)reloadPreferences {
    NSUInteger generation;
    @synchronized (self) {
        generation = ++_preferenceGeneration;
        // A Darwin notification has no value payload. Fail closed until its read
        // completes, including when an old activation is already on the worker.
        _enabled = NO;
        _pendingRequest = nil;
    }
    dispatch_async(_workQueue, ^{
        @autoreleasepool {
            @synchronized (self) { if (generation != self->_preferenceGeneration) return; }
            BOOL enabled = QSReadEnabled();
            @synchronized (self) {
                if (generation == self->_preferenceGeneration) self->_enabled = enabled;
            }
        }
    });
}

- (BOOL)isCurrentRequest:(QSOpenRequest *)request {
    @synchronized (self) {
        return _enabled && _pendingRequest == request
            && request.preferenceGeneration == _preferenceGeneration;
    }
}

- (void)finishRequest:(QSOpenRequest *)request {
    @synchronized (self) { if (_pendingRequest == request) _pendingRequest = nil; }
}

- (void)openSettingsForBundleIdentifier:(NSString *)bundleID {
    if (!QSValidBundleIdentifier(bundleID)) return;
    QSOpenRequest *request = [QSOpenRequest new];
    request.target = [bundleID copy];
    request.started = NSProcessInfo.processInfo.systemUptime;
    @synchronized (self) {
        if (!_enabled || [_pendingRequest.target isEqualToString:request.target]) return;
        request.identifier = ++_nextRequestID;
        // Capture before validation; no later generation may bless an older read.
        request.preferenceGeneration = _preferenceGeneration;
        if (request.started - _traceWindowStart >= 60) {
            _traceWindowStart = request.started;
            _tracedRequests = 0;
        }
        // At most 24 complete request traces per minute, independent of the
        // per-code diagnostic throttle. Repeated acceptance timings stay visible.
        request.traceEnabled = _tracedRequests < 24;
        if (request.traceEnabled) _tracedRequests++;
        _pendingRequest = request; // Supersedes an older target, even before its read.
    }
    QSRequestTrace(request, @"pending", @"activation", request.started);
    dispatch_async(_workQueue, ^{
        @autoreleasepool {
            if (![self isCurrentRequest:request]) {
                QSRequestTrace(request, @"pending", @"cancelled-before-validation", NSProcessInfo.processInfo.systemUptime);
                return;
            }
            QSRequestTrace(request, @"pending", @"worker-start", NSProcessInfo.processInfo.systemUptime);
            BOOL enabled = QSReadEnabled(); // The only committed read per activation.
            NSString *routeKind = nil;
            NSURL *url = QSSettingsURL(request.target, &routeKind);
            BOOL current;
            @synchronized (self) {
                if (request.preferenceGeneration != self->_preferenceGeneration) {
                    current = NO;
                } else {
                    self->_enabled = enabled;
                    if (!enabled) {
                        self->_preferenceGeneration++;
                        self->_pendingRequest = nil;
                    }
                    current = enabled && self->_pendingRequest == request;
                }
            }
            QSRequestTrace(request, routeKind, current ? @"validation-complete" : @"validation-cancelled",
                NSProcessInfo.processInfo.systemUptime);
            if (!current) return;
            if (!url) {
                QSDiagnostic(@"route-invalid", @"Could not construct a Settings route for a validated target.");
                [self finishRequest:request];
                return;
            }
            // SBIconView's UI callback returns before this main-queue submission.
            dispatch_async(dispatch_get_main_queue(), ^{
                QSRequestTrace(request, routeKind, @"opener-before", NSProcessInfo.processInfo.systemUptime);
                if (![self isCurrentRequest:request]) {
                    QSRequestTrace(request, routeKind, @"cancelled-before-open", NSProcessInfo.processInfo.systemUptime);
                    return;
                }
                // Submission is the cancellation boundary; an OS request already
                // in flight cannot be recalled by a subsequent toggle/selection.
                NSTimeInterval invoking = NSProcessInfo.processInfo.systemUptime;
                @try {
                    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL accepted) {
                        QSRequestTrace(request, routeKind,
                            accepted ? @"open-accepted (destination-unverified)" : @"open-rejected",
                            NSProcessInfo.processInfo.systemUptime);
                        if (!accepted) QSDiagnostic(@"open-rejected", [NSString stringWithFormat:
                            @"Settings URL rejected for %@; no retry.", request.target]);
                        [self finishRequest:request];
                    }];
                    NSTimeInterval returned = NSProcessInfo.processInfo.systemUptime;
                    QSRequestTrace(request, routeKind, [NSString stringWithFormat:@"opener-return call=%.1fms",
                        (returned - invoking) * 1000.0], returned);
                } @catch (NSException *exception) {
                    QSRequestTrace(request, routeKind, @"opener-exception", NSProcessInfo.processInfo.systemUptime);
                    QSDiagnostic(@"open-exception", exception.name);
                    [self finishRequest:request];
                }
            });
        }
    });
}
@end
