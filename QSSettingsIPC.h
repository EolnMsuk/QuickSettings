// QuickSettings — EolnMsuk. See LICENSE.
#pragma once
#import <Foundation/Foundation.h>

// One writer per key: SpringBoard owns command; Settings owns the other three.
// Notifications carry no data. All reads synchronize; all writes commit first.
#define QS_BRIDGE_DOMAIN CFSTR("com.eolnmsuk.quicksettings.native-bridge")
#define QS_COMMAND_HINT CFSTR("com.eolnmsuk.quicksettings.native-bridge/command")
#define QS_INDEX_HINT CFSTR("com.eolnmsuk.quicksettings.native-bridge/index")
#define QS_REPLY_HINT CFSTR("com.eolnmsuk.quicksettings.native-bridge/reply")
#define QS_REFRESH_HINT CFSTR("com.eolnmsuk.quicksettings.native-bridge/refresh")

FOUNDATION_EXPORT NSString *const QSNavigationMarker;
FOUNDATION_EXPORT NSString *const QSNativeAdapter;
FOUNDATION_EXPORT NSString *const QSIPCCommandKey;
FOUNDATION_EXPORT NSString *const QSIPCInventoryKey;
FOUNDATION_EXPORT NSString *const QSIPCReplyKey;
FOUNDATION_EXPORT NSString *const QSIPCDiagnosticsKey;
enum { QSIPCMaximumRecords = 1024, QSIPCMaximumRows = 2048 };
FOUNDATION_EXPORT const NSTimeInterval QSIPCRequestLifetime; // ten seconds, boot-scoped continuous uptime

FOUNDATION_EXPORT NSString *QSOSBuild(void);
FOUNDATION_EXPORT NSString *QSBootIdentity(void);
// Monotonic seconds including device sleep; suspended requests still expire.
FOUNDATION_EXPORT NSTimeInterval QSIPCUptime(void);
FOUNDATION_EXPORT BOOL QSIPCValidUUID(id value);
FOUNDATION_EXPORT BOOL QSIPCValidLocator(id value);
FOUNDATION_EXPORT NSDictionary *QSIPCHeader(void);
FOUNDATION_EXPORT BOOL QSIPCHeaderMatches(id value);
// A nil value with success=YES means the key has never been published.
FOUNDATION_EXPORT id QSIPCRead(NSString *key, BOOL *success);
FOUNDATION_EXPORT BOOL QSIPCWrite(NSString *key, NSDictionary *value, CFStringRef hint);
FOUNDATION_EXPORT BOOL QSIPCValidRecord(id value, NSString *appID);
FOUNDATION_EXPORT BOOL QSIPCValidInventory(id value);
FOUNDATION_EXPORT BOOL QSIPCValidCommand(id value);
FOUNDATION_EXPORT BOOL QSIPCValidRequest(id value);
FOUNDATION_EXPORT BOOL QSIPCValidReply(id value);
FOUNDATION_EXPORT BOOL QSIPCSameRequest(NSDictionary *a, NSDictionary *b);
FOUNDATION_EXPORT BOOL QSIPCRequestIsLive(NSDictionary *request);
FOUNDATION_EXPORT NSDictionary *QSIPCReply(NSDictionary *request, NSString *stage,
                                         NSString *reason, BOOL terminal);
