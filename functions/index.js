'use strict';
/**
 * محتاج صنايعي — Cloud Functions entry point
 * المنطقة: europe-west1 (الأقرب لمصر بين مناطق Firebase المدعومة بالكامل)
 */
const { setGlobalOptions } = require('firebase-functions/v2');
const { REGION } = require('./src/common');

setGlobalOptions({ region: REGION, maxInstances: 20, memory: '256MiB' });

const authFns = require('./src/auth');
const workers = require('./src/workers');
const requests = require('./src/requests');
const reviews = require('./src/reviews');
const support = require('./src/support');
const payments = require('./src/payments');
const adminApi = require('./src/adminApi');
const scheduled = require('./src/scheduled');

// الحساب
exports.completeSignup = authFns.completeSignup;
exports.recordLogin = authFns.recordLogin;
// الصنايعي
exports.submitWorkerApplication = workers.submitWorkerApplication;
exports.requestWorkerChange = workers.requestWorkerChange;
// الطلبات
exports.createRequest = requests.createRequest;
exports.requestAction = requests.requestAction;
// التقييم والبلاغات والدعم والشات
exports.submitReview = reviews.submitReview;
exports.submitReport = support.submitReport;
exports.submitSupportTicket = support.submitSupportTicket;
exports.onChatMessage = support.onChatMessage;
exports.markChatRead = support.markChatRead;
exports.stripIdDocTokens = support.stripIdDocTokens;
// المدفوعات
exports.getPaymentInstructions = payments.getPaymentInstructions;
exports.submitPayment = payments.submitPayment;
// الإدارة
exports.adminReviewWorker = adminApi.adminReviewWorker;
exports.adminReviewChange = adminApi.adminReviewChange;
exports.adminGetWorkerPrivate = adminApi.adminGetWorkerPrivate;
exports.adminSetUserStatus = adminApi.adminSetUserStatus;
exports.adminUpdateUser = adminApi.adminUpdateUser;
exports.adminDeleteUser = adminApi.adminDeleteUser;
exports.adminReviewPayment = adminApi.adminReviewPayment;
exports.adminUpdateSettings = adminApi.adminUpdateSettings;
exports.adminSetReviewHidden = adminApi.adminSetReviewHidden;
exports.adminUpdateReport = adminApi.adminUpdateReport;
exports.adminBroadcast = adminApi.adminBroadcast;
exports.adminSetAdminRole = adminApi.adminSetAdminRole;
exports.claimOwner = adminApi.claimOwner;
// مهام مجدولة
exports.dailyMaintenance = scheduled.dailyMaintenance;
