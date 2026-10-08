'use strict';
const { db, messaging, FieldValue } = require('./common');
const { render } = require('./lib/i18n');

/**
 * يرسل إشعار لمستخدم واحد:
 *  1) يحفظه في صندوق الإشعارات داخل التطبيق notifications/{uid}/items
 *  2) يرسل Push عبر FCM بلغة المستخدم، ويحذف التوكنات المنتهية
 *
 * @param {string} uid
 * @param {string} type نوع الإشعار (انظر lib/i18n.js)
 * @param {object} params قيم النص
 * @param {object} data بيانات للتطبيق (requestId, screen ...) — قيم نصية فقط
 * @param {{urgent?: boolean}} opts
 */
async function notify(uid, type, params = {}, data = {}, opts = {}) {
  if (!uid) return;
  try {
    const userSnap = await db.doc(`users/${uid}`).get();
    if (!userSnap.exists) return;
    const user = userSnap.data();
    const lang = user.lang === 'en' ? 'en' : 'ar';
    const text = render(type, lang, params);
    if (!text) return;

    const cleanData = {};
    for (const [k, v] of Object.entries(data || {})) if (v !== undefined && v !== null) cleanData[k] = String(v);
    cleanData.type = type;

    await db.collection(`notifications/${uid}/items`).add({
      type,
      title: text.title,
      body: text.body,
      titleAr: render(type, 'ar', params).title,
      bodyAr: render(type, 'ar', params).body,
      titleEn: render(type, 'en', params).title,
      bodyEn: render(type, 'en', params).body,
      data: cleanData,
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    });

    const tokens = Array.isArray(user.fcmTokens) ? user.fcmTokens.filter(Boolean) : [];
    if (!tokens.length) return;
    const res = await messaging.sendEachForMulticast({
      tokens,
      notification: { title: text.title, body: text.body },
      data: cleanData,
      android: {
        priority: 'high',
        notification: {
          channelId: opts.urgent ? 'urgent' : 'default',
          sound: 'default',
          tag: cleanData.requestId || undefined,
        },
      },
    });
    const bad = [];
    res.responses.forEach((r, i) => {
      const code = r.error && r.error.code;
      if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
        bad.push(tokens[i]);
      }
    });
    if (bad.length) await db.doc(`users/${uid}`).update({ fcmTokens: FieldValue.arrayRemove(...bad) });
  } catch (e) {
    // الإشعار لا يجب أن يُفشل العملية الأساسية أبدًا
    console.error('notify failed', uid, type, e.message);
  }
}

async function notifyMany(uids, type, paramsFn, dataFn, opts) {
  await Promise.all(uids.map((u) => notify(u, type, paramsFn(u), dataFn ? dataFn(u) : {}, opts)));
}

module.exports = { notify, notifyMany };
