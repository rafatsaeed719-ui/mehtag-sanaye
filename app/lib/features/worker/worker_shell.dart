import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repos/request_repo.dart';
import '../../data/services/location_service.dart';
import '../../data/session.dart';
import '../shared/account_tab.dart';
import '../shared/request_details_screen.dart';
import '../shared/requests_tab.dart';
import '../shared/widgets.dart';
import 'wallet_screen.dart';

class WorkerShell extends StatefulWidget {
  const WorkerShell({super.key});
  @override
  State<WorkerShell> createState() => _WorkerShellState();
}

class _WorkerShellState extends State<WorkerShell> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: const [
          WorkerHomeTab(),
          RequestsTab(asWorker: true),
          WalletScreen(asTab: true),
          AccountTab(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.near_me_outlined), selectedIcon: const Icon(Icons.near_me), label: context.t('nav_nearby')),
            NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: context.t('nav_requests')),
            NavigationDestination(
                icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet), label: context.t('nav_wallet')),
            NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: context.t('nav_account')),
          ],
        ),
      );
}

/// الرئيسية للصنايعي: حالة التوفر + الطلبات الموجهة له + 📍 طلبات قريبة منك
class WorkerHomeTab extends StatefulWidget {
  const WorkerHomeTab({super.key});
  @override
  State<WorkerHomeTab> createState() => _WorkerHomeTabState();
}

class _WorkerHomeTabState extends State<WorkerHomeTab> {
  Future<List<(ServiceRequest, double)>>? _nearby;
  double _radius = 25;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final w = context.read<Session>().worker;
    if (w == null) return;
    setState(() {
      _nearby = () async {
        // نستخدم موقع الجهاز الحالي لو متاح، وإلا موقع الصنايعي المسجل
        final r = await LocationService.instance.current();
        final lat = r.ok ? r.lat! : w.lat;
        final lng = r.ok ? r.lng! : w.lng;
        return RequestRepo.instance.nearbyOpen(lat: lat, lng: lng, categoryIds: w.categoryIds, radiusKm: _radius);
      }();
    });
  }

  Future<void> _toggleAvailable(Worker w, bool v) async {
    try {
      await FirebaseFirestore.instance.doc('workers/${w.id}').update({
        'available': v,
        'availableUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final w = s.worker!;
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Row(children: [
          Image.asset('assets/images/logo_mark.png', width: 32, height: 32),
          const SizedBox(width: 8),
          Text(context.t('app_name')),
        ]),
        actions: const [NotificationBell()],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          Text(context.t('hello_name', {'name': w.name.split(' ').first}), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.verified, size: 18, color: AppColors.success),
            const SizedBox(width: 4),
            Text(context.t('verified_worker'), style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            RatingLine(avg: w.ratingAvg, count: w.ratingCount),
          ]),
          const SizedBox(height: 12),
          Card(
            color: w.available ? const Color(0xFFE8F5EE) : Colors.white,
            child: SwitchListTile(
              value: w.available,
              onChanged: (v) => _toggleAvailable(w, v),
              title: Text(w.available ? context.t('available_now') : context.t('not_available'), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(w.available ? context.t('you_are_available') : context.t('you_are_unavailable')),
              secondary: Icon(Icons.circle, color: w.available ? AppColors.success : AppColors.muted, size: 16),
            ),
          ),

          // الطلبات الموجهة (جديدة)
          StreamBuilder<List<ServiceRequest>>(
            stream: RequestRepo.instance.mine(s.uid!, asWorker: true, limit: 30),
            builder: (context, snap) {
              final incoming = (snap.data ?? []).where((r) => r.status == 'new' || r.status == 'proposed' || r.status == 'price_set').toList();
              if (incoming.isEmpty) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SectionTitle(context.t('incoming_requests')),
                for (final r in incoming) ...[
                  RequestCard(
                    r: r,
                    asWorker: true,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestDetailsScreen(requestId: r.id))),
                  ),
                  const SizedBox(height: 10),
                ],
              ]);
            },
          ),

          // الطلبات القريبة المفتوحة
          SectionTitle(
            context.t('nearby_requests'),
            trailing: DropdownButton<double>(
              value: _radius,
              underline: const SizedBox.shrink(),
              items: [5.0, 10.0, 25.0, 50.0]
                  .map((r) => DropdownMenuItem(value: r, child: Text(context.t('within_km', {'km': r.toInt()}))))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                _radius = v;
                _load();
              },
            ),
          ),
          if (_nearby == null)
            const LoadingView()
          else
            FutureBuilder<List<(ServiceRequest, double)>>(
              future: _nearby,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const LoadingView();
                if (snap.hasError) return ErrorView(message: friendlyError(context, snap.error!), onRetry: _load);
                final list = snap.data ?? [];
                if (list.isEmpty) return EmptyView(text: context.t('nearby_empty'), icon: Icons.near_me_disabled_outlined);
                return Column(children: [
                  for (final item in list) ...[
                    RequestCard(
                      r: item.$1,
                      asWorker: true,
                      trailingText: '${Fmt.km(item.$2, lang)} ${context.t('km')}',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestDetailsScreen(requestId: item.$1.id))),
                    ),
                    const SizedBox(height: 10),
                  ],
                ]);
              },
            ),
        ]),
      ),
    );
  }
}
