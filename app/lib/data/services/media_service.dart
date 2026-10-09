import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

/// الصور على الخطة المجانية: الصورة تتضغط (عرض أقصى 900px وجودة 55%) وتتخزن
/// Base64 في وثيقة media/{id}. المرجع اللي بيتخزن في البيانات: "media:<id>".
/// النوع (kind) بيحدد مين يشوفها: public للكل، id/receipt/report لصاحبها والإدارة، chat لأطراف الطلب.
class MediaService {
  MediaService._();
  static final instance = MediaService._();

  final _picker = ImagePicker();
  final _db = FirebaseFirestore.instance;
  final Map<String, Uint8List> _cache = {};

  static const maxBytes = 650 * 1024;

  Future<XFile?> pick({required bool camera, int maxWidth = 900, int quality = 55}) async {
    final x = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: quality,
      maxWidth: maxWidth.toDouble(),
      maxHeight: maxWidth.toDouble(),
    );
    return x;
  }

  Future<List<XFile>> pickMany({int max = 4}) async {
    if (max <= 0) return [];
    final xs = await _picker.pickMultiImage(imageQuality: 55, maxWidth: 900, maxHeight: 900, limit: max < 2 ? 2 : max);
    return xs.take(max).toList();
  }

  /// يرفع الصورة ويرجع المرجع "media:<id>"
  Future<String> upload(XFile file, {required String ownerId, required String kind, String? requestId}) async {
    var bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) {
      throw const MediaTooLarge();
    }
    final ref = _db.collection('media').doc();
    await ref.set({
      'ownerId': ownerId,
      'kind': kind,
      if (requestId != null) 'requestId': requestId,
      'mime': 'image/jpeg',
      'data': base64Encode(bytes),
      'createdAt': FieldValue.serverTimestamp(),
    });
    _cache[ref.id] = bytes;
    return 'media:${ref.id}';
  }

  static bool isMediaRef(String s) => s.startsWith('media:');

  Future<Uint8List?> load(String ref) async {
    if (!isMediaRef(ref)) return null;
    final id = ref.substring(6);
    if (_cache.containsKey(id)) return _cache[id];
    final d = await _db.doc('media/$id').get();
    final data = d.data()?['data'];
    if (data is! String) return null;
    final bytes = base64Decode(data);
    _cache[id] = bytes;
    return bytes;
  }
}

class MediaTooLarge implements Exception {
  const MediaTooLarge();
}
