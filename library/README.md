# مكتبة الدايلب

التطبيق يقرأ القائمة من `library/index.json` في فرع `main` مباشرة، فأي تعديل هنا يظهر في التطبيق فوراً بدون بناء نسخة جديدة.

## إضافة دايلب جديد

1. ارفع الملف (`.dylib` أو `.deb`) إلى مجلد `library/files/`
   (من GitHub: افتح المجلد ← **Add file** ← **Upload files**).
2. عدّل `library/index.json` وأضف عنصراً داخل `dylibs`:

```json
{
  "id": "my-tweak",
  "name": "اسم الأداة",
  "summary": "سطر واحد يظهر في القائمة",
  "description": "شرح مختصر لوظيفة الأداة.",
  "activation": "1. افتح التطبيق بعد الحقن\n2. اضغط بثلاث أصابع على الشاشة لفتح القائمة",
  "file": "files/MyTweak.dylib",
  "version": "1.0",
  "author": "اسم المطوّر",
  "category": "ألعاب",
  "icon": "gamecontroller.fill",
  "needsSubstrate": false
}
```

| الحقل | مطلوب | الوصف |
|---|---|---|
| `id` | نعم | معرّف فريد بالإنجليزية بدون مسافات |
| `name` | نعم | اسم الأداة |
| `summary` | نعم | وصف قصير يظهر في القائمة |
| `description` | لا | شرح وظيفة الأداة |
| `activation` | لا | طريقة التفعيل (استخدم `\n` لسطر جديد) |
| `file` | نعم | مسار الملف داخل `library/` أو رابط مباشر كامل `https://...` |
| `version` / `author` / `category` | لا | معلومات إضافية |
| `icon` | لا | اسم أيقونة من SF Symbols (مثل `star.fill`، `gamecontroller.fill`) |
| `needsSubstrate` | لا | `true` إذا كانت الأداة تحتاج CydiaSubstrate |

> انتبه أن يبقى الملف JSON صالحاً (فواصل بين العناصر وعلامات تنصيص). يمكنك التحقق منه في أي موقع JSON validator.
