// QuickSettings — EolnMsuk. See LICENSE.
#pragma once
#import <Foundation/Foundation.h>

// Opt in with make QS_VERBOSE_DIAGNOSTICS=1 for bounded request/snapshot traces.
#ifndef QS_VERBOSE_DIAGNOSTICS
#define QS_VERBOSE_DIAGNOSTICS 0
#endif

FOUNDATION_EXPORT void QSDiagnostic(NSString *code, NSString *detail);
FOUNDATION_EXPORT BOOL QSValidBundleIdentifier(id value);

#if QS_VERBOSE_DIAGNOSTICS
#define QSVerboseDiagnostic(code, detail) QSDiagnostic((code), (detail))
#else
#define QSVerboseDiagnostic(code, detail) do {} while (0)
#endif
