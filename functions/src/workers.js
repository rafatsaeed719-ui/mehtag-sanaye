'use strict';
const { onCall } = require('firebase-functions/v2/https');
const {
  db, FieldValue, HttpsError, wrap, requireUser, rateLimit, hashNationalId, encrypt,
} = require('./common');
const v = require('./lib/validate');
const geo = require('./lib/geo');

/** يتأكد أن المهن والخدمات موجودة ومفعلة وأن كل خدمة تتبع مهنة مختارة */
async function validateCatalog(categoryIds, serviceIds) {
  const cats = await Promise.all(categoryIds.map((id) => db.doc(`categories/${id}`).get()));
  if (cats.some((c) => !c.exists || c.data().active === false)) throw new v.ValidationError('categoryIds', 'invalid');
  const svcs = await Promise.all(serviceIds.map((id) => db.doc(`services/${id}`).get()));
  if (svcs.some((s) => !s.exists || s.data().active === false || !categoryIds.includes(s.data().categoryId))) {
    throw new v.ValidationError('serviceIds', 'invalid');
  }
  return {
    categoryNames: cats.map((c) => ({ ar: c.data().nameAr, en: c.data().nameEn })),
    serviceNames: svcs.map((s) => ({ ar: s.data().nameAr, en: s.data().nameEn })),
  };
}

/** يسجل رقم البطاقة بشكل مشفر ويمنع تكراره بين الصنايعية */
async function prepareNationalId(idNumber) {
  const hash = await hashNationalId(idNumber);
  return { hash, ref: db.doc(`nationalIds/${hash}`), encrypted: await encrypt(idNumber), last4: idNumber.slice(-4) };
}

function readProfile(data, uid) {
  const lat = v.num(data.lat, 'lat', { min: -90, max: 90 });
  const lng = v.num(data.lng, 'lng', { min: -180, max: 180 });
  if (!geo.isInEgypt(lat, lng)) throw new v.ValidationError('location', 'outside-egypt');
  return {
    name: v.str(data.name, 'name', { min: 2, max: 60 }),
    categoryIds: v.idList(data.categoryIds, 'categoryIds', { min: 1, max: 5 }),
    serviceIds: v.idList(data.serviceIds || [], 'serviceIds', { min: 0, max: 30 }),
    governorate: v.str(data.governorate, 'governorate', { max: 40 }),
    city: v.str(data.city, 'city', { max: 60 }),
    area: v.str(data.area, 'area', { max: 80, required: false }),
    lat, lng,
    bio: v.longText(data.bio, 'bio', { max: 500, required: false }),
    visitFee: v.num(data.visitFee, 'visitFee', { min: 0, max: 10000, required: false }),
    whatsapp: v.mobile(data.whatsapp, 'whatsapp', { required: false }),
    callPhone: v.mobile(data.callPhone, 'callPhone', { required: false }),
    photoUrl: (data.photoUrl && v.urlList([data.photoUrl], 'photoUrl', { max: 1 })[0]) || '',
    workImages: v.urlList(data.workImages, 'workImages', { max: 12 }),
    idNumber: v.nationalId(data.idNumber, 'idNumber', { required: false }),
    idFrontPath: v.storagePath(data.idFrontPath, 'idFrontPath', `idDocs/${uid}/`, { required: false }),
    idBackPath: v.storagePath(data.idBackPath, 'idBackPath', `idDocs/${uid}/`, { required: false }),
  };
}

/**
 * تسجيل/إعادة تقديم بيانات الصنايعي — الحالة تصبح "قيد المراجعة"
 * ولا يظهر للعملاء إلا بعد موافقة الإدارة.
 */
exports.submitWorkerApplication = onCall(wrap(async (req) => {
  const { uid, user } = await requireUser(req, { roles: ['worker'] });
  await rateLimit(uid, 'apply', 10, 24 * 3600);
  const p = readProfile(req.data || {}, uid);
  const names = await validateCatalog(p.categoryIds, p.serviceIds);
  if ((p.idFrontPath && !p.idNumber) || (p.idNumber && !p.idFrontPath)) {
    throw new v.ValidationError('idNumber', 'id-number-and-image-required');
  }

  const workerRef = db.doc(`workers/${uid}`);
  const privRef = db.doc(`workerPrivate/${uid}`);

  const preparedId = p.idNumber ? await prepareNationalId(p.idNumber) : null;

  await db.runTransaction(async (tx) => {
    const cur = await tx.get(workerRef);
    if (cur.exists && cur.data().verificationStatus === 'approved') {
      throw new HttpsError('failed-precondition', 'already-approved-use-change-request');
    }
    const idInfo = preparedId;
    if (idInfo) {
      const owner = await tx.get(idInfo.ref);
      if (owner.exists && owner.data().uid !== uid) throw new HttpsError('already-exists', 'national-id-in-use');
    }

    const prev = cur.exists ? cur.data() : {};
    tx.set(workerRef, {
      uid,
      name: p.name,
      nameLower: p.name.toLowerCase(),
      phone: user.phone,
      photoUrl: p.photoUrl || user.photoUrl || '',
      categoryIds: p.categoryIds,
      serviceIds: p.serviceIds,
      categoryNames: names.categoryNames,
      serviceNames: names.serviceNames,
      governorate: p.governorate,
      city: p.city,
      area: p.area,
      geo: { lat: p.lat, lng: p.lng },
      geohash: geo.encode(p.lat, p.lng, 10),
      bio: p.bio,
      visitFee: p.visitFee,
      whatsapp: p.whatsapp || user.phone,
      callPhone: p.callPhone || user.phone,
      workImages: p.workImages,
      available: prev.available ?? true,
      verificationStatus: 'pending',
      rejectionReason: '',
      idVerified: false,
      hasIdDoc: !!idInfo,
      suspended: false,
      ratingAvg: prev.ratingAvg || 0,
      ratingCount: prev.ratingCount || 0,
      ratingSum: prev.ratingSum || 0,
      completedCount: prev.completedCount || 0,
      stats: prev.stats || { received: 0, responded: 0, responseMinutesTotal: 0, accepted: 0, cancelled: 0 },
      badges: [],
      searchTokens: v.searchTokens(p.name, ...names.categoryNames.flatMap((n) => [n.ar, n.en])),
      submittedAt: FieldValue.serverTimestamp(),
      createdAt: prev.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    const priv = {
      uid,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (idInfo) {
      priv.idHash = idInfo.hash;
      priv.idEncrypted = idInfo.encrypted;
      priv.idLast4 = idInfo.last4;
      priv.idFrontPath = p.idFrontPath;
      priv.idBackPath = p.idBackPath || '';
      tx.set(idInfo.ref, { uid, createdAt: FieldValue.serverTimestamp() });
    }
    tx.set(privRef, priv, { merge: true });
  });
  return { status: 'pending' };
}));

/**
 * تعديل البيانات الحساسة (المهنة، الخدمات، الاسم، الهوية) بعد التوثيق
 * يتطلب مراجعة الإدارة قبل الاعتماد.
 */
exports.requestWorkerChange = onCall(wrap(async (req) => {
  const { uid } = await requireUser(req, { roles: ['worker'] });
  await rateLimit(uid, 'change', 5, 24 * 3600);
  const worker = await db.doc(`workers/${uid}`).get();
  if (!worker.exists || worker.data().verificationStatus !== 'approved') {
    throw new HttpsError('failed-precondition', 'not-approved');
  }
  const d = req.data || {};
  const changes = {};
  if (d.name !== undefined) changes.name = v.str(d.name, 'name', { min: 2, max: 60 });
  if (d.categoryIds !== undefined) changes.categoryIds = v.idList(d.categoryIds, 'categoryIds', { min: 1, max: 5 });
  if (d.serviceIds !== undefined) changes.serviceIds = v.idList(d.serviceIds, 'serviceIds', { min: 0, max: 30 });
  const cats = changes.categoryIds || worker.data().categoryIds;
  const svcs = changes.serviceIds || worker.data().serviceIds;
  if (changes.categoryIds || changes.serviceIds) await validateCatalog(cats, svcs);

  const priv = {};
  if (d.idNumber) {
    const idNumber = v.nationalId(d.idNumber, 'idNumber', { required: true });
    const idFrontPath = v.storagePath(d.idFrontPath, 'idFrontPath', `idDocs/${uid}/`);
    const hash = await hashNationalId(idNumber);
    const owner = await db.doc(`nationalIds/${hash}`).get();
    if (owner.exists && owner.data().uid !== uid) throw new HttpsError('already-exists', 'national-id-in-use');
    priv.idHash = hash;
    priv.idEncrypted = await encrypt(idNumber);
    priv.idLast4 = idNumber.slice(-4);
    priv.idFrontPath = idFrontPath;
    priv.idBackPath = v.storagePath(d.idBackPath, 'idBackPath', `idDocs/${uid}/`, { required: false }) || '';
  }
  if (!Object.keys(changes).length && !Object.keys(priv).length) throw new v.ValidationError('changes', 'empty');

  // طلب واحد معلق في المرة
  const pending = await db.collection('workerChangeRequests')
    .where('workerId', '==', uid).where('status', '==', 'pending').limit(1).get();
  const ref = pending.empty ? db.collection('workerChangeRequests').doc() : pending.docs[0].ref;
  await ref.set({
    workerId: uid,
    workerName: worker.data().name,
    changes,
    identity: Object.keys(priv).length ? { idLast4: priv.idLast4, idFrontPath: priv.idFrontPath, idBackPath: priv.idBackPath } : null,
    status: 'pending',
    createdAt: FieldValue.serverTimestamp(),
  });
  if (Object.keys(priv).length) {
    await db.doc(`workerPrivate/${uid}`).set({ pendingIdentity: priv }, { merge: true });
  }
  await db.doc(`workers/${uid}`).update({ pendingChange: true });
  return { requestId: ref.id };
}));

exports.validateCatalog = validateCatalog;
