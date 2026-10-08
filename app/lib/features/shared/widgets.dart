import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/session.dart';
import 'notifications_screen.dart';

/// جرس الإشعارات مع عدد غير المقروء (مباشر)
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = context.read<Session>().uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications/$uid/items')
          .where('read', isEqualTo: false)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        final n = snap.data?.docs.length ?? 0;
        return IconButton(
          tooltip: context.t('notifications'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          icon: Badge(isLabelVisible: n > 0, label: Text(n > 99 ? '99+' : '$n'), child: const Icon(Icons.notifications_outlined)),
        );
      },
    );
  }
}

/// بطاقة صنايعي في نتائج البحث
class WorkerCard extends StatelessWidget {
  final Worker w;
  final VoidCallback onTap;
  const WorkerCard({super.key, required this.w, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final profession = w.categoryNames.map((n) => context.loc(n)).join(' • ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              Avatar(url: w.photoUrl, name: w.name, size: 60),
              PositionedDirectional(
                bottom: 0,
                end: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: w.available ? AppColors.success : AppColors.muted,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(w.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  if (w.idVerified) ...[const SizedBox(width: 4), const Icon(Icons.verified, size: 18, color: AppColors.success)],
                ]),
                Text(profession, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 4),
                RatingLine(avg: w.ratingAvg, count: w.ratingCount),
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (w.distanceKm != null)
                    _meta(Icons.near_me_outlined, context.t('away', {'km': Fmt.km(w.distanceKm!, lang)})),
                  _meta(Icons.payments_outlined,
                      w.visitFee == null ? context.t('no_visit_fee') : context.t('visit_fee_value', {'fee': Fmt.money(w.visitFee, lang)})),
                  if (w.available) _meta(Icons.circle, context.t('available_now'), color: AppColors.success, size: 10),
                ]),
                if (w.badges.where((b) => b != 'verified').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  BadgeChips(badges: w.badges.where((b) => b != 'verified').toList(), small: true),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, {Color color = AppColors.muted, double size = 15}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: size, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12.5, color: color == AppColors.muted ? AppColors.text : color)),
      ]);
}

/// بطاقة طلب في القوائم
class RequestCard extends StatelessWidget {
  final ServiceRequest r;
  final bool asWorker;
  final VoidCallback onTap;
  final String? trailingText;
  const RequestCard({super.key, required this.r, required this.asWorker, required this.onTap, this.trailingText});

  @override
  Widget build(BuildContext context) {
    final uid = context.read<Session>().uid ?? '';
    final other = asWorker ? r.customerName : (r.workerName ?? context.t('waiting_workers'));
    final unread = r.unreadFor(uid);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (r.isEmergency) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.emergency, borderRadius: BorderRadius.circular(12)),
                  child: Text(context.t('emergency_tag'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(child: Text(context.loc(r.displayService), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              StatusChip(r.status),
            ]),
            const SizedBox(height: 6),
            Text(other, style: const TextStyle(color: AppColors.muted)),
            if (r.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(r.description, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.schedule, size: 15, color: AppColors.muted),
              const SizedBox(width: 4),
              Expanded(child: Text(Fmt.dateTime(r.scheduledAt, context.lang), style: const TextStyle(fontSize: 12.5, color: AppColors.muted))),
              if (trailingText != null) Text(trailingText!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.navy)),
              if (unread > 0)
                Badge(label: Text('$unread'), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.chat_bubble_outline, size: 18))),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// شريط يظهر عند فقد الاتصال (يعتمد على كاش Firestore)
class OfflineAware extends StatelessWidget {
  final Widget child;
  final bool fromCache;
  const OfflineAware({super.key, required this.child, required this.fromCache});
  @override
  Widget build(BuildContext context) => Column(children: [
        if (fromCache)
          Container(
            width: double.infinity,
            color: AppColors.amberSoft,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Text(context.t('offline_banner'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5)),
          ),
        Expanded(child: child),
      ]);
}
