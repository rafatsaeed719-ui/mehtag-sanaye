// يتأكد من حالة حساب صاحب التطبيق (موجود؟ البريد متأكد؟ مدير؟)
const admin = require('firebase-admin');
admin.initializeApp();
const EMAIL = 'rafatsaeed719@gmail.com';
(async () => {
  try {
    const u = await admin.auth().getUserByEmail(EMAIL);
    const a = await admin.firestore().doc(`admins/${u.uid}`).get();
    console.log(`OWNER exists uid=${u.uid} verified=${u.emailVerified} providers=${u.providerData.map((p) => p.providerId).join(',')} admin=${a.exists ? JSON.stringify(a.data().role) : 'no'}`);
  } catch (e) {
    console.log(`OWNER ${e.code || e.message}`);
  }
})();
