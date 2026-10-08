'use strict';
/**
 * تهيئة قاعدة البيانات بالكتالوج الأساسي (مهن + خدمات + محافظات + إعدادات).
 * آمن للتشغيل أكثر من مرة (لا يكرر ولا يمسح تعديلاتك من لوحة التحكم إلا لو استخدمت --overwrite).
 *
 * التشغيل:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *   node scripts/seed.js            # يضيف الناقص فقط
 *   node scripts/seed.js --overwrite
 */
const admin = require('firebase-admin');
const { categories, governorates } = require('./catalog-data');

admin.initializeApp();
const db = admin.firestore();
const overwrite = process.argv.includes('--overwrite');

async function upsert(ref, data) {
  const s = await ref.get();
  if (s.exists && !overwrite) return false;
  await ref.set({ ...data, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  return true;
}

(async () => {
  let n = 0;
  for (const [i, c] of categories.entries()) {
    if (await upsert(db.doc(`categories/${c.id}`), {
      nameAr: c.nameAr, nameEn: c.nameEn, icon: c.icon, iconUrl: '', active: true, order: i,
    })) n++;
    for (const [j, [ar, en]] of c.services.entries()) {
      if (await upsert(db.doc(`services/${c.id}_${j + 1}`), {
        categoryId: c.id, nameAr: ar, nameEn: en, active: true, order: j,
      })) n++;
    }
  }
  for (const [i, [code, ar, en, lat, lng]] of governorates.entries()) {
    if (await upsert(db.doc(`locations/gov_${code}`), {
      type: 'governorate', code, nameAr: ar, nameEn: en, parentId: '', order: i, active: true, lat, lng,
    })) n++;
  }
  await upsert(db.doc('settings/app'), {
    commissionRate: 0.05, overdueDays: 7, instapayHandle: '', instapayPhone: '',
    emergencyRadiusKm: 15, openRequestRadiusKm: 25, maxNotifiedWorkers: 30,
    badgeRules: {
      topRated: { enabled: true, minAvg: 4.7, minCount: 10 },
      mostCompleted: { enabled: true, minCompleted: 50 },
      fastResponse: { enabled: true, maxAvgMinutes: 15, minResponses: 5, minResponseRate: 0.8 },
    },
  });
  await upsert(db.doc('settings/public'), {
    commissionRate: 0.05, overdueDays: 7, instapayHandle: '', instapayPhone: '',
    supportPhone: '', supportWhatsapp: '', supportEmail: '',
    playStoreUrl: 'https://play.google.com/store/apps/details?id=com.mehtagsanaye.app',
    minAppVersion: 1,
  });
  console.log(`✅ Seed done. ${n} documents written.`);
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
