'use strict';
const { onCall } = require('firebase-functions/v2/https');
const {
  db, auth, messaging, FieldValue, Timestamp, HttpsError, wrap, requireAdmin, logAdminAction,
  decrypt, getSettings, clearSettingsCache, OWNER_EMAIL,
} = require('./common');
const v = require('./lib/validate');
const { computeBadges, mergeRules } = require('./lib/badges');
const { validateRate } = require('./lib/commission');
const { notify } = require('./notify');
const { confirmPaymentInternal } = require('./payments');
const { recomputeWorkerRating } = require('./reviews');

// ---------------------------------------------------------------- الصنايعية
exports.adminReviewWorker = onCall(wrap(async (req) => {
  const admin = requireAdmin(req, ['moderator']);
  const d = req.data || {};
  const workerId = v.idList([d.workerId], 'workerId', { min: 1, max: 1 })[0];
  const decision = v.oneOf(d.decision, 'decision', ['approve', 'reject', 'pending']);
  const reason = decision === 'reject' ? v.str(d.reason, 'reason', { min: 3, max: 300 }) : '';
  const idVerified = d.idVerified === true;

  const ref = db.doc(`workers/${workerId}`);
  const w = await ref.get();
  if (!w.exists) throw new HttpsError('not-found', 'worker-not-found');
  const settings = await getSettings();
  const patch = {
    verificationStatus: decision === 'approve' ? 'approved' : decision === 'reject' ? 'rejected' : 'pending',
    rejectionReason: reason,
    idVerified: decision === 'approve' ? (idVerified && w.data().hasIdDoc === true) : false,
    reviewedAt: FieldValue.serverTimestamp(),
    reviewedBy: admin.uid,
  };
  patch.badges = computeBadges({ ...w.data(), ...patch }, settings.badgeRules);
  if (decision === 'approve' && !w.data().approvedAt) patch.approvedAt = FieldValue.serverTimestamp();
  await ref.update(patch);
  await logAdminAction(admin, `worker_${decision}`, 'worker', workerId, { reason, idVerified: patch.idVerified });
  if (decision === 'approve') await notify(workerId, 'account_approved', {}, { screen: 'home' });
  if (decision === 'reject') await notify(workerId, 'account_rejected', { reason }, { screen: 'application' });
  return { ok: true };
}));

exports.adminReviewChange = onCall(wrap(async (req) => {
  const admin = requireAdmin(req, ['moderator']);
  const d = req.data || {};
  const changeId = v.idList([d.changeId], 'changeId', { min: 1, max: 1 })[0];
  const decision = v.oneOf(d.decision, 'decision', ['approve', 'reject']);
  const reason = decision === 'reject' ? v.str(d.reason, 'reason', { min: 3, max: 300 }) : '';
  const cRef = db.doc(`workerChangeRequests/${changeId}`);
  const c = await cRef.get();
  if (!c.exists || c.data().status !== 'pending') throw new HttpsError('failed-precondition', 'not-pending');
  const { workerId, changes } = c.data();
  const wRef = db.doc(`workers/${workerId}`);
  const privRef = db.doc(`workerPrivate/${workerId}`);

  if (decision === 'approve') {
    const patch = { pendingChange: false, updatedAt: FieldValue.serverTimestamp() };
    if (changes.name) { patch.name = changes.name; patch.nameLower = changes.name.toLowerCase(); }
    if (changes.categoryIds || changes.serviceIds) {
      const cur = (await wRef.get()).data();
      const cats = changes.categoryIds || cur.categoryIds;
      const svcs = changes.serviceIds || cur.serviceIds;
      const catDocs = await Promise.all(cats.map((id) => db.doc(`categories/${id}`).get()));
      const svcDocs = await Promise.all(svcs.map((id) => db.doc(`services/${id}`).get()));
      patch.categoryIds = cats;
      patch.serviceIds = svcs;
      patch.categoryNames = catDocs.filter((x) => x.exists).map((x) => ({ ar: x.data().nameAr, en: x.data().nameEn }));
      patch.serviceNames = svcDocs.filter((x) => x.exists).map((x) => ({ ar: x.data().nameAr, en: x.data().nameEn }));
      patch.searchTokens = v.searchTokens(patch.name || cur.name, ...patch.categoryNames.flatMap((n) => [n.ar, n.en]));
    } else if (patch.name) {
      const cur = (await wRef.get()).data();
      patch.searchTokens = v.searchTokens(patch.name, ...(cur.categoryNames || []).flatMap((n) => [n.ar, n.en]));
    }
    const priv = (await privRef.get()).data() || {};
    if (priv.pendingIdentity) {
      const pi = priv.pendingIdentity;
      const batch = db.batch();
      if (priv.idHash && priv.idHash !== pi.idHash) batch.delete(db.doc(`nationalIds/${priv.idHash}`));
      batch.set(db.doc(`nationalIds/${pi.idHash}`), { uid: workerId, createdAt: FieldValue.serverTimestamp() });
      batch.set(privRef, { ...pi, pendingIdentity: FieldValue.delete() }, { merge: true });
      patch.hasIdDoc = true;
      patch.idVerified = d.idVerified === true;
      await batch.commit();
    }
    await wRef.update(patch);
    await notify(workerId, 'change_approved', {}, { screen: 'profile' });
  } else {
    await wRef.update({ pendingChange: false });
    await privRef.set({ pendingIdentity: FieldValue.delete() }, { merge: true });
    await notify(workerId, 'change_rejected', { reason }, { screen: 'profile' });
  }
  await cRef.update({ status: decision === 'approve' ? 'approved' : 'rejected', reason, reviewedBy: admin.uid, reviewedAt: FieldValue.serverTimestamp() });
  await logAdminAction(admin, `change_${decision}`, 'worker', workerId, { changeId, reason });
  return { ok: true };
}));

/** عرض رقم البطاقة (فك التشفير) — للإدارة المصرح لها فقط، ويُسجّل في سجل الإدارة */
exports.adminGetWorkerPrivate = onCall(wrap(async (req) => {
  const admin = requireAdmin(req, ['moderator']);
  const workerId = v.idList([req.data && req.data.workerId], 'workerId', { min: 1, max: 1 })[0];
  const p = await db.doc(`workerPrivate/${workerId}`).get();
  if (!p.exists) return { exists: false };
  const d = p.data();
  await logAdminAction(admin, 'view_identity', 'worker', workerId, {});
  const out = {
    exists: true,
    idNumber: d.idEncrypted ? await decrypt(d.idEncrypted) : '',
    idFrontPath: d.idFrontPath || '', idBackPath: d.idBackPath || '',
  };
  if (d.pendingIdentity) {
    out.pending = {
      idNumber: await decrypt(d.pendingIdentity.idEncrypted),
      idFrontPath: d.pendingIdentity.idFrontPath, idBackPath: d.pendingIdentity.idBackPath,
    };
  }
  return out;
}));

// ---------------------------------------------------------------- المستخدمون
/** إيقاف / حظر مؤقت / حظر دائم / إعادة تفعيل */
exports.adminSetUserStatus = onCall(wrap(async (req) => {
  const admin = requireAdmin(req, ['moderator']);
  const d = req.data || {};
  const uid = v.idList([d.uid], 'uid', { min: 1, max: 1 })[0];
  const status = v.oneOf(d.status, 'status', ['active', 'suspended', 'banned']);
  const reason = v.str(d.reason, 'reason', { max: 300, required: status !== 'active' });
  const untilMs = d.until ? v.num(d.until, 'until', { min: Date.now(), max: Date.now() + 3650 * 86400000 }) : null;

  const uRef = db.doc(`users/${uid}`);
  const u = await uRef.get();
  if (!u.exists) throw new HttpsError('not-found', 'user-not-found');
  await uRef.update({
    status,
    statusReason: reason,
    bannedUntil: status === 'banned' && untilMs ? Timestamp.fromMillis(untilMs) : null,
    statusUpdatedAt: FieldValue.serverTimestamp(),
  });
  await auth.updateUser(uid, { disabled: status === 'banned' });
  if (status === 'banned') await auth.revokeRefreshTokens(uid);
  const w = await db.doc(`workers/${uid}`).get();
  if (w.exists) await w.ref.update({ suspended: status !== 'active' });
  await logAdminAction(admin, `user_${status}`, 'user', uid, { reason, until: untilMs });
  if (status !== 'banned') await notify(uid, 'account_status', { reason: reason || (status === 'active' ? '✅' : '') }, {});
  return { ok: true };
}));

exports.adminUpdateUser = onCall(wrap(async (req) => {
  const admin = requireAdmin(req, ['moderator']);
  const d = req.data || {};
  const uid = v.idList([d.uid], 'uid', { min: 1, max: 1 })[0];
  const patch = {};
  if (d.name !== undefined) { patch.name = v.str(d.name, 'name', { min: 2, max: 60 }); patch.nameLower = patch.name.toLowerCase(); }
  if (d.adminNote !== undefined) patch.adminNote = v.longText(d.adminNote, 'adminNote', { max: 1000, required: false });
  if (!Object.keys(patch).length) throw new v.ValidationError('fields', 'empty');
  await db.doc(`users/${uid}`).update(patch);
  if (patch.name) {
    const w = await db.doc(`workers/${uid}`).get();
    if (w.exists) await w.ref.update({ name: patch.name, nameLower: patch.nameLower });
  }
  await logAdminAction(admin, 'user_update', 'user', uid, patch);
  return { ok: true };
}));

/**
 * حذف الحساب (المدير العام فقط): يحذف حساب الدخول ويُخفي البيانات الشخصية
 * مع الإبقاء على سجل الطلبات والعمليات المالية لأغراض المحاسبة.
 */
exports.adminDeleteUser = onCall(wrap(async (req) => {
  const admin = requireAdmin(req, ['super']);
  const d = req.data || {};
  const uid = v.idList([d.uid], 'uid', { min: 1, max: 1 })[0];
  const reason = v.str(d.reason, 'reason', { min: 3, max: 300 });
  const wallet = await db.doc(`wallets/${uid}`).get();
  if (wallet.exists && Number(wallet.data().due || 0) > 0 && d.force !== true) {
    throw new HttpsError('failed-precondition', 'has-outstanding-commission');
  }
  try { await auth.deleteUser(uid); } catch (e) { if (e.code !== 'auth/user-not-found') throw e; }
  await db.doc(`users/${uid}`).set({
    status: 'deleted', name: 'Deleted user', nameLower: '', phone: `deleted_${uid}`, email: '', photoUrl: '',
    fcmTokens: [], devices: [], deletedAt: FieldValue.serverTimestamp(), deleteReason: reason,
  }, { merge: true });
  const w = await db.doc(`workers/${uid}`).get();
  if (w.exists) {
    await w.ref.update({
      suspended: true, verificationStatus: 'deleted', name: 'Deleted', photoUrl: '', bio: '',
      whatsapp: '', callPhone: '', phone: '', workImages: [], searchTokens: [],
    });
  }
  await logAdminAction(admin, 'user_delete', 'user', uid, { reason });
  return { ok: true };
}));

// ---------------------------------------------------------------- المالية
exports.adminReviewPayment = onCall(wrap(async (req) => {
  const admin = requireAdmin(req, ['finance']);
  const d = req.data || {};
  const paymentId = v.idList([d.paymentId], 'paymentId', { min: 1, max: 1 })[0];
  const decision = v.oneOf(d.decision, 'decision', ['confirm', 'reject']);
  const note = v.str(d.note, 'note', { max: 300, required: decision === 'reject' });
  const p = await confirmPaymentInternal(paymentId, decision, note, admin.uid);
  await logAdminAction(admin, `payment_${decision}`, 'payment', paymentId, { amount: p.amount, workerId: p.workerId, note });
  await notify(p.workerId, decision === 'confirm' ? 'payment_confirmed' : 'payment_rejected',
    { amount: p.amount, reason: note }, { screen: 'wallet' });
  return { ok: true };
}));

/** تعديل الإعدادات: نسبة العمولة، بيانات InstaPay، قواعد الشارات، نطاق الطوارئ */
exports.adminUpdateSettings = onCall(wrap(async (req) => {
  const admin = requireAdmin(req, ['finance']);
  const d = req.data || {};
  const patch = {};
  if (d.commissionRate !== undefined) patch.commissionRate = validateRate(Number(d.commissionRate));
  if (d.overdueDays !== undefined) patch.overdueDays = v.num(d.overdueDays, 'overdueDays', { min: 1, max: 90 });
  if (d.instapayHandle !== undefined) patch.instapayHandle = v.str(d.instapayHandle, 'instapayHandle', { max: 80, required: false });
  if (d.instapayPhone !== undefined) patch.instapayPhone = v.str(d.instapayPhone, 'instapayPhone', { max: 20, required: false });
  if (admin.role === 'super') {
    if (d.emergencyRadiusKm !== undefined) patch.emergencyRadiusKm = v.num(d.emergencyRadiusKm, 'emergencyRadiusKm', { min: 1, max: 100 });
    if (d.openRequestRadiusKm !== undefined) patch.openRequestRadiusKm = v.num(d.openRequestRadiusKm, 'openRequestRadiusKm', { min: 1, max: 200 });
    if (d.maxNotifiedWorkers !== undefined) patch.maxNotifiedWorkers = v.num(d.maxNotifiedWorkers, 'maxNotifiedWorkers', { min: 1, max: 200 });
    if (d.badgeRules !== undefined) patch.badgeRules = mergeRules(d.badgeRules);
  }
  if (!Object.keys(patch).length) throw new v.ValidationError('settings', 'empty');
  patch.updatedAt = FieldValue.serverTimestamp();
  patch.updatedBy = admin.uid;
  await db.doc('settings/app').set(patch, { merge: true });
  // نسخة عامة يقرأها التطبيق (بدون أي بيانات حساسة)
  const pub = {};
  if (patch.commissionRate !== undefined) pub.commissionRate = patch.commissionRate;
  if (patch.instapayHandle !== undefined) pub.instapayHandle = patch.instapayHandle;
  if (patch.instapayPhone !== undefined) pub.instapayPhone = patch.instapayPhone;
  if (patch.overdueDays !== undefined) pub.overdueDays = patch.overdueDays;
  if (Object.keys(pub).length) await db.doc('settings/public').set(pub, { merge: true });
  clearSettingsCache();
  await logAdminAction(admin, 'settings_update', 'settings', 'app', { ...patch, updatedAt: null });
  return { ok: true };
}));

// ---------------------------------------------------------------- التقييمات والبلاغات
exports.adminSetReviewHidden = onCall(wrap(async (req) => {
  const admin = requireAdmin(req, ['moderator']);
  const d = req.data || {};
  const reviewId = v.str(d.reviewId, 'reviewId', { max: 100 });
  const hidden = d.hidden === true;
  const ref = db.doc(`reviews/${reviewId}`);
  const r = await ref.get();
  if (!r.exists) throw new HttpsError('not-found', 'review-not-found');
  await ref.update({ hidden, moderatedBy: admin.uid, moderatedAt: FieldValue.serverTimestamp(), moderationNote: v.str(d.note, 'note', { max: 300, required: false }) });
  if (r.data().direction === 'c2w') await recomputeWorkerRating(r.data().toId);
  await logAdminAction(admin, hidden ? 'review_hide' : 'review_show', 'review', reviewId, {});
  return { ok: true };
}));

exports.adminUpdateReport = onCall(wrap(async (req) => {
  const admin = requireAdmin(req, ['moderator']);
  const d = req.data || {};
  const reportId = v.idList([d.reportId], 'reportId', { min: 1, max: 1 })[0];
  const status = v.oneOf(d.status, 'status', ['new', 'reviewing', 'action_taken', 'closed']);
  const patch = {
    status,
    adminNote: v.longText(d.adminNote, 'adminNote', { max: 1000, required: false }),
    actionTaken: v.str(d.actionTaken, 'actionTaken', { max: 200, required: false }),
    updatedAt: FieldValue.serverTimestamp(),
    handledBy: admin.uid,
  };
  if (d.category) patch.category = v.str(d.category, 'category', { max: 40 });
  const ref = db.doc(`reports/${reportId}`);
  const r = await ref.get();
  if (!r.exists) throw new HttpsError('not-found', 'report-not-found');
  await ref.update(patch);
  await logAdminAction(admin, 'report_update', 'report', reportId, { status, actionTaken: patch.actionTaken });
  const statusText = {
    new: { ar: 'جديد', en: 'New' }, reviewing: { ar: 'قيد المراجعة', en: 'Under review' },
    action_taken: { ar: 'تم اتخاذ إجراء', en: 'Action taken' }, closed: { ar: 'مغلق', en: 'Closed' },
  }[status];
  await notify(r.data().reporterId, 'report_update', { status: statusText }, { screen: 'reports' });
  return { ok: true };
}));

// ---------------------------------------------------------------- الإشعارات الإدارية
/**
 * target: all | customers | workers | category | governorate | user
 * التطبيق مشترك في Topics بالشكل: all_ar, customers_en, workers_ar, cat_<id>_ar, gov_<code>_en
 */
exports.adminBroadcast = onCall(wrap(async (req) => {
  const admin = requireAdmin(req, ['moderator']);
  const d = req.data || {};
  const target = v.oneOf(d.target, 'target', ['all', 'customers', 'workers', 'category', 'governorate', 'user']);
  const titleAr = v.str(d.titleAr, 'titleAr', { min: 2, max: 80 });
  const bodyAr = v.longText(d.bodyAr, 'bodyAr', { min: 2, max: 400 });
  const titleEn = v.str(d.titleEn || d.titleAr, 'titleEn', { min: 2, max: 80 });
  const bodyEn = v.longText(d.bodyEn || d.bodyAr, 'bodyEn', { min: 2, max: 400 });
  const value = d.value ? v.str(d.value, 'value', { max: 128 }) : '';

  if (target === 'user') {
    let uid = value;
    if (/^(\+?20|0)1\d{9}$/.test(value)) {
      const u = await db.collection('users').where('phone', '==', v.normalizeEgPhone(value)).limit(1).get();
      if (u.empty) throw new HttpsError('not-found', 'user-not-found');
      uid = u.docs[0].id;
    }
    const uSnap = await db.doc(`users/${uid}`).get();
    if (!uSnap.exists) throw new HttpsError('not-found', 'user-not-found');
    const lang = uSnap.data().lang === 'en' ? 'en' : 'ar';
    await db.collection(`notifications/${uid}/items`).add({
      type: 'admin', title: lang === 'en' ? titleEn : titleAr, body: lang === 'en' ? bodyEn : bodyAr,
      titleAr, bodyAr, titleEn, bodyEn, data: { type: 'admin' }, read: false, createdAt: FieldValue.serverTimestamp(),
    });
    const tokens = uSnap.data().fcmTokens || [];
    if (tokens.length) {
      await messaging.sendEachForMulticast({
        tokens, notification: { title: lang === 'en' ? titleEn : titleAr, body: lang === 'en' ? bodyEn : bodyAr },
        data: { type: 'admin' }, android: { priority: 'high', notification: { channelId: 'default' } },
      });
    }
  } else {
    const safe = (s) => s.replace(/[^a-zA-Z0-9_-]/g, '_');
    let base;
    if (target === 'all') base = 'all';
    else if (target === 'customers') base = 'customers';
    else if (target === 'workers') base = 'workers';
    else if (target === 'category') { if (!value) throw new v.ValidationError('value', 'required'); base = `cat_${safe(value)}`; }
    else { if (!value) throw new v.ValidationError('value', 'required'); base = `gov_${safe(value)}`; }
    await Promise.all([
      messaging.send({ topic: `${base}_ar`, notification: { title: titleAr, body: bodyAr }, data: { type: 'admin' }, android: { priority: 'high' } }),
      messaging.send({ topic: `${base}_en`, notification: { title: titleEn, body: bodyEn }, data: { type: 'admin' }, android: { priority: 'high' } }),
    ]);
  }
  await db.collection('broadcasts').add({
    target, value, titleAr, bodyAr, titleEn, bodyEn, sentBy: admin.uid, createdAt: FieldValue.serverTimestamp(),
  });
  await logAdminAction(admin, 'broadcast', 'notification', target, { value, titleAr });
  return { ok: true };
}));

// ---------------------------------------------------------------- صلاحيات الإدارة
/** إضافة/تعديل/إزالة مدير (المدير العام فقط) */
exports.adminSetAdminRole = onCall(wrap(async (req) => {
  const admin = requireAdmin(req, ['super']);
  const d = req.data || {};
  const email = v.str(d.email, 'email', { min: 5, max: 120 }).toLowerCase();
  const role = v.oneOf(d.role, 'role', ['super', 'moderator', 'finance', 'none']);
  const user = await auth.getUserByEmail(email).catch(() => null);
  if (!user) throw new HttpsError('not-found', 'admin-user-not-found');
  if (user.uid === admin.uid && role !== 'super') throw new HttpsError('failed-precondition', 'cannot-demote-self');
  const claims = { ...(user.customClaims || {}) };
  if (role === 'none') { delete claims.admin; delete claims.adminRole; }
  else { claims.admin = true; claims.adminRole = role; }
  await auth.setCustomUserClaims(user.uid, claims);
  await db.doc(`adminUsers/${user.uid}`).set({
    email, role, active: role !== 'none', updatedAt: FieldValue.serverTimestamp(), updatedBy: admin.uid,
  }, { merge: true });
  await logAdminAction(admin, 'admin_role', 'admin', user.uid, { email, role });
  return { ok: true };
}));

// ---------------------------------------------------------------- صاحب التطبيق
/**
 * صاحب التطبيق (OWNER_EMAIL) يسجل من لوحة التحكم بالبريد وكلمة السر أو بحساب Google،
 * وبعد تأكيد البريد يحصل على صلاحية المدير العام تلقائيًا.
 */
exports.claimOwner = onCall(wrap(async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'login-required');
  const email = String(req.auth.token.email || '').toLowerCase();
  if (!email || email !== OWNER_EMAIL) throw new HttpsError('permission-denied', 'not-owner');
  const user = await auth.getUser(req.auth.uid);
  const viaGoogle = (user.providerData || []).some((p) => p.providerId === 'google.com');
  if (!user.emailVerified && !viaGoogle) throw new HttpsError('failed-precondition', 'email-not-verified');
  await auth.setCustomUserClaims(user.uid, { ...(user.customClaims || {}), admin: true, adminRole: 'super' });
  await db.doc(`adminUsers/${user.uid}`).set({
    email, role: 'super', active: true, owner: true, updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await logAdminAction({ uid: user.uid, email }, 'owner_claim', 'admin', user.uid, {});
  return { ok: true, role: 'super' };
}));
