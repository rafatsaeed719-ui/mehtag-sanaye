// حسابات مؤقتة للاختبار الآلي لنسخة الويب — بتتعمل قبل الاختبار وتتمسح بعده
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();
const PASS = process.env.TEST_PASS;
const ACC = {
  customer: { email: 'webtest-customer@mehtag-sanaye.test', role: 'customer', name: 'اختبار عميل', phone: '01099999991' },
  worker: { email: 'webtest-worker@mehtag-sanaye.test', role: 'worker', name: 'اختبار صنايعي', phone: '01099999992' },
  admin: { email: 'webtest-admin@mehtag-sanaye.test', role: null },
};
async function create() {
  for (const [k, a] of Object.entries(ACC)) {
    let u = await auth.getUserByEmail(a.email).catch(() => null);
    if (u) await auth.updateUser(u.uid, { password: PASS });
    else u = await auth.createUser({ email: a.email, password: PASS, emailVerified: true });
    if (a.role) {
      await db.doc(`users/${u.uid}`).set({
        uid: u.uid, role: a.role, name: a.name, phone: a.phone, email: a.email, photoUrl: '', lang: 'ar', status: 'active',
        customerRatingSum: 0, customerRatingCount: 0, isTest: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      await db.doc(`admins/${u.uid}`).set({ email: a.email, role: 'super', active: true, test: true });
    }
    console.log('created', k);
  }
}
async function remove() {
  for (const a of Object.values(ACC)) {
    const u = await auth.getUserByEmail(a.email).catch(() => null);
    if (!u) continue;
    for (const p of [`users/${u.uid}`, `admins/${u.uid}`, `workers/${u.uid}`, `workerPrivate/${u.uid}`, `adminRequests/${u.uid}`]) await db.doc(p).delete().catch(() => {});
    const n = await db.collection(`notifications/${u.uid}/items`).get();
    for (const d of n.docs) await d.ref.delete();
    await auth.deleteUser(u.uid);
  }
  console.log('removed test accounts');
}
(process.argv[2] === 'remove' ? remove() : create()).catch((e) => { console.error(e); process.exit(1); });
