import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// عمليات الإدارة جوه التطبيق — نفس اللي بتعمله لوحة التحكم بالظبط
/// (كتابة مباشرة محمية بقواعد الأمان firestore.rules)
class AdminService {
  AdminService._();
  static final instance = AdminService._();

  final db = FirebaseFirestore.instance;
  String role = 'moderator';

  User get _me => FirebaseAuth.instance.currentUser!;
  String get uid => _me.uid;
  String get email => _me.email ?? '';

  bool can([List<String> roles = const []]) => role == 'super' || roles.contains(role);
  bool get isModerator => can(['moderator']);
  bool get isFinance => can(['finance']);
  bool get isSuper => role == 'super';

  FieldValue get _now => FieldValue.serverTimestamp();

  CollectionReference<Map<String, dynamic>> col(String path) => db.collection(path);
  DocumentReference<Map<String, dynamic>> ref(String path) => db.doc(path);

  Future<void> logAction(String action, String targetType, String targetId, [Map<String, dynamic> details = const {}]) async {
    try {
      await col('adminActions').add({
        'adminId': uid,
        'adminEmail': email,
        'action': action,
        'targetType': targetType,
        'targetId': targetId,
        'details': details,
        'createdAt': _now,
      });
    } catch (_) {}
  }

  Future<void> notifyUser(String? to, String type, [Map<String, dynamic> params = const {}, Map<String, dynamic> data = const {}]) async {
    if (to == null || to.isEmpty) return;
    try {
      await col('notifications/$to/items').add({
        'type': type,
        'params': params,
        'data': data,
        'read': false,
        'fromUid': uid,
        'createdAt': _now,
      });
    } catch (_) {}
  }

  Future<int> count(Query<Map<String, dynamic>> q) async {
    try {
      final s = await q.count().get();
      return s.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<double> sumOf(Query<Map<String, dynamic>> q, String field) async {
    try {
      final s = await q.aggregate(sum(field)).get();
      return (s.getSum(field) ?? 0).toDouble();
    } catch (_) {
      return 0;
    }
  }

  // ------------------------------------------------------------ الصنايعية
  Future<Map<String, dynamic>> workerPrivate(String workerId) async {
    final p = await ref('workerPrivate/$workerId').get();
    await logAction('view_identity', 'worker', workerId);
    return p.data() ?? {};
  }

  Future<void> reviewWorker(String workerId, String decision, {String reason = '', bool idVerified = false}) async {
    final w = (await ref('workers/$workerId').get()).data() ?? {};
    final patch = <String, dynamic>{
      'verificationStatus': decision == 'approve' ? 'approved' : decision == 'reject' ? 'rejected' : 'pending',
      'rejectionReason': decision == 'reject' ? reason : '',
      'idVerified': decision == 'approve' ? (idVerified && w['hasIdDoc'] == true) : false,
      'reviewedAt': _now,
      'reviewedBy': uid,
    };
    if (decision == 'approve' && w['approvedAt'] == null) patch['approvedAt'] = _now;
    await ref('workers/$workerId').update(patch);
    await logAction('worker_$decision', 'worker', workerId, {'reason': reason});
    if (decision == 'approve') await notifyUser(workerId, 'account_approved');
    if (decision == 'reject') await notifyUser(workerId, 'account_rejected', {'reason': reason});
  }

  Future<void> reviewChange(String changeId, String decision, {String reason = '', bool idVerified = false}) async {
    final cRef = ref('workerChangeRequests/$changeId');
    final c = (await cRef.get()).data() ?? {};
    final workerId = c['workerId'] as String;
    final wRef = ref('workers/$workerId');
    final b = db.batch();
    if (decision == 'approve') {
      final cur = (await wRef.get()).data() ?? {};
      final ch = Map<String, dynamic>.from(c['changes'] ?? {});
      final patch = <String, dynamic>{'pendingChange': false, 'updatedAt': _now};
      if ((ch['name'] ?? '').toString().isNotEmpty) patch['name'] = ch['name'];
      if (ch['categoryIds'] != null || ch['serviceIds'] != null) {
        final cats = List<String>.from(ch['categoryIds'] ?? cur['categoryIds'] ?? []);
        final svcs = List<String>.from(ch['serviceIds'] ?? cur['serviceIds'] ?? []);
        final catDocs = await col('categories').get();
        final svcDocs = await col('services').get();
        Map<String, String>? nameOf(QuerySnapshot<Map<String, dynamic>> s, String id) {
          for (final d in s.docs) {
            if (d.id == id) return {'ar': d['nameAr'] ?? '', 'en': d['nameEn'] ?? ''};
          }
          return null;
        }

        patch['categoryIds'] = cats;
        patch['serviceIds'] = svcs;
        patch['categoryNames'] = cats.map((id) => nameOf(catDocs, id)).whereType<Map<String, String>>().toList();
        patch['serviceNames'] = svcs.map((id) => nameOf(svcDocs, id)).whereType<Map<String, String>>().toList();
      }
      if (patch['name'] != null || ch['categoryIds'] != null) {
        final names = List.from(patch['categoryNames'] ?? cur['categoryNames'] ?? [])
            .expand((n) => [(n as Map)['ar']?.toString() ?? '', n['en']?.toString() ?? ''])
            .toList();
        patch['searchTokens'] = tokens([(patch['name'] ?? cur['name'] ?? '').toString(), ...names]);
      }
      final identity = c['identity'] as Map<String, dynamic>?;
      if (identity != null) {
        final priv = (await ref('workerPrivate/$workerId').get()).data() ?? {};
        final newId = identity['nationalId'] as String;
        if (priv['nationalId'] != newId) {
          if ((priv['nationalId'] ?? '').toString().isNotEmpty) b.delete(ref('nationalIds/${priv['nationalId']}'));
          b.set(ref('nationalIds/$newId'), {'uid': workerId, 'createdAt': _now});
        }
        b.set(
          ref('workerPrivate/$workerId'),
          {'nationalId': newId, 'idFrontRef': identity['idFrontRef'] ?? '', 'idBackRef': identity['idBackRef'] ?? '', 'updatedAt': _now},
          SetOptions(merge: true),
        );
        patch['hasIdDoc'] = true;
        patch['idVerified'] = idVerified;
      }
      b.update(wRef, patch);
    } else {
      b.update(wRef, {'pendingChange': false});
    }
    b.update(cRef, {'status': decision == 'approve' ? 'approved' : 'rejected', 'reason': reason, 'reviewedBy': uid, 'reviewedAt': _now});
    await b.commit();
    await logAction('change_$decision', 'worker', workerId, {'changeId': changeId, 'reason': reason});
    await notifyUser(workerId, decision == 'approve' ? 'change_approved' : 'change_rejected', {'reason': reason});
  }

  // ------------------------------------------------------------ المستخدمون
  Future<void> setUserStatus(String userId, String status, {String reason = '', DateTime? until}) async {
    final b = db.batch();
    b.update(ref('users/$userId'), {
      'status': status,
      'statusReason': reason,
      'bannedUntil': status == 'banned' && until != null ? Timestamp.fromDate(until) : null,
      'statusUpdatedAt': _now,
    });
    final w = await ref('workers/$userId').get();
    if (w.exists) b.update(ref('workers/$userId'), {'suspended': status != 'active'});
    await b.commit();
    await logAction('user_$status', 'user', userId, {'reason': reason});
  }

  Future<void> updateUser(String userId, {required String name, String adminNote = ''}) async {
    await ref('users/$userId').update({'name': name, 'adminNote': adminNote});
    final w = await ref('workers/$userId').get();
    if (w.exists && name.isNotEmpty) await ref('workers/$userId').update({'name': name});
    await logAction('user_update', 'user', userId, {'name': name});
  }

  Future<void> deleteUser(String userId, String reason) async {
    final b = db.batch();
    b.update(ref('users/$userId'), {
      'status': 'deleted',
      'name': 'Deleted user',
      'photoUrl': '',
      'email': '',
      'statusReason': reason,
      'deletedAt': _now,
    });
    final w = await ref('workers/$userId').get();
    if (w.exists) {
      b.update(ref('workers/$userId'), {
        'suspended': true,
        'verificationStatus': 'deleted',
        'name': 'Deleted',
        'photoUrl': '',
        'bio': '',
        'whatsapp': '',
        'callPhone': '',
        'workImages': [],
        'searchTokens': [],
      });
    }
    await b.commit();
    await logAction('user_delete', 'user', userId, {'reason': reason});
  }

  // ------------------------------------------------------------ المدفوعات
  Future<void> reviewPayment(String paymentId, String decision, {String note = ''}) async {
    final pRef = ref('payments/$paymentId');
    final p = (await pRef.get()).data() ?? {};
    if (p['status'] != 'pending_review') throw Exception('تمت مراجعتها بالفعل');
    final b = db.batch();
    b.update(pRef, {'status': decision == 'confirm' ? 'confirmed' : 'rejected', 'reviewNote': note, 'reviewedBy': uid, 'reviewedAt': _now});
    for (final cid in List<String>.from(p['commissionIds'] ?? [])) {
      if (decision == 'confirm') {
        b.update(ref('commissions/$cid'), {'status': 'paid', 'paidAt': _now});
        final r = await ref('requests/$cid').get();
        if (r.exists) {
          final st = r.data()!['status'];
          final upd = <String, dynamic>{'commissionStatus': 'paid', 'updatedAt': _now};
          if (st == 'price_agreed') upd['status'] = 'commission_paid';
          b.update(r.reference, upd);
          b.set(col('requests/$cid/history').doc(), {
            'from': st,
            'to': upd['status'] ?? st,
            'action': 'commission_paid',
            'by': 'admin',
            'byUid': uid,
            'note': paymentId,
            'at': _now,
          });
        }
      } else {
        b.update(ref('commissions/$cid'), {'status': 'due', 'paymentId': null});
      }
    }
    await b.commit();
    await logAction('payment_$decision', 'payment', paymentId, {'amount': p['amount'], 'workerId': p['workerId'], 'note': note});
    await notifyUser(p['workerId'], decision == 'confirm' ? 'payment_confirmed' : 'payment_rejected', {'amount': p['amount'], 'reason': note});
  }

  // ------------------------------------------------------------ الإعدادات
  Future<void> updateSettings(Map<String, dynamic> patch) async {
    final p = Map<String, dynamic>.from(patch);
    if (p.containsKey('commissionRate')) {
      final r = (p['commissionRate'] as num).toDouble();
      if (!(r >= 0 && r <= 0.3)) throw Exception('نسبة العمولة لازم تكون بين 0% و 30%');
      p['commissionRate'] = (r * 10000).round() / 10000;
    }
    await ref('settings/public').set({...p, 'updatedAt': _now, 'updatedBy': uid}, SetOptions(merge: true));
    await logAction('settings_update', 'settings', 'public', p);
  }

  // ------------------------------------------------------------ التقييمات
  Future<void> setReviewHidden(String reviewId, bool hidden) async {
    final rRef = ref('reviews/$reviewId');
    final rv = (await rRef.get()).data() ?? {};
    await rRef.update({'hidden': hidden, 'moderatedBy': uid, 'moderatedAt': _now});
    if (rv['direction'] == 'c2w') {
      final all = await col('reviews')
          .where('toId', isEqualTo: rv['toId'])
          .where('direction', isEqualTo: 'c2w')
          .where('hidden', isEqualTo: false)
          .get();
      num total = 0;
      for (final d in all.docs) {
        total += (d.data()['stars'] as num? ?? 0);
      }
      await ref('workers/${rv['toId']}').update({'ratingSum': total, 'ratingCount': all.size});
    }
    await logAction(hidden ? 'review_hide' : 'review_show', 'review', reviewId);
  }

  // ------------------------------------------------------------ البلاغات
  Future<void> updateReport(String reportId, {required String status, String adminNote = '', String actionTaken = '', String category = ''}) async {
    final rRef = ref('reports/$reportId');
    final r = (await rRef.get()).data() ?? {};
    await rRef.update({
      'status': status,
      'adminNote': adminNote,
      'actionTaken': actionTaken,
      if (category.isNotEmpty) 'category': category,
      'handledBy': uid,
      'updatedAt': _now,
    });
    await logAction('report_update', 'report', reportId, {'status': status, 'actionTaken': actionTaken});
    const st = {
      'new': {'ar': 'جديد', 'en': 'New'},
      'reviewing': {'ar': 'قيد المراجعة', 'en': 'Under review'},
      'action_taken': {'ar': 'تم اتخاذ إجراء', 'en': 'Action taken'},
      'closed': {'ar': 'مغلق', 'en': 'Closed'},
    };
    await notifyUser(r['reporterId'], 'report_update', {'status': st[status]});
  }

  // ------------------------------------------------------------ الإشعارات الجماعية
  Future<void> broadcast({required String target, String value = '', required String titleAr, required String bodyAr, String titleEn = '', String bodyEn = ''}) async {
    if (titleAr.isEmpty || bodyAr.isEmpty) throw Exception('اكتب العنوان والنص بالعربي');
    var v = value.trim();
    if (target == 'user' && RegExp(r'^(\+?20|0)1\d{9}$').hasMatch(v)) v = v.replaceFirst(RegExp(r'^\+?20'), '0');
    await col('broadcasts').add({
      'target': target,
      'value': v,
      'titleAr': titleAr,
      'bodyAr': bodyAr,
      'titleEn': titleEn.isEmpty ? titleAr : titleEn,
      'bodyEn': bodyEn.isEmpty ? bodyAr : bodyEn,
      'sentBy': uid,
      'createdAt': _now,
    });
    await logAction('broadcast', 'notification', target, {'value': v, 'titleAr': titleAr});
  }

  // ------------------------------------------------------------ الدعم
  Future<void> closeTicket(String id, String reply) async {
    await ref('supportTickets/$id').update({'status': 'closed', 'reply': reply, 'closedBy': uid, 'closedAt': _now});
  }

  // ------------------------------------------------------------ فريق الإدارة
  Future<void> setAdminRole(String adminUid, String adminEmail, String newRole) async {
    if (adminUid == uid && newRole != 'super') throw Exception('مينفعش تشيل صلاحيتك بنفسك');
    if (newRole == 'none') {
      await ref('admins/$adminUid').delete();
    } else {
      await ref('admins/$adminUid').set(
        {'email': adminEmail, 'role': newRole, 'active': true, 'updatedAt': _now, 'updatedBy': uid},
        SetOptions(merge: true),
      );
    }
    try {
      await ref('adminRequests/$adminUid').delete();
    } catch (_) {}
    await logAction('admin_role', 'admin', adminUid, {'email': adminEmail, 'role': newRole});
  }

  // ------------------------------------------------------------ المهن والمناطق
  Future<void> saveCategory(String id, Map<String, dynamic> data) async {
    await ref('categories/$id').set({...data, 'updatedAt': _now}, SetOptions(merge: true));
    await logAction('category_save', 'catalog', id, {'nameAr': data['nameAr']});
  }

  Future<void> toggleActive(String path, bool active) async {
    await ref(path).update({'active': active});
    await logAction('toggle_active', 'catalog', path, {'active': active});
  }

  Future<void> addService(String categoryId, String ar, String en, int order) async {
    final r = await col('services').add({'categoryId': categoryId, 'nameAr': ar, 'nameEn': en, 'active': true, 'order': order, 'updatedAt': _now});
    await logAction('service_add', 'catalog', r.id, {'nameAr': ar});
  }

  Future<void> editService(String id, String ar, String en) async {
    await ref('services/$id').update({'nameAr': ar, 'nameEn': en});
    await logAction('service_edit', 'catalog', id, {'nameAr': ar});
  }

  Future<void> addLocation({required String type, required String parentId, required String ar, String en = '', double? lat, double? lng}) async {
    await col('locations').add({
      'type': type,
      'parentId': parentId,
      'nameAr': ar,
      'nameEn': en,
      'active': true,
      'code': '',
      if (lat != null && lng != null) 'lat': lat,
      if (lat != null && lng != null) 'lng': lng,
      'updatedAt': _now,
    });
  }
}

/// كلمات البحث (نفس منطق لوحة التحكم)
List<String> tokens(List<String> texts) {
  String norm(String x) => x
      .toLowerCase()
      .replaceAll(RegExp('[ً-ْـ]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي');
  final out = <String>{};
  for (final t in texts) {
    for (final w in norm(t).split(RegExp(r'[\s,.\-]+')).where((s) => s.isNotEmpty)) {
      for (var i = 2; i <= (w.length < 15 ? w.length : 15); i++) {
        out.add(w.substring(0, i));
      }
    }
  }
  return out.take(200).toList();
}
