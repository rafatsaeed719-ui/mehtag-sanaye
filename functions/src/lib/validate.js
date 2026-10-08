'use strict';
/** Input validation helpers — كل مدخلات الـAPI تمر من هنا */

class ValidationError extends Error {
  constructor(field, code = 'invalid') { super(`${field}:${code}`); this.field = field; this.code = code; }
}

const EG_MOBILE = /^01[0125][0-9]{8}$/;
const NATIONAL_ID = /^[23][0-9]{13}$/;

function str(v, field, { min = 0, max = 500, required = true } = {}) {
  if (v === undefined || v === null || v === '') {
    if (required) throw new ValidationError(field, 'required');
    return '';
  }
  if (typeof v !== 'string') throw new ValidationError(field, 'type');
  const s = v.trim().replace(/\s+/g, ' ');
  if (s.length < min) throw new ValidationError(field, 'too-short');
  if (s.length > max) throw new ValidationError(field, 'too-long');
  return s;
}

function longText(v, field, { min = 0, max = 2000, required = true } = {}) {
  if (v === undefined || v === null || v === '') {
    if (required) throw new ValidationError(field, 'required');
    return '';
  }
  if (typeof v !== 'string') throw new ValidationError(field, 'type');
  const s = v.trim();
  if (s.length < min) throw new ValidationError(field, 'too-short');
  if (s.length > max) throw new ValidationError(field, 'too-long');
  return s;
}

function num(v, field, { min = -Infinity, max = Infinity, required = true } = {}) {
  if (v === undefined || v === null || v === '') {
    if (required) throw new ValidationError(field, 'required');
    return null;
  }
  const n = typeof v === 'string' ? Number(v) : v;
  if (typeof n !== 'number' || !Number.isFinite(n)) throw new ValidationError(field, 'type');
  if (n < min || n > max) throw new ValidationError(field, 'range');
  return n;
}

function oneOf(v, field, list) {
  if (!list.includes(v)) throw new ValidationError(field, 'invalid');
  return v;
}

function idList(v, field, { min = 0, max = 10 } = {}) {
  if (!Array.isArray(v)) throw new ValidationError(field, 'type');
  const out = [...new Set(v.filter((x) => typeof x === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(x)))];
  if (out.length !== v.length && out.length < v.length) {
    // duplicates or invalid ids dropped
  }
  if (out.length < min) throw new ValidationError(field, 'too-few');
  if (out.length > max) throw new ValidationError(field, 'too-many');
  return out;
}

function storagePath(v, field, prefix, { required = true } = {}) {
  if (v === undefined || v === null || v === '') {
    if (required) throw new ValidationError(field, 'required');
    return null;
  }
  if (typeof v !== 'string' || !v.startsWith(prefix) || v.includes('..') || v.length > 300) {
    throw new ValidationError(field, 'invalid-path');
  }
  return v;
}

function pathList(v, field, prefix, { max = 10 } = {}) {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v) || v.length > max) throw new ValidationError(field, 'too-many');
  return v.map((p) => storagePath(p, field, prefix));
}

/** يقبل روابط Firebase Storage (وصورة حساب Google) فقط — يمنع روابط خارجية عشوائية */
function urlList(v, field, { max = 12 } = {}) {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v) || v.length > max) throw new ValidationError(field, 'too-many');
  return v.map((u) => {
    if (typeof u !== 'string' || u.length > 1000 || !/^https:\/\/(firebasestorage\.googleapis\.com|lh3\.googleusercontent\.com)\//.test(u)) {
      throw new ValidationError(field, 'invalid-url');
    }
    return u;
  });
}

function mobile(v, field, { required = true } = {}) {
  if (!v) { if (required) throw new ValidationError(field, 'required'); return ''; }
  const s = normalizeEgPhone(v);
  if (!EG_MOBILE.test(s)) throw new ValidationError(field, 'invalid-phone');
  return s;
}

/** +201xxxxxxxxx | 00201.. | 01.. → 01xxxxxxxxx */
function normalizeEgPhone(v) {
  let s = String(v).replace(/[\s-]/g, '');
  s = s.replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)));
  if (s.startsWith('+20')) s = '0' + s.slice(3);
  else if (s.startsWith('0020')) s = '0' + s.slice(4);
  else if (s.startsWith('20') && s.length === 12) s = '0' + s.slice(2);
  return s;
}

function nationalId(v, field, { required = false } = {}) {
  if (!v) { if (required) throw new ValidationError(field, 'required'); return ''; }
  const s = String(v).replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d))).replace(/\s/g, '');
  if (!NATIONAL_ID.test(s)) throw new ValidationError(field, 'invalid-national-id');
  return s;
}

/** كلمات البحث بالاسم: بادئات كل كلمة (عربي/إنجليزي) */
function searchTokens(...texts) {
  const tokens = new Set();
  for (const t of texts) {
    if (!t) continue;
    const words = normalizeArabic(String(t).toLowerCase()).split(/[\s,.-]+/).filter(Boolean);
    for (const w of words) {
      for (let i = 2; i <= Math.min(w.length, 15); i++) tokens.add(w.slice(0, i));
    }
  }
  return [...tokens].slice(0, 200);
}

/** توحيد الحروف العربية: أ/إ/آ→ا، ة→ه، ى→ي، وحذف التشكيل */
function normalizeArabic(s) {
  return s
    .replace(/[ً-ْـ]/g, '')
    .replace(/[أإآ]/g, 'ا')
    .replace(/ة/g, 'ه')
    .replace(/ى/g, 'ي');
}

module.exports = {
  ValidationError, str, longText, num, oneOf, idList, storagePath, pathList, urlList,
  mobile, normalizeEgPhone, nationalId, searchTokens, normalizeArabic,
};
