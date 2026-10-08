import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/geo.dart';
import '../models.dart';
import '../repos/worker_repo.dart';

/// كل عمليات الكتابة — على خطة Firebase المجانية (بدون سيرفر).
/// الحماية الحقيقية في firestore.rules: أي كتابة مخالفة (حالة غلط، عمولة غلط، طرف غريب)
/// بترجع permission-denied.
class Backend {
  Backend._();
  static final instance = Backend._();
  final _db = FirebaseFirestore.instance;

  FieldValue get _now => FieldValue.serverTimestamp();

  // ------------------------------------------------------------------ إشعارات داخل التطبيق
  Future<void> notify(String? toUid, String fromUid, String type, [Map<String, dynamic> params = const {}, Map<String, dynamic> data = const {}]) async {
    if (toUid == null || toUid.isEmpty) return;
    try {
      await _db.collection('notifications/$toUid/items').add({
        'type': type,
        'params': params,
        'data': data,
        'read': false,
        'fromUid': fromUid,
        'createdAt': _now,
      });
    } catch (_) {
      // الإشعار لا يجب أن يُفشل العملية الأساسية
    }
  }

  // ------------------------------------------------------------------ الحساب
  /// إنشاء الملف + حجز رقم الموبايل (رقم واحد لكل حساب). لو الرقم مستخدم → permission-denied
  Future<void> signup({required String uid, required String role, required String name, required String phone, required String lang, String email = '', String photoUrl = ''}) async {
    final b = _db.batch();
    b.set(_db.doc('phones/$phone'), {'uid': uid, 'createdAt': _now});
    b.set(_db.doc('users/$uid'), {
      'uid': uid,
      'role': role,
      'name': name,
      'phone': phone,
      'email': email,
      'photoUrl': photoUrl,
      'lang': lang,
      'status': 'active',
      'customerRatingSum': 0,
      'customerRatingCount': 0,
      'createdAt': _now,
      'updatedAt': _now,
    });
    await b.commit();
  }

  /// هل الرقم محجوز؟ (القواعد تمنع قراءة phones، فالتأكد الحقيقي وقت الحفظ)
  // ------------------------------------------------------------------ الصنايعي
  static List<String> searchTokens(List<String> texts) {
    final tokens = <String>{};
    for (final t in texts) {
      for (final w in WorkerRepo.normalize(t).split(RegExp(r'[\s,.-]+')).where((x) => x.isNotEmpty)) {
        for (var i = 2; i <= min(w.length, 15); i++) {
          tokens.add(w.substring(0, i));
        }
      }
    }
    return tokens.take(200).toList();
  }

  /// تسجيل/إعادة تقديم بيانات الصنايعي → "قيد المراجعة"
  Future<void> submitWorkerApplication({
    required AppUser user,
    required Worker? existing,
    required Map<String, dynamic> profile, // name, photoUrl, categoryIds, serviceIds, categoryNames, serviceNames, governorate, city, area, lat, lng, bio, visitFee, whatsapp, callPhone, workImages
    String? nationalId,
    String? idFrontRef,
    String? idBackRef,
  }) async {
    final uid = user.uid;
    final lat = (profile['lat'] as num).toDouble();
    final lng = (profile['lng'] as num).toDouble();
    final names = (profile['categoryNames'] as List).cast<Map<String, dynamic>>();
    final data = <String, dynamic>{
      'uid': uid,
      'name': profile['name'],
      'phone': user.phone,
      'photoUrl': profile['photoUrl'] ?? '',
      'categoryIds': profile['categoryIds'],
      'serviceIds': profile['serviceIds'],
      'categoryNames': profile['categoryNames'],
      'serviceNames': profile['serviceNames'],
      'governorate': profile['governorate'],
      'city': profile['city'],
      'area': profile['area'] ?? '',
      'geo': {'lat': lat, 'lng': lng},
      'geohash': Geo.encode(lat, lng, 10),
      'bio': profile['bio'] ?? '',
      'visitFee': profile['visitFee'],
      'whatsapp': profile['whatsapp'],
      'callPhone': profile['callPhone'],
      'workImages': profile['workImages'] ?? <String>[],
      'available': existing?.available ?? true,
      'verificationStatus': 'pending',
      'hasIdDoc': (idFrontRef != null) || (existing?.hasIdDoc ?? false),
      'pendingChange': false,
      'searchTokens': searchTokens([profile['name'] as String, ...names.expand((n) => ['${n['ar']}', '${n['en']}'])]),
      'submittedAt': _now,
      'updatedAt': _now,
    };

    final b = _db.batch();
    final wRef = _db.doc('workers/$uid');
    if (existing == null) {
      b.set(wRef, {
        ...data,
        'idVerified': false,
        'suspended': false,
        'ratingSum': 0,
        'ratingCount': 0,
        'completedCount': 0,
        'rejectionReason': '',
        'createdAt': _now,
      });
    } else {
      b.update(wRef, data);
    }

    if (nationalId != null || idFrontRef != null) {
      final privRef = _db.doc('workerPrivate/$uid');
      final cur = await privRef.get();
      final curId = cur.data()?['nationalId'];
      final priv = <String, dynamic>{'updatedAt': _now};
      if (nationalId != null && nationalId != curId) {
        b.set(_db.doc('nationalIds/$nationalId'), {'uid': uid, 'createdAt': _now});
        priv['nationalId'] = nationalId;
      }
      if (idFrontRef != null) priv['idFrontRef'] = idFrontRef;
      if (idBackRef != null) priv['idBackRef'] = idBackRef;
      b.set(privRef, priv, SetOptions(merge: true));
    }
    await b.commit();
  }

  /// تعديل بيانات حساسة بعد التوثيق → مراجعة الإدارة
  Future<void> requestWorkerChange(Worker w, Map<String, dynamic> changes, {Map<String, dynamic>? identity}) async {
    final b = _db.batch();
    b.set(_db.collection('workerChangeRequests').doc(), {
      'workerId': w.id,
      'workerName': w.name,
      'changes': changes,
      'identity': identity,
      'status': 'pending',
      'createdAt': _now,
    });
    b.update(_db.doc('workers/${w.id}'), {'pendingChange': true, 'updatedAt': _now});
    await b.commit();
  }

  // ------------------------------------------------------------------ الطلبات
  /// إنشاء طلب (موجه / مفتوح / طوارئ). يرجع (رقم الطلب، عدد الصنايعية اللي اتبلغوا)
  Future<(String, int)> createRequest({
    required AppUser customer,
    required Worker? worker,
    required String categoryId,
    required Map<String, dynamic> categoryName,
    String? serviceId,
    Map<String, dynamic>? serviceName,
    required String description,
    required List<String> images,
    required double lat,
    required double lng,
    required String address,
    required String governorate,
    required DateTime scheduledAt,
    required bool isEmergency,
    required Map<String, dynamic> settings,
  }) async {
    final ref = _db.collection('requests').doc();
    final code = ref.id.substring(0, 6).toUpperCase();
    final b = _db.batch();
    b.set(ref, {
      'code': code,
      'customerId': customer.uid,
      'customerName': customer.name,
      'customerPhone': null,
      'workerId': worker?.id,
      'workerName': worker?.name,
      'workerPhone': worker == null ? null : (worker.callPhone.isNotEmpty ? worker.callPhone : worker.phone),
      'workerWhatsapp': worker == null ? null : (worker.whatsapp.isNotEmpty ? worker.whatsapp : worker.phone),
      'workerPhotoUrl': worker?.photoUrl ?? '',
      'categoryId': categoryId,
      'categoryName': categoryName,
      'serviceId': serviceId,
      'serviceName': serviceName,
      'description': description,
      'images': images,
      'location': {'lat': lat, 'lng': lng, 'address': address, 'governorate': governorate},
      'geohash': Geo.encode(lat, lng, 10),
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'proposedAt': null,
      'isEmergency': isEmergency,
      'open': worker == null,
      'status': 'new',
      'agreedPrice': null,
      'commissionRate': null,
      'commissionAmount': null,
      'commissionStatus': 'none',
      'customerReviewed': false,
      'workerReviewed': false,
      'notifiedWorkerIds': <String>[],
      'createdAt': _now,
      'updatedAt': _now,
    });
    b.set(ref.collection('private').doc('contact'), {'customerPhone': customer.phone, 'customerName': customer.name});
    b.update(_db.doc('users/${customer.uid}'), {
      'lastRequestAt': _now,
      if (isEmergency) 'lastEmergencyAt': _now,
    });
    b.set(ref.collection('history').doc(), {
      'from': null, 'to': 'new', 'action': 'create', 'by': 'customer', 'byUid': customer.uid,
      'note': isEmergency ? 'emergency' : '', 'at': _now,
    });
    await b.commit();

    final svc = serviceName ?? categoryName;
    if (worker != null) {
      await notify(worker.id, customer.uid, 'new_request', {'service': svc, 'name': customer.name}, {'requestId': ref.id});
      return (ref.id, 1);
    }
    // طلب مفتوح/طوارئ: نبلغ الصنايعية القريبين المناسبين (داخل التطبيق)
    final radius = ((isEmergency ? settings['emergencyRadiusKm'] : settings['openRequestRadiusKm']) as num?)?.toDouble() ?? (isEmergency ? 15 : 25);
    final maxN = (settings['maxNotifiedWorkers'] as num?)?.toInt() ?? 30;
    var nearby = <Worker>[];
    try {
      nearby = await WorkerRepo.instance.search(
        lat: lat,
        lng: lng,
        f: SearchFilters(categoryId: categoryId, availableOnly: isEmergency, radiusKm: radius, sort: SortMode.nearest),
      );
    } catch (_) {}
    nearby = nearby.where((w) => w.id != customer.uid).take(maxN).toList();
    for (final w in nearby) {
      await notify(w.id, customer.uid, isEmergency ? 'emergency_request' : 'nearby_request',
          {'service': svc, 'km': (w.distanceKm ?? 0).toStringAsFixed(1)}, {'requestId': ref.id});
    }
    if (nearby.isNotEmpty) {
      try {
        await ref.update({'notifiedWorkerIds': nearby.map((w) => w.id).toList(), 'updatedAt': _now});
      } catch (_) {}
    }
    return (ref.id, nearby.length);
  }

  /// كل تغييرات حالة الطلب. [me] = المستخدم الحالي، [myWorker] = ملفه كصنايعي (لو صنايعي)
  Future<void> requestAction(ServiceRequest r, String action, {required AppUser me, Worker? myWorker, Map<String, dynamic> payload = const {}}) async {
    final ref = _db.doc('requests/${r.id}');
    final b = _db.batch();
    final patch = <String, dynamic>{'updatedAt': _now};
    String to;
    String by = r.customerId == me.uid ? 'customer' : 'worker';
    String note = '';
    String? notifyTo;
    String? notifyType;
    Map<String, dynamic> params = {};
    final svc = r.displayService;
    final workerName = r.workerName ?? myWorker?.name ?? '';

    switch (action) {
      case 'accept':
        to = 'accepted';
        patch['acceptedAt'] = _now;
        if (r.workerId == null) {
          // أول صنايعي يقبل الطلب المفتوح
          final w = myWorker!;
          patch.addAll({
            'workerId': me.uid,
            'workerName': w.name,
            'workerPhone': w.callPhone.isNotEmpty ? w.callPhone : w.phone,
            'workerWhatsapp': w.whatsapp.isNotEmpty ? w.whatsapp : w.phone,
            'workerPhotoUrl': w.photoUrl,
            'open': false,
          });
          notifyType = 'open_request_taken';
        } else {
          notifyType = 'request_accepted';
        }
        by = 'worker';
        notifyTo = r.customerId;
        params = {'name': myWorker?.name ?? workerName};
      case 'reject':
        to = 'rejected';
        notifyTo = r.customerId;
        notifyType = 'request_rejected';
        params = {'name': workerName};
      case 'propose_time':
        to = 'proposed';
        final at = payload['proposedAt'] as DateTime;
        patch['proposedAt'] = Timestamp.fromDate(at);
        notifyTo = r.customerId;
        notifyType = 'time_proposed';
        params = {'name': workerName, 'time': at.millisecondsSinceEpoch};
      case 'accept_proposal':
        to = 'confirmed';
        patch['scheduledAt'] = Timestamp.fromDate(r.proposedAt!);
        patch['proposedAt'] = null;
        notifyTo = r.workerId;
        notifyType = 'proposal_accepted';
        params = {'time': r.proposedAt!.millisecondsSinceEpoch};
      case 'on_the_way':
        to = 'on_the_way';
        notifyTo = r.customerId;
        notifyType = 'on_the_way';
        params = {'name': workerName};
      case 'start':
        to = 'started';
        notifyTo = r.customerId;
        notifyType = 'started';
        params = {'name': workerName};
      case 'complete':
        to = 'completed';
        notifyTo = r.customerId;
        notifyType = 'completed';
        params = {'name': workerName};
      case 'set_price':
        to = 'price_set';
        final price = (payload['price'] as num).toDouble();
        patch['agreedPrice'] = (price * 100).round() / 100;
        note = '${patch['agreedPrice']}';
        notifyTo = r.customerId;
        notifyType = 'price_set';
        params = {'name': workerName, 'price': patch['agreedPrice']};
      case 'confirm_price':
        to = 'price_agreed';
        // النسبة من الإعدادات (من السيرفر مباشرة) — القواعد بترفض أي نسبة أو مبلغ مختلف
        final s = await _db.doc('settings/public').get(const GetOptions(source: Source.server));
        final rate = (s.data()?['commissionRate'] as num?)?.toDouble() ?? 0.05;
        final price = r.agreedPrice!;
        final amount = (price * rate * 100).round() / 100;
        patch.addAll({'commissionRate': rate, 'commissionAmount': amount, 'commissionStatus': 'due', 'priceAgreedAt': _now});
        b.set(_db.doc('commissions/${r.id}'), {
          'requestId': r.id,
          'requestCode': r.code,
          'workerId': r.workerId,
          'workerName': r.workerName ?? '',
          'customerId': r.customerId,
          'servicePrice': price,
          'rate': rate,
          'amount': amount,
          'status': 'due',
          'paymentId': null,
          'createdAt': _now,
        });
        b.update(_db.doc('workers/${r.workerId}'), {'completedCount': FieldValue.increment(1), 'lastCompletedRequestId': r.id});
        notifyTo = r.workerId;
        notifyType = 'price_confirmed';
        params = {'price': price, 'commission': amount};
      case 'dispute_price':
        to = 'completed';
        patch['agreedPrice'] = null;
        notifyTo = r.workerId;
        notifyType = 'price_disputed';
      case 'cancel':
        to = 'cancelled';
        final reason = payload['reason'] as String;
        final cnote = (payload['note'] as String? ?? '').trim();
        patch.addAll({'cancelReason': reason, 'cancelNote': cnote.length > 300 ? cnote.substring(0, 300) : cnote, 'cancelledBy': by});
        if (by == 'customer' && r.open) patch['open'] = false;
        note = cnote.isEmpty ? reason : '$reason: $cnote';
        notifyTo = by == 'customer' ? r.workerId : r.customerId;
        notifyType = 'request_cancelled';
        params = {'service': svc};
      default:
        throw ArgumentError(action);
    }
    patch['status'] = to;
    b.update(ref, patch);
    b.set(ref.collection('history').doc(), {
      'from': r.status, 'to': to, 'action': action, 'by': by, 'byUid': me.uid, 'note': note, 'at': _now,
    });
    await b.commit();
    if (notifyTo != null && notifyType != null) {
      await notify(notifyTo, me.uid, notifyType, params, {'requestId': r.id});
      if (action == 'confirm_price') {
        await notify(r.workerId, me.uid, 'review_requested', {'name': r.customerName}, {'requestId': r.id});
      }
    }
  }

  // ------------------------------------------------------------------ التقييم
  Future<void> submitReview(ServiceRequest r, {required AppUser me, required int stars, required String comment}) async {
    final asCustomer = r.customerId == me.uid;
    final direction = asCustomer ? 'c2w' : 'w2c';
    final reviewId = '${r.id}_$direction';
    final toId = asCustomer ? r.workerId! : r.customerId;
    final b = _db.batch();
    b.set(_db.doc('reviews/$reviewId'), {
      'requestId': r.id,
      'direction': direction,
      'fromId': me.uid,
      'fromName': me.name,
      'toId': toId,
      'stars': stars,
      'comment': comment,
      'hidden': false,
      'serviceName': r.displayService,
      'createdAt': _now,
    });
    if (asCustomer) {
      b.update(_db.doc('workers/$toId'), {
        'ratingSum': FieldValue.increment(stars),
        'ratingCount': FieldValue.increment(1),
        'lastReviewId': reviewId,
      });
      b.update(_db.doc('requests/${r.id}'), {'customerReviewed': true, 'updatedAt': _now});
    } else {
      b.update(_db.doc('users/$toId'), {
        'customerRatingSum': FieldValue.increment(stars),
        'customerRatingCount': FieldValue.increment(1),
        'lastReviewId': reviewId,
      });
      b.update(_db.doc('requests/${r.id}'), {'workerReviewed': true, 'updatedAt': _now});
    }
    b.set(_db.collection('requests/${r.id}/history').doc(), {
      'from': r.status, 'to': r.status, 'action': 'review', 'by': asCustomer ? 'customer' : 'worker', 'byUid': me.uid,
      'note': '$stars★', 'at': _now,
    });
    await b.commit();
    if (asCustomer) await notify(toId, me.uid, 'review_received', {'stars': stars}, {'requestId': r.id});
  }

  // ------------------------------------------------------------------ الشات
  Future<void> sendMessage(ServiceRequest r, String senderId, {String? text, String? imageRef, double? lat, double? lng}) async {
    final other = senderId == r.customerId ? r.workerId : r.customerId;
    final data = <String, dynamic>{'senderId': senderId, 'createdAt': _now};
    String preview;
    if (imageRef != null) {
      data['type'] = 'image';
      data['imageRef'] = imageRef;
      preview = '📷';
    } else if (lat != null && lng != null) {
      data['type'] = 'location';
      data['lat'] = lat;
      data['lng'] = lng;
      preview = '📍';
    } else {
      data['type'] = 'text';
      data['text'] = text ?? '';
      preview = (text ?? '').length > 80 ? text!.substring(0, 80) : (text ?? '');
    }
    final b = _db.batch();
    b.set(_db.collection('requests/${r.id}/messages').doc(), data);
    b.update(_db.doc('requests/${r.id}'), {
      'lastMessage': preview,
      'lastMessageAt': _now,
      if (other != null) 'unread.$other': FieldValue.increment(1),
    });
    await b.commit();
    final fromName = senderId == r.customerId ? r.customerName : (r.workerName ?? '');
    await notify(other, senderId, 'new_message', {'name': fromName, 'text': preview}, {'requestId': r.id, 'screen': 'chat'});
  }

  Future<void> markChatRead(String requestId, String uid) async {
    try {
      await _db.doc('requests/$requestId').update({'unread.$uid': 0});
    } catch (_) {}
  }

  // ------------------------------------------------------------------ البلاغات والدعم
  Future<void> submitReport({required AppUser me, required String type, required String description, required List<String> images, ServiceRequest? request, String? againstId}) async {
    String? against = againstId;
    if (request != null) against = request.customerId == me.uid ? request.workerId : request.customerId;
    await _db.collection('reports').add({
      'reporterId': me.uid,
      'reporterName': me.name,
      'reporterRole': me.role,
      'againstId': against,
      'requestId': request?.id,
      'requestCode': request?.code ?? '',
      'type': type,
      'description': description,
      'images': images,
      'status': 'new',
      'adminNote': '',
      'actionTaken': '',
      'createdAt': _now,
      'updatedAt': _now,
    });
  }

  Future<void> submitTicket({required AppUser me, required String kind, required String subject, required String message}) async {
    await _db.collection('supportTickets').add({
      'uid': me.uid,
      'name': me.name,
      'phone': me.phone,
      'role': me.role,
      'kind': kind,
      'subject': subject,
      'message': message,
      'status': 'open',
      'reply': '',
      'createdAt': _now,
    });
  }

  // ------------------------------------------------------------------ دفع العمولة (InstaPay يدوي)
  Future<String> submitPayment({required AppUser me, required List<Commission> commissions, required String reference, String senderAccount = '', String? receiptRef}) async {
    final amount = commissions.fold<int>(0, (a, c) => a + (c.amount * 100).round()) / 100;
    final payRef = _db.collection('payments').doc();
    await payRef.set({
      'workerId': me.uid,
      'workerName': me.name,
      'workerPhone': me.phone,
      'provider': 'instapay_manual',
      'amount': amount,
      'commissionIds': commissions.map((c) => c.id).toList(),
      'reference': reference,
      'senderAccount': senderAccount,
      'receiptRef': receiptRef ?? '',
      'status': 'pending_review',
      'reviewNote': '',
      'createdAt': _now,
    });
    final b = _db.batch();
    for (final c in commissions) {
      b.update(_db.doc('commissions/${c.id}'), {'status': 'claimed', 'paymentId': payRef.id});
    }
    await b.commit();
    return payRef.id;
  }
}
