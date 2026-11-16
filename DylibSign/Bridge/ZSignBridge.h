#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin Objective-C++ wrapper around zsign (https://github.com/zhlynn/zsign).
/// zsign keeps global state: call from one thread at a time.
@interface ZSignBridge : NSObject

+ (BOOL)extractZipAtPath:(NSString *)zipPath toFolder:(NSString *)folder;

/// `folder` is the directory that contains `Payload/`.
+ (BOOL)archiveFolder:(NSString *)folder toZip:(NSString *)zipPath level:(int)level;

/// Signs the app found under `folder/Payload`. Returns nil on success, or an error message.
/// adhoc = YES → fakesign without a certificate (p12/provision are ignored).
+ (nullable NSString *)signFolder:(NSString *)folder
                          p12Path:(nullable NSString *)p12Path
                         password:(nullable NSString *)password
                    provisionPath:(nullable NSString *)provisionPath
                            adhoc:(BOOL)adhoc
                         iconPath:(nullable NSString *)iconPath;

@end

NS_ASSUME_NONNULL_END
