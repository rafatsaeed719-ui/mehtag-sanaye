import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'services/api.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';

const kAppVersion = '1.0.0';

enum SessionState {
  loading,
  chooseRole, // أول فتح: عميل ولا صنايعي
  signedOut,
  needsPhone, // دخل بـGoogle ولازم يربط رقم موبايل
  needsProfile, // أول مرة: الاسم ونوع الحساب
  blocked,
  customer,
  workerOnboarding, // صنايعي لسه بيسجل / قيد المراجعة / مرفوض
  worker, // صنايعي موثق
}

/// الحالة العامة للمستخدم — كل شاشات التطبيق بتتحدد منها
class Session extends ChangeNotifier {
  static const _roleKey = 'chosen_role';
  static const _deviceKey = 'device_id';

  SessionState state = SessionState.loading;
  User? authUser;
  AppUser? user;
  Worker? worker;
  String chosenRole = '';
  String deviceId = '';
  String lang = 'ar';

  StreamSubscription<User?>? _authSub;
  StreamSubscription? _userSub;
  StreamSubscription? _workerSub;
  bool _registeredThisSession = false;

  String? get uid => authUser?.uid;
  bool get isWorker => user?.isWorker == true;

  Future<void> start(String currentLang) async {
    lang = currentLang;
    final prefs = await SharedPreferences.getInstance();
    chosenRole = prefs.getString(_roleKey) ?? '';
    deviceId = prefs.getString(_deviceKey) ?? '';
    if (deviceId.isEmpty) {
      final r = Random.secure();
      deviceId = List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
      await prefs.setString(_deviceKey, deviceId);
    }
    _authSub = FirebaseAuth.instance.userChanges().listen(_onAuth);
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
    final changedUser = u?.uid != authUser?.uid;
    authUser = u;
    if (u == null) {
      await _userSub?.cancel();
      await _workerSub?.cancel();
      user = null;
      worker = null;
      _registeredThisSession = false;
      _set(chosenRole.isEmpty ? SessionState.chooseRole : SessionState.signedOut);
      return;
    }
    if (u.phoneNumber == null || u.phoneNumber!.isEmpty) {
      _set(SessionState.needsPhone);
      return;
    }
    if (changedUser || _userSub == null) _listenUser(u.uid);
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
      _afterProfileReady();
      if (user!.isWorker) {
        _listenWorker(uid);
      } else {
        _workerSub?.cancel();
        worker = null;
        _set(SessionState.customer);
      }
    }, onError: (_) {
      // غالبًا offline بدون كاش: نخلي الحالة كما هي
      if (state == SessionState.loading) _set(SessionState.needsProfile);
    });
  }

  void _listenWorker(String uid) {
    _workerSub?.cancel();
    _workerSub = FirebaseFirestore.instance.doc('workers/$uid').snapshots().listen((d) {
      worker = d.exists ? Worker.fromDoc(d) : null;
      final approved = worker != null && worker!.isApproved && !worker!.suspended;
      _set(approved ? SessionState.worker : SessionState.workerOnboarding);
      _syncTopics();
    }, onError: (_) => _set(SessionState.workerOnboarding));
  }

  void _afterProfileReady() {
    if (_registeredThisSession || uid == null) return;
    _registeredThisSession = true;
    PushService.instance.register(uid!);
    Api.instance.recordLogin(deviceId, kAppVersion).catchError((_) {});
    // مزامنة لغة الإشعارات مع لغة التطبيق
    if (user != null && user!.lang != lang) {
      FirebaseFirestore.instance.doc('users/$uid').update({'lang': lang}).catchError((_) {});
    }
    _syncTopics();
  }

  void _syncTopics() {
    if (user == null) return;
    PushService.instance.syncTopics(
      role: user!.role,
      lang: lang,
      categoryIds: worker?.categoryIds ?? const [],
      governorate: worker?.governorate,
    );
  }

  Future<void> onLanguageChanged(String newLang) async {
    lang = newLang;
    if (uid != null && user != null) {
      await FirebaseFirestore.instance.doc('users/$uid').update({'lang': newLang}).catchError((_) {});
      _syncTopics();
    }
  }

  Future<void> completeProfile(String name) async {
    final role = chosenRole.isEmpty ? 'customer' : chosenRole;
    await Api.instance.completeSignup(role: role, name: name, lang: lang);
    // الـlistener هيلاحظ إنشاء الوثيقة تلقائيًا
  }

  Future<void> signOut() async {
    await PushService.instance.unregister();
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
