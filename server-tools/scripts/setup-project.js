'use strict';
/**
 * إعداد مشروع Firebase أوتوماتيك (خطة Spark المجانية) باستخدام حساب الخدمة:
 *   1) إنشاء قاعدة Firestore لو مش موجودة
 *   2) تفعيل الدخول بالبريد وكلمة السر
 *   3) تسجيل تطبيق الويب (لوحة التحكم) وكتابة admin/config.js
 *   4) تحديث android/app/google-services.json (عشان Google Sign-In)
 * أي خطوة تفشل بتطبع المطلوب يدويًا وتكمل الباقي.
 *
 *   GOOGLE_APPLICATION_CREDENTIALS=sa.json node scripts/setup-project.js
 */
const fs = require('fs');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');

const sa = JSON.parse(fs.readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));
const PROJECT = process.env.FIREBASE_PROJECT_ID || sa.project_id;
const ROOT = path.resolve(__dirname, '../..');
const ANDROID_PACKAGE = 'com.mehtagsanaye.app';

const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform', 'https://www.googleapis.com/auth/firebase'] });
let client;
async function api(method, url, body) {
  client = client || (await auth.getClient());
  try {
    const res = await client.request({ method, url, data: body, validateStatus: () => true });
    return { status: res.status, data: res.data };
  } catch (e) {
    return { status: 0, data: { error: { message: e.message } } };
  }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const summary = [];
const ok = (m) => { console.log('✅ ' + m); summary.push('✅ ' + m); };
const warn = (m) => { console.log('⚠️  ' + m); summary.push('⚠️ ' + m); };

async function waitOp(base, op) {
  for (let i = 0; i < 30 && op && !op.done; i++) {
    await sleep(3000);
    const r = await api('GET', `${base}/${op.name}`);
    op = r.data;
  }
  return op;
}

async function firestoreDb() {
  const base = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases`;
  const g = await api('GET', `${base}/(default)`);
  if (g.status === 200) return ok('قاعدة البيانات Firestore موجودة');
  const c = await api('POST', `${base}?databaseId=(default)`, { locationId: 'eur3', type: 'FIRESTORE_NATIVE' });
  if (c.status === 200) {
    await waitOp('https://firestore.googleapis.com/v1', c.data);
    return ok('تم إنشاء قاعدة البيانات Firestore (eur3)');
  }
  warn(`ماقدرتش أنشئ قاعدة البيانات أوتوماتيك (${c.status}): ${c.data?.error?.message || ''}
   → من Firebase Console: Build → Firestore Database → Create database → Production mode → eur3`);
}

async function emailAuth() {
  const url = `https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT}/config`;
  const r = await api('PATCH', `${url}?updateMask=signIn.email.enabled,signIn.email.passwordRequired`, {
    signIn: { email: { enabled: true, passwordRequired: true } },
  });
  if (r.status === 200) return ok('تم تفعيل الدخول بالبريد وكلمة السر');
  warn(`ماقدرتش أفعّل الدخول بالبريد أوتوماتيك (${r.status}): ${r.data?.error?.message || ''}
   → من Firebase Console: Build → Authentication → Get started → Sign-in method → Email/Password → Enable`);
}

async function googleProviderStatus() {
  const r = await api('GET', `https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT}/defaultSupportedIdpConfigs/google.com`);
  if (r.status === 200 && r.data.enabled) return ok('الدخول بـ Google مفعّل');
  warn(`الدخول بـ Google مش مفعّل
   → من Firebase Console: Authentication → Sign-in method → Add new provider → Google → Enable → Save`);
}

async function webApp() {
  const base = `https://firebase.googleapis.com/v1beta1/projects/${PROJECT}`;
  let list = await api('GET', `${base}/webApps`);
  if (list.status !== 200) {
    return warn(`ماقدرتش أقرأ تطبيقات الويب (${list.status}): ${list.data?.error?.message || ''}
   → سجّل تطبيق ويب يدوي: Project settings → Add app → Web، وابعت الكود لـ Claude`);
  }
  let app = (list.data.apps || [])[0];
  if (!app) {
    const c = await api('POST', `${base}/webApps`, { displayName: 'لوحة التحكم' });
    if (c.status !== 200) return warn(`ماقدرتش أسجل تطبيق الويب (${c.status}): ${c.data?.error?.message || ''}`);
    await waitOp('https://firebase.googleapis.com/v1beta1', c.data);
    list = await api('GET', `${base}/webApps`);
    app = (list.data.apps || [])[0];
  }
  if (!app) return warn('تطبيق الويب لسه مش جاهز — أعد التشغيل بعد دقيقة');
  const cfg = await api('GET', `https://firebase.googleapis.com/v1beta1/${app.name}/config`);
  if (cfg.status !== 200) return warn(`ماقدرتش أقرأ إعدادات تطبيق الويب (${cfg.status})`);
  const c = cfg.data;
  const file = path.join(ROOT, 'admin/config.js');
  const content = `// =============================================================
//  إعدادات لوحة التحكم — بتتكتب أوتوماتيك من workflow الإعداد
// =============================================================
export const firebaseConfig = ${JSON.stringify({
    apiKey: c.apiKey, authDomain: c.authDomain || `${PROJECT}.firebaseapp.com`, projectId: c.projectId,
    storageBucket: c.storageBucket || '', messagingSenderId: c.messagingSenderId, appId: c.appId,
  }, null, 2)};

// صاحب التطبيق — يصبح مديرًا عامًا تلقائيًا بعد تأكيد بريده
export const OWNER_EMAIL = 'rafatsaeed719@gmail.com';
`;
  fs.writeFileSync(file, content);
  ok('تم تجهيز إعدادات لوحة التحكم (admin/config.js)');
}

async function androidConfig() {
  const base = `https://firebase.googleapis.com/v1beta1/projects/${PROJECT}`;
  const list = await api('GET', `${base}/androidApps`);
  const app = (list.data?.apps || []).find((a) => a.packageName === ANDROID_PACKAGE);
  if (!app) return warn(`مفيش تطبيق Android بالحزمة ${ANDROID_PACKAGE} في المشروع`);
  const cfg = await api('GET', `https://firebase.googleapis.com/v1beta1/${app.name}/config`);
  if (cfg.status !== 200) return warn(`ماقدرتش أنزل google-services.json (${cfg.status})`);
  const json = Buffer.from(cfg.data.configFileContents, 'base64').toString('utf8');
  const parsed = JSON.parse(json);
  const hasOAuth = (parsed.client || []).some((c) => (c.oauth_client || []).length > 0);
  fs.writeFileSync(path.join(ROOT, 'app/android/app/google-services.json'), json);
  if (hasOAuth) ok('تم تحديث google-services.json (فيه إعدادات الدخول بـ Google)');
  else warn('google-services.json اتحدث، بس لسه مفيهوش إعدادات Google — فعّل Google في Authentication وأعد التشغيل');
}

(async () => {
  console.log(`مشروع: ${PROJECT}\n`);
  await firestoreDb();
  await emailAuth();
  await googleProviderStatus();
  await webApp();
  await androidConfig();
  fs.writeFileSync(path.join(ROOT, 'setup-summary.md'), `## نتيجة الإعداد\n\n${summary.join('\n\n')}\n`);
  console.log('\n' + summary.join('\n'));
})().catch((e) => { console.error(e); process.exit(1); });
