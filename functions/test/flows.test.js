'use strict';
/**
 * اختبار المسارات الكاملة على كود الـCloud Functions الحقيقي (مع Firebase وهمي في الذاكرة):
 *  1) عميل يسجل → يبحث → يطلب → الصنايعي يقبل → شات → السعر → 5% → تقييم الطرفين → دفع العمولة
 *  2) صنايعي جديد → تسجيل + بطاقة → مراجعة الأدمن → قبول → ظهور للعملاء
 *  3) طلب طوارئ → إشعار القريبين المتاحين → أول صنايعي يقبل → متابعة الحالة
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const { install } = require('./fake-firebase');

const F = install();
const fns = require('../index.js');
const support = require('../src/support');
const geo = require('../src/lib/geo');

const { db, auth, messaging } = F;
const CAIRO = { lat: 30.0444, lng: 31.2357 };
const STORAGE = 'https://firebasestorage.googleapis.com/v0/b/x/o/';

// ---------------------------------------------------------------- helpers
const as = (uid, token = {}) => ({ auth: { uid, token } });
const call = (fn, uid, data, token) => fn({ ...as(uid, token), data });
const admin = (uid = 'admin1') => ({ uid, token: { admin: true, adminRole: 'super', email: 'a@x.com' } });
const callAdmin = (fn, data) => fn({ auth: admin(), data });
const get = async (p) => (await db.doc(p).get()).data();
async function expectError(promise, code) {
  await assert.rejects(promise, (e) => {
    const text = `${e.code} ${e.message} ${JSON.stringify(e.details || {})}`;
    assert.ok(text.includes(code), `expected "${code}" but got: ${text}`);
    return true;
  });
}

async function seed() {
  await db.doc('categories/plumber').set({ nameAr: 'سباك', nameEn: 'Plumber', active: true, order: 0 });
  await db.doc('categories/electrician').set({ nameAr: 'كهربائي', nameEn: 'Electrician', active: true, order: 1 });
  await db.doc('services/plumber_1').set({ categoryId: 'plumber', nameAr: 'تسريب مياه', nameEn: 'Water leak', active: true, order: 0 });
  await db.doc('services/electrician_1').set({ categoryId: 'electrician', nameAr: 'عطل كهرباء', nameEn: 'Fault', active: true, order: 0 });
  await db.doc('settings/app').set({ commissionRate: 0.05, overdueDays: 7, emergencyRadiusKm: 15, openRequestRadiusKm: 25, maxNotifiedWorkers: 30 });
}

async function signup(uid, phone, role, name) {
  auth._add({ uid, phoneNumber: phone, providerData: [{ providerId: 'phone' }] });
  const r = await call(fns.completeSignup, uid, { role, name, lang: 'ar' });
  await db.doc(`users/${uid}`).update({ fcmTokens: [`token_${uid}`] });
  return r;
}

async function makeApprovedWorker(uid, phone, name, cat, dLat, dLng, { available = true, idNumber } = {}) {
  await signup(uid, phone, 'worker', name);
  await call(fns.submitWorkerApplication, uid, {
    name, categoryIds: [cat], serviceIds: [`${cat}_1`], governorate: 'cairo', city: 'وسط البلد', area: '',
    lat: CAIRO.lat + dLat, lng: CAIRO.lng + dLng, bio: 'خبرة 10 سنين', visitFee: 100,
    whatsapp: phone.replace('+2', ''), callPhone: phone.replace('+2', ''), photoUrl: STORAGE + 'p.jpg', workImages: [],
    ...(idNumber ? { idNumber, idFrontPath: `idDocs/${uid}/front.jpg` } : {}),
  });
  await callAdmin(fns.adminReviewWorker, { workerId: uid, decision: 'approve', idVerified: !!idNumber });
  if (!available) await db.doc(`workers/${uid}`).update({ available: false });
}

/** نفس استعلام البحث اللي بيعمله التطبيق (lib/data/repos/worker_repo.dart) */
async function searchWorkers(lat, lng, radiusKm, categoryId) {
  const out = new Map();
  for (const [s, e] of geo.queryBounds(lat, lng, radiusKm)) {
    const snap = await db.collection('workers').where('verificationStatus', '==', 'approved').where('suspended', '==', false)
      .where('categoryIds', 'array-contains', categoryId).orderBy('geohash').startAt(s).endAt(e).limit(120).get();
    snap.forEach((d) => {
      const w = d.data();
      const km = geo.distanceKm(lat, lng, w.geo.lat, w.geo.lng);
      if (km <= radiusKm) out.set(d.id, { id: d.id, km });
    });
  }
  return [...out.values()].sort((a, b) => a.km - b.km);
}

test.before(seed);

// =================================================================== 2) تسجيل صنايعي ومراجعة
test('flow 2: new worker → register + ID → pending (hidden) → admin approves → visible', async () => {
  await signup('w1', '+201011111111', 'worker', 'محمد السباك');
  await call(fns.submitWorkerApplication, 'w1', {
    name: 'محمد السباك', categoryIds: ['plumber'], serviceIds: ['plumber_1'], governorate: 'cairo', city: 'وسط البلد',
    lat: CAIRO.lat + 0.01, lng: CAIRO.lng + 0.01, bio: 'سباك محترف', visitFee: 150,
    whatsapp: '01011111111', callPhone: '01011111111', photoUrl: STORAGE + 'a.jpg', workImages: [STORAGE + 'w1.jpg'],
    idNumber: '29001011234567', idFrontPath: 'idDocs/w1/front.jpg', idBackPath: 'idDocs/w1/back.jpg',
  });
  let w = await get('workers/w1');
  assert.equal(w.verificationStatus, 'pending');
  assert.equal(w.hasIdDoc, true);
  assert.equal(w.geohash, geo.encode(CAIRO.lat + 0.01, CAIRO.lng + 0.01, 10));

  // الرقم القومي مشفر — لا يظهر بشكل صريح في أي وثيقة
  const priv = await get('workerPrivate/w1');
  assert.equal(priv.idLast4, '4567');
  assert.ok(!JSON.stringify([...db.store.values()]).includes('29001011234567'), 'national ID stored in plain text!');

  // غير ظاهر للعملاء قبل الموافقة
  assert.equal((await searchWorkers(CAIRO.lat, CAIRO.lng, 10, 'plumber')).length, 0);

  // نفس الرقم القومي لصنايعي آخر → مرفوض
  await signup('w_dup', '+201099999999', 'worker', 'منتحل');
  await expectError(call(fns.submitWorkerApplication, 'w_dup', {
    name: 'منتحل', categoryIds: ['plumber'], governorate: 'cairo', city: 'x', lat: CAIRO.lat, lng: CAIRO.lng,
    idNumber: '29001011234567', idFrontPath: 'idDocs/w_dup/f.jpg',
  }), 'national-id-in-use');

  // الأدمن يرفض بسبب ← الصنايعي يعدل ويعيد التقديم ← الأدمن يقبل
  await callAdmin(fns.adminReviewWorker, { workerId: 'w1', decision: 'reject', reason: 'الصورة غير واضحة' });
  w = await get('workers/w1');
  assert.equal(w.verificationStatus, 'rejected');
  assert.equal(w.rejectionReason, 'الصورة غير واضحة');
  await call(fns.submitWorkerApplication, 'w1', {
    name: 'محمد السباك', categoryIds: ['plumber'], serviceIds: ['plumber_1'], governorate: 'cairo', city: 'وسط البلد',
    lat: CAIRO.lat + 0.01, lng: CAIRO.lng + 0.01, photoUrl: STORAGE + 'b.jpg',
    idNumber: '29001011234567', idFrontPath: 'idDocs/w1/front2.jpg',
  });
  assert.equal((await get('workers/w1')).verificationStatus, 'pending');

  // غير الأدمن لا يستطيع الموافقة
  await expectError(fns.adminReviewWorker({ auth: { uid: 'w1', token: {} }, data: { workerId: 'w1', decision: 'approve' } }), 'admin-only');

  await callAdmin(fns.adminReviewWorker, { workerId: 'w1', decision: 'approve', idVerified: true });
  w = await get('workers/w1');
  assert.equal(w.verificationStatus, 'approved');
  assert.deepEqual(w.badges, ['verified']);
  const found = await searchWorkers(CAIRO.lat, CAIRO.lng, 10, 'plumber');
  assert.deepEqual(found.map((x) => x.id), ['w1']);
  // إشعار "تم توثيق حسابك"
  const notes = await db.collection('notifications/w1/items').get();
  assert.ok(notes.docs.some((d) => d.data().type === 'account_approved'));
});

// =================================================================== 1) المسار الكامل للعميل
test('flow 1: customer → search → request → accept → chat → price → 5% → reviews → commission paid', async () => {
  await signup('c1', '+201222222222', 'customer', 'أحمد العميل');
  // رقم الهاتف مطلوب
  auth._add({ uid: 'nophone', providerData: [{ providerId: 'google.com' }] });
  await expectError(call(fns.completeSignup, 'nophone', { role: 'customer', name: 'x' }), 'phone-required');

  const found = await searchWorkers(CAIRO.lat, CAIRO.lng, 25, 'plumber');
  assert.equal(found[0].id, 'w1');

  const { requestId } = await call(fns.createRequest, 'c1', {
    workerId: 'w1', categoryId: 'plumber', serviceId: 'plumber_1', description: 'تسريب تحت الحوض',
    images: [STORAGE + 'leak.jpg'], lat: CAIRO.lat, lng: CAIRO.lng, address: 'التحرير', governorate: 'cairo',
    scheduledAt: Date.now() + 3600e3,
  });
  let r = await get(`requests/${requestId}`);
  assert.equal(r.status, 'new');
  assert.equal(r.customerPhone, null, 'customer phone must be hidden before acceptance');
  assert.ok((await db.collection('notifications/w1/items').get()).docs.some((d) => d.data().type === 'new_request'));

  // طرف غريب لا يستطيع التحكم
  await signup('c_other', '+201233333333', 'customer', 'غريب');
  await expectError(call(fns.requestAction, 'c_other', { requestId, action: 'cancel', payload: { reason: 'other', note: 'xxx' } }), 'not-participant');
  // العميل لا يستطيع القبول بدل الصنايعي
  await expectError(call(fns.requestAction, 'c1', { requestId, action: 'accept' }), 'wrong-role');

  // الصنايعي يقترح موعد ← العميل يوافق
  const proposed = Date.now() + 7200e3;
  await call(fns.requestAction, 'w1', { requestId, action: 'propose_time', payload: { proposedAt: proposed } });
  assert.equal((await get(`requests/${requestId}`)).status, 'proposed');
  await call(fns.requestAction, 'c1', { requestId, action: 'accept_proposal' });
  r = await get(`requests/${requestId}`);
  assert.equal(r.status, 'confirmed');
  assert.equal(r.scheduledAt.toMillis(), proposed);

  // شات مرتبط بالطلب + إشعار للطرف الآخر
  const msgRef = await db.collection(`requests/${requestId}/messages`).add({ senderId: 'c1', type: 'text', text: 'هستناك', createdAt: F.Timestamp.now() });
  await support.onChatMessage({ data: await msgRef.get(), params: { requestId, messageId: msgRef.id } });
  r = await get(`requests/${requestId}`);
  assert.equal(r.unread.w1, 1);
  await call(fns.markChatRead, 'w1', { requestId });
  assert.equal((await get(`requests/${requestId}`)).unread.w1, 0);

  for (const a of ['on_the_way', 'start', 'complete']) await call(fns.requestAction, 'w1', { requestId, action: a });
  assert.equal((await get(`requests/${requestId}`)).status, 'completed');

  // السعر: الصنايعي يسجل 500 → العميل يعترض → يسجل 500 من جديد → العميل يأكد
  await call(fns.requestAction, 'w1', { requestId, action: 'set_price', payload: { price: 600 } });
  await call(fns.requestAction, 'c1', { requestId, action: 'dispute_price' });
  assert.equal((await get(`requests/${requestId}`)).status, 'completed');
  await call(fns.requestAction, 'w1', { requestId, action: 'set_price', payload: { price: 500 } });
  // محاولة التلاعب: العميل لا يستطيع تغيير السعر، والصنايعي لا يستطيع تأكيده بنفسه
  await expectError(call(fns.requestAction, 'c1', { requestId, action: 'set_price', payload: { price: 1 } }), 'wrong-role');
  await expectError(call(fns.requestAction, 'w1', { requestId, action: 'confirm_price' }), 'wrong-role');
  await call(fns.requestAction, 'c1', { requestId, action: 'confirm_price' });

  r = await get(`requests/${requestId}`);
  assert.equal(r.status, 'price_agreed');
  assert.equal(r.agreedPrice, 500);
  assert.equal(r.commissionAmount, 25, '5% of 500 must be 25 — computed on server');
  const com = await get(`commissions/${requestId}`);
  assert.equal(com.amount, 25);
  assert.equal(com.status, 'due');
  let wallet = await get('wallets/w1');
  assert.equal(wallet.totalServices, 500);
  assert.equal(wallet.totalCommission, 25);
  assert.equal(wallet.due, 25);
  assert.equal((await get('workers/w1')).completedCount, 1);

  // التقييم: الطرفان مرة واحدة فقط
  await call(fns.submitReview, 'c1', { requestId, stars: 5, comment: 'ممتاز وفي الميعاد' });
  await call(fns.submitReview, 'w1', { requestId, stars: 4 });
  await expectError(call(fns.submitReview, 'c1', { requestId, stars: 1, comment: 'تاني' }), 'already-reviewed');
  const w = await get('workers/w1');
  assert.equal(w.ratingAvg, 5);
  assert.equal(w.ratingCount, 1);
  assert.equal((await get('users/c1')).customerRatingAvg, 4);

  // الدفع: الصنايعي يرسل إثبات InstaPay → المبلغ يُحسب على السيرفر → الأدمن يؤكد
  const pay = await call(fns.submitPayment, 'w1', { commissionIds: [requestId], reference: 'IPN123456' });
  assert.equal(pay.amount, 25);
  assert.equal((await get(`commissions/${requestId}`)).status, 'claimed');
  await expectError(call(fns.submitPayment, 'w1', { commissionIds: [requestId], reference: 'AGAIN123' }), 'commission-not-due');
  await callAdmin(fns.adminReviewPayment, { paymentId: pay.paymentId, decision: 'confirm' });
  assert.equal((await get(`commissions/${requestId}`)).status, 'paid');
  r = await get(`requests/${requestId}`);
  assert.equal(r.status, 'commission_paid');
  assert.equal(r.commissionStatus, 'paid');
  wallet = await get('wallets/w1');
  assert.equal(wallet.paid, 25);
  assert.equal(wallet.due, 0);

  // سجل كامل للطلب
  const hist = (await db.collection(`requests/${requestId}/history`).get()).docs.map((d) => d.data().action);
  for (const a of ['create', 'propose_time', 'accept_proposal', 'on_the_way', 'start', 'complete', 'set_price', 'dispute_price', 'confirm_price', 'review', 'commission_paid']) {
    assert.ok(hist.includes(a), `history missing ${a}`);
  }
  // إحصائيات اليوم
  const stats = (await db.collection('dailyStats').get()).docs[0].data();
  assert.equal(stats.commissionTotal, 25);
  assert.equal(stats.byCategory.plumber >= 1, true);
});

// =================================================================== 3) الطوارئ
test('flow 3: emergency → nearby available workers notified → first accepts → status tracking', async () => {
  await makeApprovedWorker('w2', '+201044444444', 'سباك قريب', 'plumber', 0.005, 0.005);
  await makeApprovedWorker('w3', '+201055555555', 'سباك تاني', 'plumber', -0.01, 0.0);
  await makeApprovedWorker('w4', '+201066666666', 'سباك مش متاح', 'plumber', 0.002, 0.0, { available: false });
  await makeApprovedWorker('w5', '+201077777777', 'كهربائي', 'electrician', 0.001, 0.001);
  await makeApprovedWorker('w6', '+201088888888', 'سباك بعيد', 'plumber', 1.0, 1.0); // > 100 كم
  await signup('c2', '+201244444444', 'customer', 'عميل مستعجل');

  messaging.sent.length = 0;
  const res = await call(fns.createRequest, 'c2', { categoryId: 'plumber', isEmergency: true, lat: CAIRO.lat, lng: CAIRO.lng, address: 'وسط البلد' });
  const r0 = await get(`requests/${res.requestId}`);
  assert.equal(r0.open, true);
  assert.equal(r0.workerId, null);
  // w1, w2, w3 سباكين متاحين وقريبين — بدون w4 (غير متاح)، w5 (مهنة أخرى)، w6 (بعيد)
  assert.deepEqual([...r0.notifiedWorkerIds].sort(), ['w1', 'w2', 'w3']);
  const urgent = messaging.sent.filter((m) => m.android?.notification?.channelId === 'urgent');
  assert.equal(urgent.length, 3);

  // الطلب يظهر في "طلبات قريبة منك" لكل صنايعي سباك قريب (نفس استعلام التطبيق)
  const bounds = geo.queryBounds(CAIRO.lat + 0.005, CAIRO.lng + 0.005, 25);
  let visible = false;
  for (const [s, e] of bounds) {
    const q = await db.collection('requests').where('open', '==', true).where('categoryId', 'in', ['plumber'])
      .orderBy('geohash').startAt(s).endAt(e).get();
    if (q.docs.some((d) => d.id === res.requestId)) visible = true;
  }
  assert.ok(visible);

  // كهربائي لا يستطيع قبول طلب سباكة
  await expectError(call(fns.requestAction, 'w5', { requestId: res.requestId, action: 'accept' }), 'not-participant');
  // أول صنايعي يقبل
  await call(fns.requestAction, 'w2', { requestId: res.requestId, action: 'accept' });
  // الثاني يتأخر — مرفوض
  await expectError(call(fns.requestAction, 'w3', { requestId: res.requestId, action: 'accept' }), 'not-participant');
  let r = await get(`requests/${res.requestId}`);
  assert.equal(r.workerId, 'w2');
  assert.equal(r.open, false);
  assert.equal(r.customerPhone, '01244444444', 'phone revealed to the assigned worker after acceptance');
  assert.ok((await db.collection('notifications/c2/items').get()).docs.some((d) => d.data().type === 'open_request_taken'));

  await call(fns.requestAction, 'w2', { requestId: res.requestId, action: 'on_the_way' });
  assert.equal((await get(`requests/${res.requestId}`)).status, 'on_the_way');
  // العميل يلغي مع سبب
  await expectError(call(fns.requestAction, 'c2', { requestId: res.requestId, action: 'cancel', payload: {} }), 'invalid-reason');
  await call(fns.requestAction, 'c2', { requestId: res.requestId, action: 'cancel', payload: { reason: 'worker_late' } });
  r = await get(`requests/${res.requestId}`);
  assert.equal(r.status, 'cancelled');
  assert.equal(r.cancelReason, 'worker_late');
  assert.equal(r.cancelledBy, 'customer');
  assert.ok((await db.collection('notifications/w2/items').get()).docs.some((d) => d.data().type === 'request_cancelled'));
});

// =================================================================== أمان إضافي
test('security: rate limiting, banned users, duplicate phone, sensitive edits need review', async () => {
  await signup('c3', '+201255555555', 'customer', 'سبام');
  let blocked = false;
  for (let i = 0; i < 5; i++) {
    try { await call(fns.createRequest, 'c3', { categoryId: 'plumber', isEmergency: true, lat: CAIRO.lat, lng: CAIRO.lng }); } catch (e) { if (String(e.message).includes('rate-limited')) blocked = true; }
  }
  assert.ok(blocked, 'emergency requests must be rate limited (3/hour)');

  // الحظر
  await callAdmin(fns.adminSetUserStatus, { uid: 'c3', status: 'banned', reason: 'سبام' });
  await expectError(call(fns.createRequest, 'c3', { categoryId: 'plumber', isEmergency: true, lat: CAIRO.lat, lng: CAIRO.lng }), 'account-banned');
  assert.equal((await auth.getUser('c3')).disabled, true);

  // ملف بنفس الرقم (حساب قديم) مرفوض
  auth._add({ uid: 'c3_new', phoneNumber: '+201255555555', providerData: [] });
  await expectError(call(fns.completeSignup, 'c3_new', { role: 'customer', name: 'تاني' }), 'phone-in-use');

  // تعديل المهنة بعد التوثيق يحتاج مراجعة ولا يتغير فورًا
  await call(fns.requestWorkerChange, 'w2', { categoryIds: ['plumber', 'electrician'] });
  assert.deepEqual((await get('workers/w2')).categoryIds, ['plumber']);
  const ch = (await db.collection('workerChangeRequests').where('workerId', '==', 'w2').get()).docs[0];
  await callAdmin(fns.adminReviewChange, { changeId: ch.id, decision: 'approve' });
  assert.deepEqual((await get('workers/w2')).categoryIds, ['plumber', 'electrician']);

  // تغيير نسبة العمولة ينعكس على الطلبات الجديدة فقط
  await callAdmin(fns.adminUpdateSettings, { commissionRate: 0.1 });
  assert.equal((await get('settings/public')).commissionRate, 0.1);
  await expectError(callAdmin(fns.adminUpdateSettings, { commissionRate: 0.9 }), 'invalid-rate');
  await callAdmin(fns.adminUpdateSettings, { commissionRate: 0.05 });
});

test('daily maintenance marks overdue commissions and lifts expired bans', async () => {
  await signup('c4', '+201266666666', 'customer', 'عميل');
  const { requestId } = await call(fns.createRequest, 'c4', { workerId: 'w3', categoryId: 'plumber', description: 'تسليك حوض', lat: CAIRO.lat, lng: CAIRO.lng, scheduledAt: Date.now() + 3600e3 });
  for (const a of ['accept', 'start', 'complete']) await call(fns.requestAction, 'w3', { requestId, action: a });
  await call(fns.requestAction, 'w3', { requestId, action: 'set_price', payload: { price: 333.33 } });
  await call(fns.requestAction, 'c4', { requestId, action: 'confirm_price' });
  assert.equal((await get(`commissions/${requestId}`)).amount, 16.67);
  // نرجّع تاريخ العمولة 10 أيام
  await db.doc(`commissions/${requestId}`).update({ createdAt: F.Timestamp.fromMillis(Date.now() - 10 * 86400e3) });
  // حظر مؤقت منتهي
  await db.doc('users/c4').update({ status: 'banned', bannedUntil: F.Timestamp.fromMillis(Date.now() - 1000) });

  await fns.dailyMaintenance();
  assert.equal((await get('wallets/w3')).overdue, 16.67);
  assert.ok((await db.collection('notifications/w3/items').get()).docs.some((d) => d.data().type === 'commission_overdue'));
  assert.equal((await get('users/c4')).status, 'active');
});
