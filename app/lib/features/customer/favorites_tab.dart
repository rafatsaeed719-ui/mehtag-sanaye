import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/utils/geo.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repos/worker_repo.dart';
import '../../data/session.dart';
import '../shared/widgets.dart';
import 'customer_location.dart';
import 'worker_profile_screen.dart';

class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  Future<List<Worker>> _load(List<String> ids, BuildContext context) async {
    final loc = context.read<CustomerLocation>().current;
    final list = <Worker>[];
    for (final id in ids) {
      try {
        final w = await WorkerRepo.instance.get(id);
        if (w == null) continue;
        if (loc != null) w.distanceKm = Geo.distanceKm(loc.lat, loc.lng, w.lat, w.lng);
        list.add(w);
      } catch (_) {
        // صنايعي اتوقف أو مبقاش ظاهر — نتجاهله
      }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<Session>().uid!;
    return Scaffold(
      appBar: AppBar(title: Text('❤️ ${context.t('nav_favorites')}')),
      body: StreamBuilder<List<String>>(
        stream: WorkerRepo.instance.favoriteIds(uid),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final ids = snap.data!;
          if (ids.isEmpty) return EmptyView(text: context.t('favorites_empty'), icon: Icons.favorite_border);
          return FutureBuilder<List<Worker>>(
            future: _load(ids, context),
            builder: (context, f) {
              if (!f.hasData) return const LoadingView();
              final list = f.data!;
              if (list.isEmpty) return EmptyView(text: context.t('favorites_empty'), icon: Icons.favorite_border);
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => Dismissible(
                  key: ValueKey(list[i].id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: AlignmentDirectional.centerEnd,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                  onDismissed: (_) => WorkerRepo.instance.setFavorite(uid, list[i].id, false),
                  child: WorkerCard(
                    w: list[i],
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerProfileScreen(workerId: list[i].id, distanceKm: list[i].distanceKm))),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
