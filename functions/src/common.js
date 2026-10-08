'use strict';
const admin = require('firebase-admin');
const { HttpsError } = require('firebase-functions/v2/https');
const crypto = require('crypto');
const { ValidationError } = require('./lib/validate');
const { TransitionError } = require('./lib/statusMachine');
const { CommissionError } = require('./lib/commission');

if (!admin.apps.length) admin.initializeApp();

const db = admin.firestore();
const auth = admin.auth();
const messaging = admin.messaging();
const storage = admin.storage();
const { FieldValue, Timestamp } = admin.firestore;

const REGION = 'europe-west1';

const DEFAULT_SETTINGS = Object.freeze({
  commissionRate: 0.05,
  overdueDays: 7,
  instapayHandle: '',
  instapayPhone: '',
  emergencyRadiusKm: 15,
  openRequestRadiusKm: 25,
  maxNotifiedWorkers: 30,
  badgeRules: null,
});

let settingsCache = null;
let settingsCacheAt = 0;
async function getSettings() {
  if (settingsCache && Date.now() - settingsCacheAt < 60 * 1000) return settingsCache;
  const snap = await db.doc('settings/app').get();
  settingsCache = { ...DEFAULT_SETTINGS, ...(snap.exists ? snap.data() : {}) };
  settingsCacheAt = Date.now();
  return settingsCache;
}
function clearSettingsCache() { settingsCache = null; }

/** يحوّل أخطاء المنطق الداخلي لأخطاء HTTPS مفهومة للتطبيق */
function wrap(handler) {
  return async (req) => {
    try {
      return await handler(req);
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      if (e instanceof ValidationError) throw new HttpsError('invalid-argument', e.message, { field: e.field, code: e.code });
      if (e instanceof TransitionError) throw new HttpsError('failed-precondition', e.code, { code: e.code, detail: e.detail });
      if (e instanceof CommissionError) throw new HttpsError('invalid-argument', e.code, { code: e.code });
      console.error('Unhandled error', e);
      throw new HttpsError('internal', 'server-error');
    }
  };
}

/** يتحقق أن المستخدم مسجل ونشط (غير موقوف/محظور) ويعيد بياناته */
async function requireUser(req, { roles } = {}) {
  if (!req.auth) throw new HttpsError('unauthenticated', 'login-required');
  const uid = req.auth.uid;
  const snap = await db.doc(`users/${uid}`).get();
  if (!snap.exists) throw new HttpsError('failed-precondition', 'profile-missing');
  const user = snap.data();
  if (user.status !== 'active') throw new HttpsError('permission-denied', 'account-' + user.status);
  if (roles && !roles.includes(user.role)) throw new HttpsError('permission-denied', 'wrong-role');
  return { uid, user };
}

/** صلاحيات الإدارة: super | moderator | finance */
function requireAdmin(req, roles = ['super']) {
  if (!req.auth || req.auth.token.admin !== true) throw new HttpsError('permission-denied', 'admin-only');
  const role = req.auth.token.adminRole || 'moderator';
  if (role !== 'super' && !roles.includes(role)) throw new HttpsError('permission-denied', 'admin-role');
  return { uid: req.auth.uid, role, email: req.auth.token.email || '' };
}

/** Rate limiting بسيط بنافذة زمنية ثابتة لكل مستخدم/عملية */
async function rateLimit(uid, key, max, windowSec) {
  const ref = db.doc(`rateLimits/${uid}_${key}`);
  const now = Date.now();
  await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const d = s.exists ? s.data() : { start: now, count: 0 };
    if (now - d.start > windowSec * 1000) { d.start = now; d.count = 0; }
    if (d.count >= max) throw new HttpsError('resource-exhausted', 'rate-limited');
    d.count += 1;
    tx.set(ref, d);
  });
}

async function logAdminAction(adminInfo, action, targetType, targetId, details = {}) {
  await db.collection('adminActions').add({
    adminId: adminInfo.uid,
    adminEmail: adminInfo.email || '',
    action, targetType, targetId,
    details,
    createdAt: FieldValue.serverTimestamp(),
  });
}

/** مفتاح التشفير والـpepper للهوية — يُنشأ تلقائيًا ويُخزن في وثيقة لا يقرأها أي عميل */
let secretCache = null;
async function getSecrets() {
  if (secretCache) return secretCache;
  const ref = db.doc('secrets/identity');
  secretCache = await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (s.exists) return s.data();
    const d = {
      pepper: crypto.randomBytes(32).toString('hex'),
      encKey: crypto.randomBytes(32).toString('base64'),
      createdAt: FieldValue.serverTimestamp(),
    };
    tx.set(ref, d);
    return d;
  });
  return secretCache;
}

async function hashNationalId(id) {
  const { pepper } = await getSecrets();
  return crypto.createHmac('sha256', pepper).update(id).digest('hex');
}

async function encrypt(text) {
  const { encKey } = await getSecrets();
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', Buffer.from(encKey, 'base64'), iv);
  const enc = Buffer.concat([c.update(text, 'utf8'), c.final()]);
  return [iv.toString('base64'), c.getAuthTag().toString('base64'), enc.toString('base64')].join('.');
}

async function decrypt(payload) {
  if (!payload) return '';
  const { encKey } = await getSecrets();
  const [iv, tag, data] = payload.split('.');
  const d = crypto.createDecipheriv('aes-256-gcm', Buffer.from(encKey, 'base64'), Buffer.from(iv, 'base64'));
  d.setAuthTag(Buffer.from(tag, 'base64'));
  return Buffer.concat([d.update(Buffer.from(data, 'base64')), d.final()]).toString('utf8');
}

/** مفتاح يوم بتوقيت القاهرة للإحصائيات اليومية */
function dayKey(date = new Date()) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo', year: 'numeric', month: '2-digit', day: '2-digit' })
    .format(date);
}

function statsRef(date) { return db.doc(`dailyStats/${dayKey(date)}`); }

module.exports = {
  admin, db, auth, messaging, storage, FieldValue, Timestamp, HttpsError, REGION,
  getSettings, clearSettingsCache, wrap, requireUser, requireAdmin, rateLimit, logAdminAction,
  hashNationalId, encrypt, decrypt, dayKey, statsRef, DEFAULT_SETTINGS,
};
