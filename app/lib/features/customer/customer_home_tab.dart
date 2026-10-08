import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/request_repo.dart';
import '../../data/repos/worker_repo.dart';
import '../../data/session.dart';
import '../shared/location_picker.dart';
import '../shared/request_details_screen.dart';
import '../shared/widgets.dart';
import 'create_request_screen.dart';
import 'customer_location.dart';
import 'map_screen.dart';
import 'search_screen.dart';
import 'worker_profile_screen.dart';

class CustomerHomeTab extends StatefulWidget {
  final VoidCallback onOpenRequests;
  const CustomerHomeTab({super.key, required this.onOpenRequests});
  @override
  State<CustomerHomeTab> createState() => _CustomerHomeTabState();
}

class _CustomerHomeTabState extends State<CustomerHomeTab> {
  Future<List<Worker>>? _nearby;
  PickedLocation? _loadedFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLocation());
  }

  Future<void> _ensureLocation() async {
    final loc = context.read<CustomerLocation>();
    if (loc.current == null) {
      final p = await getGpsLocation(context);
      if (p != null) await loc.set(p);
    }
  }

  void _loadNearby(PickedLocation p) {
    if (_loadedFor == p) return;
    _loadedFor = p;
    _nearby = WorkerRepo.instance.search(lat: p.lat, lng: p.lng, f: SearchFilters(radiusKm: 15));
  }

  Future<void> _changeLocation() async {
    final loc = context.read<CustomerLocation>();
    final p = await showLocationChooser(context, current: loc.current);
    if (p != null) await loc.set(p);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final catalog = context.watch<CatalogRepo>();
    final loc = context.watch<CustomerLocation>().current;
    if (loc != null) _loadNearby(loc);
    final firstName = (session.user?.name ?? '').split(' ').first;

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
        onRefresh: () async {
          _loadedFor = null;
          if (loc != null) setState(() => _loadNearby(loc));
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          Text(context.t('hello_name', {'name': firstName}), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          Text(context.t('what_need'), style: const TextStyle(color: AppColors.muted, fontSize: 15)),
          const SizedBox(height: 14),

          // الموقع
          InkWell(
            onTap: _changeLocation,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                const Icon(Icons.location_on, color: AppColors.emergency),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc == null ? context.t('location_unknown') : (loc.label.isEmpty ? context.t('your_location') : loc.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // البحث
          TextField(
            readOnly: true,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen(focusSearch: true))),
            decoration: InputDecoration(hintText: context.t('search_hint'), prefixIcon: const Icon(Icons.search)),
          ),
          const SizedBox(height: 16),

          // الطوارئ
          Material(
            color: AppColors.emergency,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateRequestScreen(emergency: true))),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.t('emergency_btn'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(context.t('emergency_sub'), style: const TextStyle(color: Colors.white70)),
                    ]),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white),
                ]),
              ),
            ),
          ),

          // المهن
          SectionTitle(context.t('categories')),
          if (!catalog.loaded)
            const LoadingView()
          else
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
              children: [
                for (final c in catalog.categories)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SearchScreen(categoryId: c.id))),
                    child: Column(children: [
                      Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(16)),
                        child: CategoryIcon(category: c, size: 30),
                      ),
                      const SizedBox(height: 6),
                      Text(c.name(context.lang), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ],
            ),

          // القريبون
          SectionTitle(
            context.t('nearby_workers'),
            trailing: TextButton.icon(
              onPressed: loc == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapScreen())),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(context.t('open_map')),
            ),
          ),
          if (loc == null)
            EmptyView(
              text: context.t('location_permission_needed'),
              icon: Icons.location_off_outlined,
              action: OutlinedButton(onPressed: _changeLocation, child: Text(context.t('location_unknown'))),
            )
          else
            FutureBuilder<List<Worker>>(
              future: _nearby,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const LoadingView();
                if (snap.hasError) {
                  return ErrorView(message: context.t('error_network'), onRetry: () => setState(() => _loadedFor = null));
                }
                final list = snap.data ?? [];
                if (list.isEmpty) return EmptyView(text: context.t('no_workers_found'), icon: Icons.person_search_outlined);
                return Column(children: [
                  for (final w in list.take(8)) ...[
                    WorkerCard(w: w, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerProfileScreen(workerId: w.id, distanceKm: w.distanceKm)))),
                    const SizedBox(height: 10),
                  ],
                  if (list.length > 8)
                    OutlinedButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                      child: Text(context.t('see_all')),
                    ),
                ]);
              },
            ),

          // آخر الطلبات
          if (session.uid != null)
            StreamBuilder<List<ServiceRequest>>(
              stream: RequestRepo.instance.mine(session.uid!, asWorker: false, limit: 3),
              builder: (context, snap) {
                final list = snap.data ?? [];
                if (list.isEmpty) return const SizedBox.shrink();
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SectionTitle(context.t('recent_requests'), trailing: TextButton(onPressed: widget.onOpenRequests, child: Text(context.t('see_all')))),
                  for (final r in list) ...[
                    RequestCard(
                      r: r,
                      asWorker: false,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestDetailsScreen(requestId: r.id))),
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
