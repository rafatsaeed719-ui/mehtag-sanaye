import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/services/auth_service.dart';

/// إدخال رقم الموبايل ثم كود OTP (للدخول أو لربط الرقم بحساب Google)
class PhoneOtpForm extends StatefulWidget {
  const PhoneOtpForm({super.key});
  @override
  State<PhoneOtpForm> createState() => _PhoneOtpFormState();
}

class _PhoneOtpFormState extends State<PhoneOtpForm> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _verificationId;
  int? _resendToken;
  bool _busy = false;
  int _seconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _seconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _seconds--);
      if (_seconds <= 0) t.cancel();
    });
  }

  Future<void> _send({bool resend = false}) async {
    final phone = Fmt.normalizePhone(_phone.text);
    if (!Fmt.isEgMobile(phone)) {
      showSnack(context, context.t('invalid_phone'), error: true);
      return;
    }
    setState(() => _busy = true);
    await AuthService.instance.sendCode(
      phone: phone,
      resendToken: resend ? _resendToken : null,
      onCodeSent: (id, token) {
        if (!mounted) return;
        setState(() {
          _verificationId = id;
          _resendToken = token;
          _busy = false;
        });
        _startTimer();
      },
      onAutoVerified: (cred) async {
        // Android أحيانًا بيقرأ الكود تلقائيًا
        try {
          await AuthService.instance.signInOrLinkWithCredential(cred);
        } catch (e) {
          if (mounted) showError(context, e);
        }
        if (mounted) setState(() => _busy = false);
      },
      onError: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() => _busy = false);
        showError(context, e);
      },
    );
  }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6 || _verificationId == null) {
      showSnack(context, context.t('invalid_code'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthService.instance.verifyCode(_verificationId!, _code.text);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verificationId == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+٠-٩ ]')), LengthLimitingTextInputFormatter(16)],
          decoration: InputDecoration(
            labelText: context.t('phone_number'),
            hintText: context.t('phone_hint'),
            prefixIcon: const Icon(Icons.phone_iphone),
          ),
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: 16),
        BusyButton(label: context.t('send_code'), busy: _busy, onPressed: () => _send()),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(context.t('otp_sent_to', {'phone': Fmt.normalizePhone(_phone.text)}), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 16),
      TextField(
        controller: _code,
        autofocus: true,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: const TextStyle(fontSize: 26, letterSpacing: 12, fontWeight: FontWeight.w700),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        decoration: const InputDecoration(hintText: '------'),
        onChanged: (v) {
          if (v.length == 6) _verify();
        },
      ),
      const SizedBox(height: 16),
      BusyButton(label: context.t('verify'), busy: _busy, onPressed: _verify),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _seconds > 0 || _busy ? null : () => _send(resend: true),
        child: Text(_seconds > 0 ? context.t('resend_in', {'s': _seconds}) : context.t('resend_code')),
      ),
      TextButton(
        onPressed: () => setState(() {
          _verificationId = null;
          _code.clear();
        }),
        child: Text(context.t('back')),
      ),
    ]);
  }
}
