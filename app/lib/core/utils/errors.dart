import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/services/media_service.dart';
import '../i18n/i18n.dart';

/// يحوّل أي خطأ لرسالة مفهومة للمستخدم بلغته
String friendlyError(BuildContext context, Object e) {
  final ar = context.isAr;
  String m(String a, String en) => ar ? a : en;

  if (e is MediaTooLarge) return context.t('image_too_large');
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-verification-code':
        return context.t('invalid_code');
      case 'invalid-phone-number':
        return context.t('invalid_phone');
      case 'too-many-requests':
        return context.t('too_many_requests');
      case 'credential-already-in-use':
      case 'provider-already-linked':
        return context.t('phone_in_use');
      case 'network-request-failed':
        return context.t('error_network');
      case 'user-disabled':
        return context.t('account_blocked_sub');
      case 'wrong-password':
      case 'invalid-credential':
      case 'user-not-found':
      case 'invalid-login-credentials':
        return context.t('wrong_password');
      case 'email-already-in-use':
        return context.t('email_in_use');
      case 'weak-password':
        return context.t('weak_password');
      case 'invalid-email':
        return context.t('invalid_email');
    }
    return e.message ?? context.t('error_generic');
  }
  if (e is FirebaseException) {
    if (e.code == 'unavailable') return context.t('error_network');
    if (e.code == 'permission-denied') return context.t('error_permission');
    if (e.code == 'failed-precondition') return m('العملية مش متاحة دلوقتي — حدّث الصفحة', 'Not available right now — refresh');
  }
  return context.t('error_generic');
}

void showSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFB91C1C) : null,
      behavior: SnackBarBehavior.floating,
    ));
}

void showError(BuildContext context, Object e) => showSnack(context, friendlyError(context, e), error: true);
