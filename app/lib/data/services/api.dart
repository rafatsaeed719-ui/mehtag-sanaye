import 'package:cloud_functions/cloud_functions.dart';

/// كل العمليات الحساسة (الحالات، العمولة، التقييم، التسجيل) تمر عبر Cloud Functions
/// لضمان التحقق والحساب على السيرفر.
class Api {
  Api._();
  static final instance = Api._();

  /// نفس منطقة السيرفر في functions/src/common.js
  static const region = 'europe-west1';
  final _fn = FirebaseFunctions.instanceFor(region: region);

  Future<Map<String, dynamic>> call(String name, [Map<String, dynamic>? data]) async {
    final res = await _fn.httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 30))).call(data ?? {});
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<Map<String, dynamic>> completeSignup({required String role, required String name, required String lang}) =>
      call('completeSignup', {'role': role, 'name': name, 'lang': lang});

  Future<void> recordLogin(String deviceId, String appVersion) =>
      call('recordLogin', {'deviceId': deviceId, 'platform': 'android', 'appVersion': appVersion});

  Future<Map<String, dynamic>> submitWorkerApplication(Map<String, dynamic> data) => call('submitWorkerApplication', data);
  Future<Map<String, dynamic>> requestWorkerChange(Map<String, dynamic> data) => call('requestWorkerChange', data);

  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> data) => call('createRequest', data);

  Future<Map<String, dynamic>> requestAction(String requestId, String action, [Map<String, dynamic>? payload]) =>
      call('requestAction', {'requestId': requestId, 'action': action, 'payload': payload ?? {}});

  Future<void> submitReview(String requestId, int stars, String comment) =>
      call('submitReview', {'requestId': requestId, 'stars': stars, 'comment': comment});

  Future<void> submitReport(Map<String, dynamic> data) => call('submitReport', data);
  Future<void> submitSupportTicket(Map<String, dynamic> data) => call('submitSupportTicket', data);
  Future<void> markChatRead(String requestId) => call('markChatRead', {'requestId': requestId});

  Future<Map<String, dynamic>> getPaymentInstructions() => call('getPaymentInstructions');
  Future<Map<String, dynamic>> submitPayment(Map<String, dynamic> data) => call('submitPayment', data);
}
