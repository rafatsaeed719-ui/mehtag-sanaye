import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _ts(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  return null;
}

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
List<String> _sl(dynamic v) => v is List ? v.map((e) => '$e').toList() : <String>[];
Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class AppUser {
  final String uid;
  final String role; // customer | worker
  final String name;
  final String phone;
  final String photoUrl;
  final String lang;
  final String status; // active | suspended | banned | deleted
  final double customerRatingAvg;
  final int customerRatingCount;

  AppUser({
    required this.uid,
    required this.role,
    required this.name,
    required this.phone,
    required this.photoUrl,
    required this.lang,
    required this.status,
    required this.customerRatingAvg,
    required this.customerRatingCount,
  });

  bool get isWorker => role == 'worker';
  bool get isActive => status == 'active';

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return AppUser(
      uid: d.id,
      role: m['role'] ?? 'customer',
      name: m['name'] ?? '',
      phone: m['phone'] ?? '',
      photoUrl: m['photoUrl'] ?? '',
      lang: m['lang'] ?? 'ar',
      status: m['status'] ?? 'active',
      customerRatingAvg: _d(m['customerRatingAvg']),
      customerRatingCount: _i(m['customerRatingCount']),
    );
  }
}

class JobCategory {
  final String id;
  final String nameAr;
  final String nameEn;
  final String icon;
  final String iconUrl;
  final bool active;
  final int order;
  JobCategory({required this.id, required this.nameAr, required this.nameEn, required this.icon, required this.iconUrl, required this.active, required this.order});

  String name(String lang) => lang == 'en' ? nameEn : nameAr;
  Map<String, String> get names => {'ar': nameAr, 'en': nameEn};

  factory JobCategory.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return JobCategory(
      id: d.id,
      nameAr: m['nameAr'] ?? '',
      nameEn: m['nameEn'] ?? '',
      icon: m['icon'] ?? 'handyman',
      iconUrl: m['iconUrl'] ?? '',
      active: m['active'] != false,
      order: _i(m['order']),
    );
  }
}

class Service {
  final String id;
  final String categoryId;
  final String nameAr;
  final String nameEn;
  final bool active;
  final int order;
  Service({required this.id, required this.categoryId, required this.nameAr, required this.nameEn, required this.active, required this.order});
  String name(String lang) => lang == 'en' ? nameEn : nameAr;

  factory Service.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Service(
      id: d.id,
      categoryId: m['categoryId'] ?? '',
      nameAr: m['nameAr'] ?? '',
      nameEn: m['nameEn'] ?? '',
      active: m['active'] != false,
      order: _i(m['order']),
    );
  }
}

/// محافظة / مدينة / منطقة — يديرها الأدمن، مع إحداثيات المركز (اختياري)
class Place {
  final String id;
  final String type; // governorate | city | area
  final String code;
  final String nameAr;
  final String nameEn;
  final String parentId;
  final double? lat;
  final double? lng;
  Place({required this.id, required this.type, required this.code, required this.nameAr, required this.nameEn, required this.parentId, this.lat, this.lng});
  String name(String lang) => lang == 'en' && nameEn.isNotEmpty ? nameEn : nameAr;

  factory Place.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Place(
      id: d.id,
      type: m['type'] ?? 'governorate',
      code: m['code'] ?? d.id,
      nameAr: m['nameAr'] ?? '',
      nameEn: m['nameEn'] ?? '',
      parentId: m['parentId'] ?? '',
      lat: m['lat'] is num ? (m['lat'] as num).toDouble() : null,
      lng: m['lng'] is num ? (m['lng'] as num).toDouble() : null,
    );
  }
}

class Worker {
  final String id;
  final String name;
  final String phone;
  final String photoUrl;
  final List<String> categoryIds;
  final List<String> serviceIds;
  final List<Map<String, dynamic>> categoryNames;
  final List<Map<String, dynamic>> serviceNames;
  final String governorate;
  final String city;
  final String area;
  final double lat;
  final double lng;
  final String bio;
  final double? visitFee;
  final String whatsapp;
  final String callPhone;
  final List<String> workImages;
  final bool available;
  final String verificationStatus; // pending | approved | rejected
  final String rejectionReason;
  final bool idVerified;
  final bool hasIdDoc;
  final bool suspended;
  final bool pendingChange;
  final double ratingAvg;
  final int ratingCount;
  final int completedCount;
  final Map<String, dynamic> stats;
  final List<String> badges;

  /// تُحسب على الجهاز بعد البحث
  double? distanceKm;
  double score = 0;

  Worker({
    required this.id,
    required this.name,
    required this.phone,
    required this.photoUrl,
    required this.categoryIds,
    required this.serviceIds,
    required this.categoryNames,
    required this.serviceNames,
    required this.governorate,
    required this.city,
    required this.area,
    required this.lat,
    required this.lng,
    required this.bio,
    required this.visitFee,
    required this.whatsapp,
    required this.callPhone,
    required this.workImages,
    required this.available,
    required this.verificationStatus,
    required this.rejectionReason,
    required this.idVerified,
    required this.hasIdDoc,
    required this.suspended,
    required this.pendingChange,
    required this.ratingAvg,
    required this.ratingCount,
    required this.completedCount,
    required this.stats,
    required this.badges,
  });

  bool get isApproved => verificationStatus == 'approved';
  int get received => _i(stats['received']);
  int get responded => _i(stats['responded']);
  int get accepted => _i(stats['accepted']);
  int get cancelled => _i(stats['cancelled']);
  double get avgResponseMinutes => responded > 0 ? _d(stats['responseMinutesTotal']) / responded : 0;
  double get responseRate => received > 0 ? (responded / received).clamp(0, 1).toDouble() : 0;

  factory Worker.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final g = _m(m['geo']);
    return Worker(
      id: d.id,
      name: m['name'] ?? '',
      phone: m['phone'] ?? '',
      photoUrl: m['photoUrl'] ?? '',
      categoryIds: _sl(m['categoryIds']),
      serviceIds: _sl(m['serviceIds']),
      categoryNames: (m['categoryNames'] is List ? m['categoryNames'] as List : const []).map((e) => _m(e)).toList(),
      serviceNames: (m['serviceNames'] is List ? m['serviceNames'] as List : const []).map((e) => _m(e)).toList(),
      governorate: m['governorate'] ?? '',
      city: m['city'] ?? '',
      area: m['area'] ?? '',
      lat: _d(g['lat']),
      lng: _d(g['lng']),
      bio: m['bio'] ?? '',
      visitFee: m['visitFee'] is num ? (m['visitFee'] as num).toDouble() : null,
      whatsapp: m['whatsapp'] ?? '',
      callPhone: m['callPhone'] ?? '',
      workImages: _sl(m['workImages']),
      available: m['available'] == true,
      verificationStatus: m['verificationStatus'] ?? 'pending',
      rejectionReason: m['rejectionReason'] ?? '',
      idVerified: m['idVerified'] == true,
      hasIdDoc: m['hasIdDoc'] == true,
      suspended: m['suspended'] == true,
      pendingChange: m['pendingChange'] == true,
      ratingAvg: _d(m['ratingAvg']),
      ratingCount: _i(m['ratingCount']),
      completedCount: _i(m['completedCount']),
      stats: _m(m['stats']),
      badges: _sl(m['badges']),
    );
  }
}

class ServiceRequest {
  final String id;
  final String code;
  final String customerId;
  final String customerName;
  final String? customerPhone;
  final String? workerId;
  final String? workerName;
  final String? workerPhone;
  final String? workerWhatsapp;
  final String workerPhotoUrl;
  final String categoryId;
  final Map<String, dynamic> categoryName;
  final String? serviceId;
  final Map<String, dynamic>? serviceName;
  final String description;
  final List<String> images;
  final double lat;
  final double lng;
  final String address;
  final String governorate;
  final DateTime? scheduledAt;
  final DateTime? proposedAt;
  final bool isEmergency;
  final bool open;
  final String status;
  final double? agreedPrice;
  final double? commissionRate;
  final double? commissionAmount;
  final String commissionStatus;
  final bool customerReviewed;
  final bool workerReviewed;
  final String? cancelReason;
  final String? cancelNote;
  final String? cancelledBy;
  final List<String> notifiedWorkerIds;
  final Map<String, dynamic> unread;
  final String lastMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ServiceRequest({
    required this.id,
    required this.code,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.workerId,
    required this.workerName,
    required this.workerPhone,
    required this.workerWhatsapp,
    required this.workerPhotoUrl,
    required this.categoryId,
    required this.categoryName,
    required this.serviceId,
    required this.serviceName,
    required this.description,
    required this.images,
    required this.lat,
    required this.lng,
    required this.address,
    required this.governorate,
    required this.scheduledAt,
    required this.proposedAt,
    required this.isEmergency,
    required this.open,
    required this.status,
    required this.agreedPrice,
    required this.commissionRate,
    required this.commissionAmount,
    required this.commissionStatus,
    required this.customerReviewed,
    required this.workerReviewed,
    required this.cancelReason,
    required this.cancelNote,
    required this.cancelledBy,
    required this.notifiedWorkerIds,
    required this.unread,
    required this.lastMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  static const activeStatuses = ['new', 'accepted', 'proposed', 'confirmed', 'on_the_way', 'started', 'completed', 'price_set'];
  static const reviewableStatuses = ['completed', 'price_set', 'price_agreed', 'commission_paid'];
  static const cancellableStatuses = ['new', 'accepted', 'proposed', 'confirmed', 'on_the_way', 'started'];

  bool get isActive => activeStatuses.contains(status);
  bool get isReviewable => reviewableStatuses.contains(status);
  bool get isCancellable => cancellableStatuses.contains(status);
  Map<String, dynamic> get displayService => serviceName ?? categoryName;
  int unreadFor(String uid) => _i(unread[uid]);

  factory ServiceRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final loc = _m(m['location']);
    return ServiceRequest(
      id: d.id,
      code: m['code'] ?? d.id.substring(0, 6).toUpperCase(),
      customerId: m['customerId'] ?? '',
      customerName: m['customerName'] ?? '',
      customerPhone: m['customerPhone'],
      workerId: m['workerId'],
      workerName: m['workerName'],
      workerPhone: m['workerPhone'],
      workerWhatsapp: m['workerWhatsapp'],
      workerPhotoUrl: m['workerPhotoUrl'] ?? '',
      categoryId: m['categoryId'] ?? '',
      categoryName: _m(m['categoryName']),
      serviceId: m['serviceId'],
      serviceName: m['serviceName'] == null ? null : _m(m['serviceName']),
      description: m['description'] ?? '',
      images: _sl(m['images']),
      lat: _d(loc['lat']),
      lng: _d(loc['lng']),
      address: loc['address'] ?? '',
      governorate: loc['governorate'] ?? '',
      scheduledAt: _ts(m['scheduledAt']),
      proposedAt: _ts(m['proposedAt']),
      isEmergency: m['isEmergency'] == true,
      open: m['open'] == true,
      status: m['status'] ?? 'new',
      agreedPrice: m['agreedPrice'] is num ? (m['agreedPrice'] as num).toDouble() : null,
      commissionRate: m['commissionRate'] is num ? (m['commissionRate'] as num).toDouble() : null,
      commissionAmount: m['commissionAmount'] is num ? (m['commissionAmount'] as num).toDouble() : null,
      commissionStatus: m['commissionStatus'] ?? 'none',
      customerReviewed: m['customerReviewed'] == true,
      workerReviewed: m['workerReviewed'] == true,
      cancelReason: m['cancelReason'],
      cancelNote: m['cancelNote'],
      cancelledBy: m['cancelledBy'],
      notifiedWorkerIds: _sl(m['notifiedWorkerIds']),
      unread: _m(m['unread']),
      lastMessage: m['lastMessage'] ?? '',
      createdAt: _ts(m['createdAt']),
      updatedAt: _ts(m['updatedAt']),
    );
  }
}

class HistoryEntry {
  final String? from;
  final String to;
  final String action;
  final String by;
  final String note;
  final DateTime? at;
  HistoryEntry({this.from, required this.to, required this.action, required this.by, required this.note, this.at});
  factory HistoryEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return HistoryEntry(from: m['from'], to: m['to'] ?? '', action: m['action'] ?? '', by: m['by'] ?? '', note: m['note'] ?? '', at: _ts(m['at']));
  }
}

class ChatMessage {
  final String id;
  final String senderId;
  final String type; // text | image | location
  final String text;
  final String imagePath;
  final double? lat;
  final double? lng;
  final DateTime? createdAt;
  ChatMessage({required this.id, required this.senderId, required this.type, required this.text, required this.imagePath, this.lat, this.lng, this.createdAt});
  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return ChatMessage(
      id: d.id,
      senderId: m['senderId'] ?? '',
      type: m['type'] ?? 'text',
      text: m['text'] ?? '',
      imagePath: m['imagePath'] ?? '',
      lat: m['lat'] is num ? (m['lat'] as num).toDouble() : null,
      lng: m['lng'] is num ? (m['lng'] as num).toDouble() : null,
      createdAt: _ts(m['createdAt']),
    );
  }
}

class Review {
  final String id;
  final String fromName;
  final int stars;
  final String comment;
  final DateTime? createdAt;
  final Map<String, dynamic> serviceName;
  Review({required this.id, required this.fromName, required this.stars, required this.comment, this.createdAt, required this.serviceName});
  factory Review.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Review(id: d.id, fromName: m['fromName'] ?? '', stars: _i(m['stars']), comment: m['comment'] ?? '', createdAt: _ts(m['createdAt']), serviceName: _m(m['serviceName']));
  }
}

class AppNotification {
  final String id;
  final String type;
  final String titleAr, bodyAr, titleEn, bodyEn, title, body;
  final Map<String, dynamic> data;
  final bool read;
  final DateTime? createdAt;
  AppNotification({required this.id, required this.type, required this.titleAr, required this.bodyAr, required this.titleEn, required this.bodyEn, required this.title, required this.body, required this.data, required this.read, this.createdAt});
  String titleFor(String lang) => (lang == 'en' ? titleEn : titleAr).isNotEmpty ? (lang == 'en' ? titleEn : titleAr) : title;
  String bodyFor(String lang) => (lang == 'en' ? bodyEn : bodyAr).isNotEmpty ? (lang == 'en' ? bodyEn : bodyAr) : body;
  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return AppNotification(
      id: d.id,
      type: m['type'] ?? '',
      titleAr: m['titleAr'] ?? '',
      bodyAr: m['bodyAr'] ?? '',
      titleEn: m['titleEn'] ?? '',
      bodyEn: m['bodyEn'] ?? '',
      title: m['title'] ?? '',
      body: m['body'] ?? '',
      data: _m(m['data']),
      read: m['read'] == true,
      createdAt: _ts(m['createdAt']),
    );
  }
}

class Commission {
  final String id;
  final String requestId;
  final String requestCode;
  final double servicePrice;
  final double rate;
  final double amount;
  final String status; // due | claimed | paid
  final DateTime? createdAt;
  Commission({required this.id, required this.requestId, required this.requestCode, required this.servicePrice, required this.rate, required this.amount, required this.status, this.createdAt});
  factory Commission.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Commission(
      id: d.id,
      requestId: m['requestId'] ?? d.id,
      requestCode: m['requestCode'] ?? '',
      servicePrice: _d(m['servicePrice']),
      rate: _d(m['rate']),
      amount: _d(m['amount']),
      status: m['status'] ?? 'due',
      createdAt: _ts(m['createdAt']),
    );
  }
}

class Payment {
  final String id;
  final double amount;
  final String reference;
  final String status; // pending_review | confirmed | rejected
  final String reviewNote;
  final DateTime? createdAt;
  Payment({required this.id, required this.amount, required this.reference, required this.status, required this.reviewNote, this.createdAt});
  factory Payment.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Payment(id: d.id, amount: _d(m['amount']), reference: m['reference'] ?? '', status: m['status'] ?? 'pending_review', reviewNote: m['reviewNote'] ?? '', createdAt: _ts(m['createdAt']));
  }
}

class Wallet {
  final double totalServices, totalCommission, paid, due, overdue;
  final int jobs;
  Wallet({this.totalServices = 0, this.totalCommission = 0, this.paid = 0, this.due = 0, this.overdue = 0, this.jobs = 0});
  factory Wallet.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Wallet(
      totalServices: _d(m['totalServices']),
      totalCommission: _d(m['totalCommission']),
      paid: _d(m['paid']),
      due: _d(m['due']),
      overdue: _d(m['overdue']),
      jobs: _i(m['jobs']),
    );
  }
}

class ReportItem {
  final String id;
  final String type;
  final String description;
  final String status;
  final String requestCode;
  final DateTime? createdAt;
  ReportItem({required this.id, required this.type, required this.description, required this.status, required this.requestCode, this.createdAt});
  factory ReportItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return ReportItem(id: d.id, type: m['type'] ?? 'other', description: m['description'] ?? '', status: m['status'] ?? 'new', requestCode: m['requestCode'] ?? '', createdAt: _ts(m['createdAt']));
  }
}
