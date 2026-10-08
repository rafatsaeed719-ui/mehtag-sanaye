import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';

/// المهن والخدمات والمحافظات والإعدادات العامة — مباشرة من قاعدة البيانات،
/// فأي تعديل من لوحة التحكم يظهر فورًا بدون تحديث التطبيق.
class CatalogRepo extends ChangeNotifier {
  final _db = FirebaseFirestore.instance;
  final List<StreamSubscription> _subs = [];

  List<JobCategory> categories = [];
  List<Service> services = [];
  List<Place> places = [];
  Map<String, dynamic> publicSettings = {};
  bool loaded = false;

  double get commissionRate => (publicSettings['commissionRate'] is num) ? (publicSettings['commissionRate'] as num).toDouble() : 0.05;
  String get commissionPercent {
    final p = commissionRate * 100;
    return p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(1);
  }

  String get playStoreUrl => publicSettings['playStoreUrl'] ?? 'https://play.google.com/store/apps/details?id=com.mehtagsanaye.app';
  int get overdueDays => (publicSettings['overdueDays'] as num?)?.toInt() ?? 7;

  void start() {
    if (_subs.isNotEmpty) return;
    _subs.add(_db.collection('categories').where('active', isEqualTo: true).snapshots().listen((s) {
      categories = s.docs.map(JobCategory.fromDoc).toList()..sort((a, b) => a.order.compareTo(b.order));
      loaded = true;
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(_db.collection('services').where('active', isEqualTo: true).snapshots().listen((s) {
      services = s.docs.map(Service.fromDoc).toList()..sort((a, b) => a.order.compareTo(b.order));
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(_db.collection('locations').where('active', isEqualTo: true).snapshots().listen((s) {
      places = s.docs.map(Place.fromDoc).toList();
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(_db.doc('settings/public').snapshots().listen((s) {
      publicSettings = s.data() ?? {};
      notifyListeners();
    }, onError: (_) {}));
  }

  JobCategory? category(String? id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<Service> servicesOf(String? categoryId) => services.where((s) => s.categoryId == categoryId).toList();
  List<Service> servicesOfMany(List<String> categoryIds) => services.where((s) => categoryIds.contains(s.categoryId)).toList();

  List<Place> get governorates {
    final g = places.where((p) => p.type == 'governorate').toList();
    g.sort((a, b) => a.nameAr.compareTo(b.nameAr));
    return g;
  }

  List<Place> childrenOf(String parentId) {
    final c = places.where((p) => p.parentId == parentId).toList();
    c.sort((a, b) => a.nameAr.compareTo(b.nameAr));
    return c;
  }

  Place? place(String id) {
    for (final p in places) {
      if (p.id == id) return p;
    }
    return null;
  }

  Place? governorateByCode(String code) {
    for (final p in places) {
      if (p.type == 'governorate' && p.code == code) return p;
    }
    return null;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
