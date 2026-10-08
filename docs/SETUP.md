# دليل التشغيل — محتاج صنايعي

الدليل ده بيمشي معاك خطوة بخطوة من الصفر لحد ما التطبيق يبقى على Google Play. مش محتاج تثبت أي برامج برمجة على جهازك: البناء والنشر بيحصلوا أوتوماتيك على GitHub.

**المدة المتوقعة:** ساعة إلى ساعتين أول مرة.

---

## 0) اللي هتحتاجه
- حساب Google (يفضل حساب خاص بالمشروع).
- كارت دفع (فيزا/ماستركارد) لتفعيل خطة **Blaze** في Firebase — فيها حصة مجانية كبيرة، والتكلفة الفعلية في البداية غالبًا صفر أو قروش بسيطة (رسائل SMS للـOTP بتتحاسب بالرسالة).
- حساب GitHub مجاني.
- حساب Google Play Console (رسوم مرة واحدة 25 دولار) — وقت النشر بس.

---

## 1) إنشاء مشروع Firebase
1. ادخل [console.firebase.google.com](https://console.firebase.google.com) → **Add project** → اسم: `mehtag-sanaye`.
2. من الترس ⚙️ → **Usage and billing** → **Modify plan** → اختار **Blaze**.
   - نصيحة: من Google Cloud Billing اعمل **Budget alert** بمبلغ صغير (مثلاً 5 دولار) علشان يوصلك تنبيه.
3. اكتب **Project ID** في ورقة — هتحتاجه (مثال: `mehtag-sanaye-1a2b3`).

## 2) تفعيل الخدمات
من القائمة الجانبية:
1. **Authentication → Get started → Sign-in method** وفعّل:
   - **Phone** ✅
   - **Google** ✅ (اختار بريد الدعم)
   - **Email/Password** ✅ (ده لدخول لوحة التحكم فقط)
2. في **Authentication → Settings → SMS region policy**: اختار **Allow** وضيف **Egypt** (يمنع إساءة استخدام SMS من دول تانية).
3. **Firestore Database → Create database** → Location: **eur3 (europe-west)** أو `europe-west1` → **Production mode**.
4. **Storage → Get started** → نفس المنطقة → Production mode.

## 3) إضافة تطبيق Android
1. من ⚙️ **Project settings → General → Add app → Android**.
2. **Package name:** `com.mehtagsanaye.app` (لازم يكون كده بالظبط).
3. **App nickname:** محتاج صنايعي.
4. **SHA-1:** انسخه من ملف `fingerprints.txt` اللي وصلك مع مفتاح التوقيع.
5. اضغط **Register app** ونزّل ملف **google-services.json**.
6. ارجع لنفس صفحة التطبيق → **Add fingerprint** → ضيف كمان **SHA-256** من نفس الملف.
   - لما ترفع على Google Play هتضيف كمان بصمة **App signing key** من Play Console (الخطوة 12).

## 4) إضافة تطبيق Web (للوحة التحكم)
1. **Project settings → General → Add app → Web** → اسم: `admin` → فعّل **Firebase Hosting**.
2. هيظهرلك كود فيه `firebaseConfig`. انسخ القيم في ملف **`admin/config.js`** مكان `PASTE_...` و`YOUR_PROJECT_ID`.
3. عدّل ملف **`.firebaserc`** وحط Project ID مكان `YOUR_FIREBASE_PROJECT_ID`.

> بيانات `firebaseConfig` مش سرية — الحماية الحقيقية في قواعد الأمان والصلاحيات على السيرفر.

## 5) مفتاح Google Maps
1. ادخل [console.cloud.google.com](https://console.cloud.google.com) واختار نفس المشروع.
2. **APIs & Services → Library** وفعّل: **Maps SDK for Android**.
3. وفعّل كمان **Play Integrity API** (مطلوب لتأكيد OTP على Android بدون صفحة reCAPTCHA).
4. **APIs & Services → Credentials → Create credentials → API key**.
5. اضغط على المفتاح → **Application restrictions: Android apps** → Add:
   - Package: `com.mehtagsanaye.app` + SHA-1 بتاعك (ونفس الحاجة لبصمة Google Play بعدين).
   - **API restrictions:** Maps SDK for Android فقط.
6. احفظ المفتاح — اسمه في الأسرار `MAPS_API_KEY`.

## 6) حساب الخدمة (Service Account) للنشر الأوتوماتيك
1. Firebase → ⚙️ **Project settings → Service accounts → Generate new private key** → هينزل ملف JSON.
2. ⚠️ الملف ده سري جدًا — متبعتهوش لحد ومترفعهوش في الكود. هيتحط بس في GitHub Secrets.

## 7) رفع الكود على GitHub
1. اعمل مستودع **Private** جديد اسمه `mehtag-sanaye`.
2. ارفع كل محتويات مجلد المشروع (من الموقع: **Add file → Upload files** واسحب الملفات، أو اطلب مني أرفعه لك لو ربطت GitHub).
3. ⚠️ **متترفعش** ملفات `upload-keystore.jks` و`key.properties` و`google-services.json` وملف حساب الخدمة — دول بيروحوا في الـSecrets.

## 8) الأسرار (Secrets) في GitHub
في المستودع: **Settings → Secrets and variables → Actions → New repository secret**:

| الاسم | القيمة |
|---|---|
| `GOOGLE_SERVICES_JSON` | محتوى ملف google-services.json كامل (افتحه بـNotepad وانسخ كله) |
| `MAPS_API_KEY` | مفتاح الخرائط من الخطوة 5 |
| `ANDROID_KEYSTORE_BASE64` | محتوى ملف `upload-keystore.base64.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | كلمة السر الموجودة في `key.properties` (storePassword) |
| `FIREBASE_SERVICE_ACCOUNT` | محتوى ملف JSON من الخطوة 6 كامل |
| `FIREBASE_PROJECT_ID` | الـProject ID |
| `ADMIN_EMAIL` | بريدك اللي هتدخل بيه لوحة التحكم |
| `ADMIN_PASSWORD` | كلمة سر قوية (12 حرف على الأقل) |
| `DEMO_ADMIN_PASSWORD` | (اختياري) كلمة سر للحساب التجريبي |

## 9) نشر الباك إند ولوحة التحكم
1. في المستودع: **Actions → Deploy Firebase → Run workflow**.
2. بيشغّل 28 اختبار للسيرفر، وبعدين ينشر: Cloud Functions + قواعد الأمان + الفهارس + لوحة التحكم.
3. أول مرة بياخد 5–10 دقايق. لو ظهر خطأ إن API معين مش مفعل، الرسالة بيكون فيها رابط — افتحه واضغط Enable وأعد التشغيل.
4. لوحة التحكم هتبقى على: `https://<PROJECT_ID>.web.app`

## 10) تهيئة قاعدة البيانات وحساب المدير
**Actions → Setup database & admin → Run workflow**، شغّله بالترتيب:
1. `seed` — يضيف 14 مهنة وخدماتها، و27 محافظة بإحداثياتها، والإعدادات (عمولة 5%).
2. `admin` — ينشئ حسابك كمدير عام بالبريد وكلمة السر اللي في الأسرار.
3. (اختياري) `demo` — بيانات تجريبية منفصلة (6 صنايعية حوالين ميدان التحرير + عميل) + **حساب أدمن تجريبي** `demo-admin@mehtag-sanaye.test` بصلاحية مشرف فقط.
4. قبل الإطلاق الرسمي: `remove-demo` يمسح كل البيانات والحساب التجريبي.

بعدها ادخل لوحة التحكم → **الإعدادات** وحط:
- عنوان InstaPay (IPA) أو رقم الموبايل المرتبط بيه — ده اللي الصنايعية هيحولوا عليه العمولة.
- أرقام الدعم وواتساب الدعم ورابط Google Play.

## 11) بناء التطبيق (APK)
1. **Actions → Build Android → Run workflow** (وبيشتغل لوحده مع أي تعديل في مجلد `app/`).
2. بعد ~10–15 دقيقة افتح التشغيل → تحت **Artifacts** نزّل `mehtag-sanaye-android` — جواه:
   - `app-release.apk` — ثبّته على أي موبايل للتجربة.
   - `app-release.aab` — ده اللي بيترفع على Google Play.

### تجربة OTP من غير رسائل حقيقية
Firebase → Authentication → Sign-in method → Phone → **Phone numbers for testing**: ضيف
`+201000000001` … `+201000000007` بالكود `123456` (دي أرقام بيانات الـDemo). الأرقام دي بتشتغل من غير ما SMS يتبعت.

### سيناريوهات الاختبار المقترحة على الموبايل
1. **عميل:** سجل بالرقم ← اسمح بالموقع ← اختار "سباك" ← افتح صنايعي ← اطلب ← (من موبايل الصنايعي) اقبل ← شات ← في الطريق ← بدء ← انتهاء ← سجل 500 ← (العميل) أكّد السعر ← العمولة 25 ← قيّموا بعض.
2. **صنايعي جديد:** سجل كـ"أنا صنايعي" ← البيانات + البطاقة ← "قيد المراجعة" ← من لوحة التحكم: الصنايعية ← مراجعة ← قبول ← يظهر في بحث العملاء.
3. **طوارئ:** من العميل "🚨 محتاج صنايعي الآن" ← يوصل إشعار عاجل للصنايعية المتاحين القريبين ← أول واحد يقبل ← تابع الحالة.
4. **العمولة:** من الصنايعي "الحساب المالي" ← دفع العمولة ← رقم عملية InstaPay ← من لوحة التحكم "العمولات والمدفوعات" ← طابق وأكّد.

## 12) النشر على Google Play
1. [play.google.com/console](https://play.google.com/console) → **Create app** → الاسم "محتاج صنايعي"، اللغة الافتراضية العربية، App، Free.
2. **App integrity → App signing:** فعّل **Play App Signing** (الافتراضي). بعدها انسخ **SHA-1 و SHA-256 الخاصين بـ App signing key** وضيفهم:
   - في Firebase (الخطوة 3) — **ضروري** وإلا الدخول بـGoogle والـOTP مش هيشتغلوا من نسخة المتجر.
   - في قيود مفتاح الخرائط (الخطوة 5).
   - ثم نزّل `google-services.json` الجديد وحدّث السر `GOOGLE_SERVICES_JSON` وابنِ تاني.
3. **Store listing:** الوصف، أيقونة 512×512 (`branding/png/app-icon-512.png`)، صورة مميزة 1024×500، ولقطات شاشة (2 على الأقل).
4. **App content:** سياسة الخصوصية (لازم رابط — ممكن نعمل صفحة على نفس Hosting)، تصنيف المحتوى، الجمهور المستهدف (18+)، **Data safety** (بتجمعوا: الاسم، الموبايل، الموقع التقريبي والدقيق، الصور، الرسائل — ومشفرة أثناء النقل، والمستخدم يقدر يطلب الحذف).
5. صلاحية الموقع: التطبيق بيستخدم الموقع أثناء الاستخدام فقط (مش في الخلفية) — مش محتاج إقرار خاص.
6. **Testing → Internal testing** → ارفع `app-release.aab` وجرّب مع أصحابك أولًا، وبعدين **Production**.
7. لكل إصدار جديد: زوّد `version` في `app/pubspec.yaml` (مثلاً `1.0.1+2`) قبل البناء.

---

## قائمة كل المفاتيح والإعدادات الخارجية
| المفتاح | منين | فين بيتحط |
|---|---|---|
| google-services.json | Firebase → Android app | Secret `GOOGLE_SERVICES_JSON` |
| Web firebaseConfig | Firebase → Web app | `admin/config.js` |
| Project ID | Firebase | `.firebaserc` + Secret `FIREBASE_PROJECT_ID` |
| Maps SDK for Android key | Google Cloud Credentials | Secret `MAPS_API_KEY` |
| Service account JSON | Firebase → Service accounts | Secret `FIREBASE_SERVICE_ACCOUNT` |
| مفتاح التوقيع | ملف `upload-keystore.jks` (أرسلته لك) | Secrets `ANDROID_KEYSTORE_*` |
| SHA-1 / SHA-256 | `fingerprints.txt` + Play Console | Firebase Android app + قيود مفتاح الخرائط |
| OTP (SMS) | Firebase Phone Auth (مدمج — مفيش مزود منفصل) | تفعيل Phone + Blaze + Play Integrity API |
| Push Notifications | FCM (مدمج مع google-services.json) | مفيش مفتاح إضافي |
| Google Sign-In | Firebase Google provider + SHA-1 | مفيش مفتاح إضافي |
| InstaPay | حسابك البنكي | لوحة التحكم → الإعدادات |

## نظام الدفع والعمولة — مهم تعرفه
- العمولة بتتحسب **على السيرفر فقط** لحظة تأكيد العميل للسعر (التطبيق مايقدرش يغيرها).
- **InstaPay مالوش API عام للتحقق التلقائي**، فالنظام **مش بيعتبر أي تحويل مدفوع** إلا لما حد من الإدارة (صلاحية مالية) يطابق رقم العملية والمبلغ مع كشف الحساب ويضغط "تأكيد".
- طبقة الدفع معمولة بحيث تقدر تضيف مزود إلكتروني لاحقًا (Paymob/Fawry/Kashier) بـwebhook يؤكد تلقائيًا — راجع `functions/src/payments.js`.

## صلاحيات الإدارة
- **مدير عام (super):** كل حاجة + حذف الحسابات + إضافة مديرين.
- **مشرف (moderator):** الصنايعية، المستخدمين، الطلبات، البلاغات، التقييمات، الإشعارات، المهن، المناطق.
- **مالية (finance):** الإحصائيات، الطلبات، العمولات والمدفوعات، نسبة العمولة وبيانات InstaPay.
- إضافة مدير: الشخص يعمل حساب (أو `create-admin`)، وبعدين من **الإدارة والسجل** تحدد دوره. كل عملية إدارية بتتسجل.

## البناء على جهازك (بديل لـ GitHub)
1. ثبّت [Flutter 3.29](https://docs.flutter.dev/get-started/install) و Android Studio.
2. حط `google-services.json` في `app/android/app/`، و`upload-keystore.jks` في `app/android/app/`، و`key.properties` في `app/android/`.
3. في `app/android/local.properties` ضيف سطر: `MAPS_API_KEY=المفتاح`.
4. من مجلد `app`: `flutter pub get` ثم `flutter build apk --release`.
5. للباك إند: ثبّت Node 20 ثم `npm i -g firebase-tools` ثم من جذر المشروع `firebase login` و `firebase deploy`.

## مشاكل شائعة
| المشكلة | الحل |
|---|---|
| الـOTP مش بيوصل / خطأ `app-not-authorized` | SHA-1 و SHA-256 مش مضافين في Firebase، أو Play Integrity API مش مفعل، أو مصر مش في SMS region policy |
| الخريطة رمادية | مفتاح الخرائط غلط أو Maps SDK for Android مش مفعل أو القيود مش فيها SHA-1 الصح |
| رسالة "The query requires an index" | الفهارس لسه بتتبني (بتاخد دقايق بعد أول نشر) |
| الدخول بـGoogle بيفشل من نسخة Play | ضيف بصمة App signing key من Play Console في Firebase |
| لوحة التحكم: "ليس له صلاحية" | شغّل `admin` من Setup database أو حدد الدور من صفحة الإدارة |
| الإشعارات مش بتظهر على Android 13+ | لازم المستخدم يوافق على إذن الإشعارات أول ما يفتح التطبيق |
