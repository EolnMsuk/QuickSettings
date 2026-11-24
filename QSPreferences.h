// QuickSettings — EolnMsuk. See LICENSE.
#pragma once
#import <Foundation/Foundation.h>

// Synchronous committed read. SpringBoard callers must use the resolver's worker.
FOUNDATION_EXPORT BOOL QSReadEnabled(void);
// A failed synchronization/type check cannot authorize navigation.
FOUNDATION_EXPORT BOOL QSReadEnabledWithStatus(BOOL *enabled);
// Posts ReloadPrefs only after a successful synchronized commit.
FOUNDATION_EXPORT BOOL QSWriteEnabled(BOOL enabled);
