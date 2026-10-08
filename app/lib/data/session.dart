import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'services/auth_service.dart';
import 'services/backend.dart';

const kAppVersion = '1.1.2';

enum SessionState {
  loading,
  chooseRole, // أول فتح: عميل ولا صنايعي
  signedOut,
  needsProfile, // أول مرة: الاسم والموبايل ونوع الحساب
  blocked,
  customer,
  workerOnboarding, // صنايعي لسه بيسجل / قيد المراجعة / مرفوض
  worker, // صنايعي موثق
}

/// الحالة العامة للمستخدم — كل شاشات التطبيق بتتحدد منها
class Session extends ChangeNotifier {
  static const _roleKey = 'chosen_role';

  SessionState state = SessionState.loading;
  User? authUser;
  AppUser? user;
  Worker? worker;
  String chosenRole = '';
  String lang = 'ar';

  StreamSubscription<User?>? _authSub;
  StreamSubscription? _userSub;
  StreamSubscription? _workerSub;

  String? get uid => authUser?.uid;
  bool get isWorker => user?.isWorker == true;

  Future<void> start(String currentLang) async {
    lang = currentLang;
    final prefs = await SharedPreferences.getInstance();
    chosenRole = prefs.getString(_roleKey) ?? '';
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuth);
  }

  Future<void> chooseRole(String role) async {
    chosenRole = role;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roleKey, role);
    if (authUser == null) _set(SessionState.signedOut);
  }

  Future<void> resetRoleChoice() async {
    chosenRole = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roleKey);
    _set(SessionState.chooseRole);
  }

  void _set(SessionState s) {
    state = s;
    notifyListeners();
  }

  Future<void> _onAuth(User? u) async {
    final changed = u?.uid != authUser?.uid;
    authUser = u;
    if (u == null) {
      await _userSub?.cancel();
      await _workerSub?.cancel();
      _userSub = null;
      user = null;
      worker = null;
      _set(chosenRole.isEmpty ? SessionState.chooseRole : SessionState.signedOut);
      return;
    }
    if (changed || _userSub == null) _listenUser(u.uid);
  }

  void _listenUser(String uid) {
    _userSub?.cancel();
    _userSub = FirebaseFirestore.instance.doc('users/$uid').snapshots().listen((d) {
      if (!d.exists) {
        user = null;
        _set(SessionState.needsProfile);
        return;
      }
      user = AppUser.fromDoc(d);
      if (!user!.isActive) {
        _set(SessionState.blocked);
        return;
      }
      if (user!.lang != lang) {
        FirebaseFirestore.instance.doc('users/$uid').update({'lang': lang}).catchError((_) {});
      }
      if (user!.isWorker) {
        _listenWorker(uid);
      } else {
        _workerSub?.cancel();
        worker = null;
        _set(SessionState.customer);
      }
    }, onError: (_) {
      if (state == SessionState.loading) _set(SessionState.needsProfile);
    });
  }

  void _listenWorker(String uid) {
    _workerSub?.cancel();
    _workerSub = FirebaseFirestore.instance.doc('workers/$uid').snapshots().listen((d) {
      worker = d.exists ? Worker.fromDoc(d) : null;
      final approved = worker != null && worker!.isApproved && !worker!.suspended;
      _set(approved ? SessionState.worker : SessionState.workerOnboarding);
    }, onError: (_) => _set(SessionState.workerOnboarding));
  }

  Future<void> onLanguageChanged(String newLang) async {
    lang = newLang;
    if (uid != null && user != null) {
      await FirebaseFirestore.instance.doc('users/$uid').update({'lang': newLang}).catchError((_) {});
    }
  }

  /// إنشاء الملف: الاسم + رقم الموبايل (رقم واحد لكل حساب) + نوع الحساب
  Future<void> completeProfile({required String name, required String phone, required String role}) async {
    final u = authUser!;
    await chooseRole(role);
    await Backend.instance.signup(
      uid: u.uid,
      role: role,
      name: name,
      phone: phone,
      lang: lang,
      email: u.email ?? '',
      photoUrl: u.photoURL ?? '',
    );
  }

  Future<void> signOut() async {
    await AuthService.instance.signOut();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userSub?.cancel();
    _workerSub?.cancel();
    super.dispose();
  }
}
