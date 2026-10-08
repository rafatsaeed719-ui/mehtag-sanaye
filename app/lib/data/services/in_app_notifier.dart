import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/notification_texts.dart';
import '../models.dart';

/// إشعارات داخل التطبيق (الخطة المجانية): بيسمع لصندوق الإشعارات ويطلّع بانر
/// لأي إشعار جديد يوصل والتطبيق مفتوح.
class InAppNotifier {
  InAppNotifier._();
  static final instance = InAppNotifier._();

  final incoming = StreamController<AppNotification>.broadcast();
  StreamSubscription? _sub;
  String? _uid;
  DateTime _since = DateTime.now();

  void start(String uid) {
    if (_uid == uid && _sub != null) return;
    stop();
    _uid = uid;
    _since = DateTime.now().subtract(const Duration(seconds: 5));
    _sub = FirebaseFirestore.instance
        .collection('notifications/$uid/items')
        .orderBy('createdAt', descending: true)
        .limit(5)
        .snapshots()
        .listen((s) {
      for (final ch in s.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final n = AppNotification.fromDoc(ch.doc);
        if (n.read || n.createdAt == null || n.createdAt!.isBefore(_since)) continue;
        incoming.add(n);
      }
    }, onError: (_) {});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
  }
}

/// نص الإشعار حسب النوع واللغة
(String, String) notificationText(AppNotification n, String lang) {
  if (n.isBroadcast) {
    return lang == 'en' ? (n.titleEn ?? '', n.bodyEn ?? '') : (n.titleAr ?? '', n.bodyAr ?? '');
  }
  final t = kNotificationTexts[n.type];
  if (t == null) return (n.type, '');
  final title = lang == 'en' ? t[2] : t[0];
  final body = lang == 'en' ? t[3] : t[1];
  String val(Object? v, String key) {
    if (v == null) return '';
    if (v is Map) return '${v[lang] ?? v['ar'] ?? v['en'] ?? ''}';
    if (key == 'time' && v is num) {
      return DateFormat('EEE d MMM • h:mm a', lang == 'ar' ? 'ar' : 'en').format(DateTime.fromMillisecondsSinceEpoch(v.toInt()));
    }
    return '$v';
  }

  String fill(String s) => s.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => val(n.params[m[1]], m[1]!));
  return (fill(title), fill(body));
}
