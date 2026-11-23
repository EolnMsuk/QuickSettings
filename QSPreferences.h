// QuickSettings — EolnMsuk. See LICENSE.
#pragma once
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT BOOL QSReadEnabled(void);
// Posts ReloadPrefs only after a successful synchronized commit.
FOUNDATION_EXPORT BOOL QSWriteEnabled(BOOL enabled);
