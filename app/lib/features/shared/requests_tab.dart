import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repos/request_repo.dart';
import '../../data/session.dart';
import 'request_details_screen.dart';
import 'widgets.dart';

/// قائمة الطلبات (الحالية / السابقة) للعميل أو للصنايعي
class RequestsTab extends StatelessWidget {
  final bool asWorker;
  const RequestsTab({super.key, required this.asWorker});

  @override
  Widget build(BuildContext context) {
    final uid = context.read<Session>().uid!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.t('my_requests')),
          actions: const [NotificationBell()],
          bottom: TabBar(tabs: [Tab(text: context.t('active')), Tab(text: context.t('history'))]),
        ),
        body: StreamBuilder<List<ServiceRequest>>(
          stream: RequestRepo.instance.mine(uid, asWorker: asWorker),
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: friendlyError(context, snap.error!));
            if (!snap.hasData) return const LoadingView();
            final all = snap.data!;
            final active = all.where((r) => r.isActive).toList();
            final past = all.where((r) => !r.isActive).toList();
            Widget list(List<ServiceRequest> items) => items.isEmpty
                ? EmptyView(text: context.t('requests_empty'), icon: Icons.receipt_long_outlined)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => RequestCard(
                      r: items[i],
                      asWorker: asWorker,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestDetailsScreen(requestId: items[i].id))),
                    ),
                  );
            return TabBarView(children: [list(active), list(past)]);
          },
        ),
      ),
    );
  }
}
