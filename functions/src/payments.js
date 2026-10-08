'use strict';
const { onCall } = require('firebase-functions/v2/https');
const { db, FieldValue, HttpsError, wrap, requireUser, rateLimit, getSettings } = require('./common');
const v = require('./lib/validate');
const { sumMoney } = require('./lib/commission');

/**
 * طبقة الدفع (Payment Provider abstraction)
 * ------------------------------------------------------------
 * حاليًا: InstaPay يدوي — الصنايعي يحوّل للحساب المعلن في الإعدادات،
 * ثم يرسل رقم العملية + صورة الإيصال، والإدارة تطابق التحويل وتؤكده.
 *
 * ⚠️ لا يوجد API رسمي عام للتحقق التلقائي من تحويلات InstaPay، لذلك
 * النظام لا يعتبر أي تحويل "مدفوع" إلا بعد تأكيد يدوي من الإدارة.
 *
 * لإضافة مزود دفع إلكتروني لاحقًا (Paymob / Fawry / Kashier):
 *   أضف provider جديد بنفس الواجهة في PROVIDERS ثم webhook يستدعي
 *   confirmPaymentInternal() بعد التحقق من توقيع المزود.
 */
const PROVIDERS = {
  instapay_manual: {
    id: 'instapay_manual',
    autoVerify: false,
    async instructions(settings) {
      return {
        method: 'InstaPay',
        handle: settings.instapayHandle || '',
        phone: settings.instapayPhone || '',
        note: 'manual_review',
      };
    },
  },
};

exports.getPaymentInstructions = onCall(wrap(async (req) => {
  await requireUser(req, { roles: ['worker'] });
  const settings = await getSettings();
  return PROVIDERS.instapay_manual.instructions(settings);
}));

/**
 * الصنايعي يرسل إثبات تحويل لعمولة واحدة أو أكثر.
 * المبلغ يُحسب على السيرفر من العمولات المختارة (لا يُقبل من التطبيق).
 */
exports.submitPayment = onCall(wrap(async (req) => {
  const { uid, user } = await requireUser(req, { roles: ['worker'] });
  await rateLimit(uid, 'payment', 10, 24 * 3600);
  const d = req.data || {};
  const commissionIds = v.idList(d.commissionIds, 'commissionIds', { min: 1, max: 50 });
  const reference = v.str(d.reference, 'reference', { min: 4, max: 60 });
  const receiptPath = v.storagePath(d.receiptPath, 'receiptPath', `payments/${uid}/`, { required: false });
  const senderAccount = v.str(d.senderAccount, 'senderAccount', { max: 80, required: false });

  const payRef = db.collection('payments').doc();
  const amount = await db.runTransaction(async (tx) => {
    const refs = commissionIds.map((id) => db.doc(`commissions/${id}`));
    const snaps = await Promise.all(refs.map((r) => tx.get(r)));
    for (const s of snaps) {
      if (!s.exists || s.data().workerId !== uid) throw new HttpsError('permission-denied', 'commission-not-yours');
      if (s.data().status !== 'due') throw new HttpsError('failed-precondition', 'commission-not-due');
    }
    const total = sumMoney(snaps.map((s) => s.data().amount));
    tx.set(payRef, {
      workerId: uid,
      workerName: user.name,
      workerPhone: user.phone,
      provider: 'instapay_manual',
      amount: total,
      commissionIds,
      reference,
      senderAccount,
      receiptPath: receiptPath || '',
      status: 'pending_review', // pending_review → confirmed | rejected
      reviewNote: '',
      createdAt: FieldValue.serverTimestamp(),
      reviewedAt: null,
    });
    refs.forEach((r) => tx.update(r, { status: 'claimed', paymentId: payRef.id }));
    return total;
  });
  return { paymentId: payRef.id, amount, status: 'pending_review' };
}));

/** تأكيد/رفض دفعة — يُستدعى من لوحة الإدارة (أو webhook مزود دفع لاحقًا) */
async function confirmPaymentInternal(paymentId, decision, note, reviewer) {
  const payRef = db.doc(`payments/${paymentId}`);
  return db.runTransaction(async (tx) => {
    const p = await tx.get(payRef);
    if (!p.exists) throw new HttpsError('not-found', 'payment-not-found');
    const pd = p.data();
    if (pd.status !== 'pending_review') throw new HttpsError('failed-precondition', 'already-reviewed');
    const cRefs = pd.commissionIds.map((id) => db.doc(`commissions/${id}`));
    const cSnaps = await Promise.all(cRefs.map((r) => tx.get(r)));
    const reqRefs = cSnaps.filter((s) => s.exists).map((s) => db.doc(`requests/${s.data().requestId}`));
    const reqSnaps = await Promise.all(reqRefs.map((r) => tx.get(r)));

    tx.update(payRef, {
      status: decision === 'confirm' ? 'confirmed' : 'rejected',
      reviewNote: note || '',
      reviewedBy: reviewer || '',
      reviewedAt: FieldValue.serverTimestamp(),
    });
    if (decision === 'confirm') {
      cRefs.forEach((r) => tx.update(r, { status: 'paid', paidAt: FieldValue.serverTimestamp() }));
      reqSnaps.forEach((s) => {
        if (!s.exists) return;
        const upd = { commissionStatus: 'paid', updatedAt: FieldValue.serverTimestamp() };
        if (s.data().status === 'price_agreed') upd.status = 'commission_paid';
        tx.update(s.ref, upd);
        tx.set(s.ref.collection('history').doc(), {
          from: s.data().status, to: upd.status || s.data().status, action: 'commission_paid',
          by: 'admin', byUid: reviewer || '', note: paymentId, at: FieldValue.serverTimestamp(),
        });
      });
      tx.set(db.doc(`wallets/${pd.workerId}`), {
        paid: FieldValue.increment(pd.amount),
        due: FieldValue.increment(-pd.amount),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    } else {
      cRefs.forEach((r) => tx.update(r, { status: 'due', paymentId: null }));
    }
    return pd;
  });
}

exports.confirmPaymentInternal = confirmPaymentInternal;
exports.PROVIDERS = PROVIDERS;
