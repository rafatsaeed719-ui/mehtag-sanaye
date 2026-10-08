# قاعدة البيانات — Cloud Firestore

Firestore قاعدة NoSQL؛ كل "جدول" من المطلوب أصبح **Collection**. العلاقات بالمعرّفات (`customerId`, `workerId`, `requestId`...)، والفهارس المركبة كلها في `firestore.indexes.json` (37 فهرس) وتُنشر تلقائيًا.

| الجدول المطلوب | Collection | ملاحظات |
|---|---|---|
| Users / Customers | `users/{uid}` | العميل = `role: customer`. تقييم العميل الداخلي `customerRatingAvg` |
| Workers | `workers/{uid}` | الملف العام. لا يظهر إلا `verificationStatus == approved && suspended == false` |
| WorkerSkills | داخل `workers`: `categoryIds[]`, `serviceIds[]` | للبحث بـ `array-contains` |
| Categories / Services | `categories/{id}`, `services/{id}` | اسم عربي/إنجليزي + أيقونة + `active` |
| Locations | `locations/{id}` | محافظة ← مركز/مدينة ← منطقة/قرية (`parentId`) + إحداثيات |
| WorkerDocuments | `workerPrivate/{uid}` + Storage `idDocs/{uid}/` | الرقم القومي **مشفر AES-256-GCM** + بصمة HMAC لمنع التكرار في `nationalIds/{hash}` |
| (تعديلات حساسة) | `workerChangeRequests/{id}` | المهنة/الخدمات/الاسم/الهوية تنتظر موافقة الإدارة |
| WorkerImages | `workers.workImages[]` + Storage `workers/{uid}/works/` | |
| Favorites | `users/{uid}/favorites/{workerId}` | |
| ServiceRequests + Bookings | `requests/{id}` | الطلب والحجز وثيقة واحدة: `scheduledAt`, `proposedAt`, `status`, `isEmergency`, `open` |
| RequestStatusHistory | `requests/{id}/history/{id}` | كل تغيير: من/إلى/بواسطة/الوقت/السبب |
| Chats / Messages | `requests/{id}/messages/{id}` | الشات مربوط بالطلب نفسه (نص/صورة/موقع) |
| Reviews | `reviews/{requestId}_{c2w|w2c}` | مرة واحدة لكل طرف لكل طلب |
| Reports | `reports/{id}` | new → reviewing → action_taken → closed |
| Notifications | `notifications/{uid}/items/{id}` | صندوق الإشعارات داخل التطبيق |
| Commissions | `commissions/{requestId}` | due → claimed → paid |
| Payments | `payments/{id}` | إثبات تحويل InstaPay: pending_review → confirmed/rejected |
| WorkerFinancialAccounts | `wallets/{workerId}` | totalServices, totalCommission, paid, due, overdue |
| Badges | `workers.badges[]` + قواعد في `settings/app.badgeRules` | |
| AdminUsers | `adminUsers/{uid}` + Custom Claims (`admin`, `adminRole`) | super / moderator / finance |
| AdminActions | `adminActions/{id}` | سجل كل عملية إدارية |
| SupportTickets | `supportTickets/{id}` | |
| (إضافي) | `dailyStats/{yyyy-mm-dd}` | إحصائيات يومية للوحة التحكم (طلبات، أرباح، حسب المهنة/المحافظة) |
| (إضافي) | `loginEvents`, `adminAlerts`, `rateLimits`, `settings/app`, `settings/public` | أمان وإعدادات |

## البحث الجغرافي
كل صنايعي وكل طلب له `geohash` (10 خانات). البحث يحسب 4–9 نطاقات geohash تغطي دائرة البحث، ويستعلم Firestore بفهرس `(verificationStatus, suspended, categoryIds, geohash)` ثم يفلتر بالمسافة الحقيقية — **لا يتم تحميل كل الصنايعية أبدًا**. الخوارزمية متطابقة في `functions/src/lib/geo.js` و`app/lib/core/utils/geo.dart` ومختبرة بـ 12,000 نقطة عشوائية.

## من يكتب ماذا (قواعد الأمان)
- **السيرفر فقط**: الحالات، السعر، العمولة، المحافظ، التقييمات والمتوسطات، التوثيق، الهوية.
- **الصنايعي مباشرة**: النبذة، الصور، سعر الكشف، الأرقام، الموقع، حالة التوفر — فقط.
- **العميل مباشرة**: الاسم، الصورة، اللغة، المفضلة.
- **الشات**: أطراف الطلب فقط، وبعد وجود صنايعي على الطلب.
- صور البطاقة: رفع من صاحبها، قراءة للإدارة فقط، وتوكن الرابط العام يُحذف فور الرفع.
