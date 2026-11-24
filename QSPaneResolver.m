// QuickSettings — EolnMsuk. See LICENSE.
#import "QSPaneResolver.h"
#import "QSPreferences.h"
#import "QSSettingsEligibility.h"
#import "QSSettingsSupport.h"
#import <UIKit/UIKit.h>

@interface QSOpenRequest : NSObject
@property (nonatomic) NSUInteger identifier;
@property (nonatomic) NSUInteger preferenceGeneration;
@property (nonatomic) NSUInteger eligibilityGeneration;
@property (nonatomic, copy) NSString *target;
@property (nonatomic, strong) QSSettingsDestination *destination;
@property (nonatomic) NSTimeInterval started;
@property (nonatomic) BOOL traceEnabled;
@end
@implementation QSOpenRequest
@end

static void QSRequestTrace(QSOpenRequest *request, NSString *routeKind, NSString *stage,
                           NSTimeInterval timestamp) {
    if (!QS_VERBOSE_DIAGNOSTICS || !request.traceEnabled) return;
    NSLog(@"[QuickSettings] request=%lu target=%@ route=%@ elapsed=%.1fms %@",
        (unsigned long)request.identifier, request.target, routeKind,
        (timestamp - request.started) * 1000.0, stage);
}

@implementation QSPaneResolver {
    dispatch_queue_t _workQueue;
    QSSettingsEligibility *_eligibility;
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
        _eligibility = QSSettingsEligibility.sharedEligibility;
    }
    return self;
}

- (BOOL)isEnabled {
    @synchronized (self) { return _enabled; }
}

- (BOOL)hasSettingsForBundleIdentifier:(NSString *)bundleID {
    return self.isEnabled && [_eligibility destinationForBundleIdentifier:bundleID generation:NULL].state == QSSettingsEligibilityEligible;
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
    [_eligibility setEnabled:NO preferenceGeneration:generation];
    dispatch_async(_workQueue, ^{
        @autoreleasepool {
            @synchronized (self) { if (generation != self->_preferenceGeneration) return; }
            BOOL enabled = QSReadEnabled();
            BOOL current;
            @synchronized (self) {
                current = generation == self->_preferenceGeneration;
                if (current) self->_enabled = enabled;
            }
            if (current) [self->_eligibility setEnabled:enabled preferenceGeneration:generation];
        }
    });
}

- (BOOL)isCurrentRequest:(QSOpenRequest *)request {
    if (![_eligibility isCurrentDestination:request.destination generation:request.eligibilityGeneration]) return NO;
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
    NSUInteger eligibilityGeneration;
    request.destination = [_eligibility destinationForBundleIdentifier:request.target generation:&eligibilityGeneration];
    request.eligibilityGeneration = eligibilityGeneration;
    @synchronized (self) {
        if (!_enabled) return;
        if (request.destination.state == QSSettingsEligibilityEligible && [_pendingRequest.target isEqualToString:request.target]
            && _pendingRequest.eligibilityGeneration == request.eligibilityGeneration) return;
        request.identifier = ++_nextRequestID;
        // Capture before validation; no later generation may bless an older read.
        request.preferenceGeneration = _preferenceGeneration;
        #if QS_VERBOSE_DIAGNOSTICS
        if (request.started - _traceWindowStart >= 60) {
            _traceWindowStart = request.started;
            _tracedRequests = 0;
        }
        // At most 24 complete request traces per minute, independent of the
        // per-code diagnostic throttle. Repeated acceptance timings stay visible.
        request.traceEnabled = _tracedRequests < 24;
        if (request.traceEnabled) _tracedRequests++;
        #endif
        _pendingRequest = request; // Supersedes an older target, even before its read.
    }
    if (request.destination.state != QSSettingsEligibilityEligible) {
        // A stale owned tap supersedes older work but never waits for discovery to launch later.
        [self finishRequest:request];
        return;
    }
    QSRequestTrace(request, @"pending", @"activation", request.started);
    dispatch_async(_workQueue, ^{
        @autoreleasepool {
            if (![self isCurrentRequest:request]) {
                QSRequestTrace(request, @"pending", @"cancelled-before-validation", NSProcessInfo.processInfo.systemUptime);
                [self finishRequest:request];
                return;
            }
            QSRequestTrace(request, @"pending", @"worker-start", NSProcessInfo.processInfo.systemUptime);
            BOOL enabled = QSReadEnabled(); // The only committed read per activation.
            NSString *routeKind = request.destination.evidence & QSSettingsEvidenceBuiltinCatalog ? @"builtin-root" : @"app";
            NSURL *url = request.destination.URL; // Captured with the eligibility generation at activation.
            BOOL current;
            NSUInteger disabledGeneration = 0;
            @synchronized (self) {
                if (request.preferenceGeneration != self->_preferenceGeneration) {
                    current = NO;
                } else {
                    self->_enabled = enabled;
                    if (!enabled) {
                        self->_preferenceGeneration++;
                        disabledGeneration = self->_preferenceGeneration;
                        self->_pendingRequest = nil;
                    }
                    current = enabled && self->_pendingRequest == request;
                }
            }
            if (disabledGeneration) [self->_eligibility setEnabled:NO preferenceGeneration:disabledGeneration];
            current = current && [self->_eligibility validateDestinationForOpening:request.destination
                generation:request.eligibilityGeneration] && [self isCurrentRequest:request];
            QSRequestTrace(request, routeKind, current ? @"validation-complete" : @"validation-cancelled",
                NSProcessInfo.processInfo.systemUptime);
            if (!current) {
                [self finishRequest:request];
                return;
            }
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
                    [self finishRequest:request];
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
