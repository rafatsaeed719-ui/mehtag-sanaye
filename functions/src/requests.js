'use strict';
const { onCall } = require('firebase-functions/v2/https');
const {
  db, FieldValue, Timestamp, HttpsError, wrap, requireUser, rateLimit, getSettings, statsRef,
} = require('./common');
const v = require('./lib/validate');
const geo = require('./lib/geo');
const sm = require('./lib/statusMachine');
const { computeCommission } = require('./lib/commission');
const { formatTime } = require('./lib/i18n');
const { notify } = require('./notify');

/**
 * البحث الجغرافي على السيرفر: الصنايعية الموثقون القريبون لمهنة معينة.
 * يستخدم نطاقات geohash (فهارس Firestore) ثم يفلتر بالمسافة الحقيقية.
 */
async function findNearbyWorkers({ lat, lng, radiusKm, categoryId, availableOnly, limit, excludeUid }) {
  const bounds = geo.queryBounds(lat, lng, radiusKm);
  const snaps = await Promise.all(bounds.map(([start, end]) => {
    let q = db.collection('workers')
      .where('verificationStatus', '==', 'approved')
      .where('suspended', '==', false);
    if (availableOnly) q = q.where('available', '==', true);
    return q.where('categoryIds', 'array-contains', categoryId)
      .orderBy('geohash').startAt(start).endAt(end).limit(200).get();
  }));
  const seen = new Map();
  for (const s of snaps) {
    for (const d of s.docs) {
      if (d.id === excludeUid || seen.has(d.id)) continue;
      const w = d.data();
      if (!w.geo) continue;
      const km = geo.distanceKm(lat, lng, w.geo.lat, w.geo.lng);
      if (km <= radiusKm) seen.set(d.id, { id: d.id, km, name: w.name });
    }
  }
  return [...seen.values()].sort((a, b) => a.km - b.km).slice(0, limit);
}

/**
 * إنشاء طلب خدمة:
 *  - موجّه لصنايعي بعينه (workerId)
 *  - أو مفتوح للصنايعية القريبين (بدون workerId)
 *  - أو طوارئ "محتاج صنايعي الآن" (مفتوح + إشعار عاجل للمتاحين القريبين)
 */
exports.createRequest = onCall(wrap(async (req) => {
  const { uid, user } = await requireUser(req, { roles: ['customer'] });
  const d = req.data || {};
  const isEmergency = d.isEmergency === true;
  await rateLimit(uid, isEmergency ? 'emergency' : 'request', isEmergency ? 3 : 15, 3600);

  const categoryId = v.idList([d.categoryId], 'categoryId', { min: 1, max: 1 })[0];
  const serviceId = d.serviceId ? v.idList([d.serviceId], 'serviceId', { min: 1, max: 1 })[0] : null;
  const description = v.longText(d.description, 'description', { min: isEmergency ? 0 : 5, max: 1000, required: !isEmergency });
  const images = v.urlList(d.images, 'images', { max: 6 });
  const lat = v.num(d.lat, 'lat', { min: -90, max: 90 });
  const lng = v.num(d.lng, 'lng', { min: -180, max: 180 });
  if (!geo.isInEgypt(lat, lng)) throw new v.ValidationError('location', 'outside-egypt');
  const address = v.str(d.address, 'address', { max: 200, required: false });
  const governorate = v.str(d.governorate, 'governorate', { max: 40, required: false });
  const now = Date.now();
  let scheduledAt = now;
  if (!isEmergency) {
    scheduledAt = v.num(d.scheduledAt, 'scheduledAt', { min: now - 10 * 60 * 1000, max: now + 90 * 24 * 3600 * 1000 });
  }

  const catSnap = await db.doc(`categories/${categoryId}`).get();
  if (!catSnap.exists || catSnap.data().active === false) throw new v.ValidationError('categoryId', 'invalid');
  let serviceName = null;
  if (serviceId) {
    const s = await db.doc(`services/${serviceId}`).get();
    if (!s.exists || s.data().active === false || s.data().categoryId !== categoryId) throw new v.ValidationError('serviceId', 'invalid');
    serviceName = { ar: s.data().nameAr, en: s.data().nameEn };
  }
  const categoryName = { ar: catSnap.data().nameAr, en: catSnap.data().nameEn };

  let worker = null;
  const workerId = isEmergency ? null : (d.workerId || null);
  if (workerId) {
    if (workerId === uid) throw new HttpsError('invalid-argument', 'self-request');
    const w = await db.doc(`workers/${workerId}`).get();
    if (!w.exists || w.data().verificationStatus !== 'approved' || w.data().suspended) {
      throw new HttpsError('failed-precondition', 'worker-unavailable');
    }
    if (!w.data().categoryIds.includes(categoryId)) throw new v.ValidationError('categoryId', 'not-offered-by-worker');
    worker = w.data();
  }

  const ref = db.collection('requests').doc();
  const shortCode = ref.id.slice(0, 6).toUpperCase();
  const settings = await getSettings();
  const batch = db.batch();
  batch.set(ref, {
    code: shortCode,
    customerId: uid,
    customerName: user.name,
    customerPhone: null, // يظهر للصنايعي بعد قبول الطلب فقط
    workerId: workerId || null,
    workerName: worker ? worker.name : null,
    workerPhone: worker ? (worker.callPhone || worker.phone) : null,
    workerWhatsapp: worker ? (worker.whatsapp || worker.phone) : null,
    workerPhotoUrl: worker ? (worker.photoUrl || '') : '',
    categoryId, categoryName,
    serviceId, serviceName,
    description,
    images,
    location: { lat, lng, address, governorate },
    geohash: geo.encode(lat, lng, 10),
    scheduledAt: Timestamp.fromMillis(scheduledAt),
    proposedAt: null,
    isEmergency,
    open: !workerId,
    status: sm.S.NEW,
    agreedPrice: null,
    commissionRate: null,
    commissionAmount: null,
    commissionStatus: 'none',
    customerReviewed: false,
    workerReviewed: false,
    notifiedWorkerIds: [],
    lastMessageAt: null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.set(ref.collection('history').doc(), {
    from: null, to: sm.S.NEW, action: 'create', by: 'customer', byUid: uid,
    note: isEmergency ? 'emergency' : '', at: FieldValue.serverTimestamp(),
  });
  if (workerId) {
    batch.update(db.doc(`workers/${workerId}`), { 'stats.received': FieldValue.increment(1) });
  }
  // ملاحظة: set+merge لا يفسر النقاط في المفاتيح، لذلك نستخدم كائنات متداخلة
  const stat = { requests: FieldValue.increment(1), byCategory: { [categoryId]: FieldValue.increment(1) } };
  if (isEmergency) stat.emergencies = FieldValue.increment(1);
  if (governorate) stat.byGov = { [governorate.replace(/[.~*/[\]]/g, '_')]: FieldValue.increment(1) };
  batch.set(statsRef(), stat, { merge: true });
  await batch.commit();

  const svc = serviceName || categoryName;
  let notified = [];
  if (workerId) {
    await notify(workerId, 'new_request', { service: svc, name: user.name }, { requestId: ref.id, screen: 'request' });
  } else {
    const nearby = await findNearbyWorkers({
      lat, lng, categoryId,
      radiusKm: isEmergency ? settings.emergencyRadiusKm : settings.openRequestRadiusKm,
      availableOnly: isEmergency,
      limit: settings.maxNotifiedWorkers,
      excludeUid: uid,
    });
    notified = nearby.map((n) => n.id);
    await Promise.all(nearby.map((n) => notify(
      n.id,
      isEmergency ? 'emergency_request' : 'nearby_request',
      { service: svc, km: n.km.toFixed(1) },
      { requestId: ref.id, screen: 'request' },
      { urgent: isEmergency },
    )));
    if (notified.length) await ref.update({ notifiedWorkerIds: notified });
  }
  return { requestId: ref.id, code: shortCode, notifiedCount: workerId ? 1 : notified.length };
}));

/**
 * كل تغيير في حالة الطلب يمر من هنا (القبول، الرفض، اقتراح موعد، في الطريق،
 * بدء العمل، الانتهاء، تسجيل السعر، تأكيد السعر، الإلغاء).
 * العمولة تُحسب هنا على السيرفر عند تأكيد العميل للسعر.
 */
exports.requestAction = onCall(wrap(async (req) => {
  const { uid } = await requireUser(req);
  await rateLimit(uid, 'action', 60, 3600);
  const d = req.data || {};
  const requestId = v.idList([d.requestId], 'requestId', { min: 1, max: 1 })[0];
  const action = v.oneOf(d.action, 'action', Object.keys(sm.ACTIONS));
  const payload = d.payload && typeof d.payload === 'object' ? d.payload : {};
  const settings = await getSettings();
  const ref = db.doc(`requests/${requestId}`);
  const now = Date.now();

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'request-not-found');
    const r = snap.data();

    // قراءة ملف الصنايعي (للطلب المفتوح أو للإحصائيات)
    const workerUid = r.workerId || uid;
    const wSnap = await tx.get(db.doc(`workers/${workerUid}`));
    const w = wSnap.exists ? wSnap.data() : null;
    const eligible = !!w && workerUid === uid && w.verificationStatus === 'approved' && !w.suspended &&
      Array.isArray(w.categoryIds) && w.categoryIds.includes(r.categoryId);

    const role = sm.actorRole(r, uid, { isEligibleWorker: eligible });
    const t = sm.transition(r, action, role, payload, now);

    const custSnap = action === 'accept' ? await tx.get(db.doc(`users/${r.customerId}`)) : null;

    // ---- كل القراءات انتهت؛ الكتابة بعد هذا السطر ----
    const patch = { ...t.patch, updatedAt: FieldValue.serverTimestamp() };
    if (patch.proposedAt) patch.proposedAt = Timestamp.fromMillis(patch.proposedAt);
    if (action === 'accept_proposal' && r.proposedAt) patch.scheduledAt = r.proposedAt;

    if (action === 'accept') {
      patch.customerPhone = custSnap && custSnap.exists ? custSnap.data().phone : null;
      patch.acceptedAt = FieldValue.serverTimestamp();
    }
    if (t.meta.claimOpen) {
      patch.workerId = uid;
      patch.workerName = w.name;
      patch.workerPhone = w.callPhone || w.phone;
      patch.workerWhatsapp = w.whatsapp || w.phone;
      patch.workerPhotoUrl = w.photoUrl || '';
      patch.open = false;
    }
    if (action === 'cancel' && r.open && !r.workerId) patch.open = false;

    // إحصائيات سرعة الاستجابة (للطلبات الموجهة فقط)
    const wRef = db.doc(`workers/${workerUid}`);
    const wInc = {};
    if (t.role === 'worker' && r.status === sm.S.NEW && ['accept', 'reject', 'propose_time'].includes(action)) {
      if (!t.meta.claimOpen) {
        const created = r.createdAt ? r.createdAt.toMillis() : now;
        const mins = Math.min(24 * 60, Math.max(0, (now - created) / 60000));
        wInc['stats.responded'] = FieldValue.increment(1);
        wInc['stats.responseMinutesTotal'] = FieldValue.increment(Math.round(mins * 10) / 10);
      } else {
        wInc['stats.received'] = FieldValue.increment(1);
        wInc['stats.responded'] = FieldValue.increment(1);
      }
    }
    if (action === 'accept') wInc['stats.accepted'] = FieldValue.increment(1);
    if (action === 'cancel' && t.role === 'worker') wInc['stats.cancelled'] = FieldValue.increment(1);

    let commission = null;
    if (t.meta.createCommission) {
      commission = computeCommission(r.agreedPrice, settings.commissionRate);
      patch.commissionRate = commission.rate;
      patch.commissionAmount = commission.commission;
      patch.commissionStatus = 'due';
      patch.priceAgreedAt = FieldValue.serverTimestamp();
      tx.set(db.doc(`commissions/${requestId}`), {
        requestId,
        requestCode: r.code || '',
        workerId: r.workerId,
        workerName: r.workerName || '',
        customerId: r.customerId,
        servicePrice: commission.price,
        rate: commission.rate,
        amount: commission.commission,
        status: 'due', // due → claimed (الصنايعي أرسل إثبات تحويل) → paid / due
        paymentId: null,
        createdAt: FieldValue.serverTimestamp(),
        paidAt: null,
      });
      tx.set(db.doc(`wallets/${r.workerId}`), {
        workerId: r.workerId,
        totalServices: FieldValue.increment(commission.price),
        totalCommission: FieldValue.increment(commission.commission),
        due: FieldValue.increment(commission.commission),
        jobs: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      wInc.completedCount = FieldValue.increment(1);
      tx.set(db.doc(`workers/${r.workerId}/customers/${r.customerId}`), {
        customerId: r.customerId, lastRequestId: requestId, at: FieldValue.serverTimestamp(),
      }, { merge: true });
      tx.set(statsRef(), {
        completed: FieldValue.increment(1),
        servicesTotal: FieldValue.increment(commission.price),
        commissionTotal: FieldValue.increment(commission.commission),
      }, { merge: true });
    }
    if (action === 'cancel') {
      tx.set(statsRef(), { cancelled: FieldValue.increment(1) }, { merge: true });
    }
    if (Object.keys(wInc).length && w) tx.update(wRef, wInc);

    tx.update(ref, patch);
    tx.set(ref.collection('history').doc(), {
      from: t.from, to: t.to, action, by: t.role, byUid: uid,
      note: action === 'cancel' ? `${patch.cancelReason}${patch.cancelNote ? ': ' + patch.cancelNote : ''}` :
        action === 'set_price' ? String(patch.agreedPrice) : '',
      at: FieldValue.serverTimestamp(),
    });
    return { r, t, w, commission, proposedAt: t.patch.proposedAt || (r.proposedAt ? r.proposedAt.toMillis() : null) };
  });

  // ---- الإشعارات بعد نجاح العملية ----
  const { r, t, w, commission } = result;
  const svc = r.serviceName || r.categoryName;
  const data = { requestId, screen: 'request' };
  const workerName = (w && w.name) || r.workerName || '';
  const workerTarget = r.workerId || uid;
  const timeParam = (ms) => ({ ar: formatTime(ms, 'ar'), en: formatTime(ms, 'en') });
  switch (action) {
    case 'accept':
      await notify(r.customerId, t.meta.claimOpen ? 'open_request_taken' : 'request_accepted', { name: workerName }, data);
      break;
    case 'reject':
      await notify(r.customerId, 'request_rejected', { name: workerName }, data);
      break;
    case 'propose_time':
      await notify(r.customerId, 'time_proposed', { name: workerName, time: timeParam(result.proposedAt) }, data);
      break;
    case 'accept_proposal':
      await notify(workerTarget, 'proposal_accepted', { time: timeParam(result.proposedAt) }, data);
      break;
    case 'on_the_way':
    case 'start':
      await notify(r.customerId, action === 'start' ? 'started' : 'on_the_way', { name: workerName }, data);
      break;
    case 'complete':
      await notify(r.customerId, 'completed', { name: workerName }, data);
      break;
    case 'set_price':
      await notify(r.customerId, 'price_set', { name: workerName, price: t.patch.agreedPrice }, data);
      break;
    case 'confirm_price':
      await notify(workerTarget, 'price_confirmed', { price: commission.price, commission: commission.commission }, { ...data, screen: 'wallet' });
      await notify(workerTarget, 'review_requested', { name: r.customerName }, data);
      break;
    case 'dispute_price':
      await notify(workerTarget, 'price_disputed', {}, data);
      break;
    case 'cancel': {
      const other = t.role === 'customer' ? r.workerId : r.customerId;
      if (other) await notify(other, 'request_cancelled', { service: svc }, data);
      break;
    }
    default: break;
  }
  return { status: t.to };
}));

exports.findNearbyWorkers = findNearbyWorkers;
