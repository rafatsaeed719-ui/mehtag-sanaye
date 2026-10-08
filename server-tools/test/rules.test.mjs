// اختبارات قواعد الأمان على محاكي Firestore الحقيقي (تشتغل في GitHub Actions)
//   npx firebase emulators:exec --only firestore "node --test test/rules.test.mjs"
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, updateDoc, writeBatch, serverTimestamp, Timestamp, collection, addDoc, increment, query, where, getDocs,
} from 'firebase/firestore';

const PROJECT = 'demo-mehtag';
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); await seed(); });

const CAIRO = { lat: 30.0444, lng: 31.2357 };
const db = (uid, token = {}) => (uid ? env.authenticatedContext(uid, token).firestore() : env.unauthenticatedContext().firestore());

async function seed() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const a = ctx.firestore();
    await setDoc(doc(a, 'settings/public'), { commissionRate: 0.05 });
    await setDoc(doc(a, 'categories/plumber'), { nameAr: 'سباك', nameEn: 'Plumber', active: true });
    // عميل
    await setDoc(doc(a, 'users/c1'), { uid: 'c1', role: 'customer', name: 'عميل', phone: '01011111111', status: 'active', customerRatingSum: 0, customerRatingCount: 0 });
    await setDoc(doc(a, 'phones/01011111111'), { uid: 'c1' });
    // صنايعي موثق
    await setDoc(doc(a, 'users/w1'), { uid: 'w1', role: 'worker', name: 'صنايعي', phone: '01022222222', status: 'active', customerRatingSum: 0, customerRatingCount: 0 });
    await setDoc(doc(a, 'workers/w1'), worker('w1', '01022222222', 'approved'));
    // صنايعي تاني موثق
    await setDoc(doc(a, 'users/w2'), { uid: 'w2', role: 'worker', name: 'صنايعي ٢', phone: '01033333333', status: 'active', customerRatingSum: 0, customerRatingCount: 0 });
    await setDoc(doc(a, 'workers/w2'), worker('w2', '01033333333', 'approved'));
    // مدير
    await setDoc(doc(a, 'admins/adm'), { email: 'a@x.com', role: 'super', active: true });
  });
}

function worker(uid, phone, status) {
  return {
    uid, name: 'صنايعي ' + uid, phone, categoryIds: ['plumber'], serviceIds: [], geo: { lat: CAIRO.lat + 0.01, lng: CAIRO.lng },
    geohash: 'stq4', bio: '', workImages: [], visitFee: 100, available: true, verificationStatus: status,
    idVerified: false, suspended: false, ratingSum: 0, ratingCount: 0, completedCount: 0,
  };
}

function newRequest(extra = {}) {
  return {
    customerId: 'c1', customerName: 'عميل', customerPhone: null, workerId: 'w1', categoryId: 'plumber',
    description: 'تسريب مياه', images: [], location: { lat: CAIRO.lat, lng: CAIRO.lng, address: '' }, geohash: 'stq4',
    scheduledAt: Timestamp.fromMillis(Date.now() + 3600e3), proposedAt: null, isEmergency: false, open: false,
    status: 'new', agreedPrice: null, commissionRate: null, commissionAmount: null, commissionStatus: 'none',
    customerReviewed: false, workerReviewed: false, notifiedWorkerIds: [],
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra,
  };
}

async function createRequest(id = 'r1', extra = {}, uid = 'c1') {
  const f = db(uid);
  const b = writeBatch(f);
  b.set(doc(f, `requests/${id}`), newRequest(extra));
  b.update(doc(f, `users/${uid}`), { lastRequestAt: serverTimestamp(), ...(extra.isEmergency ? { lastEmergencyAt: serverTimestamp() } : {}) });
  return b.commit();
}

async function setStatus(id, data) {
  await env.withSecurityRulesDisabled(async (ctx) => updateDoc(doc(ctx.firestore(), `requests/${id}`), data));
}

// ------------------------------------------------------------------ التسجيل
test('signup: one account per phone number', async () => {
  const f = db('u9');
  const b = writeBatch(f);
  b.set(doc(f, 'phones/01099999999'), { uid: 'u9' });
  b.set(doc(f, 'users/u9'), { uid: 'u9', role: 'customer', name: 'جديد', phone: '01099999999', status: 'active', customerRatingSum: 0, customerRatingCount: 0 });
  await assertSucceeds(b.commit());

  const g = db('u10');
  const b2 = writeBatch(g);
  b2.set(doc(g, 'phones/01099999999'), { uid: 'u10' });
  b2.set(doc(g, 'users/u10'), { uid: 'u10', role: 'customer', name: 'منتحل', phone: '01099999999', status: 'active', customerRatingSum: 0, customerRatingCount: 0 });
  await assertFails(b2.commit());
});

test('signup: cannot self-assign admin fields or bad status', async () => {
  const f = db('u11');
  const b = writeBatch(f);
  b.set(doc(f, 'phones/01088888888'), { uid: 'u11' });
  b.set(doc(f, 'users/u11'), { uid: 'u11', role: 'customer', name: 'x y', phone: '01088888888', status: 'active', customerRatingSum: 5, customerRatingCount: 1 });
  await assertFails(b.commit());
});

// ------------------------------------------------------------------ الصنايعي
test('worker: new application is pending and cannot self-approve', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/w9'), { uid: 'w9', role: 'worker', name: 'جديد', phone: '01077777777', status: 'active', customerRatingSum: 0, customerRatingCount: 0 });
  });
  const f = db('w9');
  await assertFails(setDoc(doc(f, 'workers/w9'), worker('w9', '01077777777', 'approved')));
  await assertSucceeds(setDoc(doc(f, 'workers/w9'), worker('w9', '01077777777', 'pending')));
  await assertFails(updateDoc(doc(f, 'workers/w9'), { verificationStatus: 'approved' }));
  await assertFails(updateDoc(doc(f, 'workers/w9'), { idVerified: true }));
  // غير ظاهر للعملاء قبل الموافقة
  await assertFails(getDoc(doc(db('c1'), 'workers/w9')));
  // الأدمن يوافق
  await assertSucceeds(updateDoc(doc(db('adm'), 'workers/w9'), { verificationStatus: 'approved', idVerified: true }));
  await assertSucceeds(getDoc(doc(db('c1'), 'workers/w9')));
});

test('worker: approved worker cannot change profession directly', async () => {
  const f = db('w1');
  await assertFails(updateDoc(doc(f, 'workers/w1'), { categoryIds: ['electrician'] }));
  await assertSucceeds(updateDoc(doc(f, 'workers/w1'), { available: false, bio: 'جديد' }));
  await assertSucceeds(addDoc(collection(f, 'workerChangeRequests'), { workerId: 'w1', status: 'pending', changes: { categoryIds: ['electrician'] } }));
});

test('national ID: unique and private', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/w8'), { uid: 'w8', role: 'worker', name: 'ص', phone: '01066666666', status: 'active', customerRatingSum: 0, customerRatingCount: 0 });
    await setDoc(doc(ctx.firestore(), 'users/w7'), { uid: 'w7', role: 'worker', name: 'ص', phone: '01055555555', status: 'active', customerRatingSum: 0, customerRatingCount: 0 });
  });
  const f = db('w8');
  const b = writeBatch(f);
  b.set(doc(f, 'nationalIds/29001011234567'), { uid: 'w8' });
  b.set(doc(f, 'workerPrivate/w8'), { nationalId: '29001011234567' });
  await assertSucceeds(b.commit());
  const g = db('w7');
  const b2 = writeBatch(g);
  b2.set(doc(g, 'nationalIds/29001011234567'), { uid: 'w7' });
  b2.set(doc(g, 'workerPrivate/w7'), { nationalId: '29001011234567' });
  await assertFails(b2.commit());
  await assertFails(getDoc(doc(db('c1'), 'workerPrivate/w8')));
  await assertSucceeds(getDoc(doc(db('adm'), 'workerPrivate/w8')));
});

// ------------------------------------------------------------------ المسار الكامل + العمولة
test('full flow: request → accept → price → 5% commission → reviews', async () => {
  await assertSucceeds(createRequest('r1'));
  const w = db('w1'); const c = db('c1');
  // طرف غريب لا يقرأ ولا يعدل
  await assertFails(getDoc(doc(db('w2'), 'requests/r1')));
  await assertFails(updateDoc(doc(c, 'requests/r1'), { status: 'accepted', updatedAt: serverTimestamp() }));
  for (const s of ['accepted', 'on_the_way', 'started', 'completed']) {
    await assertSucceeds(updateDoc(doc(w, 'requests/r1'), { status: s, updatedAt: serverTimestamp() }));
  }
  await assertSucceeds(updateDoc(doc(w, 'requests/r1'), { status: 'price_set', agreedPrice: 500, updatedAt: serverTimestamp() }));
  // العميل لا يستطيع تغيير السعر
  await assertFails(updateDoc(doc(c, 'requests/r1'), { status: 'price_set', agreedPrice: 1, updatedAt: serverTimestamp() }));

  const confirm = (amount, rate = 0.05) => {
    const b = writeBatch(c);
    b.update(doc(c, 'requests/r1'), { status: 'price_agreed', commissionRate: rate, commissionAmount: amount, commissionStatus: 'due', priceAgreedAt: serverTimestamp(), updatedAt: serverTimestamp() });
    b.set(doc(c, 'commissions/r1'), { requestId: 'r1', customerId: 'c1', workerId: 'w1', servicePrice: 500, rate, amount, status: 'due', createdAt: serverTimestamp() });
    b.update(doc(c, 'workers/w1'), { completedCount: increment(1), lastCompletedRequestId: 'r1' });
    return b.commit();
  };
  await assertFails(confirm(5));          // عمولة غلط
  await assertFails(confirm(2.5, 0.005)); // نسبة غير نسبة الإعدادات
  await assertSucceeds(confirm(25));      // 5% من 500 = 25

  // التقييم: مرة واحدة وتحديث تقييم الصنايعي مربوط بيه
  const rb = writeBatch(c);
  rb.set(doc(c, 'reviews/r1_c2w'), { requestId: 'r1', direction: 'c2w', fromId: 'c1', toId: 'w1', stars: 5, comment: 'ممتاز', hidden: false, createdAt: serverTimestamp() });
  rb.update(doc(c, 'workers/w1'), { ratingSum: 5, ratingCount: 1, lastReviewId: 'r1_c2w' });
  rb.update(doc(c, 'requests/r1'), { customerReviewed: true, updatedAt: serverTimestamp() });
  await assertSucceeds(rb.commit());
  const rb2 = writeBatch(c);
  rb2.set(doc(c, 'reviews/r1_c2w'), { requestId: 'r1', direction: 'c2w', fromId: 'c1', toId: 'w1', stars: 1, comment: 'تاني', hidden: false, createdAt: serverTimestamp() });
  await assertFails(rb2.commit());
  // تلاعب بالتقييم من غير تقييم حقيقي
  await assertFails(updateDoc(doc(c, 'workers/w1'), { ratingSum: 50, ratingCount: 10, lastReviewId: 'fake' }));

  // الصنايعي يعلن الدفع؛ لا يقدر يعلّمها مدفوعة
  await assertFails(updateDoc(doc(w, 'commissions/r1'), { status: 'paid' }));
  await assertSucceeds(updateDoc(doc(w, 'commissions/r1'), { status: 'claimed', paymentId: 'p1' }));
  await assertSucceeds(updateDoc(doc(db('adm'), 'commissions/r1'), { status: 'paid' }));
});

test('emergency: open request claimed by first approved worker only + rate limit', async () => {
  await assertSucceeds(createRequest('e1', { workerId: null, open: true, isEmergency: true }));
  // طوارئ تاني في نفس الدقايق → مرفوض
  await assertFails(createRequest('e2', { workerId: null, open: true, isEmergency: true }));
  const claim = (uid) => updateDoc(doc(db(uid), 'requests/e1'), {
    status: 'accepted', workerId: uid, open: false, workerName: 'x', updatedAt: serverTimestamp(), acceptedAt: serverTimestamp(),
  });
  await assertSucceeds(getDoc(doc(db('w2'), 'requests/e1')));
  await assertFails(claim('c1'));
  await assertSucceeds(claim('w2'));
  await assertFails(claim('w1')); // اتاخد خلاص
});

test('cancel requires participant and reason', async () => {
  await createRequest('r3');
  await assertSucceeds(updateDoc(doc(db('c1'), 'requests/r3'), { status: 'cancelled', cancelledBy: 'customer', cancelReason: 'found_other', cancelNote: '', updatedAt: serverTimestamp() }));
  await createRequest('r4').catch(() => {}); // rate limit (30s) — نتأكد بس إن الإلغاء من غير سبب مرفوض
  await setStatus('r3', { status: 'accepted' });
  await assertFails(updateDoc(doc(db('c1'), 'requests/r3'), { status: 'cancelled', cancelledBy: 'worker', updatedAt: serverTimestamp() }));
});

// ------------------------------------------------------------------ الإدارة
test('owner email becomes super admin only when verified', async () => {
  const unverified = db('own', { email: 'rafatsaeed719@gmail.com', email_verified: false });
  await assertFails(setDoc(doc(unverified, 'admins/own'), { email: 'rafatsaeed719@gmail.com', role: 'super', active: true }));
  const verified = db('own', { email: 'rafatsaeed719@gmail.com', email_verified: true });
  await assertSucceeds(setDoc(doc(verified, 'admins/own'), { email: 'rafatsaeed719@gmail.com', role: 'super', active: true }));
  const other = db('evil', { email: 'evil@x.com', email_verified: true });
  await assertFails(setDoc(doc(other, 'admins/evil'), { email: 'rafatsaeed719@gmail.com', role: 'super', active: true }));
});

test('settings and catalog: only admins write; banned users cannot act', async () => {
  await assertFails(setDoc(doc(db('c1'), 'settings/public'), { commissionRate: 0 }));
  await assertSucceeds(setDoc(doc(db('adm'), 'settings/public'), { commissionRate: 0.05 }));
  await assertSucceeds(updateDoc(doc(db('adm'), 'users/c1'), { status: 'banned', statusReason: 'سبام' }));
  await assertFails(createRequest('r5'));
});

test('media: ID images private, public images readable', async () => {
  const w = db('w1');
  await assertSucceeds(setDoc(doc(w, 'media/m1'), { ownerId: 'w1', kind: 'id', data: 'abc', mime: 'image/jpeg', createdAt: serverTimestamp() }));
  await assertSucceeds(setDoc(doc(w, 'media/m2'), { ownerId: 'w1', kind: 'public', data: 'abc', mime: 'image/jpeg', createdAt: serverTimestamp() }));
  await assertFails(getDoc(doc(db('c1'), 'media/m1')));
  await assertSucceeds(getDoc(doc(db('c1'), 'media/m2')));
  await assertSucceeds(getDoc(doc(db('adm'), 'media/m1')));
});

test('customer phone hidden from worker until accepted', async () => {
  const c = db('c1');
  const b = writeBatch(c);
  b.set(doc(c, 'requests/r6'), newRequest());
  b.update(doc(c, 'users/c1'), { lastRequestAt: serverTimestamp() });
  b.set(doc(c, 'requests/r6/private/contact'), { customerPhone: '01011111111', customerName: 'عميل' });
  await assertSucceeds(b.commit());
  await assertFails(getDoc(doc(db('w1'), 'requests/r6/private/contact')));
  await assertSucceeds(updateDoc(doc(db('w1'), 'requests/r6'), { status: 'accepted', updatedAt: serverTimestamp() }));
  await assertSucceeds(getDoc(doc(db('w1'), 'requests/r6/private/contact')));
});

test('worker nearby query for open requests is allowed', async () => {
  await createRequest('e9', { workerId: null, open: true, isEmergency: false });
  const q = query(collection(db('w1'), 'requests'), where('open', '==', true), where('status', '==', 'new'), where('categoryId', 'in', ['plumber']));
  await assertSucceeds(getDocs(q));
});
