'use strict';
const { onCall } = require('firebase-functions/v2/https');
const { db, auth, FieldValue, HttpsError, wrap, rateLimit } = require('./common');
const v = require('./lib/validate');

/**
 * يُستدعى بعد تسجيل الدخول (رقم الهاتف + OTP، أو Google ثم ربط رقم الهاتف).
 * Firebase Auth نفسه يمنع استخدام نفس رقم الهاتف في حسابين، وهنا نتأكد أن
 * الحساب لديه رقم هاتف موثّق قبل إنشاء الملف.
 */
exports.completeSignup = onCall(wrap(async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'login-required');
  const uid = req.auth.uid;
  await rateLimit(uid, 'signup', 10, 3600);

  const record = await auth.getUser(uid);
  if (!record.phoneNumber) throw new HttpsError('failed-precondition', 'phone-required');

  const ref = db.doc(`users/${uid}`);
  const existing = await ref.get();
  if (existing.exists) {
    // نوع الحساب لا يتغير بعد إنشائه
    return { created: false, role: existing.data().role, status: existing.data().status };
  }

  const role = v.oneOf(req.data.role, 'role', ['customer', 'worker']);
  const name = v.str(req.data.name, 'name', { min: 2, max: 60 });
  const lang = ['ar', 'en'].includes(req.data.lang) ? req.data.lang : 'ar';
  const phone = v.normalizeEgPhone(record.phoneNumber);

  // حماية إضافية: لا يوجد ملف آخر بنفس الرقم (مثلاً حساب قديم محذوف من Auth)
  const dup = await db.collection('users').where('phone', '==', phone).limit(1).get();
  if (!dup.empty) throw new HttpsError('already-exists', 'phone-in-use');

  const googleLinked = record.providerData.some((p) => p.providerId === 'google.com');
  await ref.set({
    uid,
    role,
    name,
    nameLower: name.toLowerCase(),
    phone,
    email: record.email || '',
    photoUrl: record.photoURL || '',
    lang,
    status: 'active',
    providers: record.providerData.map((p) => p.providerId),
    googleLinked,
    fcmTokens: [],
    customerRatingAvg: 0,
    customerRatingCount: 0,
    customerRatingSum: 0,
    flags: {},
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await auth.setCustomUserClaims(uid, { ...(record.customClaims || {}), role });
  return { created: true, role, status: 'active' };
}));

/**
 * تسجيل الدخول + اكتشاف السلوك غير الطبيعي:
 *  - نفس الجهاز يستخدم حسابات كثيرة → تنبيه للإدارة (حسابات مكررة/وهمية)
 *  - دخول من أجهزة كثيرة مختلفة خلال يوم → تنبيه
 */
exports.recordLogin = onCall(wrap(async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'login-required');
  const uid = req.auth.uid;
  await rateLimit(uid, 'login', 30, 3600);
  const deviceId = v.str(req.data.deviceId, 'deviceId', { min: 6, max: 100 });
  const platform = v.str(req.data.platform || 'android', 'platform', { max: 20 });
  const appVersion = v.str(req.data.appVersion || '', 'appVersion', { max: 20, required: false });

  await db.collection('loginEvents').add({
    uid, deviceId, platform, appVersion,
    createdAt: FieldValue.serverTimestamp(),
  });

  const userRef = db.doc(`users/${uid}`);
  const userSnap = await userRef.get();
  if (!userSnap.exists) return { ok: true };

  await userRef.update({
    lastLoginAt: FieldValue.serverTimestamp(),
    devices: FieldValue.arrayUnion(deviceId),
  });

  // كم حساب آخر استخدم نفس الجهاز؟
  const sameDevice = await db.collection('users').where('devices', 'array-contains', deviceId).limit(6).get();
  const others = sameDevice.docs.map((d) => d.id).filter((id) => id !== uid);
  if (others.length >= 2) {
    await userRef.update({ 'flags.sharedDevice': true });
    await db.doc(`adminAlerts/device_${deviceId.slice(0, 60)}`).set({
      type: 'shared_device',
      deviceId,
      uids: [uid, ...others],
      resolved: false,
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  const dayAgo = new Date(Date.now() - 24 * 3600 * 1000);
  const recent = await db.collection('loginEvents').where('uid', '==', uid).where('createdAt', '>=', dayAgo).limit(50).get();
  const distinct = new Set(recent.docs.map((d) => d.data().deviceId));
  if (distinct.size >= 4) {
    await userRef.update({ 'flags.manyDevices': true });
    await db.doc(`adminAlerts/devices_${uid}`).set({
      type: 'many_devices', uid, count: distinct.size, resolved: false,
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  return { ok: true };
}));
