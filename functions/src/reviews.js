'use strict';
const { onCall } = require('firebase-functions/v2/https');
const { db, FieldValue, HttpsError, wrap, requireUser, rateLimit, getSettings } = require('./common');
const v = require('./lib/validate');
const sm = require('./lib/statusMachine');
const { computeBadges } = require('./lib/badges');
const { notify } = require('./notify');

/**
 * تقييم بعد انتهاء الخدمة:
 *  العميل → الصنايعي (c2w): يظهر في ملف الصنايعي، التعليق مطلوب
 *  الصنايعي → العميل (w2c): داخلي للإدارة، التعليق اختياري
 * كل طرف يقيّم مرة واحدة لكل طلب. المتوسطات تُحدّث على السيرفر.
 */
exports.submitReview = onCall(wrap(async (req) => {
  const { uid, user } = await requireUser(req);
  await rateLimit(uid, 'review', 30, 3600);
  const d = req.data || {};
  const requestId = v.idList([d.requestId], 'requestId', { min: 1, max: 1 })[0];
  const stars = v.num(d.stars, 'stars', { min: 1, max: 5 });
  if (!Number.isInteger(stars)) throw new v.ValidationError('stars', 'integer');

  const settings = await getSettings();
  const reqRef = db.doc(`requests/${requestId}`);

  const out = await db.runTransaction(async (tx) => {
    const s = await tx.get(reqRef);
    if (!s.exists) throw new HttpsError('not-found', 'request-not-found');
    const r = s.data();
    if (!sm.REVIEWABLE.includes(r.status)) throw new HttpsError('failed-precondition', 'not-reviewable-yet');

    let direction; let toId;
    if (uid === r.customerId) { direction = 'c2w'; toId = r.workerId; }
    else if (uid === r.workerId) { direction = 'w2c'; toId = r.customerId; }
    else throw new HttpsError('permission-denied', 'not-participant');

    const flag = direction === 'c2w' ? 'customerReviewed' : 'workerReviewed';
    if (r[flag]) throw new HttpsError('already-exists', 'already-reviewed');
    const comment = direction === 'c2w'
      ? v.longText(d.comment, 'comment', { min: 2, max: 500 })
      : v.longText(d.comment, 'comment', { max: 500, required: false });

    const targetRef = direction === 'c2w' ? db.doc(`workers/${toId}`) : db.doc(`users/${toId}`);
    const target = await tx.get(targetRef);
    if (!target.exists) throw new HttpsError('not-found', 'target-missing');
    const t = target.data();

    const reviewRef = db.doc(`reviews/${requestId}_${direction}`);
    tx.set(reviewRef, {
      requestId, direction, fromId: uid, fromName: user.name, toId,
      stars, comment, hidden: false,
      serviceName: r.serviceName || r.categoryName,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.update(reqRef, { [flag]: true, updatedAt: FieldValue.serverTimestamp() });
    tx.set(reqRef.collection('history').doc(), {
      from: r.status, to: r.status, action: 'review', by: direction === 'c2w' ? 'customer' : 'worker',
      byUid: uid, note: `${stars}★`, at: FieldValue.serverTimestamp(),
    });

    if (direction === 'c2w') {
      const sum = Number(t.ratingSum || 0) + stars;
      const count = Number(t.ratingCount || 0) + 1;
      const avg = Math.round((sum / count) * 100) / 100;
      const badges = computeBadges({ ...t, ratingSum: sum, ratingCount: count, ratingAvg: avg }, settings.badgeRules);
      tx.update(targetRef, { ratingSum: sum, ratingCount: count, ratingAvg: avg, badges });
    } else {
      const sum = Number(t.customerRatingSum || 0) + stars;
      const count = Number(t.customerRatingCount || 0) + 1;
      tx.update(targetRef, {
        customerRatingSum: sum, customerRatingCount: count,
        customerRatingAvg: Math.round((sum / count) * 100) / 100,
      });
    }
    return { toId, direction, r };
  });

  if (out.direction === 'c2w') {
    await notify(out.toId, 'review_received', { stars }, { requestId, screen: 'reviews' });
  }
  return { ok: true };
}));

/** يعيد حساب متوسط تقييم صنايعي (بعد إخفاء/إظهار تقييم من الإدارة) */
async function recomputeWorkerRating(workerId) {
  const snap = await db.collection('reviews')
    .where('toId', '==', workerId).where('direction', '==', 'c2w').where('hidden', '==', false).get();
  let sum = 0;
  snap.forEach((d) => { sum += Number(d.data().stars || 0); });
  const count = snap.size;
  const avg = count ? Math.round((sum / count) * 100) / 100 : 0;
  const settings = await getSettings();
  const wRef = db.doc(`workers/${workerId}`);
  const w = await wRef.get();
  if (!w.exists) return;
  const badges = computeBadges({ ...w.data(), ratingSum: sum, ratingCount: count, ratingAvg: avg }, settings.badgeRules);
  await wRef.update({ ratingSum: sum, ratingCount: count, ratingAvg: avg, badges });
}

exports.recomputeWorkerRating = recomputeWorkerRating;
