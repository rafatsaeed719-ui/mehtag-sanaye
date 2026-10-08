import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/session.dart';
import '../auth/language_toggle.dart';
import '../shared/help_screen.dart';
import '../shared/notifications_screen.dart';
import 'worker_application_screen.dart';

/// الصنايعي قبل التوثيق: تسجيل البيانات ← قيد المراجعة ← (مرفوض: تعديل وإعادة التقديم)
class ApplicationStatusScreen extends StatelessWidget {
  const ApplicationStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final w = s.worker;

    final actions = [
      const LanguageToggle(),
      IconButton(
        icon: const Icon(Icons.notifications_outlined),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      ),
      PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'help') Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen()));
          if (v == 'logout') s.signOut();
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'help', child: Text(context.t('help_support'))),
          PopupMenuItem(value: 'logout', child: Text(context.t('logout'))),
        ],
      ),
    ];

    // لسه مسجلش بياناته
    if (w == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.t('worker_application')), actions: actions),
        body: Column(children: [
          Container(
            width: double.infinity,
            color: AppColors.amberSoft,
            padding: const EdgeInsets.all(12),
            child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 4, children: [
              Text(context.t('worker_step1')),
              Text(context.t('worker_step2')),
              Text(context.t('worker_step3')),
              Text(context.t('worker_step4')),
            ]),
          ),
          const Expanded(child: WorkerApplicationScreen(embedded: true)),
        ]),
      );
    }

    final rejected = w.verificationStatus == 'rejected';
    final suspended = w.suspended;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('app_name')), actions: actions),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 24),
        Icon(rejected || suspended ? Icons.error_outline : Icons.hourglass_top_rounded,
            size: 84, color: rejected || suspended ? AppColors.emergency : AppColors.amber),
        const SizedBox(height: 16),
        Text(
          suspended ? context.t('account_blocked') : (rejected ? context.t('status_rejected_title') : context.t('status_pending_title')),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Text(
          suspended
              ? context.t('account_blocked_sub')
              : (rejected ? context.t('status_rejected_sub', {'reason': w.rejectionReason}) : context.t('status_pending_sub')),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, height: 1.5),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Avatar(url: w.photoUrl, name: w.name, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(w.categoryNames.map((n) => context.loc(n)).join(' • '), style: const TextStyle(color: AppColors.muted)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        if (!suspended)
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerApplicationScreen(existing: w))),
            icon: const Icon(Icons.edit_outlined),
            label: Text(rejected ? context.t('edit_and_resubmit') : context.t('edit_profile')),
          ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen())),
          child: Text(context.t('help_support')),
        ),
      ]),
    );
  }
}
