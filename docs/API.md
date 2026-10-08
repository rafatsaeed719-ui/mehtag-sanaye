# API — Cloud Functions (Callable, region `europe-west1`)

كل الدوال تتطلب تسجيل دخول Firebase، وبها **Input Validation** و**Rate Limiting** لكل مستخدم. الأخطاء ترجع بأكواد واضحة (`rate-limited`, `invalid-transition`, `national-id-in-use`...).

## الحساب
| Function | من | الوصف |
|---|---|---|
| `completeSignup {role, name, lang}` | أي مستخدم برقم موثّق | إنشاء الملف. يرفض لو مفيش رقم هاتف موثّق أو الرقم مستخدم |
| `recordLogin {deviceId, platform, appVersion}` | الكل | تسجيل الدخول + اكتشاف الحسابات المكررة (نفس الجهاز) والدخول المريب |

## الصنايعي
| `submitWorkerApplication {...}` | صنايعي | تسجيل/إعادة تقديم → `pending`. يمنع تكرار الرقم القومي |
| `requestWorkerChange {name?, categoryIds?, serviceIds?, idNumber?...}` | صنايعي موثّق | تعديل حساس ينتظر المراجعة |

## الطلبات
| `createRequest {workerId?, categoryId, serviceId?, description, images[], lat, lng, address, governorate, scheduledAt, isEmergency}` | عميل | طلب موجه / مفتوح / طوارئ. يرسل الإشعارات (العاجلة لأقرب المتاحين) |
| `requestAction {requestId, action, payload}` | أطراف الطلب | `accept`, `reject`, `propose_time{proposedAt}`, `accept_proposal`, `on_the_way`, `start`, `complete`, `set_price{price}`, `confirm_price`, `dispute_price`, `cancel{reason, note}` — العمولة تُحسب هنا على السيرفر عند `confirm_price` |
| `markChatRead {requestId}` | أطراف الطلب | تصفير غير المقروء |

## التقييم والبلاغات والدعم
| `submitReview {requestId, stars, comment}` | أطراف الطلب | مرة واحدة لكل طرف بعد الانتهاء |
| `submitReport {type, description, imagePaths[], requestId? | againstId?}` | الكل | |
| `submitSupportTicket {kind, subject, message}` | الكل | |

## المدفوعات
| `getPaymentInstructions` | صنايعي | بيانات InstaPay من الإعدادات |
| `submitPayment {commissionIds[], reference, senderAccount?, receiptPath?}` | صنايعي | المبلغ يُحسب على السيرفر من العمولات |

## الإدارة (Custom Claims: `admin` + `adminRole`)
| Function | الدور |
|---|---|
| `adminReviewWorker {workerId, decision: approve|reject|pending, reason, idVerified}` | moderator |
| `adminReviewChange {changeId, decision, reason, idVerified}` | moderator |
| `adminGetWorkerPrivate {workerId}` (يفك تشفير الرقم القومي ويُسجَّل) | moderator |
| `adminSetUserStatus {uid, status: active|suspended|banned, reason, until?}` | moderator |
| `adminUpdateUser {uid, name?, adminNote?}` | moderator |
| `adminDeleteUser {uid, reason, force?}` | super |
| `adminReviewPayment {paymentId, decision: confirm|reject, note}` | finance |
| `adminUpdateSettings {commissionRate, overdueDays, instapayHandle, instapayPhone, emergencyRadiusKm, ...}` | finance / super |
| `adminSetReviewHidden {reviewId, hidden}` | moderator |
| `adminUpdateReport {reportId, status, adminNote, actionTaken, category}` | moderator |
| `adminBroadcast {target: all|customers|workers|category|governorate|user, value, titleAr, bodyAr, titleEn, bodyEn}` | moderator |
| `adminSetAdminRole {email, role: super|moderator|finance|none}` | super |

## Triggers ومهام مجدولة
- `onChatMessage` — إشعار بالرسالة الجديدة + عداد غير المقروء.
- `stripIdDocTokens` — يحذف رابط التحميل العام لصور البطاقة.
- `dailyMaintenance` (3 ص بتوقيت القاهرة) — العمولات المتأخرة + تذكير، إعادة حساب الشارات، رفع الحظر المؤقت المنتهي.
