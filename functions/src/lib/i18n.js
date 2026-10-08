'use strict';
/**
 * نصوص الإشعارات بالعربي والإنجليزي.
 * {param} يتم استبداله بالقيمة. اللغة تؤخذ من users/{uid}.lang
 */

const T = {
  new_request: {
    ar: ['طلب جديد 🔧', 'لديك طلب {service} جديد من {name}'],
    en: ['New request 🔧', 'You have a new {service} request from {name}'],
  },
  nearby_request: {
    ar: ['طلب قريب منك 📍', 'طلب {service} على بعد {km} كم'],
    en: ['Request near you 📍', '{service} request {km} km away'],
  },
  emergency_request: {
    ar: ['🚨 طلب طوارئ قريب', 'محتاج {service} الآن على بعد {km} كم — افتح الطلب واقبله'],
    en: ['🚨 Urgent request nearby', 'Someone needs a {service} now, {km} km away — open to accept'],
  },
  request_accepted: {
    ar: ['تم قبول طلبك ✅', '{name} قبل طلبك'],
    en: ['Request accepted ✅', '{name} accepted your request'],
  },
  request_rejected: {
    ar: ['تم رفض الطلب', 'اعتذر {name} عن طلبك، جرّب صنايعي آخر'],
    en: ['Request declined', '{name} declined your request, try another worker'],
  },
  time_proposed: {
    ar: ['موعد مقترح 🕒', '{name} اقترح موعدًا جديدًا: {time}'],
    en: ['New time proposed 🕒', '{name} proposed a new time: {time}'],
  },
  proposal_accepted: {
    ar: ['تم تأكيد الموعد ✅', 'العميل وافق على الموعد {time}'],
    en: ['Appointment confirmed ✅', 'The customer accepted the time {time}'],
  },
  on_the_way: {
    ar: ['الصنايعي في الطريق 🚗', '{name} في الطريق إليك'],
    en: ['Worker on the way 🚗', '{name} is on the way'],
  },
  started: {
    ar: ['بدأ العمل 🛠️', '{name} بدأ العمل على طلبك'],
    en: ['Work started 🛠️', '{name} started working on your request'],
  },
  completed: {
    ar: ['تم الانتهاء 🎉', '{name} أنهى العمل. قيّم التجربة من فضلك'],
    en: ['Job completed 🎉', '{name} finished the job. Please rate your experience'],
  },
  price_set: {
    ar: ['تأكيد قيمة الخدمة 💵', '{name} سجّل قيمة الخدمة {price} جنيه — أكّدها من التطبيق'],
    en: ['Confirm service price 💵', '{name} entered the service price {price} EGP — please confirm'],
  },
  price_confirmed: {
    ar: ['تم تأكيد السعر ✅', 'العميل أكد قيمة الخدمة {price} جنيه. عمولة التطبيق {commission} جنيه'],
    en: ['Price confirmed ✅', 'Customer confirmed {price} EGP. App commission: {commission} EGP'],
  },
  price_disputed: {
    ar: ['اعتراض على السعر', 'العميل لم يوافق على القيمة المسجلة. تواصلوا وسجّل القيمة الصحيحة'],
    en: ['Price disputed', 'The customer did not confirm the price. Talk and enter the correct amount'],
  },
  request_cancelled: {
    ar: ['تم إلغاء الطلب', 'تم إلغاء طلب {service}'],
    en: ['Request cancelled', 'The {service} request was cancelled'],
  },
  open_request_taken: {
    ar: ['تم قبول طلبك ✅', '{name} قبل طلبك وسيتواصل معك'],
    en: ['Request accepted ✅', '{name} accepted your request and will contact you'],
  },
  new_message: {
    ar: ['رسالة جديدة 💬', '{name}: {text}'],
    en: ['New message 💬', '{name}: {text}'],
  },
  review_requested: {
    ar: ['قيّم التجربة ⭐', 'رأيك يساعد الجميع — قيّم {name}'],
    en: ['Rate your experience ⭐', 'Your feedback helps everyone — rate {name}'],
  },
  review_received: {
    ar: ['تقييم جديد ⭐', 'حصلت على تقييم {stars} نجوم'],
    en: ['New review ⭐', 'You received a {stars}-star review'],
  },
  account_approved: {
    ar: ['تم توثيق حسابك 🟢', 'مبروك! حسابك اتقبل وتقدر تستقبل الطلبات دلوقتي'],
    en: ['Account approved 🟢', 'Congrats! Your account is approved and you can receive requests now'],
  },
  account_rejected: {
    ar: ['لم يتم قبول الحساب', 'السبب: {reason}. عدّل بياناتك وأعد التقديم'],
    en: ['Account not approved', 'Reason: {reason}. Update your details and resubmit'],
  },
  change_approved: {
    ar: ['تم اعتماد التعديل ✅', 'تم اعتماد التعديلات على بياناتك'],
    en: ['Changes approved ✅', 'Your profile changes were approved'],
  },
  change_rejected: {
    ar: ['لم يتم اعتماد التعديل', 'السبب: {reason}'],
    en: ['Changes not approved', 'Reason: {reason}'],
  },
  commission_due: {
    ar: ['عمولة مستحقة 💳', 'عمولة التطبيق {commission} جنيه على الطلب الأخير'],
    en: ['Commission due 💳', 'App commission of {commission} EGP for your last job'],
  },
  commission_overdue: {
    ar: ['تذكير بالعمولة المتأخرة', 'عليك عمولات متأخرة بقيمة {amount} جنيه. ادفعها عبر InstaPay'],
    en: ['Overdue commission reminder', 'You have {amount} EGP overdue. Please pay via InstaPay'],
  },
  payment_confirmed: {
    ar: ['تم تأكيد الدفع ✅', 'تم تأكيد تحويلك بقيمة {amount} جنيه. شكرًا لك'],
    en: ['Payment confirmed ✅', 'Your transfer of {amount} EGP was confirmed. Thank you'],
  },
  payment_rejected: {
    ar: ['لم يتم تأكيد الدفع', 'لم نتمكن من مطابقة التحويل. السبب: {reason}'],
    en: ['Payment not confirmed', 'We could not match your transfer. Reason: {reason}'],
  },
  account_status: {
    ar: ['حالة الحساب', '{reason}'],
    en: ['Account status', '{reason}'],
  },
  report_update: {
    ar: ['تحديث على بلاغك', 'تم تحديث حالة البلاغ: {status}'],
    en: ['Report update', 'Your report status changed: {status}'],
  },
};

function render(type, lang, params = {}) {
  const entry = T[type];
  if (!entry) return null;
  const pair = entry[lang === 'en' ? 'en' : 'ar'];
  const l = lang === 'en' ? 'en' : 'ar';
  const val = (v) => {
    if (v === undefined || v === null) return '';
    if (typeof v === 'object' && ('ar' in v || 'en' in v)) return String(v[l] || v.ar || v.en || '');
    return String(v);
  };
  const fill = (s) => s.replace(/\{(\w+)\}/g, (_, k) => val(params[k]));
  return { title: fill(pair[0]), body: fill(pair[1]) };
}

/** وقت مقروء بتوقيت القاهرة */
function formatTime(ms, lang) {
  try {
    return new Date(ms).toLocaleString(lang === 'en' ? 'en-GB' : 'ar-EG', {
      timeZone: 'Africa/Cairo', weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit',
    });
  } catch (_) {
    return new Date(ms).toISOString();
  }
}

module.exports = { T, render, formatTime };
