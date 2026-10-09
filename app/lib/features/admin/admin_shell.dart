import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/session.dart';
import 'admin_content.dart';
import 'admin_ops.dart';
import 'admin_people.dart';
import 'admin_service.dart';
import 'admin_ui.dart';

/// الشاشة الرئيسية للإدارة جوه التطبيق
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _Stats {
  int customers = 0, workers = 0, approved = 0, pendingWorkers = 0, pendingChanges = 0;
  int totalReq = 0, activeReq = 0, completedReq = 0, cancelledReq = 0;
  int pendingPayments = 0, newReports = 0, openTickets = 0;
  double today = 0, week = 0, month = 0, due = 0, paid = 0;
  double wAvg = 0, cAvg = 0;
}

class _AdminShellState extends State<AdminShell> {
  final a = AdminService.instance;
  late Future<_Stats> _future = _load();

  Future<_Stats> _load() async {
    final s = _Stats();
    final c = a.col;
    final futures = <Future>[];
    void n(Future<int> f, void Function(int) set) => futures.add(f.then(set));
    void d(Future<double> f, void Function(double) set) => futures.add(f.then(set));

    n(a.count(c('users').where('role', isEqualTo: 'customer')), (v) => s.customers = v);
    n(a.count(c('users').where('role', isEqualTo: 'worker')), (v) => s.workers = v);
    n(a.count(c('workers').where('verificationStatus', isEqualTo: 'approved')), (v) => s.approved = v);
    n(a.count(c('requests')), (v) => s.totalReq = v);
    n(a.count(c('requests').where('status', whereIn: ['price_agreed', 'commission_paid'])), (v) => s.completedReq = v);
    n(a.count(c('requests').where('status', isEqualTo: 'cancelled')), (v) => s.cancelledReq = v);
    n(a.count(c('requests').where('status', whereIn: ['new', 'accepted', 'proposed', 'confirmed', 'on_the_way', 'started', 'completed', 'price_set'])),
        (v) => s.activeReq = v);
    if (a.isModerator) {
      n(a.count(c('workers').where('verificationStatus', isEqualTo: 'pending')), (v) => s.pendingWorkers = v);
      n(a.count(c('workerChangeRequests').where('status', isEqualTo: 'pending')), (v) => s.pendingChanges = v);
      n(a.count(c('reports').where('status', isEqualTo: 'new')), (v) => s.newReports = v);
      n(a.count(c('supportTickets').where('status', isEqualTo: 'open')), (v) => s.openTickets = v);
    }
    if (a.isFinance) {
      n(a.count(c('payments').where('status', isEqualTo: 'pending_review')), (v) => s.pendingPayments = v);
    }
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    Query<Map<String, dynamic>> since(DateTime t) => c('commissions').where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(t));
    d(a.sumOf(since(startToday), 'amount'), (v) => s.today = v);
    d(a.sumOf(since(now.subtract(const Duration(days: 7))), 'amount'), (v) => s.week = v);
    d(a.sumOf(since(DateTime(now.year, now.month)), 'amount'), (v) => s.month = v);
    d(a.sumOf(c('commissions').where('status', whereIn: ['due', 'claimed']), 'amount'), (v) => s.due = v);
    d(a.sumOf(c('commissions').where('status', isEqualTo: 'paid'), 'amount'), (v) => s.paid = v);
    double ws = 0, wc = 0, cs = 0, cc = 0;
    d(a.sumOf(c('workers'), 'ratingSum'), (v) => ws = v);
    d(a.sumOf(c('workers'), 'ratingCount'), (v) => wc = v);
    d(a.sumOf(c('users'), 'customerRatingSum'), (v) => cs = v);
    d(a.sumOf(c('users'), 'customerRatingCount'), (v) => cc = v);
    await Future.wait(futures);
    s.wAvg = wc > 0 ? ws / wc : 0;
    s.cAvg = cc > 0 ? cs / cc : 0;
    return s;
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final roleName = {'super': 'مدير عام', 'moderator': 'مشرف', 'finance': 'مالية'}[a.role] ?? a.role;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Row(mainAxisSize: MainAxisSize.min, children: [
            ClipOval(child: Image.asset('assets/images/logo_mark.png', width: 30, height: 30)),
            const SizedBox(width: 8),
            const Text('لوحة التحكم'),
          ]),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.account_circle_outlined),
              onSelected: (v) async {
                if (v == 'logout' && await askConfirm(context, 'تسجيل الخروج من الإدارة؟')) {
                  await session.leaveAdmin();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(enabled: false, child: Text('${a.email}\n$roleName', style: const TextStyle(fontSize: 13))),
                const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, color: AppColors.emergency), SizedBox(width: 8), Text('تسجيل الخروج')])),
              ],
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<_Stats>(
            future: _future,
            builder: (context, snap) {
              final s = snap.data;
              return ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.navy, AppColors.navyDark]),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(children: [
                      const Icon(Icons.admin_panel_settings, color: AppColors.amber, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('أهلاً بيك 👋', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                          Text('صلاحيتك: $roleName', style: const TextStyle(color: Colors.white70)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  if (s == null && snap.connectionState != ConnectionState.done)
                    const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
                  if (s != null) ..._todo(s),
                  _title('الأقسام'),
                  _sections(s),
                  if (s != null) ...[
                    _title('الإحصائيات'),
                    _kpis(s),
                  ],
                  const SizedBox(height: 20),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
        child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      );

  List<Widget> _todo(_Stats s) {
    final items = <(String, int, IconData, Widget)>[
      if (a.isModerator) ('صنايعية بانتظار المراجعة', s.pendingWorkers, Icons.engineering, const WorkersAdminScreen()),
      if (a.isModerator) ('تعديلات بيانات بانتظار المراجعة', s.pendingChanges, Icons.edit_note, const WorkersAdminScreen(initialTab: 3)),
      if (a.isFinance) ('تحويلات InstaPay بانتظار التأكيد', s.pendingPayments, Icons.payments_outlined, const FinanceAdminScreen()),
      if (a.isModerator) ('بلاغات جديدة', s.newReports, Icons.flag_outlined, const ReportsAdminScreen()),
      if (a.isModerator) ('رسائل دعم مفتوحة', s.openTickets, Icons.support_agent, const SupportAdminScreen()),
    ].where((e) => e.$2 > 0).toList();
    if (items.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
          child: const Row(children: [
            Icon(Icons.check_circle, color: AppColors.success),
            SizedBox(width: 10),
            Expanded(child: Text('مفيش حاجة مستنية مراجعة دلوقتي 👌', style: TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
      ];
    }
    return [
      _title('محتاج مراجعتك'),
      for (final e in items)
        AdminCard(
          onTap: () => _open(e.$4),
          child: Row(children: [
            Icon(e.$3, color: AppColors.warning),
            const SizedBox(width: 12),
            Expanded(child: Text(e.$1, style: const TextStyle(fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: AppColors.emergency, borderRadius: BorderRadius.circular(20)),
              child: Text('${e.$2}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_left),
          ]),
        ),
    ];
  }

  Widget _sections(_Stats? s) {
    final tiles = <(String, IconData, Color, Widget, int)>[
      if (a.isModerator) ('الصنايعية', Icons.engineering, AppColors.navy, const WorkersAdminScreen(), (s?.pendingWorkers ?? 0) + (s?.pendingChanges ?? 0)),
      if (a.isModerator) ('المستخدمون', Icons.people_alt_outlined, AppColors.navy, const UsersAdminScreen(), 0),
      ('الطلبات', Icons.receipt_long, AppColors.navy, const RequestsAdminScreen(), 0),
      if (a.isFinance) ('العمولات والمدفوعات', Icons.payments_outlined, AppColors.success, const FinanceAdminScreen(), s?.pendingPayments ?? 0),
      if (a.isModerator) ('الشكاوى والبلاغات', Icons.flag_outlined, AppColors.emergency, const ReportsAdminScreen(), s?.newReports ?? 0),
      if (a.isModerator) ('الدعم', Icons.support_agent, AppColors.navy, const SupportAdminScreen(), s?.openTickets ?? 0),
      if (a.isModerator) ('التقييمات', Icons.star_outline, AppColors.amber, const ReviewsAdminScreen(), 0),
      if (a.isModerator) ('إرسال إشعار', Icons.campaign_outlined, AppColors.amber, const BroadcastAdminScreen(), 0),
      if (a.isModerator) ('المهن والخدمات', Icons.handyman_outlined, AppColors.navy, const CatalogAdminScreen(), 0),
      if (a.isModerator) ('المناطق', Icons.place_outlined, AppColors.navy, const LocationsAdminScreen(), 0),
      if (a.isFinance) ('الإعدادات', Icons.settings_outlined, AppColors.muted, const SettingsAdminScreen(), 0),
      if (a.isSuper) ('فريق الإدارة والسجل', Icons.shield_outlined, AppColors.muted, const TeamAdminScreen(), 0),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.95,
      children: [
        for (final t in tiles)
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _open(t.$4),
              child: Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                padding: const EdgeInsets.all(8),
                child: Stack(children: [
                  Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(color: t.$3.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: Icon(t.$2, color: t.$3),
                      ),
                      const SizedBox(height: 8),
                      Text(t.$1, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ]),
                  ),
                  if (t.$5 > 0)
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.emergency, borderRadius: BorderRadius.circular(12)),
                        child: Text('${t.$5}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _kpis(_Stats s) {
    String pct(int a, int b) => b == 0 ? '—' : '${(a * 100 / b).round()}%';
    final k = <(String, String)>[
      ('العملاء', '${s.customers}'),
      ('الصنايعية', '${s.workers}'),
      ('الموثّقون', '${s.approved}'),
      ('كل الطلبات', '${s.totalReq}'),
      ('طلبات جارية', '${s.activeReq}'),
      ('مكتملة', '${s.completedReq}'),
      ('ملغاة', '${s.cancelledReq}'),
      ('معدل الإتمام', pct(s.completedReq, s.totalReq)),
      ('معدل الإلغاء', pct(s.cancelledReq, s.totalReq)),
      ('أرباح النهارده', money(s.today)),
      ('آخر 7 أيام', money(s.week)),
      ('أرباح الشهر', money(s.month)),
      ('عمولات مستحقة', money(s.due)),
      ('عمولات مدفوعة', money(s.paid)),
      ('تقييم الصنايعية', s.wAvg > 0 ? '${s.wAvg.toStringAsFixed(1)} ★' : '—'),
      ('تقييم العملاء', s.cAvg > 0 ? '${s.cAvg.toStringAsFixed(1)} ★' : '—'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: [
        for (final e in k)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              FittedBox(child: Text(e.$2, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.navy))),
              Text(e.$1, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ]),
          ),
      ],
    );
  }
}
