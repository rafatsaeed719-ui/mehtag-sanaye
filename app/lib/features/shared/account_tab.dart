import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/common.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/services/media_service.dart';
import '../../data/session.dart';
import '../worker/wallet_screen.dart';
import '../worker/worker_edit_profile_screen.dart';
import 'help_screen.dart';
import 'notifications_screen.dart';
import 'report_screen.dart';
import 'stats_screen.dart';

class AccountTab extends StatelessWidget {
  const AccountTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final lc = context.watch<LocaleController>();
    final user = s.user;
    final isWorker = s.isWorker;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('my_account'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Avatar(url: isWorker ? (s.worker?.photoUrl ?? user?.photoUrl ?? '') : (user?.photoUrl ?? ''), name: user?.name ?? '', size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?.name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(user?.phone ?? '', textDirection: TextDirection.ltr, style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 4),
                  Text(isWorker ? '🔧 ${context.t('worker')}' : '👤 ${context.t('customer')}', style: const TextStyle(fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.t('edit_profile')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => isWorker ? const WorkerEditProfileScreen() : const CustomerEditProfileScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_rounded),
              title: Text(context.t('my_stats')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen())),
            ),
            if (isWorker)
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(context.t('wallet')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
              ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text(context.t('notifications')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(context.t('my_reports')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyReportsScreen())),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(context.t('language')),
              trailing: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 'ar', label: Text('عربي')), ButtonSegment(value: 'en', label: Text('EN'))],
                selected: {lc.lang},
                onSelectionChanged: (v) => lc.setLang(v.first),
              ),
            ),
            if (s.isOwnerEmail)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined, color: AppColors.navy),
                title: Text(context.t('admin_panel')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => s.switchToAdmin(),
              ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: Text(context.t('help_support')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(context.t('share_app')),
              onTap: () => Share.share(context.t('share_app_text', {'url': context.read<CatalogRepo>().playStoreUrl})),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.emergency),
              title: Text(context.t('logout'), style: const TextStyle(color: AppColors.emergency)),
              onTap: () async {
                if (await confirmDialog(context, context.t('logout_confirm'), danger: true)) {
                  await context.read<Session>().signOut();
                }
              },
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Center(child: Text(context.t('app_version', {'v': kAppVersion}), style: const TextStyle(color: AppColors.muted, fontSize: 12))),
      ]),
    );
  }
}

/// تعديل بيانات العميل: الاسم + الصورة
class CustomerEditProfileScreen extends StatefulWidget {
  const CustomerEditProfileScreen({super.key});
  @override
  State<CustomerEditProfileScreen> createState() => _CustomerEditProfileScreenState();
}

class _CustomerEditProfileScreenState extends State<CustomerEditProfileScreen> {
  late final _name = TextEditingController(text: context.read<Session>().user?.name ?? '');
  String? _photoUrl;
  bool _busy = false;

  Future<void> _pickPhoto() async {
    final cam = await pickSourceSheet(context);
    if (cam == null) return;
    final f = await MediaService.instance.pick(camera: cam, maxWidth: 400);
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final uid = context.read<Session>().uid!;
      final url = await MediaService.instance.upload(f, ownerId: uid, kind: 'public');
      setState(() => _photoUrl = url);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) return;
    setState(() => _busy = true);
    try {
      final uid = context.read<Session>().uid!;
      await FirebaseFirestore.instance.doc('users/$uid').update({
        'name': _name.text.trim(),
        if (_photoUrl != null) 'photoUrl': _photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      showSnack(context, context.t('saved'));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<Session>().user;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('edit_profile'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(
          child: GestureDetector(
            onTap: _busy ? null : _pickPhoto,
            child: Stack(children: [
              Avatar(url: _photoUrl ?? user?.photoUrl ?? '', name: _name.text, size: 100),
              const PositionedDirectional(bottom: 0, end: 0, child: CircleAvatar(radius: 16, child: Icon(Icons.camera_alt, size: 16))),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        TextField(controller: _name, maxLength: 60, decoration: InputDecoration(labelText: context.t('your_name'))),
        const SizedBox(height: 12),
        BusyButton(label: context.t('save'), busy: _busy, onPressed: _save),
      ]),
    );
  }
}
