import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/services/in_app_notifier.dart';
import '../../data/session.dart';
import 'chat_screen.dart';
import 'request_details_screen.dart';

/// صندوق الإشعارات: إشعاراتي + إشعارات الإدارة الموجهة لفئتي
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  bool _forMe(Map<String, dynamic> b, Session s) {
    final target = b['target'] ?? 'all';
    final value = '${b['value'] ?? ''}';
    final u = s.user;
    if (u == null) return false;
    switch (target) {
      case 'all':
        return true;
      case 'customers':
        return !u.isWorker;
      case 'workers':
        return u.isWorker;
      case 'category':
        return s.worker?.categoryIds.contains(value) ?? false;
      case 'governorate':
        return s.worker?.governorate == value;
      case 'user':
        return value == u.uid || value == u.phone;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final uid = s.uid!;
    final lang = context.lang;
    final col = FirebaseFirestore.instance.collection('notifications/$uid/items');
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('notifications')),
        actions: [
          IconButton(
            tooltip: context.t('mark_all_read'),
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              final unread = await col.where('read', isEqualTo: false).limit(200).get();
              final b = FirebaseFirestore.instance.batch();
              for (final d in unread.docs) {
                b.update(d.reference, {'read': true});
              }
              await b.commit();
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: col.orderBy('createdAt', descending: true).limit(100).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('broadcasts').orderBy('createdAt', descending: true).limit(20).snapshots(),
            builder: (context, bs) {
              final items = [
                ...snap.data!.docs.map(AppNotification.fromDoc),
                ...(bs.data?.docs ?? []).where((d) => _forMe(d.data(), s)).map(AppNotification.fromBroadcast),
              ]..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
              return Column(children: [
                Container(
                  width: double.infinity,
                  color: AppColors.amberSoft,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(context.t('in_app_notice'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5)),
                ),
                Expanded(
                  child: items.isEmpty
                      ? EmptyView(text: context.t('notifications_empty'), icon: Icons.notifications_none)
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final n = items[i];
                            final (title, body) = notificationText(n, lang);
                            return ListTile(
                              tileColor: n.read ? null : AppColors.amberSoft.withValues(alpha: 0.6),
                              leading: CircleAvatar(
                                backgroundColor: n.type.contains('emergency') ? AppColors.emergency : AppColors.navy,
                                child: Icon(_icon(n.type), color: Colors.white, size: 20),
                              ),
                              title: Text(title, style: TextStyle(fontWeight: n.read ? FontWeight.w500 : FontWeight.w800)),
                              subtitle: Text('$body\n${Fmt.relative(n.createdAt, lang)}'),
                              isThreeLine: true,
                              onTap: () {
                                if (!n.read && !n.isBroadcast) col.doc(n.id).update({'read': true});
                                final rid = n.data['requestId']?.toString();
                                if (rid == null) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => n.data['screen'] == 'chat' ? ChatScreen(requestId: rid) : RequestDetailsScreen(requestId: rid)),
                                );
                              },
                            );
                          },
                        ),
                ),
              ]);
            },
          );
        },
      ),
    );
  }

  IconData _icon(String type) {
    if (type.contains('message')) return Icons.chat_bubble_outline;
    if (type.contains('price') || type.contains('commission') || type.contains('payment')) return Icons.payments_outlined;
    if (type.contains('review')) return Icons.star_outline;
    if (type.contains('account') || type.contains('change')) return Icons.verified_user_outlined;
    if (type.contains('emergency')) return Icons.campaign;
    if (type == 'admin') return Icons.campaign_outlined;
    return Icons.handyman_outlined;
  }
}
