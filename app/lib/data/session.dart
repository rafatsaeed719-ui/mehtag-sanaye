import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'services/auth_service.dart';
import 'services/backend.dart';
import '../features/admin/admin_service.dart';

const kAppVersion = '1.4.2';

enum SessionState {
  loading,
  chooseRole, // أول فتح: عميل ولا صنايعي
  signedOut,
  needsProfile, // أول مرة: الاسم والموبايل ونوع الحساب
  blocked,
  customer,
  workerOnboarding, // صنايعي لسه بيسجل / قيد المراجعة / مرفوض
  worker, // صنايعي موثق
  admin, // الإدارة جوه التطبيق
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
  String adminError = '';
  static const ownerEmail = 'rafatsaeed719@gmail.com';

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
    if (chosenRole == 'admin') {
      await _userSub?.cancel();
      await _workerSub?.cancel();
      _userSub = null;
      _workerSub = null;
      await _enterAdmin(u);
      return;
    }
    if (changed || _userSub == null) _listenUser(u.uid);
  }

  bool get isOwnerEmail => (authUser?.email ?? '').toLowerCase() == ownerEmail;

  /// الدخول كإدارة: لازم يكون ليه صلاحية في admins/{uid}
  /// (صاحب التطبيق بياخد صلاحية المدير العام تلقائيًا بعد تأكيد بريده)
  Future<void> _enterAdmin(User u) async {
    _set(SessionState.loading);
    adminError = '';
    final db = FirebaseFirestore.instance;
    try {
      var adm = await db.doc('admins/${u.uid}').get(const GetOptions(source: Source.server));
      if (!adm.exists) {
        if ((u.email ?? '').toLowerCase() == ownerEmail) {
          await u.reload();
          final cur = FirebaseAuth.instance.currentUser!;
          if (!cur.emailVerified) {
            try {
              await cur.sendEmailVerification();
            } catch (_) {}
            adminError = 'لازم تأكد بريدك الأول — بعتنالك رابط تأكيد على الإيميل (بص في Spam كمان)، دوس عليه وبعدين ادخل تاني.';
            await AuthService.instance.signOut();
            return;
          }
          await cur.getIdToken(true);
          await db.doc('admins/${u.uid}').set({
            'email': ownerEmail,
            'role': 'super',
            'active': true,
            'owner': true,
            'createdAt': FieldValue.serverTimestamp(),
          });
          adm = await db.doc('admins/${u.uid}').get(const GetOptions(source: Source.server));
        } else {
          try {
            await db.doc('adminRequests/${u.uid}').set({'email': (u.email ?? '').toLowerCase(), 'createdAt': FieldValue.serverTimestamp()});
          } catch (_) {}
        }
      }
      if (!adm.exists || adm.data()?['active'] != true) {
        adminError = 'الحساب ده مالوش صلاحية إدارة. اتبعت طلب صلاحية للمدير العام.';
        await AuthService.instance.signOut();
        return;
      }
      AdminService.instance.role = (adm.data()?['role'] ?? 'moderator').toString();
      _set(SessionState.admin);
    } catch (e) {
      adminError = 'تعذر الدخول للإدارة — اتأكد من الإنترنت وجرب تاني.';
      await AuthService.instance.signOut();
    }
  }

  /// من داخل حساب عادي (صاحب التطبيق) → وضع الإدارة
  Future<void> switchToAdmin() async {
    final u = authUser;
    if (u == null) return;
    chosenRole = 'admin';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roleKey, 'admin');
    await _userSub?.cancel();
    await _workerSub?.cancel();
    _userSub = null;
    _workerSub = null;
    await _enterAdmin(u);
  }

  /// خروج من الإدارة → شاشة الترحيب
  Future<void> leaveAdmin() async {
    chosenRole = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roleKey);
    await AuthService.instance.signOut();
    _set(SessionState.chooseRole);
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
