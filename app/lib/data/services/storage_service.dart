import 'dart:io';
import 'dart:math';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// رفع الصور مع ضغطها (جودة 70% وعرض أقصى 1600px) لتقليل استهلاك البيانات
class StorageService {
  StorageService._();
  static final instance = StorageService._();

  final _picker = ImagePicker();
  final _storage = FirebaseStorage.instance;

  Future<File?> pick({required bool camera}) async {
    final x = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    return x == null ? null : File(x.path);
  }

  Future<List<File>> pickMany({int max = 6}) async {
    final xs = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1600, maxHeight: 1600, limit: max);
    return xs.take(max).map((x) => File(x.path)).toList();
  }

  String _name() => '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}.jpg';

  /// يرفع الصورة ويعيد المسار داخل Storage
  Future<String> uploadPath(File file, String folder) async {
    final path = '$folder/${_name()}';
    await _storage.ref(path).putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return path;
  }

  /// يرفع الصورة ويعيد رابط العرض (للصور العامة فقط — ليس للبطاقة)
  Future<String> uploadUrl(File file, String folder) async {
    final path = await uploadPath(file, folder);
    return _storage.ref(path).getDownloadURL();
  }

  final Map<String, String> _urlCache = {};
  Future<String> urlForPath(String path) async {
    if (_urlCache.containsKey(path)) return _urlCache[path]!;
    final u = await _storage.ref(path).getDownloadURL();
    _urlCache[path] = u;
    return u;
  }
}
