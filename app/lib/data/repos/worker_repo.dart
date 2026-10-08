import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/geo.dart';
import '../models.dart';

enum SortMode { smart, nearest, rating, reviews, feeLow, feeHigh }

class SearchFilters {
  String? categoryId;
  String? serviceId;
  bool availableOnly;
  bool verifiedOnly;
  double radiusKm;
  SortMode sort;
  String nameQuery;

  SearchFilters({
    this.categoryId,
    this.serviceId,
    this.availableOnly = false,
    this.verifiedOnly = false,
    this.radiusKm = 25,
    this.sort = SortMode.smart,
    this.nameQuery = '',
  });

  SearchFilters copy() => SearchFilters(
        categoryId: categoryId,
        serviceId: serviceId,
        availableOnly: availableOnly,
        verifiedOnly: verifiedOnly,
        radiusKm: radiusKm,
        sort: sort,
        nameQuery: nameQuery,
      );
}

/// البحث عن الصنايعية + الترتيب الذكي + المفضلة
class WorkerRepo {
  WorkerRepo._();
  static final instance = WorkerRepo._();
  final _db = FirebaseFirestore.instance;

  Query<Map<String, dynamic>> _visible() => _db
      .collection('workers')
      .where('verificationStatus', isEqualTo: 'approved')
      .where('suspended', isEqualTo: false);

  /// بحث جغرافي بفهارس geohash — لا يحمّل كل الصنايعية أبدًا
  Future<List<Worker>> search({required double lat, required double lng, required SearchFilters f}) async {
    final List<Worker> raw;
    if (f.nameQuery.trim().length >= 2) {
      raw = await _searchByName(f.nameQuery);
    } else {
      raw = await _searchNearby(lat, lng, f);
    }
    final out = <Worker>[];
    for (final w in raw) {
      w.distanceKm = Geo.distanceKm(lat, lng, w.lat, w.lng);
      if (f.nameQuery.trim().length < 2 && w.distanceKm! > f.radiusKm) continue;
      if (f.categoryId != null && !w.categoryIds.contains(f.categoryId)) continue;
      if (f.serviceId != null && !w.serviceIds.contains(f.serviceId)) continue;
      if (f.availableOnly && !w.available) continue;
      if (f.verifiedOnly && !w.idVerified) continue;
      w.score = smartScore(w);
      out.add(w);
    }
    sortWorkers(out, f.sort);
    return out;
  }

  Future<List<Worker>> _searchNearby(double lat, double lng, SearchFilters f) async {
    final bounds = Geo.queryBounds(lat, lng, f.radiusKm);
    final futures = bounds.map((b) {
      Query<Map<String, dynamic>> q = _visible();
      if (f.serviceId != null) {
        q = q.where('serviceIds', arrayContains: f.serviceId);
      } else if (f.categoryId != null) {
        q = q.where('categoryIds', arrayContains: f.categoryId);
      }
      return q.orderBy('geohash').startAt([b.$1]).endAt([b.$2]).limit(120).get();
    });
    final snaps = await Future.wait(futures);
    final seen = <String, Worker>{};
    for (final s in snaps) {
      for (final d in s.docs) {
        seen.putIfAbsent(d.id, () => Worker.fromDoc(d));
      }
    }
    return seen.values.toList();
  }

  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[ً-ْـ]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي');

  Future<List<Worker>> _searchByName(String query) async {
    final words = normalize(query).split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
    if (words.isEmpty) return [];
    final first = words.first.length > 15 ? words.first.substring(0, 15) : words.first;
    final s = await _visible().where('searchTokens', arrayContains: first).limit(60).get();
    final list = s.docs.map(Worker.fromDoc).toList();
    if (words.length == 1) return list;
    return list.where((w) {
      final hay = normalize('${w.name} ${w.categoryNames.map((e) => '${e['ar']} ${e['en']}').join(' ')}');
      return words.skip(1).every(hay.contains);
    }).toList();
  }

  /// الترتيب الذكي (عادل وشفاف):
  /// المسافة 35% + التقييم (بايزي) 25% + عدد التقييمات 10% + التوثيق 10% + متاح الآن 10%
  /// + الخدمات المكتملة 5% + سرعة الاستجابة 5%.
  /// الصنايعي الجديد ياخد قيم محايدة (مش صفر) علشان ميتظلمش. لا يوجد أي ترتيب مدفوع.
  static double smartScore(Worker w) {
    final km = w.distanceKm ?? 10;
    final dist = math.exp(-km / 8);
    const prior = 4.0, weight = 5.0;
    final bayes = ((prior * weight) + w.ratingAvg * w.ratingCount) / (weight + w.ratingCount) / 5;
    final count = math.min(1.0, math.log(1 + w.ratingCount) / math.log(51));
    final verified = w.idVerified ? 1.0 : 0.0;
    final avail = w.available ? 1.0 : 0.0;
    final completed = math.min(1.0, math.log(1 + w.completedCount) / math.log(101));
    double response = 0.5;
    if (w.responded >= 3) {
      response = ((1 - w.avgResponseMinutes / 120).clamp(0.0, 1.0)) * w.responseRate;
    }
    return 0.35 * dist + 0.25 * bayes + 0.10 * count + 0.10 * verified + 0.10 * avail + 0.05 * completed + 0.05 * response;
  }

  static void sortWorkers(List<Worker> list, SortMode mode) {
    int byDist(Worker a, Worker b) => (a.distanceKm ?? 1e9).compareTo(b.distanceKm ?? 1e9);
    switch (mode) {
      case SortMode.smart:
        list.sort((a, b) => b.score.compareTo(a.score));
      case SortMode.nearest:
        list.sort(byDist);
      case SortMode.rating:
        list.sort((a, b) {
          final c = b.ratingAvg.compareTo(a.ratingAvg);
          return c != 0 ? c : b.ratingCount.compareTo(a.ratingCount);
        });
      case SortMode.reviews:
        list.sort((a, b) => b.ratingCount.compareTo(a.ratingCount));
      case SortMode.feeLow:
        list.sort((a, b) => (a.visitFee ?? 1e9).compareTo(b.visitFee ?? 1e9));
      case SortMode.feeHigh:
        list.sort((a, b) => (b.visitFee ?? -1).compareTo(a.visitFee ?? -1));
    }
  }

  Stream<Worker?> watch(String id) =>
      _db.doc('workers/$id').snapshots().map((d) => d.exists ? Worker.fromDoc(d) : null);

  Future<Worker?> get(String id) async {
    final d = await _db.doc('workers/$id').get();
    return d.exists ? Worker.fromDoc(d) : null;
  }

  Stream<List<Review>> reviews(String workerId, {int limit = 30}) => _db
      .collection('reviews')
      .where('toId', isEqualTo: workerId)
      .where('direction', isEqualTo: 'c2w')
      .where('hidden', isEqualTo: false)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(Review.fromDoc).toList());

  // ---------------- المفضلة
  CollectionReference<Map<String, dynamic>> _fav(String uid) => _db.collection('users/$uid/favorites');

  Stream<bool> isFavorite(String uid, String workerId) => _fav(uid).doc(workerId).snapshots().map((d) => d.exists);

  Future<void> setFavorite(String uid, String workerId, bool fav) async {
    if (fav) {
      await _fav(uid).doc(workerId).set({'workerId': workerId, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      await _fav(uid).doc(workerId).delete();
    }
  }

  Stream<List<String>> favoriteIds(String uid) =>
      _fav(uid).orderBy('createdAt', descending: true).snapshots().map((s) => s.docs.map((d) => d.id).toList());
}
