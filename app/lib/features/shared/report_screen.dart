import 'package:image_picker/image_picker.dart' show XFile;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repos/request_repo.dart';
import '../../data/services/backend.dart';
import '../../data/services/media_service.dart';
import '../../data/session.dart';

const kReportTypes = ['no_show', 'bad_behavior', 'poor_quality', 'overcharge', 'fraud', 'harassment', 'fake_account', 'payment_issue', 'other'];

/// بلاغ/شكوى: نوع المشكلة + وصف + صور + رقم الطلب المرتبط
class ReportScreen extends StatefulWidget {
  final String? requestId;
  final String? againstId;
  const ReportScreen({super.key, this.requestId, this.againstId});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String? _type;
  final _desc = TextEditingController();
  final List<XFile> _images = [];
  bool _busy = false;

  Future<void> _submit() async {
    if (_type == null) {
      showSnack(context, '${context.t('report_type')}: ${context.t('required')}', error: true);
      return;
    }
    if (_desc.text.trim().length < 10) {
      showSnack(context, context.isAr ? 'اكتب وصف أوضح (10 حروف على الأقل)' : 'Please describe in more detail (10+ characters)', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final me = context.read<Session>().user!;
      final refs = <String>[];
      for (final f in _images) {
        refs.add(await MediaService.instance.upload(f, ownerId: me.uid, kind: 'report'));
      }
      final req = widget.requestId == null ? null : await RequestRepo.instance.watch(widget.requestId!).first;
      await Backend.instance.submitReport(
        me: me,
        type: _type!,
        description: _desc.text.trim(),
        images: refs,
        request: req,
        againstId: widget.againstId,
      );
      if (!mounted) return;
      showSnack(context, context.t('report_sent'));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.t('report_title'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(context.t('report_type'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in kReportTypes)
              ChoiceChip(label: Text(context.t('report_$t')), selected: _type == t, onSelected: (_) => setState(() => _type = t)),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _desc,
            maxLines: 5,
            maxLength: 2000,
            decoration: InputDecoration(labelText: context.t('report_desc'), alignLabelWithHint: true),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < _images.length; i++)
              Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: XImage(_images[i], width: 80, height: 80, fit: BoxFit.cover)),
                PositionedDirectional(
                  top: 2,
                  end: 2,
                  child: InkWell(
                    onTap: () => setState(() => _images.removeAt(i)),
                    child: const CircleAvatar(radius: 11, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 13, color: Colors.white)),
                  ),
                ),
              ]),
            if (_images.length < 3)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(80, 80)),
                onPressed: () async {
                  final cam = await pickSourceSheet(context);
                  if (cam == null) return;
                  final f = await MediaService.instance.pick(camera: cam);
                  if (f != null) setState(() => _images.add(f));
                },
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(context.t('add_photo')),
              ),
          ]),
          const SizedBox(height: 24),
          BusyButton(label: context.t('send'), busy: _busy, onPressed: _submit),
        ]),
      );
}

/// بلاغاتي وحالتها
class MyReportsScreen extends StatelessWidget {
  const MyReportsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = context.read<Session>().uid!;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('my_reports'))),
      body: StreamBuilder<List<ReportItem>>(
        stream: RequestRepo.instance.myReports(uid),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final list = snap.data!;
          if (list.isEmpty) return EmptyView(text: context.t('empty'), icon: Icons.flag_outlined);
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final r = list[i];
              return Card(
                child: ListTile(
                  title: Text(context.t('report_${r.type}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${r.description}\n${r.requestCode.isEmpty ? '' : '#${r.requestCode} • '}${Fmt.date(r.createdAt, context.lang)}',
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                  isThreeLine: true,
                  trailing: Text(context.t('report_status_${r.status}'), style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
