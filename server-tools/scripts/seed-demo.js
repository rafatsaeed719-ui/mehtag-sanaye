'use strict';
/**
 * بيانات Demo منفصلة للاختبار فقط (كل الوثائق عليها isDemo: true).
 * تنشئ 6 صنايعية موثقين حول وسط القاهرة + عميل تجريبي، بأرقام هواتف تجريبية.
 *
 * الدخول: demo1@mehtag-sanaye.test ... demo7@mehtag-sanaye.test (demo7 = العميل)
 *
 *   node scripts/seed-demo.js           # إنشاء
 *   node scripts/seed-demo.js --remove  # حذف كل بيانات الـDemo قبل الإطلاق
 */
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();
const { FieldValue } = admin.firestore;
const geo = require('../src/lib/geo');
const { searchTokens } = require('../src/lib/validate');

const CENTER = { lat: 30.0444, lng: 31.2357 }; // ميدان التحرير
const workers = [
  ['+201000000001', 'محمد السباك (Demo)', ['plumber'], ['plumber_1', 'plumber_2'], 0.01, 0.008, 150],
  ['+201000000002', 'أحمد الكهربائي (Demo)', ['electrician'], ['electrician_1', 'electrician_2'], -0.012, 0.01, 100],
  ['+201000000003', 'محمود النجار (Demo)', ['carpenter'], ['carpenter_1'], 0.02, -0.015, 0],
  ['+201000000004', 'كريم فني التكييف (Demo)', ['ac_technician'], ['ac_technician_1', 'ac_technician_2'], -0.025, -0.02, 200],
  ['+201000000005', 'سيد النقاش (Demo)', ['painter'], ['painter_1'], 0.03, 0.025, 0],
  ['+201000000006', 'حسن سباك وكهربائي (Demo)', ['plumber', 'electrician'], ['plumber_1', 'electrician_1'], 0.005, -0.03, 120],
];
const CUSTOMER = ['+201000000007', 'عميل تجريبي (Demo)'];

// حسابات الـDemo بالبريد: demo1@mehtag-sanaye.test ... demo7 — كلمة السر من DEMO_ADMIN_PASSWORD أو Demo-123456
const DEMO_PASS = process.env.DEMO_ADMIN_PASSWORD || 'Demo-123456';
async function ensureUser(phone, name) {
  const email = `demo${phone.slice(-1)}@mehtag-sanaye.test`;
  let u = await auth.getUserByEmail(email).catch(() => null);
  if (!u) u = await auth.createUser({ email, password: DEMO_PASS, emailVerified: true, displayName: name });
  await db.doc(`phones/0${phone.slice(3)}`).set({ uid: u.uid });
  return u;
}

async function remove() {
  for (const col of ['workers', 'users', 'workerPrivate', 'wallets']) {
    const s = await db.collection(col).where('isDemo', '==', true).get();
    for (const d of s.docs) await d.ref.delete();
  }
  for (const [phone] of [...workers, CUSTOMER]) {
    const u = await auth.getUserByEmail(`demo${phone.slice(-1)}@mehtag-sanaye.test`).catch(() => null);
    if (u) await auth.deleteUser(u.uid);
    await db.doc(`phones/0${phone.slice(3)}`).delete().catch(() => {});
  }
  console.log('✅ Demo data removed.');
}

async function create() {
  for (const [phone, name, cats, svcs, dLat, dLng, fee] of workers) {
    const u = await ensureUser(phone, name);
    const lat = CENTER.lat + dLat; const lng = CENTER.lng + dLng;
    const catDocs = await Promise.all(cats.map((c) => db.doc(`categories/${c}`).get()));
    const svcDocs = await Promise.all(svcs.map((s) => db.doc(`services/${s}`).get()));
    const categoryNames = catDocs.map((c) => ({ ar: c.data().nameAr, en: c.data().nameEn }));
    const local = '0' + phone.slice(3);
    await db.doc(`users/${u.uid}`).set({
      uid: u.uid, role: 'worker', name, nameLower: name.toLowerCase(), phone: local, email: '', photoUrl: '',
      lang: 'ar', status: 'active', fcmTokens: [], flags: {}, isDemo: true,
      customerRatingAvg: 0, customerRatingCount: 0, customerRatingSum: 0, createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    await db.doc(`workers/${u.uid}`).set({
      uid: u.uid, name, nameLower: name.toLowerCase(), phone: local, photoUrl: '',
      categoryIds: cats, serviceIds: svcs, categoryNames,
      serviceNames: svcDocs.map((s) => ({ ar: s.data().nameAr, en: s.data().nameEn })),
      governorate: 'cairo', city: 'وسط البلد', area: 'التحرير',
      geo: { lat, lng }, geohash: geo.encode(lat, lng, 10),
      bio: 'حساب تجريبي للاختبار فقط.', visitFee: fee || null, whatsapp: local, callPhone: local, workImages: [],
      available: true, verificationStatus: 'approved', rejectionReason: '', idVerified: true, hasIdDoc: false,
      suspended: false, ratingCount: 0, ratingSum: 0, completedCount: 0,
      stats: { received: 0, responded: 0, responseMinutesTotal: 0, accepted: 0, cancelled: 0 },
      badges: ['verified'], searchTokens: searchTokens(name, ...categoryNames.flatMap((n) => [n.ar, n.en])),
      isDemo: true, submittedAt: FieldValue.serverTimestamp(), approvedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
  }
  const c = await ensureUser(CUSTOMER[0], CUSTOMER[1]);
  await db.doc(`users/${c.uid}`).set({
    uid: c.uid, role: 'customer', name: CUSTOMER[1], nameLower: CUSTOMER[1].toLowerCase(), phone: '0' + CUSTOMER[0].slice(3),
    email: '', photoUrl: '', lang: 'ar', status: 'active', fcmTokens: [], flags: {}, isDemo: true,
    customerRatingAvg: 0, customerRatingCount: 0, customerRatingSum: 0, createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log('✅ Demo data created: 6 workers + 1 customer (OTP for test numbers: set 123456 in Firebase console)');
}

(async () => {
  if (process.argv.includes('--remove')) await remove(); else await create();
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
