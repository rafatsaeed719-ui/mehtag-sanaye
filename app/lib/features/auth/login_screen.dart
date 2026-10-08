import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/common.dart';
import '../../data/services/auth_service.dart';
import '../../data/session.dart';
import '../shared/help_screen.dart';
import 'language_toggle.dart';

/// الدخول: البريد وكلمة السر (دخول / حساب جديد) أو Google
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _googleBusy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  bool _validEmail(String e) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e.trim());

  Future<void> _submit() async {
    if (!_validEmail(_email.text)) {
      showSnack(context, context.t('invalid_email'), error: true);
      return;
    }
    if (_pass.text.length < 8) {
      showSnack(context, context.t('password_short'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (_register) {
        await AuthService.instance.register(_email.text, _pass.text);
      } else {
        await AuthService.instance.signIn(_email.text, _pass.text);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    if (!_validEmail(_email.text)) {
      showSnack(context, context.t('invalid_email'), error: true);
      return;
    }
    try {
      await AuthService.instance.resetPassword(_email.text);
      if (mounted) showSnack(context, context.t('reset_sent'));
    } on FirebaseAuthException catch (e) {
      if (mounted) showError(context, e);
    }
  }

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
        title: Text(_register ? context.t('create_account') : context.t('login_title')),
        actions: const [LanguageToggle()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(child: Image.asset('assets/images/logo_full.png', height: 110)),
            const SizedBox(height: 12),
            Center(
              child: Chip(
                avatar: Text(isWorker ? '🔧' : '👤'),
                label: Text(isWorker ? context.t('i_am_worker') : context.t('i_am_customer')),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(context.t('login_title'))),
                ButtonSegment(value: true, label: Text(context.t('new_account'))),
              ],
              selected: {_register},
              onSelectionChanged: (v) => setState(() => _register = v.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: context.t('email'), prefixIcon: const Icon(Icons.email_outlined)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: _obscure,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: context.t('password'),
                helperText: _register ? context.t('password_short') : null,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscure = !_obscure)),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (!_register)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(onPressed: _forgot, child: Text(context.t('forgot_password'))),
              ),
            const SizedBox(height: 12),
            BusyButton(label: _register ? context.t('create_account') : context.t('login_title'), busy: _busy, onPressed: _submit),
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
