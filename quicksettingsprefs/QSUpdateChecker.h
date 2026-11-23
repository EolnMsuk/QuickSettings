// Adapted from HaptiX by EolnMsuk; GPL-3.0, see ../LICENSE.
// Adapted from ChoySee. See Resources/ChoySee-LICENSE.txt.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^QSUpdateCompletion)(NSString * _Nullable tag,
    NSURL * _Nullable newerReleaseURL, NSString * _Nullable failureMessage);

@interface QSUpdateChecker : NSObject
// Called by the Updates action. Completion runs on the main thread.
+ (void)checkInstalledVersion:(nullable NSString *)version completion:(QSUpdateCompletion)completion;
@end

NS_ASSUME_NONNULL_END
