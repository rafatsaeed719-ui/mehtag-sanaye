import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../data/services/auth_service.dart';
import '../../data/session.dart';
import '../shared/help_screen.dart';
import 'language_toggle.dart';
import 'phone_otp_form.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _googleBusy = false;

  Future<void> _google() async {
    setState(() => _googleBusy = true);
    try {
      await AuthService.instance.signInWithGoogle();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final isWorker = session.chosenRole == 'worker';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const BackButtonIcon(), onPressed: session.resetRoleChoice),
        title: Text(context.t('login_title')),
        actions: const [LanguageToggle()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(child: Image.asset('assets/images/logo_full.png', height: 120)),
            const SizedBox(height: 12),
            Center(
              child: Chip(
                avatar: Text(isWorker ? '🔧' : '👤'),
                label: Text(isWorker ? context.t('i_am_worker') : context.t('i_am_customer')),
              ),
            ),
            const SizedBox(height: 24),
            const PhoneOtpForm(),
            const SizedBox(height: 20),
            Row(children: [
              const Expanded(child: Divider()),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(context.t('or'), style: const TextStyle(color: AppColors.muted))),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _googleBusy ? null : _google,
              icon: _googleBusy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('G', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF4285F4))),
              label: Text(context.t('google_signin')),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PoliciesScreen())),
              child: Text(context.t('terms_agree'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }
}
