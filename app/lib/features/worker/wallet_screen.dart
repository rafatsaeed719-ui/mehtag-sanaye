import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/services/api.dart';
import '../../data/services/storage_service.dart';
import '../../data/session.dart';
import '../shared/request_details_screen.dart';

/// الحساب المالي للصنايعي: الإجماليات + العمولات + المدفوعات + دفع العمولة عبر InstaPay
class WalletScreen extends StatelessWidget {
  final bool asTab;
  const WalletScreen({super.key, this.asTab = false});

  @override
  Widget build(BuildContext context) {
    final uid = context.read<Session>().uid!;
    final db = FirebaseFirestore.instance;
    final lang = context.lang;
    final egp = context.t('egp');
    final rate = context.watch<CatalogRepo>().commissionPercent;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: Text(context.t('wallet')), automaticallyImplyLeading: !asTab),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: db.doc('wallets/$uid').snapshots(),
                builder: (context, snap) {
                  final w = snap.data != null && snap.data!.exists ? Wallet.fromDoc(snap.data!) : Wallet();
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.navy, AppColors.navyDark]),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(context.t('stats_due'), style: const TextStyle(color: Colors.white70)),
                          Text('${Fmt.money(w.due, lang)} $egp', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                          if (w.overdue > 0)
                            Text('${context.t('stats_overdue')}: ${Fmt.money(w.overdue, lang)} $egp',
                                style: const TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.w700)),
                          const SizedBox(height: 14),
                          Row(children: [
                            _mini(context.t('stats_services_total'), '${Fmt.money(w.totalServices, lang)} $egp'),
                            _mini(context.t('stats_commission_total'), '${Fmt.money(w.totalCommission, lang)} $egp'),
                            _mini(context.t('stats_paid'), '${Fmt.money(w.paid, lang)} $egp'),
                          ]),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      InfoBox(context.t('wallet_note', {'rate': rate})),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.amber, foregroundColor: AppColors.navyDark),
                        onPressed: w.due <= 0
                            ? null
                            : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PayCommissionScreen())),
                        icon: const Icon(Icons.send_to_mobile_outlined),
                        label: Text(context.t('pay_commission')),
                      ),
                    ]),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(child: TabBar(tabs: [Tab(text: context.t('commissions')), Tab(text: context.t('payments'))])),
          ],
          body: TabBarView(children: [
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db.collection('commissions').where('workerId', isEqualTo: uid).orderBy('createdAt', descending: true).limit(100).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return ErrorView(message: friendlyError(context, snap.error!));
                if (!snap.hasData) return const LoadingView();
                final list = snap.data!.docs.map(Commission.fromDoc).toList();
                if (list.isEmpty) return EmptyView(text: context.t('no_commissions'), icon: Icons.receipt_outlined);
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = list[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestDetailsScreen(requestId: c.requestId))),
                      title: Text('#${c.requestCode} • ${Fmt.money(c.servicePrice, lang)} $egp'),
                      subtitle: Text(Fmt.date(c.createdAt, lang)),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${Fmt.money(c.amount, lang)} $egp', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(context.t('commission_status_${c.status}'), style: TextStyle(fontSize: 12, color: _statusColor(c.status))),
                      ]),
                    );
                  },
                );
              },
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db.collection('payments').where('workerId', isEqualTo: uid).orderBy('createdAt', descending: true).limit(100).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return ErrorView(message: friendlyError(context, snap.error!));
                if (!snap.hasData) return const LoadingView();
                final list = snap.data!.docs.map(Payment.fromDoc).toList();
                if (list.isEmpty) return EmptyView(text: context.t('no_payments'), icon: Icons.payments_outlined);
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = list[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.send_to_mobile_outlined),
                      title: Text('${Fmt.money(p.amount, lang)} $egp • InstaPay'),
                      subtitle: Text('${p.reference} • ${Fmt.date(p.createdAt, lang)}${p.reviewNote.isNotEmpty ? '\n${p.reviewNote}' : ''}'),
                      trailing: Text(context.t('payment_status_${p.status}'),
                          style: TextStyle(fontWeight: FontWeight.w700, color: _statusColor(p.status))),
                    );
                  },
                );
              },
            ),
          ]),
        ),
      ),
    );
  }

  static Color _statusColor(String s) {
    if (s == 'paid' || s == 'confirmed') return AppColors.success;
    if (s == 'rejected') return AppColors.emergency;
    if (s == 'claimed' || s == 'pending_review') return AppColors.warning;
    return AppColors.navy;
  }

  Widget _mini(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 2, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}

/// دفع العمولة: اختيار العمولات المستحقة + رقم عملية InstaPay + صورة الإيصال
class PayCommissionScreen extends StatefulWidget {
  const PayCommissionScreen({super.key});
  @override
  State<PayCommissionScreen> createState() => _PayCommissionScreenState();
}

class _PayCommissionScreenState extends State<PayCommissionScreen> {
  final Set<String> _selected = {};
  final _ref = TextEditingController();
  final _sender = TextEditingController();
  File? _receipt;
  bool _busy = false;
  Map<String, dynamic>? _instructions;
  List<Commission> _due = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = context.read<Session>().uid!;
    try {
      final results = await Future.wait([
        Api.instance.getPaymentInstructions(),
        FirebaseFirestore.instance.collection('commissions').where('workerId', isEqualTo: uid).where('status', isEqualTo: 'due').get(),
      ]);
      _instructions = results[0] as Map<String, dynamic>;
      final snap = results[1] as QuerySnapshot<Map<String, dynamic>>;
      _due = snap.docs.map(Commission.fromDoc).toList()..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
      _selected.addAll(_due.map((c) => c.id));
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _loaded = true);
  }

  double get _total => _due.where((c) => _selected.contains(c.id)).fold<int>(0, (a, c) => a + (c.amount * 100).round()) / 100;

  Future<void> _submit() async {
    if (_selected.isEmpty || _ref.text.trim().length < 4) {
      showSnack(context, '${context.t('transfer_reference')}: ${context.t('required')}', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final uid = context.read<Session>().uid!;
      String? receiptPath;
      if (_receipt != null) receiptPath = await StorageService.instance.uploadPath(_receipt!, 'payments/$uid');
      await Api.instance.submitPayment({
        'commissionIds': _selected.toList(),
        'reference': _ref.text.trim(),
        'senderAccount': _sender.text.trim(),
        if (receiptPath != null) 'receiptPath': receiptPath,
      });
      if (!mounted) return;
      showSnack(context, context.t('payment_submitted'));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final egp = context.t('egp');
    final handle = [_instructions?['handle'], _instructions?['phone']].where((x) => x != null && '$x'.isNotEmpty).join(' / ');
    return Scaffold(
      appBar: AppBar(title: Text(context.t('pay_commission'))),
      body: !_loaded
          ? const LoadingView()
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (handle.isEmpty)
                InfoBox(context.t('instapay_not_set'), color: AppColors.emergency)
              else ...[
                InfoBox(context.t('pay_steps', {'handle': handle}), icon: Icons.send_to_mobile_outlined),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${_instructions?['handle'] ?? _instructions?['phone'] ?? ''}'));
                    showSnack(context, context.t('done'));
                  },
                  icon: const Icon(Icons.copy),
                  label: Text(handle, textDirection: TextDirection.ltr),
                ),
              ],
              const SizedBox(height: 8),
              InfoBox(context.t('manual_review_note'), icon: Icons.verified_user_outlined, color: AppColors.warning),
              SectionTitle(context.t('select_commissions')),
              if (_due.isEmpty) EmptyView(text: context.t('no_commissions')),
              for (final c in _due)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _selected.contains(c.id),
                  onChanged: (v) => setState(() => v == true ? _selected.add(c.id) : _selected.remove(c.id)),
                  title: Text('#${c.requestCode} • ${Fmt.money(c.amount, lang)} $egp'),
                  subtitle: Text('${context.t('agreed_price')}: ${Fmt.money(c.servicePrice, lang)} $egp • ${Fmt.date(c.createdAt, lang)}'),
                ),
              const Divider(),
              Text(context.t('total_to_pay', {'amount': Fmt.money(_total, lang)}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              TextField(controller: _ref, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: context.t('transfer_reference'))),
              const SizedBox(height: 12),
              TextField(controller: _sender, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: context.t('sender_account'))),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final cam = await pickSourceSheet(context);
                  if (cam == null) return;
                  final f = await StorageService.instance.pick(camera: cam);
                  if (f != null) setState(() => _receipt = f);
                },
                icon: Icon(_receipt == null ? Icons.receipt_long_outlined : Icons.check_circle, color: _receipt == null ? null : AppColors.success),
                label: Text(context.t('receipt_photo')),
              ),
              if (_receipt != null) ...[
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_receipt!, height: 160, fit: BoxFit.cover)),
              ],
              const SizedBox(height: 20),
              BusyButton(label: context.t('submit_payment'), busy: _busy, onPressed: _due.isEmpty ? null : _submit),
            ]),
    );
  }
}
