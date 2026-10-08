import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../data/session.dart';
import 'phone_otp_form.dart';

/// بعد الدخول بـGoogle: لازم ربط رقم موبايل (رقم واحد لكل حساب)
class LinkPhoneScreen extends StatelessWidget {
  const LinkPhoneScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.t('link_phone_title')),
          actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => context.read<Session>().signOut())],
        ),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const Icon(Icons.verified_user_outlined, size: 64, color: AppColors.navy),
            const SizedBox(height: 12),
            Text(context.t('link_phone_sub'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
            const SizedBox(height: 24),
            const PhoneOtpForm(),
          ]),
        ),
      );
}
