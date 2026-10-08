# محتاج صنايعي — Mehtag Sanaye

Marketplace يربط العملاء بالصنايعية القريبين في مصر. تطبيق Android (Flutter) بواجهتين (عميل/صنايعي) + Backend على Firebase + لوحة تحكم ويب.

**ابدأ من هنا:** [`docs/SETUP.md`](docs/SETUP.md) — دليل التشغيل خطوة بخطوة.

## التقنيات
| الجزء | التقنية |
|---|---|
| التطبيق | Flutter 3.29 (Dart 3) — Android أولًا، وجاهز للتوسع لـiOS والويب من نفس الكود |
| الحالة | Provider + Streams مباشرة من Firestore (تحديث لحظي + كاش للعمل بدون إنترنت) |
| الدخول | Firebase Auth: رقم الهاتف + OTP، Google Sign-In (مع ربط إجباري برقم هاتف) |
| قاعدة البيانات | Cloud Firestore + Geohash للبحث الجغرافي |
| الباك إند | Cloud Functions (Node 20) — كل الحالات والعمولة والتقييمات على السيرفر |
| الملفات | Cloud Storage (البطاقة الشخصية للإدارة فقط) |
| الإشعارات | Firebase Cloud Messaging (قناة عادية + قناة عاجلة للطوارئ + Topics للإشعارات الإدارية) |
| الخرائط | Google Maps SDK + Geolocator |
| لوحة التحكم | HTML/JS + Firebase Web SDK + Chart.js على Firebase Hosting |
| البناء والنشر | GitHub Actions (APK + AAB + نشر Firebase) |

## هيكل المشروع
```
mehtag-sanaye/
├── app/                         تطبيق Flutter
│   ├── lib/
│   │   ├── main.dart, app.dart  التهيئة والتوجيه حسب حالة المستخدم
│   │   ├── core/                الثيم، الترجمة (ar/en + RTL)، geohash، أدوات، مكونات مشتركة
│   │   ├── data/                النماذج، Session، المستودعات، خدمات (Auth/API/Push/Location/Storage)
│   │   └── features/
│   │       ├── auth/            الترحيب، الدخول + OTP، ربط الرقم، استكمال الملف
│   │       ├── customer/        الرئيسية، البحث والفلاتر، الخريطة، ملف الصنايعي، إنشاء طلب/طوارئ، المفضلة
│   │       ├── worker/          التسجيل والمراجعة، الطلبات القريبة، الحساب المالي ودفع العمولة، تعديل البيانات
│   │       └── shared/          تفاصيل الطلب والحالات، الشات، التقييم، البلاغات، الإشعارات، الحساب، الإحصائيات، المساعدة
│   ├── android/                 إعدادات Android (الحزمة com.mehtagsanaye.app)
│   └── assets/images/           اللوجو
├── functions/                   Cloud Functions
│   ├── src/lib/                 منطق نقي مختبر: geo, commission, statusMachine, badges, validate, i18n
│   ├── src/*.js                 auth, workers, requests, reviews, support, payments, adminApi, scheduled
│   ├── scripts/                 seed (الكتالوج)، create-admin، seed-demo
│   └── test/                    28 اختبار (منها المسارات الثلاثة الكاملة)
├── admin/                       لوحة التحكم (Firebase Hosting)
├── firestore.rules, storage.rules, firestore.indexes.json, firebase.json
├── branding/                    اللوجو والأيقونات (SVG + PNG)
├── docs/                        SETUP.md, DATABASE.md, API.md
└── .github/workflows/           build-android, deploy-firebase, setup-database
```

## التوثيق
- [دليل التشغيل والنشر](docs/SETUP.md)
- [قاعدة البيانات](docs/DATABASE.md)
- [API endpoints](docs/API.md)

## الاختبارات
```bash
cd functions && npm install && npm test
```
تشغّل منطق السيرفر الحقيقي على Firebase وهمي في الذاكرة وتختبر: تسجيل صنايعي ← رفض ← إعادة تقديم ← قبول ← ظهور، المسار الكامل للعميل حتى دفع العمولة، الطوارئ وأول صنايعي يقبل، الحظر، Rate limiting، منع تكرار الرقم القومي والهاتف، والمتأخرات اليومية.
