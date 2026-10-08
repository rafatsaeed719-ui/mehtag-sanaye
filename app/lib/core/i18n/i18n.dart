import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings.dart';

/// يتحكم في لغة التطبيق (عربي/إنجليزي) ويحفظها على الجهاز.
class LocaleController extends ChangeNotifier {
  static const _key = 'app_lang';
  String _lang = 'ar';
  final List<void Function(String oldLang, String newLang)> _listeners = [];

  String get lang => _lang;
  Locale get locale => Locale(_lang);
  bool get isArabic => _lang == 'ar';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _lang = prefs.getString(_key) ?? 'ar';
  }

  /// يُستدعى عند تغيير اللغة (لتحديث لغة الإشعارات على السيرفر واشتراكات Topics)
  void onLangChanged(void Function(String oldLang, String newLang) cb) => _listeners.add(cb);

  Future<void> setLang(String lang) async {
    if (lang == _lang || !kStrings.containsKey(lang)) return;
    final old = _lang;
    _lang = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, lang);
    notifyListeners();
    for (final l in _listeners) {
      l(old, lang);
    }
  }

  String t(String key, [Map<String, Object?>? params]) {
    var s = kStrings[_lang]?[key] ?? kStrings['ar']?[key] ?? key;
    if (params != null) {
      params.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
    }
    return s;
  }
}

extension I18nX on BuildContext {
  String t(String key, [Map<String, Object?>? params]) => read<LocaleController>().t(key, params);
  String get lang => read<LocaleController>().lang;
  bool get isAr => read<LocaleController>().isArabic;

  /// يختار النص حسب اللغة من خريطة {ar, en} القادمة من قاعدة البيانات
  String loc(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Map) {
      final v = value[lang] ?? value['ar'] ?? value['en'];
      return v?.toString() ?? '';
    }
    return value.toString();
  }
}
