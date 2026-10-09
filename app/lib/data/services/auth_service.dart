import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// الدخول بالبريد وكلمة السر أو بحساب Google (بدون SMS — مجاني بالكامل)
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;
  GoogleSignIn? _g;
  GoogleSignIn get _google => _g ??= GoogleSignIn(scopes: ['email']);

  User? get currentUser => _auth.currentUser;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> register(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    try {
      await cred.user?.sendEmailVerification();
    } catch (_) {}
  }

  Future<void> resetPassword(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  /// يعيد false لو المستخدم لغى اختيار الحساب
  Future<bool> signInWithGoogle() async {
    if (kIsWeb) {
      // على المتصفح: نافذة Google مباشرة من Firebase
      try {
        await _auth.signInWithPopup(GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'}));
        return true;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'popup-closed-by-user' || e.code == 'cancelled-popup-request') return false;
        rethrow;
      }
    }
    final account = await _google.signIn();
    if (account == null) return false;
    final gAuth = await account.authentication;
    final cred = GoogleAuthProvider.credential(idToken: gAuth.idToken, accessToken: gAuth.accessToken);
    await _auth.signInWithCredential(cred);
    return true;
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await _google.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
  }
}
