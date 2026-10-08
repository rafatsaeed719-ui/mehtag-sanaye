'use strict';
/**
 * إنشاء حساب مدير للوحة التحكم.
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *   node scripts/create-admin.js you@example.com super        # حسابك الحقيقي
 *   node scripts/create-admin.js --demo                       # حساب تجريبي للاختبار فقط
 *
 * الأدوار: super (كل الصلاحيات) | moderator (الصنايعية/البلاغات/التقييمات) | finance (المالية)
 * كلمة المرور تُولّد عشوائيًا وتُطبع مرة واحدة فقط — احفظها، ولا تُحفظ في أي مكان.
 * الحساب التجريبي: احذفه قبل الإطلاق:  node scripts/create-admin.js --remove-demo
 */
const admin = require('firebase-admin');
const crypto = require('crypto');

admin.initializeApp();
const auth = admin.auth();
const db = admin.firestore();
const DEMO_EMAIL = 'demo-admin@mehtag-sanaye.test';

function strongPassword() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%*?';
  return Array.from(crypto.randomBytes(20), (b) => chars[b % chars.length]).join('');
}

(async () => {
  const args = process.argv.slice(2);
  if (args[0] === '--remove-demo') {
    const u = await auth.getUserByEmail(DEMO_EMAIL).catch(() => null);
    if (u) { await auth.deleteUser(u.uid); await db.doc(`adminUsers/${u.uid}`).delete(); }
    console.log('✅ Demo admin removed.');
    return process.exit(0);
  }
  const demo = args[0] === '--demo';
  const email = demo ? DEMO_EMAIL : (args[0] || '').toLowerCase();
  const role = demo ? 'moderator' : (args[1] || 'super');
  if (!email.includes('@') || !['super', 'moderator', 'finance'].includes(role)) {
    console.error('Usage: node scripts/create-admin.js <email> <super|moderator|finance>  |  --demo  |  --remove-demo');
    return process.exit(1);
  }
  // كلمة المرور من متغير بيئة (GitHub Secret) — وإلا تُولّد عشوائيًا وتُطبع مرة واحدة
  const fromEnv = demo ? process.env.DEMO_ADMIN_PASSWORD : process.env.ADMIN_PASSWORD;
  if (fromEnv && fromEnv.length < 12) { console.error('Password must be at least 12 characters'); return process.exit(1); }
  const password = fromEnv || strongPassword();
  let user = await auth.getUserByEmail(email).catch(() => null);
  if (user) await auth.updateUser(user.uid, { password });
  else user = await auth.createUser({ email, password, emailVerified: true, displayName: demo ? 'Demo Admin' : 'Admin' });
  await auth.setCustomUserClaims(user.uid, { ...(user.customClaims || {}), admin: true, adminRole: role, demo });
  await db.doc(`adminUsers/${user.uid}`).set({ email, role, active: true, demo, createdAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  console.log('\n✅ Admin ready');
  console.log('   Email   :', email);
  console.log('   Password:', fromEnv ? '(from secret — not printed)' : `${password}   (shown once — save it now)`);
  console.log('   Role    :', role, demo ? '(DEMO — remove before launch)' : '');
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
