import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/utils/format.dart';

/// تسجيل الدخول: رقم الهاتف + OTP، أو Google ثم ربط رقم الهاتف.
/// Firebase Auth يمنع ربط نفس الرقم بحسابين → رقم هاتف واحد لكل حساب.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;
  final _google = GoogleSignIn(scopes: ['email']);

  User? get currentUser => _auth.currentUser;

  Future<void> sendCode({
    required String phone,
    int? resendToken,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(PhoneAuthCredential credential) onAutoVerified,
    required void Function(FirebaseAuthException e) onError,
  }) {
    return _auth.verifyPhoneNumber(
      phoneNumber: Fmt.toE164(phone),
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: onAutoVerified,
      verificationFailed: onError,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  /// لو المستخدم داخل بـGoogle من غير رقم → نربط الرقم بحسابه. غير كده → تسجيل دخول بالرقم.
  Future<void> signInOrLinkWithCredential(PhoneAuthCredential credential) async {
    final u = _auth.currentUser;
    if (u != null && (u.phoneNumber == null || u.phoneNumber!.isEmpty)) {
      await u.linkWithCredential(credential);
      await u.reload();
    } else {
      await _auth.signInWithCredential(credential);
    }
  }

  Future<void> verifyCode(String verificationId, String code) {
    final cred = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code.trim());
    return signInOrLinkWithCredential(cred);
  }

  /// يعيد false لو المستخدم لغى اختيار الحساب
  Future<bool> signInWithGoogle() async {
    final account = await _google.signIn();
    if (account == null) return false;
    final gAuth = await account.authentication;
    final cred = GoogleAuthProvider.credential(idToken: gAuth.idToken, accessToken: gAuth.accessToken);
    await _auth.signInWithCredential(cred);
    return true;
  }

  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {}
    await _auth.signOut();
  }
}
