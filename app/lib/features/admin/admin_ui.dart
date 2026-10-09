import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/widgets/common.dart';

/// أدوات واجهة مشتركة لشاشات الإدارة
String locName(dynamic v) {
  if (v is Map) return (v['ar'] ?? v['en'] ?? '').toString();
  return (v ?? '').toString();
}

String money(dynamic v) => '${NumberFormat('#,##0.##', 'en').format((v as num?) ?? 0)} ج';

DateTime? tsDate(dynamic t) => t is Timestamp ? t.toDate() : null;

String fmtTs(dynamic t) {
  final d = tsDate(t);
  if (d == null) return '—';
  return DateFormat('d MMM yyyy • h:mm a', 'ar').format(d.toLocal());
}

const kReqStatus = {
  'new': 'طلب جديد',
  'accepted': 'تم القبول',
  'rejected': 'مرفوض',
  'proposed': 'موعد مقترح',
  'confirmed': 'تم تأكيد الموعد',
  'on_the_way': 'في الطريق',
  'started': 'بدأ العمل',
  'completed': 'تم الانتهاء',
  'price_set': 'بانتظار تأكيد السعر',
  'price_agreed': 'تم الاتفاق على السعر',
  'commission_paid': 'تم دفع العمولة',
  'cancelled': 'ملغي',
};
const kReportTypes = {
  'no_show': 'لم يحضر',
  'bad_behavior': 'سوء معاملة',
  'poor_quality': 'جودة سيئة',
  'overcharge': 'مبالغة في السعر',
  'fraud': 'احتيال',
  'harassment': 'تحرش/تهديد',
  'fake_account': 'حساب وهمي',
  'payment_issue': 'مشكلة دفع',
  'other': 'أخرى',
};
const kReportStatus = {'new': 'جديد', 'reviewing': 'قيد المراجعة', 'action_taken': 'تم اتخاذ إجراء', 'closed': 'مغلق'};
const kUserStatus = {'active': 'نشط', 'suspended': 'موقوف', 'banned': 'محظور', 'deleted': 'محذوف'};
const kWorkerStatus = {'pending': 'قيد المراجعة', 'approved': 'موثّق', 'rejected': 'مرفوض', 'deleted': 'محذوف'};
const kComStatus = {'due': 'مستحقة', 'claimed': 'قيد المراجعة', 'paid': 'مدفوعة', 'none': '—'};
const kPayStatus = {'pending_review': 'قيد المراجعة', 'confirmed': 'مؤكد', 'rejected': 'مرفوض'};

Color toneOf(String s) {
  switch (s) {
    case 'approved':
    case 'active':
    case 'paid':
    case 'confirmed':
    case 'price_agreed':
    case 'commission_paid':
    case 'action_taken':
      return AppColors.success;
    case 'pending':
    case 'pending_review':
    case 'due':
    case 'new':
    case 'proposed':
    case 'suspended':
      return AppColors.warning;
    case 'rejected':
    case 'banned':
    case 'cancelled':
    case 'deleted':
      return AppColors.emergency;
  }
  return AppColors.navy;
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, {super.key, this.color = AppColors.navy});
  factory Pill.status(String status, Map<String, String> labels, {Key? key}) =>
      Pill(labels[status] ?? status, key: key, color: toneOf(status));
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}

class KV extends StatelessWidget {
  final String label;
  final String value;
  final bool ltr;
  final Widget? trailing;
  const KV(this.label, this.value, {super.key, this.ltr = false, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13.5))),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '—' : value,
              textDirection: ltr ? TextDirection.ltr : null,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class AdminCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  const AdminCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14)});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}

/// تنفيذ عملية مع رسالة نجاح/خطأ
Future<bool> runAdmin(BuildContext context, Future<void> Function() fn, {String ok = 'تم ✅'}) async {
  try {
    await fn();
    if (context.mounted && ok.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok), backgroundColor: AppColors.success));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      var m = e.toString().replaceFirst('Exception: ', '');
      if (m.contains('permission-denied')) m = 'ليس لديك صلاحية لهذه العملية';
      if (m.contains('unavailable') || m.contains('network')) m = 'مفيش اتصال بالإنترنت';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: AppColors.emergency));
    }
    return false;
  }
}

/// نافذة إدخال نص
Future<String?> askText(BuildContext context, String title, {String initial = '', String hint = '', bool required = true, int lines = 1}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: TextField(controller: c, autofocus: true, minLines: lines, maxLines: lines + 2, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (required && c.text.trim().isEmpty) return;
            Navigator.pop(d, c.text.trim());
          },
          child: const Text('تم'),
        ),
      ],
    ),
  );
}

Future<bool> askConfirm(BuildContext context, String message, {bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('لا')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.emergency) : null,
          onPressed: () => Navigator.pop(d, true),
          child: const Text('أيوه'),
        ),
      ],
    ),
  );
  return r == true;
}

/// قائمة من استعلام Firestore (بتتحدث لحظيًا)
class QueryList extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  final Widget Function(BuildContext, QueryDocumentSnapshot<Map<String, dynamic>>) itemBuilder;
  final String empty;
  final EdgeInsets padding;
  final Widget? header;
  const QueryList({super.key, required this.query, required this.itemBuilder, this.empty = 'لا يوجد', this.padding = const EdgeInsets.all(14), this.header});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, s) {
          if (s.hasError) {
            return ListView(padding: padding, children: [if (header != null) header!, ErrorView(message: 'حصلت مشكلة في التحميل\n${s.error}')]);
          }
          if (!s.hasData) return const LoadingView();
          final docs = s.data!.docs;
          return ListView(
            padding: padding,
            children: [
              if (header != null) header!,
              if (docs.isEmpty) EmptyView(text: empty),
              for (final d in docs) itemBuilder(context, d),
            ],
          );
        },
      );
}

/// صورة قابلة للتكبير
class AdminThumb extends StatelessWidget {
  final String src;
  final double size;
  const AdminThumb(this.src, {super.key, this.size = 90});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => openImageViewer(context, src),
        child: NetImage(url: src, width: size, height: size),
      );
}

void openMap(dynamic lat, dynamic lng) {
  if (lat == null || lng == null) return;
  launchUrl(Uri.parse('https://www.google.com/maps?q=$lat,$lng'), mode: LaunchMode.externalApplication);
}

void callPhone(String phone) {
  if (phone.isEmpty) return;
  launchUrl(Uri.parse('tel:$phone'));
}

void openWhatsapp(String phone) {
  if (phone.isEmpty) return;
  final p = phone.startsWith('0') ? '2$phone' : phone.replaceAll('+', '');
  launchUrl(Uri.parse('https://wa.me/$p'), mode: LaunchMode.externalApplication);
}

/// شاشات الإدارة بالعربي ومن اليمين للشمال دايمًا
Widget rtl(Widget child) => Directionality(textDirection: TextDirection.rtl, child: child);
