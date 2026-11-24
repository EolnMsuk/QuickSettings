// QuickSettings — EolnMsuk. See LICENSE.
#import "QSPaneResolver.h"
#import "QSConstants.h"
#import "QSPreferences.h"
#import "QSSettingsEligibility.h"
#import "QSSettingsIPC.h"
#import "QSPrivateInterfaces.h"
#import "QSSettingsSupport.h"

@interface QSOpenRequest : NSObject
@property (nonatomic, copy) NSDictionary *envelope;
@property (nonatomic, copy) NSDictionary *record;
@end
@implementation QSOpenRequest
@end

// No URL opener or fallback exists in this adapter. BOOL acceptance is launch only.
static BOOL QSLaunchSettings(NSString **failure) {
    @try {
        Class<QSWorkspace> cls = (Class<QSWorkspace>)NSClassFromString(@"LSApplicationWorkspace");
        if (!QSCanCall(cls, @selector(defaultWorkspace), "@", "")) { *failure = @"workspace-abi-unsupported"; return NO; }
        id<QSWorkspace> workspace = [cls defaultWorkspace];
        if (!QSCanCall(workspace, @selector(openApplicationWithBundleID:), "Bc", "@")) {
            *failure = @"bundle-launch-bool-abi-unsupported"; return NO;
        }
        BOOL accepted = [workspace openApplicationWithBundleID:QSSettingsBundleID];
        if (!accepted) *failure = @"bundle-launch-rejected";
        return accepted;
    } @catch (NSException *exception) { *failure = @"bundle-launch-exception"; return NO; }
}

@interface QSPaneResolver ()
- (void)checkPendingReply;
@end
static void QSReplyHint(CFNotificationCenterRef center, void *observer, CFStringRef name,
                        const void *object, CFDictionaryRef info) {
    [QSPaneResolver.sharedResolver checkPendingReply];
}

@implementation QSPaneResolver {
    dispatch_queue_t _queue;
    QSSettingsEligibility *_eligibility;
    NSString *_session;
    BOOL _enabled;
    BOOL _sessionReady;
    NSUInteger _preferenceGeneration;
    NSUInteger _sequence;
    QSOpenRequest *_pending;
    dispatch_source_t _replyTimer; // queue-confined, bounded by the current deadline
    QSOpenRequest *_timerRequest;
}
+ (instancetype)sharedResolver {
    static QSPaneResolver *resolver; static dispatch_once_t once;
    dispatch_once(&once, ^{ resolver = [self new]; }); return resolver;
}
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.eolnmsuk.quicksettings.requests", DISPATCH_QUEUE_SERIAL);
        _session = NSUUID.UUID.UUIDString;
        _eligibility = QSSettingsEligibility.sharedEligibility;
        __weak QSPaneResolver *weakSelf = self;
        _eligibility.changeHandler = ^{ [weakSelf checkPendingReply]; };
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            QSReplyHint, QS_REPLY_HINT, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        // The first preference reload commits a fresh session with no old command.
        // Until that succeeds, the memory-only menu facade stays disabled.
    }
    return self;
}
- (BOOL)isEnabled { @synchronized (self) { return _enabled && _sessionReady; } }
- (NSDictionary *)recordForBundleIdentifier:(NSString *)bundleID {
    return self.isEnabled ? [_eligibility recordForBundleIdentifier:bundleID] : nil;
}
- (NSDictionary *)commandWithRequest:(NSDictionary *)request enabled:(BOOL)enabled
                         generation:(NSUInteger)generation reason:(NSString *)reason {
    NSMutableDictionary *command = [QSIPCHeader() mutableCopy];
    [command addEntriesFromDictionary:@{@"session": _session, @"boot": QSBootIdentity(),
        @"preferenceGeneration": @(generation), @"enabled": @(enabled), @"state": reason}];
    if (request) command[@"request"] = request;
    return [command copy];
}
- (void)reloadPreferences {
    NSUInteger generation; QSOpenRequest *cancelled;
    @synchronized (self) {
        generation = ++_preferenceGeneration; _enabled = NO;
        cancelled = _pending; _pending = nil;
    }
    if (cancelled) QSNavigationTrace(cancelled.envelope, @"cancelled", @"preference-reload");
    [_eligibility setEnabled:NO preferenceGeneration:generation];
    dispatch_async(_queue, ^{
        @autoreleasepool {
            @synchronized (self) { if (generation != self->_preferenceGeneration) return; }
            if (self->_replyTimer) { dispatch_source_cancel(self->_replyTimer); self->_replyTimer = nil; self->_timerRequest = nil; }
            BOOL enabled = NO;
            BOOL read = QSReadEnabledWithStatus(&enabled);
            NSDictionary *command = [self commandWithRequest:nil enabled:read && enabled generation:generation
                reason:read ? (enabled ? @"enabled-ready" : @"disabled") : @"preference-read-failed"];
            BOOL written = QSIPCValidCommand(command) && QSIPCWrite(QSIPCCommandKey, command, QS_COMMAND_HINT);
            BOOL current;
            @synchronized (self) {
                current = generation == self->_preferenceGeneration;
                if (current) { self->_sessionReady = written; self->_enabled = read && enabled && written; }
            }
            if (!read) QSDiagnostic(@"enable-read-failed", @"Committed enable state could not be read; navigation is disabled.");
            QSVerboseDiagnostic(@"enable-state", ([NSString stringWithFormat:@"session=%@ generation=%lu committed=%@ protocolReady=%@",
                self->_session, (unsigned long)generation, enabled ? @"enabled" : @"disabled", written ? @"yes" : @"no"]));
            if (current) [self->_eligibility setEnabled:read && enabled && written preferenceGeneration:generation];
        }
    });
}
- (NSString *)cancellationReason:(QSOpenRequest *)request {
    @synchronized (self) {
        if (_pending != request) return @"superseded";
        if (request.envelope[@"preferenceGeneration"] && [request.envelope[@"preferenceGeneration"] unsignedIntegerValue] != _preferenceGeneration)
            return @"preference-generation-changed";
        if (!_enabled) return @"disabled";
        if (!_sessionReady) return @"session-not-committed";
    }
    if (!QSIPCRequestIsLive(request.envelope)) return @"deadline-expired";
    NSDictionary *current = [_eligibility recordForBundleIdentifier:request.envelope[@"target"]];
    if (!current) return @"native-record-unavailable";
    if (![current[@"revision"] isEqual:request.record[@"revision"]]) return @"native-record-revised";
    return nil;
}
// All protocol retirement is serialized. Old callbacks never clear a new request.
- (void)finish:(QSOpenRequest *)request stage:(NSString *)stage reason:(NSString *)reason feedback:(BOOL)feedback {
    dispatch_async(_queue, ^{
        QSNavigationTrace(request.envelope, stage, reason);
        NSUInteger generation; BOOL enabled;
        @synchronized (self) {
            if (self->_pending != request) return;
            self->_pending = nil; generation = self->_preferenceGeneration; enabled = self->_enabled;
        }
        if (self->_replyTimer) {
            dispatch_source_cancel(self->_replyTimer); self->_replyTimer = nil; self->_timerRequest = nil;
        }
        NSDictionary *command = [self commandWithRequest:nil enabled:enabled generation:generation reason:reason];
        if (!QSIPCWrite(QSIPCCommandKey, command, QS_COMMAND_HINT)) {
            @synchronized (self) { self->_sessionReady = NO; self->_enabled = NO; }
        }
        if (![@[@"visible-target", @"cancelled"] containsObject:stage])
            QSDiagnostic(@"navigation-result", [NSString stringWithFormat:@"request=%@ target=%@ stage=%@ reason=%@",
                request.envelope[@"request"], request.envelope[@"target"], stage, reason]);
        if (feedback) dispatch_async(dispatch_get_main_queue(), ^{
            @synchronized (self) {
                if (self->_pending || self->_sequence != [request.envelope[@"sequence"] unsignedIntegerValue]
                    || self->_preferenceGeneration != [request.envelope[@"preferenceGeneration"] unsignedIntegerValue]) return;
            }
            QSNavigationFailureFeedback();
        });
    });
}
- (void)openSettingsForBundleIdentifier:(NSString *)bundleID recordRevision:(NSString *)revision {
    if (!QSValidBundleIdentifier(bundleID) || !QSIPCValidUUID(revision)) {
        QSDiagnostic(@"shortcut-target", @"Owned action has no valid target and native-record revision."); return;
    }
    NSDictionary *record = [self recordForBundleIdentifier:bundleID];
    QSOpenRequest *request = [QSOpenRequest new];
    request.record = record;
    QSOpenRequest *older;
    @synchronized (self) {
        if (!_enabled || !_sessionReady) return;
        if ([_pending.envelope[@"target"] isEqual:bundleID] && [_pending.envelope[@"revision"] isEqual:revision]
            && QSIPCRequestIsLive(_pending.envelope)) {
            QSNavigationTrace(_pending.envelope, @"coalesced", @"same-pending-target"); return;
        }
        double now = QSIPCUptime();
        NSMutableDictionary *envelope = [QSIPCHeader() mutableCopy];
        [envelope addEntriesFromDictionary:@{@"session": _session, @"request": NSUUID.UUID.UUIDString,
            @"sequence": @(++_sequence), @"target": bundleID, @"revision": revision,
            @"preferenceGeneration": @(_preferenceGeneration), @"created": @(now),
            @"deadline": @(now + QSIPCRequestLifetime), @"boot": QSBootIdentity(), @"operation": @"select-native-row"}];
        request.envelope = [envelope copy]; older = _pending; _pending = request;
    }
    if (older) QSNavigationTrace(older.envelope, @"cancelled", @"replacement-target");
    QSNavigationTrace(request.envelope, @"activation", @"native-index-record");
    if (!QSIPCValidRecord(record, bundleID) || ![record[@"revision"] isEqual:revision]) {
        [self finish:request stage:@"failed" reason:@"stale-menu-record" feedback:YES]; return;
    }
    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *cancel = [self cancellationReason:request];
            if (cancel) { [self finish:request stage:@"cancelled" reason:cancel feedback:NO]; return; }
            BOOL enabled = NO;
            BOOL read = QSReadEnabledWithStatus(&enabled);
            if (!read || !enabled) {
                [self finish:request stage:@"cancelled" reason:read ? @"committed-disabled" : @"preference-read-failed" feedback:NO]; return;
            }
            NSDictionary *command = [self commandWithRequest:request.envelope enabled:YES
                generation:[request.envelope[@"preferenceGeneration"] unsignedIntegerValue] reason:@"pending-native-selection"];
            if (!QSIPCValidCommand(command) || !QSIPCWrite(QSIPCCommandKey, command, QS_COMMAND_HINT)) {
                [self finish:request stage:@"failed" reason:@"request-commit-failed" feedback:YES]; return;
            }
            QSNavigationTrace(request.envelope, @"request-persisted", @"command-committed-before-launch");
            cancel = [self cancellationReason:request];
            if (cancel) { [self finish:request stage:@"cancelled" reason:cancel feedback:NO]; return; }
            if (self->_replyTimer) dispatch_source_cancel(self->_replyTimer);
            self->_timerRequest = request;
            self->_replyTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self->_queue);
            dispatch_source_set_timer(self->_replyTimer, DISPATCH_TIME_NOW, NSEC_PER_SEC / 4, NSEC_PER_SEC / 40);
            dispatch_source_set_event_handler(self->_replyTimer, ^{ [self inspectReply:request]; });
            dispatch_resume(self->_replyTimer);
            // The icon hook has returned before this main-queue operation.
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *cancel = [self cancellationReason:request];
                if (cancel) { [self finish:request stage:@"cancelled" reason:cancel feedback:NO]; return; }
                QSNavigationTrace(request.envelope, @"launch-submitted", @"com.apple.Preferences");
                NSString *failure = nil;
                BOOL accepted = QSLaunchSettings(&failure);
                QSNavigationTrace(request.envelope, accepted ? @"launch-accepted" : @"launch-rejected", failure ?: @"destination-unverified");
                if (!accepted) [self finish:request stage:@"failed" reason:failure feedback:YES];
            });
        }
    });
}
- (void)checkPendingReply {
    dispatch_async(_queue, ^{
        QSOpenRequest *request; @synchronized (self) { request = self->_pending; }
        if (request) [self inspectReply:request];
    });
}
- (void)inspectReply:(QSOpenRequest *)request {
    NSString *cancel = [self cancellationReason:request];
    if (cancel) {
        [self finish:request stage:[cancel isEqual:@"deadline-expired"] ? @"expired" : @"cancelled" reason:cancel
            feedback:[cancel isEqual:@"deadline-expired"]]; return;
    }
    BOOL ok = NO;
    NSDictionary *reply = QSIPCRead(QSIPCReplyKey, &ok);
    if (!ok || !reply) return; // Polling is bounded; notification delivery is optional.
    if (!QSIPCValidReply(reply)) { QSDiagnostic(@"reply-invalid", @"Ignored incompatible or malformed Settings reply."); return; }
    for (NSString *key in @[@"session", @"request", @"target", @"revision", @"sequence", @"preferenceGeneration", @"boot"])
        if (![reply[key] isEqual:request.envelope[key]]) return;
    double replied = [reply[@"uptime"] doubleValue];
    if (replied < [request.envelope[@"created"] doubleValue] || replied > [request.envelope[@"deadline"] doubleValue]
        || replied > QSIPCUptime()) return;
    if (![reply[@"terminal"] boolValue]) return;
    [self finish:request stage:reply[@"stage"] reason:reply[@"reason"] feedback:NO];
}
@end
