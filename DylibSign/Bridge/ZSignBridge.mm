#import "ZSignBridge.h"

#include <unistd.h>
#include <string>
#include <vector>

#include "common.h"
#include "archive.h"
#include "openssl.h"
#include "bundle.h"

static std::string ZSPath(NSString *path) {
    return path.length ? std::string(path.fileSystemRepresentation) : std::string();
}

@implementation ZSignBridge

+ (BOOL)extractZipAtPath:(NSString *)zipPath toFolder:(NSString *)folder {
    return Zip::Extract(zipPath.fileSystemRepresentation, folder.fileSystemRepresentation);
}

+ (BOOL)archiveFolder:(NSString *)folder toZip:(NSString *)zipPath level:(int)level {
    return Zip::Archive(ZSPath(folder), ZSPath(zipPath), level);
}

+ (nullable NSString *)signFolder:(NSString *)folder
                          p12Path:(nullable NSString *)p12Path
                         password:(nullable NSString *)password
                    provisionPath:(nullable NSString *)provisionPath
                            adhoc:(BOOL)adhoc
                         iconPath:(nullable NSString *)iconPath {
    // zsign writes relative cache/debug files (./.zsign_cache); keep them in tmp.
    chdir(NSTemporaryDirectory().fileSystemRepresentation);

    ZSignAsset asset;
    bool ok = asset.Init(std::string(),                         // cert file (taken from the p12)
                         adhoc ? std::string() : ZSPath(p12Path),
                         adhoc ? std::string() : ZSPath(provisionPath),
                         std::string(),                         // entitlements: from the provision
                         adhoc ? std::string() : std::string(password.UTF8String ?: ""),
                         adhoc,
                         true,                                  // SHA256 only
                         false);                                // bundle, not a single binary
    if (!ok) {
        return adhoc ? @"تعذّر تهيئة التوقيع ad-hoc"
                     : @"تعذّر فتح الشهادة أو ملف البروفايل (تحقق من كلمة المرور وصلاحية الملفات)";
    }

    ZBundle bundle;
    if (iconPath.length) {
        bundle.m_strIconFile = ZSPath(iconPath);
    }

    std::vector<std::string> noInject;
    std::vector<std::string> noRemove;
    ok = bundle.SignFolder(&asset,
                           ZSPath(folder),
                           "", "", "",          // bundle id / version / name already set in Info.plist
                           noInject, noRemove,
                           true,                // force
                           false,               // weak inject (unused)
                           false,               // cache
                           false);              // keep embedded.mobileprovision
    return ok ? nil : @"فشل zsign أثناء توقيع التطبيق";
}

@end
