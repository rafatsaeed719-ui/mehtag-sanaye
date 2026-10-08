import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repos/request_repo.dart';
import '../../data/session.dart';

/// إحصائيات العميل أو الصنايعي
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(title: Text(context.t('my_stats'))),
      body: s.isWorker ? _WorkerStats(session: s) : _CustomerStats(uid: s.uid!, user: s.user),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Tile(this.label, this.value, this.icon, {this.color = AppColors.navy});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color),
            const Spacer(),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text(label, maxLines: 2, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ]),
        ),
      );
}

Widget _grid(List<Widget> tiles) => GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(16),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: tiles,
    );

class _CustomerStats extends StatelessWidget {
  final String uid;
  final AppUser? user;
  const _CustomerStats({required this.uid, required this.user});
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, num>>(
        future: RequestRepo.instance.customerStats(uid),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final d = snap.data!;
          return _grid([
            _Tile(context.t('stats_total_requests'), '${d['total']}', Icons.receipt_long),
            _Tile(context.t('stats_completed'), '${d['completed']}', Icons.task_alt, color: AppColors.success),
            _Tile(context.t('stats_cancelled'), '${d['cancelled']}', Icons.cancel_outlined, color: AppColors.emergency),
            _Tile(context.t('stats_workers_dealt'), '${d['workers']}', Icons.engineering_outlined),
            _Tile(
              context.t('stats_my_rating'),
              (user?.customerRatingCount ?? 0) == 0 ? '—' : '${user!.customerRatingAvg.toStringAsFixed(1)} ★',
              Icons.star_outline,
              color: AppColors.amber,
            ),
          ]);
        },
      );
}

class _WorkerStats extends StatelessWidget {
  final Session session;
  const _WorkerStats({required this.session});

  Future<Map<String, num>> _load(String uid) async {
    final reqs = FirebaseFirestore.instance.collection('requests').where('workerId', isEqualTo: uid);
    final recent = await reqs.orderBy('createdAt', descending: true).limit(500).get();
    final list = recent.docs.map(ServiceRequest.fromDoc).toList();
    final received = list.length;
    final responded = list.where((r) => r.status != 'new').length;
    final accepted = list.where((r) => !['new', 'rejected'].contains(r.status) && !(r.status == 'cancelled' && r.cancelledBy == 'worker')).length;
    final completed = list.where((r) => ['completed', 'price_set', 'price_agreed', 'commission_paid'].contains(r.status)).length;
    final cancelled = list.where((r) => r.status == 'cancelled').length;
    final customers = list.map((r) => r.customerId).toSet().length;
    return {
      'received': received,
      'accepted': accepted,
      'completed': completed,
      'cancelled': cancelled,
      'customers': customers,
      'responseRate': received == 0 ? 0 : responded / received,
    };
  }

  @override
  Widget build(BuildContext context) {
    final w = session.worker;
    final uid = session.uid!;
    final lang = context.lang;
    if (w == null) return const LoadingView();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('commissions').where('workerId', isEqualTo: uid).snapshots(),
      builder: (context, ws) {
        final wallet = Wallet.fromCommissions((ws.data?.docs ?? []).map(Commission.fromDoc).toList());
        return FutureBuilder<Map<String, num>>(
          future: _load(uid),
          builder: (context, f) {
            final d = f.data;
            String n(String k) => d == null ? '…' : '${d[k]}';
            final egp = context.t('egp');
            return _grid([
              _Tile(context.t('stats_received'), n('received'), Icons.inbox_outlined),
              _Tile(context.t('stats_accepted'), n('accepted'), Icons.thumb_up_alt_outlined),
              _Tile(context.t('stats_completed'), n('completed'), Icons.task_alt, color: AppColors.success),
              _Tile(context.t('stats_cancelled'), n('cancelled'), Icons.cancel_outlined, color: AppColors.emergency),
              _Tile(context.t('stats_avg_rating'), w.ratingCount == 0 ? '—' : '${w.ratingAvg.toStringAsFixed(1)} ★', Icons.star_outline, color: AppColors.amber),
              _Tile(context.t('stats_customers'), n('customers'), Icons.groups_outlined),
              _Tile(context.t('stats_response_rate'), d == null ? '…' : '${((d['responseRate'] ?? 0) * 100).toStringAsFixed(0)}%', Icons.bolt),
              _Tile(context.t('stats_services_total'), '${Fmt.money(wallet.totalServices, lang)} $egp', Icons.payments_outlined),
              _Tile(context.t('stats_commission_total'), '${Fmt.money(wallet.totalCommission, lang)} $egp', Icons.percent),
              _Tile(context.t('stats_paid'), '${Fmt.money(wallet.paid, lang)} $egp', Icons.check_circle_outline, color: AppColors.success),
              _Tile(context.t('stats_due'), '${Fmt.money(wallet.due, lang)} $egp', Icons.schedule, color: AppColors.warning),
            ]);
          },
        );
      },
    );
  }
}
