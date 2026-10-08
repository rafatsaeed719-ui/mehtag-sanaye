import 'dart:math' as math;

/// Geohash + المسافة — نفس خوارزمية السيرفر (functions/src/lib/geo.js)
class Geo {
  static const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  static const earthRadiusKm = 6371.0;

  static String encode(double lat, double lng, [int precision = 10]) {
    double latMin = -90, latMax = 90, lngMin = -180, lngMax = 180;
    final sb = StringBuffer();
    int bit = 0, ch = 0;
    bool even = true;
    while (sb.length < precision) {
      if (even) {
        final mid = (lngMin + lngMax) / 2;
        if (lng >= mid) {
          ch = (ch << 1) | 1;
          lngMin = mid;
        } else {
          ch = ch << 1;
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (lat >= mid) {
          ch = (ch << 1) | 1;
          latMin = mid;
        } else {
          ch = ch << 1;
          latMax = mid;
        }
      }
      even = !even;
      if (++bit == 5) {
        sb.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return sb.toString();
  }

  static double _rad(double d) => d * math.pi / 180;

  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusKm * math.asin(math.min(1.0, math.sqrt(a.toDouble())));
  }

  static ({double width, double height}) _cellKm(int precision, double lat) {
    final bits = precision * 5;
    final lngBits = (bits / 2).ceil();
    final latBits = (bits / 2).floor();
    final latDeg = 180 / math.pow(2, latBits);
    final lngDeg = 360 / math.pow(2, lngBits);
    const kmPerDeg = math.pi * earthRadiusKm / 180;
    return (width: lngDeg * kmPerDeg * math.cos(_rad(lat)), height: latDeg * kmPerDeg);
  }

  /// نطاقات geohash التي تغطي دائرة البحث (بحد أقصى 9 نطاقات)
  static List<(String, String)> queryBounds(double lat, double lng, double radiusKm) {
    int precision = 1;
    for (int p = 9; p >= 1; p--) {
      final c = _cellKm(p, lat);
      if (c.width >= radiusKm && c.height >= radiusKm) {
        precision = p;
        break;
      }
    }
    final dLat = radiusKm / 111.32;
    final cosLat = math.max(0.01, math.cos(_rad(lat)));
    final dLng = radiusKm / (111.32 * cosLat);
    final hashes = <String>{};
    for (final a in [-1, 0, 1]) {
      for (final b in [-1, 0, 1]) {
        final pLat = (lat + a * dLat).clamp(-89.9999, 89.9999).toDouble();
        var pLng = lng + b * dLng;
        if (pLng > 180) pLng -= 360;
        if (pLng < -180) pLng += 360;
        hashes.add(encode(pLat, pLng, precision));
      }
    }
    final list = hashes.toList()..sort();
    return list.map((h) => (h, '$h~')).toList();
  }

  static bool isInEgypt(double lat, double lng) => lat >= 21.5 && lat <= 31.8 && lng >= 24.5 && lng <= 37.2;
}
