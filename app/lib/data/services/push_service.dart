import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Push Notifications (FCM)
///  - يحفظ توكن الجهاز في users/{uid}.fcmTokens (للإشعارات الشخصية)
///  - يشترك في Topics للإشعارات الإدارية: all_ar, customers_ar, workers_ar, cat_<id>_ar, gov_<code>_ar
class PushService {
  PushService._();
  static final instance = PushService._();

  final _fm = FirebaseMessaging.instance;
  String? _uid;
  String? _token;
  final Set<String> _topics = {};
  StreamSubscription<String>? _refreshSub;

  /// رسالة وصلت والتطبيق مفتوح → نعرضها كبانر داخل التطبيق
  final foreground = StreamController<RemoteMessage>.broadcast();

  /// المستخدم ضغط على إشعار → نفتح الشاشة المناسبة
  final opened = StreamController<Map<String, dynamic>>.broadcast();

  bool _listening = false;

  Future<void> init() async {
    if (_listening) return;
    _listening = true;
    FirebaseMessaging.onMessage.listen(foreground.add);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => opened.add(m.data));
    final initial = await _fm.getInitialMessage();
    if (initial != null) {
      // ننتظر لحد ما الواجهة تجهز
      Future.delayed(const Duration(milliseconds: 1500), () => opened.add(initial.data));
    }
  }

  Future<void> register(String uid) async {
    try {
      _uid = uid;
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      _token = await _fm.getToken();
      if (_token != null) {
        await FirebaseFirestore.instance.doc('users/$uid').update({
          'fcmTokens': FieldValue.arrayUnion([_token]),
        });
      }
      await _refreshSub?.cancel();
      _refreshSub = _fm.onTokenRefresh.listen((t) async {
        if (_uid == null) return;
        _token = t;
        await FirebaseFirestore.instance.doc('users/$_uid').update({'fcmTokens': FieldValue.arrayUnion([t])});
      });
    } catch (e) {
      debugPrint('push register failed: $e');
    }
  }

  /// يضبط الاشتراكات حسب نوع الحساب واللغة والمهن والمحافظة
  Future<void> syncTopics({required String role, required String lang, List<String> categoryIds = const [], String? governorate}) async {
    String safe(String s) => s.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final wanted = <String>{
      'all_$lang',
      '${role == 'worker' ? 'workers' : 'customers'}_$lang',
      if (role == 'worker') ...categoryIds.map((c) => 'cat_${safe(c)}_$lang'),
      if (governorate != null && governorate.isNotEmpty) 'gov_${safe(governorate)}_$lang',
    };
    try {
      for (final t in _topics.difference(wanted)) {
        await _fm.unsubscribeFromTopic(t);
      }
      for (final t in wanted.difference(_topics)) {
        await _fm.subscribeToTopic(t);
      }
      _topics
        ..clear()
        ..addAll(wanted);
    } catch (e) {
      debugPrint('topics sync failed: $e');
    }
  }

  /// عند تسجيل الخروج: نشيل التوكن من الحساب ونلغي الاشتراكات
  Future<void> unregister() async {
    try {
      if (_uid != null && _token != null) {
        await FirebaseFirestore.instance.doc('users/$_uid').update({'fcmTokens': FieldValue.arrayRemove([_token])});
      }
      for (final t in _topics) {
        await _fm.unsubscribeFromTopic(t);
      }
    } catch (_) {}
    _topics.clear();
    _uid = null;
    await _refreshSub?.cancel();
  }
}
