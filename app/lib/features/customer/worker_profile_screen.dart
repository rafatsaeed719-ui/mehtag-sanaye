import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/geo.dart';
import '../../data/models.dart';
import '../../core/widgets/common.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/worker_repo.dart';
import '../../data/session.dart';
import '../shared/report_screen.dart';
import 'create_request_screen.dart';
import 'customer_location.dart';

/// صفحة الصنايعي الكاملة
class WorkerProfileScreen extends StatelessWidget {
  final String workerId;
  final double? distanceKm;
  const WorkerProfileScreen({super.key, required this.workerId, this.distanceKm});

  Future<void> _launch(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) showSnack(context, context.t('error_generic'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final uid = session.uid!;
    final lang = context.lang;
    return StreamBuilder<Worker?>(
      stream: WorkerRepo.instance.watch(workerId),
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(appBar: AppBar(), body: ErrorView(message: friendlyError(context, snap.error!)));
        if (!snap.hasData) return Scaffold(appBar: AppBar(), body: const LoadingView());
        final w = snap.data!;
        final loc = context.read<CustomerLocation>().current;
        final km = distanceKm ?? (loc == null ? null : Geo.distanceKm(loc.lat, loc.lng, w.lat, w.lng));
        final place = [w.area, w.city].where((s) => s.isNotEmpty).join('، ');

        return Scaffold(
          appBar: AppBar(
            actions: [
              StreamBuilder<bool>(
                stream: WorkerRepo.instance.isFavorite(uid, workerId),
                builder: (context, f) {
                  final fav = f.data ?? false;
                  return IconButton(
                    tooltip: fav ? context.t('remove_favorite') : context.t('add_favorite'),
                    icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? AppColors.emergency : null),
                    onPressed: () => WorkerRepo.instance.setFavorite(uid, workerId, !fav).catchError((e) {
                      if (context.mounted) showError(context, e);
                    }),
                  );
                },
              ),
              PopupMenuButton<String>(
                onSelected: (_) => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportScreen(againstId: workerId))),
                itemBuilder: (_) => [PopupMenuItem(value: 'report', child: Text(context.t('report_user')))],
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
            Center(child: Avatar(url: w.photoUrl, name: w.name, size: 104)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text(w.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
              if (w.idVerified) ...[const SizedBox(width: 6), const Icon(Icons.verified, color: AppColors.success)],
            ]),
            Text(w.categoryNames.map((n) => context.loc(n)).join(' • '), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
            const SizedBox(height: 8),
            Center(child: RatingLine(avg: w.ratingAvg, count: w.ratingCount)),
            const SizedBox(height: 8),
            Center(child: BadgeChips(badges: w.badges)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  _row(Icons.circle, w.available ? context.t('available_now') : context.t('not_available'),
                      color: w.available ? AppColors.success : AppColors.muted, iconSize: 12),
                  _row(Icons.location_on_outlined, [place, govName(context, w.governorate)].where((s) => s.isNotEmpty).join('، ')),
                  if (km != null) _row(Icons.near_me_outlined, context.t('away', {'km': Fmt.km(km, lang)})),
                  _row(Icons.payments_outlined,
                      '${context.t('visit_fee')}: ${w.visitFee == null ? context.t('no_visit_fee') : context.t('visit_fee_value', {'fee': Fmt.money(w.visitFee, lang)})}'),
                  if (w.completedCount > 0) _row(Icons.task_alt, context.t('completed_jobs', {'n': w.completedCount})),
                ]),
              ),
            ),
            if (w.bio.isNotEmpty) ...[
              SectionTitle(context.t('about')),
              Text(w.bio, style: const TextStyle(height: 1.5)),
            ],
            if (w.serviceNames.isNotEmpty) ...[
              SectionTitle(context.t('services')),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final s in w.serviceNames) Chip(label: Text(context.loc(s)))]),
            ],
            if (w.workImages.isNotEmpty) ...[
              SectionTitle(context.t('previous_work')),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: w.workImages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => openImageViewer(context, w.workImages[i]),
                    child: NetImage(url: w.workImages[i], width: 120, height: 120),
                  ),
                ),
              ),
            ],
            SectionTitle(context.t('reviews')),
            StreamBuilder<List<Review>>(
              stream: WorkerRepo.instance.reviews(workerId),
              builder: (context, r) {
                final list = r.data ?? [];
                if (list.isEmpty) return Text(context.t('no_reviews'), style: const TextStyle(color: AppColors.muted));
                return Column(children: [
                  for (final rv in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(rv.fromName, style: const TextStyle(fontWeight: FontWeight.w700))),
                              Stars(value: rv.stars.toDouble(), size: 15),
                            ]),
                            if (rv.comment.isNotEmpty) ...[const SizedBox(height: 4), Text(rv.comment)],
                            const SizedBox(height: 4),
                            Text('${context.loc(rv.serviceName)} • ${Fmt.relative(rv.createdAt, lang)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                          ]),
                        ),
                      ),
                    ),
                ]);
              },
            ),
          ]),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: w.callPhone.isEmpty ? null : () => _launch(context, Uri.parse('tel:${w.callPhone}')),
                      icon: const Icon(Icons.call_outlined),
                      label: Text(context.t('call')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF15803D), side: const BorderSide(color: Color(0xFF15803D))),
                      onPressed: w.whatsapp.isEmpty ? null : () => _launch(context, Uri.parse(Fmt.whatsappLink(w.whatsapp))),
                      icon: const Icon(Icons.chat_outlined),
                      label: Text(context.t('whatsapp')),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: workerId == uid
                      ? null
                      : () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateRequestScreen(worker: w))),
                  icon: const Icon(Icons.handyman_outlined),
                  label: Text(context.t('request_worker')),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _row(IconData icon, String text, {Color color = AppColors.navy, double iconSize = 20}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 24, child: Icon(icon, size: iconSize, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}

/// يحوّل كود المحافظة لاسمها حسب اللغة
String govName(BuildContext context, String code) =>
    context.read<CatalogRepo>().governorateByCode(code)?.name(context.lang) ?? code;
