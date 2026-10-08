import 'package:intl/intl.dart';

class Fmt {
  static String money(num? v, String lang) {
    if (v == null) return '-';
    final f = NumberFormat.decimalPattern('en');
    final rounded = (v * 100).round() / 100;
    return f.format(rounded);
  }

  static String km(double km, String lang) {
    final v = km < 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(0);
    return v;
  }

  static String dateTime(DateTime? d, String lang) {
    if (d == null) return '-';
    return DateFormat('EEE d MMM • h:mm a', lang == 'ar' ? 'ar' : 'en').format(d.toLocal());
  }

  static String date(DateTime? d, String lang) {
    if (d == null) return '-';
    return DateFormat('d MMM yyyy', lang == 'ar' ? 'ar' : 'en').format(d.toLocal());
  }

  static String relative(DateTime? d, String lang) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    final ar = lang == 'ar';
    if (diff.inMinutes < 1) return ar ? 'الآن' : 'now';
    if (diff.inMinutes < 60) return ar ? 'منذ ${diff.inMinutes} د' : '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return ar ? 'منذ ${diff.inHours} س' : '${diff.inHours}h ago';
    if (diff.inDays < 7) return ar ? 'منذ ${diff.inDays} يوم' : '${diff.inDays}d ago';
    return date(d, lang);
  }

  /// يحوّل الأرقام العربية ويطبع الرقم بالشكل 01xxxxxxxxx
  static String normalizePhone(String input) {
    var s = input.replaceAll(RegExp(r'[\s-]'), '');
    const ar = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(ar[i], '$i');
    }
    if (s.startsWith('+20')) s = '0${s.substring(3)}';
    if (s.startsWith('0020')) s = '0${s.substring(4)}';
    return s;
  }

  static bool isEgMobile(String s) => RegExp(r'^01[0125][0-9]{8}$').hasMatch(normalizePhone(s));

  /// 01xxxxxxxxx → +201xxxxxxxxx (صيغة Firebase)
  static String toE164(String s) => '+2${normalizePhone(s)}';

  static String whatsappLink(String phone) {
    final p = normalizePhone(phone);
    return 'https://wa.me/2$p';
  }
}
