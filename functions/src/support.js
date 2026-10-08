'use strict';
const { onCall } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onObjectFinalized } = require('firebase-functions/v2/storage');
const { db, storage, FieldValue, HttpsError, wrap, requireUser, rateLimit } = require('./common');
const v = require('./lib/validate');
const { notify } = require('./notify');

const REPORT_TYPES = ['no_show', 'bad_behavior', 'poor_quality', 'overcharge', 'fraud', 'harassment', 'fake_account', 'payment_issue', 'other'];

/** بلاغ من العميل عن صنايعي أو من الصنايعي عن عميل */
exports.submitReport = onCall(wrap(async (req) => {
  const { uid, user } = await requireUser(req);
  await rateLimit(uid, 'report', 5, 24 * 3600);
  const d = req.data || {};
  const type = v.oneOf(d.type, 'type', REPORT_TYPES);
  const description = v.longText(d.description, 'description', { min: 10, max: 2000 });
  const imagePaths = v.pathList(d.imagePaths, 'imagePaths', `reports/${uid}/`, { max: 5 });

  let requestId = null; let againstId = null; let requestCode = '';
  if (d.requestId) {
    requestId = v.idList([d.requestId], 'requestId', { min: 1, max: 1 })[0];
    const r = await db.doc(`requests/${requestId}`).get();
    if (!r.exists) throw new HttpsError('not-found', 'request-not-found');
    const rd = r.data();
    if (rd.customerId === uid) againstId = rd.workerId;
    else if (rd.workerId === uid) againstId = rd.customerId;
    else throw new HttpsError('permission-denied', 'not-participant');
    requestCode = rd.code || '';
  } else if (d.againstId) {
    againstId = v.idList([d.againstId], 'againstId', { min: 1, max: 1 })[0];
  }
  if (againstId === uid) throw new v.ValidationError('againstId', 'self');

  const ref = await db.collection('reports').add({
    reporterId: uid,
    reporterName: user.name,
    reporterRole: user.role,
    againstId: againstId || null,
    requestId, requestCode,
    type, description, imagePaths,
    status: 'new', // new → reviewing → action_taken → closed
    adminNote: '',
    actionTaken: '',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (againstId) {
    await db.doc(`users/${againstId}`).set({ reportsCount: FieldValue.increment(1) }, { merge: true });
  }
  return { reportId: ref.id };
}));

/** تذكرة دعم: تواصل مع الدعم / مشكلة تقنية */
exports.submitSupportTicket = onCall(wrap(async (req) => {
  const { uid, user } = await requireUser(req);
  await rateLimit(uid, 'ticket', 5, 24 * 3600);
  const d = req.data || {};
  const ref = await db.collection('supportTickets').add({
    uid,
    name: user.name,
    phone: user.phone,
    role: user.role,
    kind: v.oneOf(d.kind, 'kind', ['support', 'technical', 'complaint', 'suggestion']),
    subject: v.str(d.subject, 'subject', { min: 3, max: 120 }),
    message: v.longText(d.message, 'message', { min: 10, max: 3000 }),
    appVersion: v.str(d.appVersion || '', 'appVersion', { max: 20, required: false }),
    device: v.str(d.device || '', 'device', { max: 120, required: false }),
    status: 'open',
    reply: '',
    createdAt: FieldValue.serverTimestamp(),
  });
  return { ticketId: ref.id };
}));

/** إشعار برسالة شات جديدة للطرف الآخر */
exports.onChatMessage = onDocumentCreated('requests/{requestId}/messages/{messageId}', async (event) => {
  const msg = event.data && event.data.data();
  if (!msg) return;
  const reqRef = db.doc(`requests/${event.params.requestId}`);
  const r = (await reqRef.get()).data();
  if (!r) return;
  const toId = msg.senderId === r.customerId ? r.workerId : r.customerId;
  const fromName = msg.senderId === r.customerId ? r.customerName : r.workerName;
  await reqRef.update({
    lastMessageAt: FieldValue.serverTimestamp(),
    lastMessage: msg.type === 'text' ? String(msg.text).slice(0, 80) : msg.type,
    [`unread.${toId}`]: FieldValue.increment(1),
  });
  const preview = msg.type === 'text' ? String(msg.text).slice(0, 80)
    : msg.type === 'image' ? { ar: '📷 صورة', en: '📷 Photo' } : { ar: '📍 موقع', en: '📍 Location' };
  await notify(toId, 'new_message', { name: fromName, text: preview }, { requestId: event.params.requestId, screen: 'chat' });
});

/** صور البطاقة: حذف توكن الرابط العام فور الرفع (لا روابط عامة لصور الهوية) */
exports.stripIdDocTokens = onObjectFinalized(async (event) => {
  const name = event.data.name || '';
  if (!name.startsWith('idDocs/')) return;
  const file = storage.bucket(event.data.bucket).file(name);
  await file.setMetadata({ metadata: { firebaseStorageDownloadTokens: null } });
});

/** يصفّر عداد الرسائل غير المقروءة عند فتح المحادثة */
exports.markChatRead = onCall(wrap(async (req) => {
  const { uid } = await requireUser(req);
  const requestId = v.idList([req.data && req.data.requestId], 'requestId', { min: 1, max: 1 })[0];
  const ref = db.doc(`requests/${requestId}`);
  const r = await ref.get();
  if (!r.exists) throw new HttpsError('not-found', 'request-not-found');
  if (r.data().customerId !== uid && r.data().workerId !== uid) throw new HttpsError('permission-denied', 'not-participant');
  await ref.update({ [`unread.${uid}`]: 0 });
  return { ok: true };
}));

exports.REPORT_TYPES = REPORT_TYPES;
