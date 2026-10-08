'use strict';
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { db, auth, FieldValue, Timestamp, getSettings } = require('./common');
const { computeBadges } = require('./lib/badges');
const { sumMoney } = require('./lib/commission');
const { notify } = require('./notify');

/**
 * يوميًا 3 صباحًا بتوقيت القاهرة:
 *  1) حساب العمولات المتأخرة لكل صنايعي + تذكير
 *  2) إعادة حساب الشارات
 *  3) رفع الحظر المؤقت المنتهي
 */
exports.dailyMaintenance = onSchedule({ schedule: '0 3 * * *', timeZone: 'Africa/Cairo', timeoutSeconds: 540 }, async () => {
  const settings = await getSettings();

  // 1) المتأخرات
  const cutoff = Timestamp.fromMillis(Date.now() - settings.overdueDays * 86400000);
  const dueSnap = await db.collection('commissions').where('status', '==', 'due').where('createdAt', '<=', cutoff).get();
  const perWorker = new Map();
  dueSnap.forEach((d) => {
    const c = d.data();
    perWorker.set(c.workerId, [...(perWorker.get(c.workerId) || []), c.amount]);
  });
  // صفّر المتأخر لمن سدد، وحدّث للباقين
  const walletsWithOverdue = await db.collection('wallets').where('overdue', '>', 0).get();
  const batch = db.batch();
  walletsWithOverdue.forEach((w) => { if (!perWorker.has(w.id)) batch.set(w.ref, { overdue: 0 }, { merge: true }); });
  for (const [workerId, amounts] of perWorker) {
    batch.set(db.doc(`wallets/${workerId}`), { overdue: sumMoney(amounts), overdueCheckedAt: FieldValue.serverTimestamp() }, { merge: true });
  }
  await batch.commit();
  await Promise.all([...perWorker].map(([workerId, amounts]) =>
    notify(workerId, 'commission_overdue', { amount: sumMoney(amounts) }, { screen: 'wallet' })));

  // 2) الشارات
  let last = null;
  for (;;) {
    let q = db.collection('workers').where('verificationStatus', '==', 'approved').orderBy('__name__').limit(300);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    if (page.empty) break;
    const b = db.batch();
    page.forEach((d) => {
      const badges = computeBadges(d.data(), settings.badgeRules);
      if (JSON.stringify(badges) !== JSON.stringify(d.data().badges || [])) b.update(d.ref, { badges });
    });
    await b.commit();
    last = page.docs[page.docs.length - 1];
    if (page.size < 300) break;
  }

  // 3) رفع الحظر المؤقت المنتهي
  const expired = await db.collection('users').where('status', '==', 'banned').where('bannedUntil', '<=', Timestamp.now()).get();
  for (const u of expired.docs) {
    await u.ref.update({ status: 'active', bannedUntil: null, statusReason: '' });
    await auth.updateUser(u.id, { disabled: false }).catch(() => {});
    const w = await db.doc(`workers/${u.id}`).get();
    if (w.exists) await w.ref.update({ suspended: false });
  }
});
