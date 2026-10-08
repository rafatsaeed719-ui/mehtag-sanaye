import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/geo.dart';
import '../models.dart';

class RequestRepo {
  RequestRepo._();
  static final instance = RequestRepo._();
  final _db = FirebaseFirestore.instance;

  Stream<List<ServiceRequest>> mine(String uid, {required bool asWorker, int limit = 100}) => _db
      .collection('requests')
      .where(asWorker ? 'workerId' : 'customerId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(ServiceRequest.fromDoc).toList());

  Stream<ServiceRequest?> watch(String id) =>
      _db.doc('requests/$id').snapshots().map((d) => d.exists ? ServiceRequest.fromDoc(d) : null);

  Stream<List<HistoryEntry>> history(String id) => _db
      .collection('requests/$id/history')
      .orderBy('at')
      .snapshots()
      .map((s) => s.docs.map(HistoryEntry.fromDoc).toList());

  /// طلبات مفتوحة قريبة تناسب مهن الصنايعي (Geo query)
  Future<List<(ServiceRequest, double)>> nearbyOpen({
    required double lat,
    required double lng,
    required List<String> categoryIds,
    double radiusKm = 25,
  }) async {
    if (categoryIds.isEmpty) return [];
    final cats = categoryIds.take(10).toList();
    final bounds = Geo.queryBounds(lat, lng, radiusKm);
    final snaps = await Future.wait(bounds.map((b) => _db
        .collection('requests')
        .where('open', isEqualTo: true)
        .where('status', isEqualTo: 'new')
        .where('categoryId', whereIn: cats)
        .orderBy('geohash')
        .startAt([b.$1])
        .endAt([b.$2])
        .limit(50)
        .get()));
    final seen = <String, (ServiceRequest, double)>{};
    for (final s in snaps) {
      for (final d in s.docs) {
        final r = ServiceRequest.fromDoc(d);
        if (r.status != 'new') continue;
        final km = Geo.distanceKm(lat, lng, r.lat, r.lng);
        if (km <= radiusKm) seen[r.id] = (r, km);
      }
    }
    final list = seen.values.toList();
    list.sort((a, b) {
      if (a.$1.isEmergency != b.$1.isEmergency) return a.$1.isEmergency ? -1 : 1;
      return a.$2.compareTo(b.$2);
    });
    return list;
  }

  // ---------------- الشات
  Stream<List<ChatMessage>> messages(String requestId) => _db
      .collection('requests/$requestId/messages')
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map(ChatMessage.fromDoc).toList());

  // ---------------- إحصائيات العميل
  Future<Map<String, num>> customerStats(String uid) async {
    final base = _db.collection('requests').where('customerId', isEqualTo: uid);
    final total = await base.count().get();
    final completed = await base.where('status', whereIn: ['completed', 'price_set', 'price_agreed', 'commission_paid']).count().get();
    final cancelled = await base.where('status', isEqualTo: 'cancelled').count().get();
    final recent = await base.orderBy('createdAt', descending: true).limit(300).get();
    final workers = recent.docs.map((d) => d.data()['workerId']).whereType<String>().toSet();
    return {
      'total': total.count ?? 0,
      'completed': completed.count ?? 0,
      'cancelled': cancelled.count ?? 0,
      'workers': workers.length,
    };
  }

  Future<int> workerCustomersCount(String workerId) async {
    final c = await _db.collection('workers/$workerId/customers').count().get();
    return c.count ?? 0;
  }

  Future<int> workerCompletedCount(String workerId) async {
    final c = await _db
        .collection('requests')
        .where('workerId', isEqualTo: workerId)
        .where('status', whereIn: ['completed', 'price_set', 'price_agreed', 'commission_paid'])
        .count()
        .get();
    return c.count ?? 0;
  }

  // ---------------- البلاغات
  Stream<List<ReportItem>> myReports(String uid) => _db
      .collection('reports')
      .where('reporterId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(ReportItem.fromDoc).toList());
}
