import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';

class LanguageToggle extends StatelessWidget {
  final bool light;
  const LanguageToggle({super.key, this.light = false});
  @override
  Widget build(BuildContext context) {
    final lc = context.watch<LocaleController>();
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: light ? Colors.white : null),
      onPressed: () => lc.setLang(lc.isArabic ? 'en' : 'ar'),
      icon: const Icon(Icons.language, size: 18),
      label: Text(lc.isArabic ? 'English' : 'العربية'),
    );
  }
}
