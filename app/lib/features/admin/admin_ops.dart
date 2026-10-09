import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'admin_people.dart';
import 'admin_service.dart';
import 'admin_ui.dart';

// =============================================================== الطلبات
class RequestsAdminScreen extends StatefulWidget {
  const RequestsAdminScreen({super.key});
  @override
  State<RequestsAdminScreen> createState() => _RequestsAdminScreenState();
}

class _RequestsAdminScreenState extends State<RequestsAdminScreen> {
  final a = AdminService.instance;
  String _status = '';
  bool _emergency = false;
  String _code = '';

  @override
  Widget build(BuildContext context) {
    final c = a.col('requests');
    final Query<Map<String, dynamic>> q;
    if (_code.isNotEmpty) {
      q = c.where('code', isEqualTo: _code);
    } else if (_status.isNotEmpty) {
      q = c.where('status', isEqualTo: _status).orderBy('createdAt', descending: true).limit(200);
    } else if (_emergency) {
      q = c.where('isEmergency', isEqualTo: true).orderBy('createdAt', descending: true).limit(200);
    } else {
      q = c.orderBy('createdAt', descending: true).limit(200);
    }
    return rtl(Scaffold(
      appBar: AppBar(title: const Text('الطلبات')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                textDirection: TextDirection.ltr,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'رقم الطلب', prefixIcon: Icon(Icons.search)),
                onSubmitted: (v) => setState(() => _code = v.trim().toUpperCase()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الحالة'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('كل الحالات')),
                  for (final e in kReqStatus.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() {
                  _status = v ?? '';
                  _code = '';
                }),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: CheckboxListTile(
            dense: true,
            value: _emergency,
            onChanged: (v) => setState(() => _emergency = v == true),
            title: const Text('🚨 طلبات الطوارئ بس'),
          ),
        ),
        Expanded(
          child: QueryList(
            key: ValueKey('$_status|$_emergency|$_code'),
            query: q,
            empty: 'مفيش طلبات',
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            itemBuilder: (context, d) {
              final r = d.data();
              return AdminCard(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestAdminDetails(requestId: d.id))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('#${r['code'] ?? ''}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w900)),
                    if (r['isEmergency'] == true) const Text(' 🚨'),
                    const Spacer(),
                    Pill.status((r['status'] ?? '').toString(), kReqStatus),
                  ]),
                  const SizedBox(height: 4),
                  Text(locName(r['serviceName'] ?? r['categoryName']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('العميل: ${r['customerName'] ?? ''} • الصنايعي: ${r['workerName'] ?? '—'}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  Row(children: [
                    Text(fmtTs(r['createdAt']), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    const Spacer(),
                    if (r['agreedPrice'] != null) Text(money(r['agreedPrice']), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ]),
              );
            },
          ),
        ),
      ]),
    ));
  }
}

class RequestAdminDetails extends StatelessWidget {
  final String requestId;
  const RequestAdminDetails({super.key, required this.requestId});

  @override
  Widget build(BuildContext context) {
    final a = AdminService.instance;
    const by = {'customer': 'العميل', 'worker': 'الصنايعي', 'admin': 'الإدارة'};
    return rtl(Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الطلب')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: a.ref('requests/$requestId').snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final r = snap.data!.data();
          if (r == null) return const EmptyView(text: 'الطلب مش موجود');
          final loc = (r['location'] as Map?) ?? {};
          final images = List<String>.from(r['images'] ?? []);
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Text('#${r['code'] ?? ''}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              if (r['isEmergency'] == true) const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Pill('طوارئ', color: AppColors.emergency)),
              const Spacer(),
              Pill.status((r['status'] ?? '').toString(), kReqStatus),
            ]),
            const SizedBox(height: 12),
            AdminCard(
              child: Column(children: [
                KV('الخدمة', locName(r['serviceName'] ?? r['categoryName'])),
                KV('العميل', (r['customerName'] ?? '').toString(),
                    trailing: TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserManageScreen(userId: r['customerId']))),
                      child: const Text('الحساب'),
                    )),
                KV('الصنايعي', (r['workerName'] ?? '').toString(),
                    trailing: r['workerId'] == null
                        ? null
                        : TextButton(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerReviewScreen(workerId: r['workerId']))),
                            child: const Text('الحساب'),
                          )),
                KV('الوصف', (r['description'] ?? '').toString()),
                KV('العنوان', (loc['address'] ?? '').toString(),
                    trailing: IconButton(icon: const Icon(Icons.map_outlined, color: AppColors.navy), onPressed: () => openMap(loc['lat'], loc['lng']))),
                KV('الموعد', fmtTs(r['scheduledAt'])),
                KV('تاريخ الطلب', fmtTs(r['createdAt'])),
                KV('قيمة الخدمة', r['agreedPrice'] == null ? '' : money(r['agreedPrice'])),
                KV(
                  'العمولة',
                  r['commissionAmount'] == null
                      ? ''
                      : '${money(r['commissionAmount'])} (${(((r['commissionRate'] as num?) ?? 0) * 100).toStringAsFixed(1)}%) — ${kComStatus[r['commissionStatus']] ?? ''}',
                ),
                if (r['cancelReason'] != null) KV('الإلغاء', '${r['cancelReason']} — ${r['cancelNote'] ?? ''} (${by[r['cancelledBy']] ?? ''})'),
                KV('صنايعية اتبعتلهم', '${List.from(r['notifiedWorkerIds'] ?? []).length}'),
              ]),
            ),
            if (images.isNotEmpty) ...[
              const Text('صور المشكلة', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final i in images) AdminThumb(i)]),
              const SizedBox(height: 12),
            ],
            const Text('سجل الحالات', style: TextStyle(fontWeight: FontWeight.w800)),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: a.col('requests/$requestId/history').orderBy('at').snapshots(),
              builder: (context, h) => Column(children: [
                for (final d in h.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.circle, size: 12, color: toneOf((d.data()['to'] ?? '').toString())),
                    title: Text('${kReqStatus[d.data()['to']] ?? d.data()['to']} — بواسطة ${by[d.data()['by']] ?? d.data()['by'] ?? ''}'),
                    subtitle: Text('${fmtTs(d.data()['at'])}${(d.data()['note'] ?? '').toString().isNotEmpty ? ' — ${d.data()['note']}' : ''}'),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            const Text('آخر رسائل الشات', style: TextStyle(fontWeight: FontWeight.w800)),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: a.col('requests/$requestId/messages').orderBy('createdAt', descending: true).limit(50).snapshots(),
              builder: (context, m) {
                final docs = m.data?.docs ?? [];
                if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('لا يوجد', style: TextStyle(color: AppColors.muted)));
                return Column(children: [
                  for (final d in docs.reversed)
                    Builder(builder: (context) {
                      final x = d.data();
                      final fromCustomer = x['senderId'] == r['customerId'];
                      final body = x['type'] == 'text' ? (x['text'] ?? '').toString() : x['type'] == 'image' ? '📷 صورة' : '📍 موقع';
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(fromCustomer ? Icons.person : Icons.engineering, color: fromCustomer ? AppColors.navy : AppColors.amber),
                        title: Text(body),
                        subtitle: Text(fmtTs(x['createdAt'])),
                        onTap: x['type'] == 'image' && (x['imageRef'] ?? x['imageUrl']) != null ? () => openImageViewer(context, (x['imageRef'] ?? x['imageUrl']).toString()) : null,
                      );
                    }),
                ]);
              },
            ),
          ]);
        },
      ),
    ));
  }
}

// =============================================================== المالية
class FinanceAdminScreen extends StatefulWidget {
  const FinanceAdminScreen({super.key});
  @override
  State<FinanceAdminScreen> createState() => _FinanceAdminScreenState();
}

class _FinanceAdminScreenState extends State<FinanceAdminScreen> {
  final a = AdminService.instance;
  String _comStatus = 'due';
  late Future<List<double>> _kpis = _loadKpis();

  Future<List<double>> _loadKpis() async {
    final c = a.col('commissions');
    final set = (await a.ref('settings/public').get()).data() ?? {};
    final overdueDays = (set['overdueDays'] as num?)?.toInt() ?? 7;
    final r = await Future.wait([
      a.sumOf(c, 'amount'),
      a.sumOf(c.where('status', isEqualTo: 'paid'), 'amount'),
      a.sumOf(c.where('status', whereIn: ['due', 'claimed']), 'amount'),
    ]);
    double overdue = 0;
    try {
      final od = await c
          .where('status', isEqualTo: 'due')
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(DateTime.now().subtract(Duration(days: overdueDays))))
          .orderBy('createdAt', descending: true)
          .get();
      for (final d in od.docs) {
        overdue += (d.data()['amount'] as num? ?? 0).toDouble();
      }
    } catch (_) {}
    return [...r, overdue];
  }

  @override
  Widget build(BuildContext context) {
    return rtl(DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('العمولات والمدفوعات'),
          bottom: const TabBar(tabs: [Tab(text: 'تحويلات بانتظار التأكيد'), Tab(text: 'العمولات')]),
        ),
        body: TabBarView(children: [
          QueryList(
            query: a.col('payments').where('status', isEqualTo: 'pending_review').orderBy('createdAt', descending: true).limit(100),
            empty: 'مفيش تحويلات مستنية تأكيد',
            header: Column(children: [
              FutureBuilder<List<double>>(
                future: _kpis,
                builder: (context, s) {
                  final k = s.data;
                  Widget box(String l, double? v, Color c) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                          child: Column(children: [
                            FittedBox(child: Text(v == null ? '...' : money(v), style: TextStyle(fontWeight: FontWeight.w900, color: c, fontSize: 16))),
                            Text(l, style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                      );
                  return Column(children: [
                    Row(children: [box('الإجمالي', k?[0], AppColors.navy), box('المدفوع', k?[1], AppColors.success)]),
                    Row(children: [box('المستحق', k?[2], AppColors.warning), box('المتأخر', k?[3], AppColors.emergency)]),
                  ]);
                },
              ),
              const SizedBox(height: 8),
              const InfoBox('⚠️ مفيش تحقق تلقائي من InstaPay — طابق رقم العملية والمبلغ مع حسابك قبل ما تأكد.', color: AppColors.warning),
              const SizedBox(height: 10),
            ]),
            itemBuilder: (context, d) => _PaymentTile(id: d.id, p: d.data(), onDone: () => setState(() => _kpis = _loadKpis())),
          ),
          Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'due', label: Text('مستحقة')),
                  ButtonSegment(value: 'claimed', label: Text('قيد المراجعة')),
                  ButtonSegment(value: 'paid', label: Text('مدفوعة')),
                ],
                selected: {_comStatus},
                onSelectionChanged: (v) => setState(() => _comStatus = v.first),
              ),
            ),
            Expanded(
              child: QueryList(
                key: ValueKey(_comStatus),
                query: a.col('commissions').where('status', isEqualTo: _comStatus).orderBy('createdAt', descending: true).limit(200),
                empty: 'لا يوجد',
                itemBuilder: (context, d) {
                  final c = d.data();
                  return AdminCard(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestAdminDetails(requestId: d.id))),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text((c['workerName'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('طلب #${c['requestCode'] ?? ''} • خدمة ${money(c['servicePrice'])} • ${(((c['rate'] as num?) ?? 0) * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                          Text(fmtTs(c['createdAt']), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ]),
                      ),
                      Text(money(c['amount']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.navy)),
                    ]),
                  );
                },
              ),
            ),
          ]),
        ]),
      ),
    ));
  }
}

class _PaymentTile extends StatefulWidget {
  final String id;
  final Map<String, dynamic> p;
  final VoidCallback onDone;
  const _PaymentTile({required this.id, required this.p, required this.onDone});
  @override
  State<_PaymentTile> createState() => _PaymentTileState();
}

class _PaymentTileState extends State<_PaymentTile> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final receipt = (p['receiptRef'] ?? '').toString();
    return AdminCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text((p['workerName'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
          Text(money(p['amount']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.success)),
        ]),
        KV('موبايل الصنايعي', (p['workerPhone'] ?? '').toString(), ltr: true),
        KV('رقم العملية', (p['reference'] ?? '').toString(), ltr: true),
        KV('حساب المحوّل', (p['senderAccount'] ?? '').toString(), ltr: true),
        KV('عدد العمولات', '${List.from(p['commissionIds'] ?? []).length}'),
        KV('التاريخ', fmtTs(p['createdAt'])),
        if (receipt.isNotEmpty) Align(alignment: AlignmentDirectional.centerStart, child: AdminThumb(receipt, size: 110)),
        const SizedBox(height: 10),
        if (_busy)
          const Center(child: CircularProgressIndicator())
        else
          Row(children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                onPressed: () async {
                  if (!await askConfirm(context, 'تأكيد إنك استلمت التحويل بعد ما طابقته؟') || !mounted) return;
                  setState(() => _busy = true);
                  await runAdmin(context, () => AdminService.instance.reviewPayment(widget.id, 'confirm'));
                  if (mounted) setState(() => _busy = false);
                  widget.onDone();
                },
                child: const Text('تأكيد الاستلام'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.emergency),
                onPressed: () async {
                  final note = await askText(context, 'سبب الرفض');
                  if (note == null || !mounted) return;
                  setState(() => _busy = true);
                  await runAdmin(context, () => AdminService.instance.reviewPayment(widget.id, 'reject', note: note));
                  if (mounted) setState(() => _busy = false);
                  widget.onDone();
                },
                child: const Text('رفض'),
              ),
            ),
          ]),
      ]),
    );
  }
}

// =============================================================== البلاغات
class ReportsAdminScreen extends StatefulWidget {
  const ReportsAdminScreen({super.key});
  @override
  State<ReportsAdminScreen> createState() => _ReportsAdminScreenState();
}

class _ReportsAdminScreenState extends State<ReportsAdminScreen> {
  String _status = 'new';
  @override
  Widget build(BuildContext context) {
    final a = AdminService.instance;
    return rtl(Scaffold(
      appBar: AppBar(title: const Text('الشكاوى والبلاغات')),
      body: Column(children: [
        SizedBox(
          height: 54,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(14, 10, 14, 0), children: [
            for (final e in kReportStatus.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(label: Text(e.value), selected: _status == e.key, onSelected: (_) => setState(() => _status = e.key)),
              ),
          ]),
        ),
        Expanded(
          child: QueryList(
            key: ValueKey(_status),
            query: a.col('reports').where('status', isEqualTo: _status).orderBy('createdAt', descending: true).limit(200),
            empty: 'مفيش بلاغات',
            itemBuilder: (context, d) {
              final p = d.data();
              return AdminCard(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportAdminDetails(reportId: d.id))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.flag, color: AppColors.emergency, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(kReportTypes[p['type']] ?? (p['type'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800))),
                    Text(fmtTs(p['createdAt']), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ]),
                  const SizedBox(height: 4),
                  Text('من: ${p['reporterName'] ?? ''} (${p['reporterRole'] == 'worker' ? 'صنايعي' : 'عميل'})${p['requestCode'] != null ? ' • طلب #${p['requestCode']}' : ''}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  Text((p['description'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              );
            },
          ),
        ),
      ]),
    ));
  }
}

class ReportAdminDetails extends StatefulWidget {
  final String reportId;
  const ReportAdminDetails({super.key, required this.reportId});
  @override
  State<ReportAdminDetails> createState() => _ReportAdminDetailsState();
}

class _ReportAdminDetailsState extends State<ReportAdminDetails> {
  final a = AdminService.instance;
  final _cat = TextEditingController();
  final _act = TextEditingController();
  final _note = TextEditingController();
  String _status = 'new';
  bool _init = false;
  bool _busy = false;

  @override
  void dispose() {
    _cat.dispose();
    _act.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rtl(Scaffold(
      appBar: AppBar(title: const Text('معالجة بلاغ')),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: a.ref('reports/${widget.reportId}').get(),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final p = snap.data!.data() ?? {};
          if (!_init) {
            _init = true;
            _status = (p['status'] ?? 'new').toString();
            _cat.text = (p['category'] ?? '').toString();
            _act.text = (p['actionTaken'] ?? '').toString();
            _note.text = (p['adminNote'] ?? '').toString();
          }
          final images = List<String>.from(p['images'] ?? []);
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: Text(kReportTypes[p['type']] ?? (p['type'] ?? '').toString(), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
              Pill.status((p['status'] ?? '').toString(), kReportStatus),
            ]),
            const SizedBox(height: 10),
            AdminCard(
              child: Column(children: [
                KV('المُبلِّغ', (p['reporterName'] ?? '').toString(),
                    trailing: TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserManageScreen(userId: p['reporterId']))),
                      child: const Text('الحساب'),
                    )),
                if ((p['againstId'] ?? '').toString().isNotEmpty)
                  KV('ضد', (p['againstName'] ?? p['againstId']).toString(),
                      trailing: TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserManageScreen(userId: p['againstId']))),
                        child: const Text('إدارة حسابه'),
                      )),
                if (p['requestId'] != null)
                  KV('الطلب', '#${p['requestCode'] ?? ''}',
                      trailing: TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestAdminDetails(requestId: p['requestId']))),
                        child: const Text('عرض'),
                      )),
                KV('التاريخ', fmtTs(p['createdAt'])),
                KV('الوصف', (p['description'] ?? '').toString()),
              ]),
            ),
            if (images.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: [for (final i in images) AdminThumb(i)]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: kReportStatus.containsKey(_status) ? _status : 'new',
              decoration: const InputDecoration(labelText: 'الحالة'),
              items: [for (final e in kReportStatus.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: 10),
            TextField(controller: _cat, decoration: const InputDecoration(labelText: 'التصنيف (مثال: سلوك / جودة / مالي)')),
            const SizedBox(height: 10),
            TextField(controller: _act, decoration: const InputDecoration(labelText: 'الإجراء المتخذ (إنذار / إيقاف / حظر / لا شيء)')),
            const SizedBox(height: 10),
            TextField(controller: _note, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'ملاحظة داخلية')),
            const SizedBox(height: 16),
            BusyButton(
              label: 'حفظ',
              busy: _busy,
              onPressed: () async {
                setState(() => _busy = true);
                final ok = await runAdmin(
                  context,
                  () => a.updateReport(widget.reportId, status: _status, adminNote: _note.text, actionTaken: _act.text, category: _cat.text.trim()),
                );
                if (mounted) setState(() => _busy = false);
                if (ok && context.mounted) Navigator.pop(context);
              },
            ),
          ]);
        },
      ),
    ));
  }
}

// =============================================================== التقييمات
class ReviewsAdminScreen extends StatefulWidget {
  const ReviewsAdminScreen({super.key});
  @override
  State<ReviewsAdminScreen> createState() => _ReviewsAdminScreenState();
}

class _ReviewsAdminScreenState extends State<ReviewsAdminScreen> {
  String _dir = 'c2w';
  @override
  Widget build(BuildContext context) {
    final a = AdminService.instance;
    return rtl(Scaffold(
      appBar: AppBar(title: const Text('التقييمات')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'c2w', label: Text('تقييمات الصنايعية')), ButtonSegment(value: 'w2c', label: Text('تقييمات العملاء'))],
            selected: {_dir},
            onSelectionChanged: (v) => setState(() => _dir = v.first),
          ),
        ),
        Expanded(
          child: QueryList(
            key: ValueKey(_dir),
            query: a.col('reviews').where('direction', isEqualTo: _dir).orderBy('createdAt', descending: true).limit(200),
            empty: 'مفيش تقييمات',
            itemBuilder: (context, d) {
              final r = d.data();
              final hidden = r['hidden'] == true;
              return AdminCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('★' * ((r['stars'] as num?)?.toInt() ?? 0), style: const TextStyle(color: AppColors.amber, fontSize: 16)),
                    const Spacer(),
                    Pill(hidden ? 'مخفي' : 'ظاهر', color: hidden ? AppColors.emergency : AppColors.success),
                  ]),
                  Text('من: ${r['fromName'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  if ((r['comment'] ?? '').toString().isNotEmpty) Text((r['comment']).toString()),
                  Row(children: [
                    Text(fmtTs(r['createdAt']), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => runAdmin(context, () => a.setReviewHidden(d.id, !hidden)),
                      child: Text(hidden ? 'إظهار' : 'إخفاء (مخالف)'),
                    ),
                  ]),
                ]),
              );
            },
          ),
        ),
      ]),
    ));
  }
}

// =============================================================== الدعم
class SupportAdminScreen extends StatefulWidget {
  const SupportAdminScreen({super.key});
  @override
  State<SupportAdminScreen> createState() => _SupportAdminScreenState();
}

class _SupportAdminScreenState extends State<SupportAdminScreen> {
  String _st = 'open';
  static const kinds = {'support': 'دعم', 'technical': 'مشكلة تقنية', 'complaint': 'شكوى', 'suggestion': 'اقتراح'};
  @override
  Widget build(BuildContext context) {
    final a = AdminService.instance;
    return rtl(Scaffold(
      appBar: AppBar(title: const Text('الدعم')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'open', label: Text('مفتوحة')), ButtonSegment(value: 'closed', label: Text('مغلقة'))],
            selected: {_st},
            onSelectionChanged: (v) => setState(() => _st = v.first),
          ),
        ),
        Expanded(
          child: QueryList(
            key: ValueKey(_st),
            query: a.col('supportTickets').where('status', isEqualTo: _st).orderBy('createdAt', descending: true).limit(200),
            empty: 'مفيش رسائل',
            itemBuilder: (context, d) {
              final t = d.data();
              final phone = (t['phone'] ?? '').toString();
              return AdminCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Pill(kinds[t['kind']] ?? (t['kind'] ?? '').toString()),
                    const SizedBox(width: 8),
                    Expanded(child: Text((t['subject'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800))),
                  ]),
                  const SizedBox(height: 6),
                  Text((t['message'] ?? '').toString()),
                  if ((t['reply'] ?? '').toString().isNotEmpty) Text('الرد: ${t['reply']}', style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 6),
                  Text('${t['name'] ?? ''} • ${fmtTs(t['createdAt'])}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  Row(children: [
                    IconButton(icon: const Icon(Icons.call, color: AppColors.navy), onPressed: () => callPhone(phone)),
                    IconButton(icon: const Icon(Icons.chat, color: AppColors.success), onPressed: () => openWhatsapp(phone)),
                    const Spacer(),
                    if (t['status'] == 'open')
                      FilledButton(
                        onPressed: () async {
                          final reply = await askText(context, 'ملاحظة الرد (داخلية — كلم المستخدم تليفون أو واتساب)', required: false, lines: 2);
                          if (reply == null || !context.mounted) return;
                          await runAdmin(context, () => a.closeTicket(d.id, reply));
                        },
                        child: const Text('رد وإغلاق'),
                      ),
                  ]),
                ]),
              );
            },
          ),
        ),
      ]),
    ));
  }
}
