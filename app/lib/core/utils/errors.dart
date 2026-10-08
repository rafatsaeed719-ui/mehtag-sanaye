import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../i18n/i18n.dart';

/// يحوّل أي خطأ لرسالة مفهومة للمستخدم بلغته
String friendlyError(BuildContext context, Object e) {
  final ar = context.isAr;
  String m(String a, String en) => ar ? a : en;

  if (e is FirebaseFunctionsException) {
    final code = e.message ?? '';
    final details = e.details is Map ? (e.details as Map) : const {};
    const known = {
      'rate-limited': ['محاولات كتير، استنى شوية', 'Too many attempts, please wait'],
      'phone-required': ['لازم تأكد رقم الموبايل الأول', 'Please verify your mobile first'],
      'phone-in-use': ['الرقم ده مسجل بحساب تاني', 'This number is used by another account'],
      'national-id-in-use': ['الرقم القومي ده مسجل لصنايعي تاني', 'This national ID is registered to another worker'],
      'worker-unavailable': ['الصنايعي ده مش متاح حاليًا', 'This worker is not available'],
      'invalid-transition': ['الطلب اتغيرت حالته، حدّث الصفحة', 'The request status changed, please refresh'],
      'not-participant': ['الطلب ده مش متاح لك (ممكن صنايعي تاني قبله)', 'This request is not available to you (another worker may have accepted it)'],
      'already-reviewed': ['قيّمت الطلب ده قبل كده', 'You already rated this request'],
      'not-reviewable-yet': ['التقييم بيتفتح بعد انتهاء الخدمة', 'Rating opens after the job is done'],
      'commission-not-due': ['العمولة دي اتدفعت أو قيد المراجعة', 'This commission is already paid or under review'],
      'already-approved-use-change-request': ['حسابك موثق؛ استخدم تعديل البيانات', 'Your account is approved; use edit profile'],
      'account-suspended': ['الحساب موقوف', 'Account suspended'],
      'account-banned': ['الحساب محظور', 'Account banned'],
      'profile-missing': ['استكمل بيانات حسابك', 'Please complete your profile'],
      'invalid-time': ['الموعد غير صالح', 'Invalid time'],
      'invalid-price': ['المبلغ غير صحيح', 'Invalid amount'],
      'self-request': ['مينفعش تطلب نفسك 🙂', "You can't request yourself 🙂"],
    };
    if (known.containsKey(code)) return m(known[code]![0], known[code]![1]);
    final dCode = details['code']?.toString();
    if (dCode != null && known.containsKey(dCode)) return m(known[dCode]![0], known[dCode]![1]);
    if (e.code == 'invalid-argument') {
      final field = details['field']?.toString() ?? '';
      final fcode = details['code']?.toString() ?? '';
      if (fcode == 'outside-egypt') return m('الموقع لازم يكون داخل مصر', 'Location must be inside Egypt');
      if (fcode == 'invalid-phone') return m('رقم الموبايل غير صحيح', 'Invalid mobile number');
      if (fcode == 'invalid-national-id') return m('الرقم القومي لازم يكون 14 رقم صحيح', 'National ID must be 14 valid digits');
      if (fcode == 'required') return m('في بيانات ناقصة ($field)', 'Missing data ($field)');
      if (fcode == 'too-short') return m('النص قصير جدًا ($field)', 'Text too short ($field)');
      return m('بيانات غير صحيحة ($field)', 'Invalid data ($field)');
    }
    if (e.code == 'unavailable' || e.code == 'deadline-exceeded') return context.t('error_network');
    if (e.code == 'permission-denied') return context.t('error_permission');
    if (e.code == 'resource-exhausted') return context.t('error_rate_limited');
    return context.t('error_generic');
  }
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
      case 'session-expired':
        return m('الكود انتهت صلاحيته، اطلب كود جديد', 'Code expired, request a new one');
    }
    return e.message ?? context.t('error_generic');
  }
  if (e is FirebaseException) {
    if (e.code == 'unavailable') return context.t('error_network');
    if (e.code == 'permission-denied') return context.t('error_permission');
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
