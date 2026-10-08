'use strict';
/**
 * Geohash + nearby queries (نفس الخوارزمية موجودة في التطبيق lib/core/utils/geo.dart)
 *
 * Firestore لا يدعم البحث الجغرافي مباشرة، لذلك نخزن لكل صنايعي/طلب "geohash"
 * ونبحث بنطاقات geohash تغطي دائرة البحث، ثم نفلتر بالمسافة الحقيقية.
 * بهذا لا نحمّل كل الصنايعية أبدًا.
 */

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';
const EARTH_RADIUS_KM = 6371;

function encode(lat, lng, precision = 10) {
  let latMin = -90, latMax = 90, lngMin = -180, lngMax = 180;
  let hash = '';
  let bit = 0, ch = 0, even = true;
  while (hash.length < precision) {
    if (even) {
      const mid = (lngMin + lngMax) / 2;
      if (lng >= mid) { ch = (ch << 1) | 1; lngMin = mid; } else { ch = ch << 1; lngMax = mid; }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat >= mid) { ch = (ch << 1) | 1; latMin = mid; } else { ch = ch << 1; latMax = mid; }
    }
    even = !even;
    if (++bit === 5) { hash += BASE32[ch]; bit = 0; ch = 0; }
  }
  return hash;
}

function distanceKm(lat1, lng1, lat2, lng2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** حجم خلية geohash بالكيلومتر عند دقة معينة وخط عرض معين */
function cellSizeKm(precision, lat) {
  const bits = precision * 5;
  const lngBits = Math.ceil(bits / 2);
  const latBits = Math.floor(bits / 2);
  const latDeg = 180 / 2 ** latBits;
  const lngDeg = 360 / 2 ** lngBits;
  const kmPerDeg = (Math.PI * EARTH_RADIUS_KM) / 180;
  return {
    height: latDeg * kmPerDeg,
    width: lngDeg * kmPerDeg * Math.cos((lat * Math.PI) / 180),
  };
}

/**
 * نطاقات [start, end] تغطي دائرة نصف قطرها radiusKm.
 * نختار أدق precision تكون فيه الخلية >= نصف القطر، ثم نأخذ geohash
 * المركز و8 نقاط على حدود المربع المحيط بالدائرة؛ لأن المسافة بين النقاط
 * أقل من حجم الخلية فلا توجد خلية متخطاة.
 */
function queryBounds(lat, lng, radiusKm) {
  let precision = 1;
  for (let p = 9; p >= 1; p--) {
    const c = cellSizeKm(p, lat);
    if (c.width >= radiusKm && c.height >= radiusKm) { precision = p; break; }
  }
  const dLat = radiusKm / 111.32;
  const cosLat = Math.max(0.01, Math.cos((lat * Math.PI) / 180));
  const dLng = radiusKm / (111.32 * cosLat);
  const hashes = new Set();
  for (const a of [-1, 0, 1]) {
    for (const b of [-1, 0, 1]) {
      const pLat = Math.max(-89.9999, Math.min(89.9999, lat + a * dLat));
      let pLng = lng + b * dLng;
      if (pLng > 180) pLng -= 360;
      if (pLng < -180) pLng += 360;
      hashes.add(encode(pLat, pLng, precision));
    }
  }
  return [...hashes].sort().map((h) => [h, h + '~']);
}

/** هل الإحداثيات داخل مصر تقريبًا؟ (حماية من مدخلات عشوائية) */
function isInEgypt(lat, lng) {
  return typeof lat === 'number' && typeof lng === 'number' &&
    lat >= 21.5 && lat <= 31.8 && lng >= 24.5 && lng <= 37.2;
}

module.exports = { encode, distanceKm, queryBounds, cellSizeKm, isInEgypt };
