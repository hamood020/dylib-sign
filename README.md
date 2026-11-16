# Dylib Sign

تطبيق آيفون لحقن ملفات **dylib / deb** داخل تطبيقات **IPA** مباشرة على الجهاز، مع توقيع **اختياري**.

## المزايا

- حقن `.dylib` أو `.deb` (يُستخرج تلقائياً، يدعم `data.tar.xz` و `data.tar.gz`) أو `.framework`.
- مسار الحقن: `@rpath` أو `@executable_path/Frameworks`، مع خيار الحقن الضعيف (Weak).
- إصلاح مسار CydiaSubstrate تلقائياً إلى `@rpath/CydiaSubstrate.framework/CydiaSubstrate`.
  أضف `CydiaSubstrate.framework` (مثل ElleKit) في «ملفات إضافية» إذا كانت الأداة تحتاجه.
- فحص التشفير (مع خيار التجاوز).
- تعديلات: Bundle ID، الاسم، الإصدار، الأيقونة، حذف URL Schemes، تفعيل Document Browser،
  حذف Extensions، حذف مجلد Watch، حذف UISupportedDevices.
- **التوقيع اختياري**:
  - **بدون توقيع**: يخرج IPA محقون غير موقّع، توقّعه لاحقاً بالأداة التي تفضلها.
  - **Fakesign**: توقيع ad-hoc بدون شهادة (TrollStore / AppSync).
  - **بشهادة**: ملف `.p12` + كلمة المرور + `.mobileprovision`.
- الناتج يُحفظ في تطبيق الملفات: `Dylib Sign/Output/` ويمكن مشاركته مباشرة.

## طريقة العمل

1. فك ضغط IPA والعثور على `Payload/*.app` والملف التنفيذي.
2. نسخ الـ dylib إلى `App.app/Frameworks/`.
3. تعديل Mach-O (ملفات thin و FAT): إضافة `LC_LOAD_DYLIB` و `LC_RPATH`، وتعديل مسارات المكتبات داخل الـ dylib.
4. تطبيق تعديلات Info.plist.
5. التوقيع (إن اختير) عبر [zsign](https://github.com/zhlynn/zsign) ثم الضغط إلى IPA.

## البناء

لا حاجة لجهاز ماك: كل دفعة (push) على `main` تبني التطبيق تلقائياً عبر GitHub Actions،
وتجد الملف `DylibSign-unsigned.ipa` في صفحة **Actions ← آخر تشغيل ← Artifacts**.
ثبّته بتوقيعك (Sideloadly، AltStore، ESign) أو عبر TrollStore.

البناء على ماك محلياً:

```bash
brew install xcodegen
bash scripts/fetch-zsign.sh
xcodegen generate
open DylibSign.xcodeproj
```

## هيكل المشروع

| المسار | الوصف |
|---|---|
| `DylibSign/Core/MachOBinary.swift` | محرر Mach-O (حقن الأوامر وتعديل المسارات) |
| `DylibSign/Core/TweakExtractor.swift` | استخراج ملفات deb (ar + tar + xz/gz) |
| `DylibSign/Core/Injector.swift` | خطوات العملية كاملة |
| `DylibSign/Bridge/ZSignBridge.mm` | ربط zsign (فك/ضغط ZIP والتوقيع) |
| `DylibSign/UI/` | واجهة SwiftUI بالعربية |
| `scripts/fetch-zsign.sh` | تحميل zsign وتجهيزه لـ iOS |

## ملاحظات

- يجب أن يكون IPA **مفكوك التشفير**.
- الأدوات التي تعتمد على مسارات الجيلبريك (`/var/jb`، ملفات في `/Library/Application Support`) قد لا تعمل بدون جيلبريك.
- التطبيق يحقن فقط ولا يضمن عمل الأداة داخل التطبيق.
