import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/request_repo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/services/backend.dart';
import '../../data/session.dart';
import 'chat_screen.dart';
import 'report_screen.dart';

class RequestDetailsScreen extends StatefulWidget {
  final String requestId;
  const RequestDetailsScreen({super.key, required this.requestId});
  @override
  State<RequestDetailsScreen> createState() => _RequestDetailsScreenState();
}

class _RequestDetailsScreenState extends State<RequestDetailsScreen> {
  String? _busyAction;
  ServiceRequest? _r;

  Future<void> _act(String action, [Map<String, dynamic>? payload]) async {
    final r = _r;
    final s = context.read<Session>();
    if (r == null || s.user == null) return;
    setState(() => _busyAction = action);
    try {
      await Backend.instance.requestAction(r, action, me: s.user!, myWorker: s.worker, payload: payload ?? const {});
      if (mounted) showSnack(context, context.t('done'));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _launch(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      showSnack(context, context.t('error_generic'), error: true);
    }
  }

  // ---------------------------------------------------------------- dialogs
  Future<void> _proposeTime() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      helpText: context.t('pick_time_title'),
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
    if (t == null) return;
    final at = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    if (at.isBefore(DateTime.now())) {
      if (mounted) showSnack(context, context.isAr ? 'اختار موعد في المستقبل' : 'Choose a future time', error: true);
      return;
    }
    await _act('propose_time', {'proposedAt': at});
  }

  Future<void> _setPrice(ServiceRequest r) async {
    final rate = context.read<CatalogRepo>().commissionPercent;
    final ctrl = TextEditingController(text: r.agreedPrice == null ? '' : r.agreedPrice!.toStringAsFixed(0));
    final price = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.t('price_enter_title')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(hintText: context.t('price_enter_hint'), suffixText: context.t('egp')),
          ),
          const SizedBox(height: 12),
          InfoBox(context.t('price_note', {'rate': rate})),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(context.t('cancel'))),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              if (v == null || v <= 0) return;
              Navigator.pop(c, v);
            },
            child: Text(context.t('save')),
          ),
        ],
      ),
    );
    if (price != null) await _act('set_price', {'price': price});
  }

  Future<void> _confirmPrice(ServiceRequest r) async {
    final ok = await confirmDialog(context, context.t('confirm_price_q', {'price': Fmt.money(r.agreedPrice, context.lang)}),
        okText: context.t('action_confirm_price'));
    if (ok) await _act('confirm_price');
  }

  Future<void> _cancel({required bool asWorker, String? presetReason}) async {
    final reasons = asWorker
        ? ['not_available', 'too_far', 'not_my_service', 'customer_unreachable', 'price_disagreement', 'other']
        : ['found_other', 'no_longer_needed', 'worker_late', 'price_disagreement', 'wrong_request', 'proposal_declined', 'other'];
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CancelSheet(reasons: reasons, preset: presetReason),
    );
    if (result != null) await _act('cancel', result);
  }

  Future<void> _review(ServiceRequest r, bool asCustomer) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReviewSheet(
        request: r,
        name: asCustomer ? (r.workerName ?? '') : r.customerName,
        commentRequired: asCustomer,
      ),
    );
    if (ok == true && mounted) showSnack(context, context.t('rate_thanks'));
  }

  void _share(ServiceRequest r) {
    Share.share(context.t('share_request_text', {
      'service': context.loc(r.displayService),
      'code': r.code,
      'worker': r.workerName ?? '-',
      'time': Fmt.dateTime(r.scheduledAt, context.lang),
      'status': context.t('status_${r.status}'),
    }));
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final uid = session.uid!;
    final lang = context.lang;
    return StreamBuilder<ServiceRequest?>(
      stream: RequestRepo.instance.watch(widget.requestId),
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(appBar: AppBar(), body: ErrorView(message: friendlyError(context, snap.error!)));
        if (!snap.hasData) return Scaffold(appBar: AppBar(), body: const LoadingView());
        final r = snap.data!;
        _r = r;
        final isCustomer = r.customerId == uid;
        final isAssignedWorker = r.workerId == uid;
        final isOpenForMe = !isCustomer && r.workerId == null && r.open && session.isWorker;
        final asWorker = isAssignedWorker || isOpenForMe;

        return Scaffold(
          appBar: AppBar(
            title: Text(context.t('request_no', {'code': r.code})),
            actions: [
              IconButton(tooltip: context.t('action_share'), icon: const Icon(Icons.share_outlined), onPressed: () => _share(r)),
              if (isCustomer || isAssignedWorker)
                IconButton(
                  tooltip: context.t('action_report'),
                  icon: const Icon(Icons.flag_outlined),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportScreen(requestId: r.id))),
                ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
            // ---- الرأس
            Row(children: [
              if (r.isEmergency) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.emergency, borderRadius: BorderRadius.circular(14)),
                  child: Text('🚨 ${context.t('emergency_tag')}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(context.loc(r.displayService), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
              StatusChip(r.status),
            ]),
            if (r.customerReviewed || r.workerReviewed) ...[
              const SizedBox(height: 6),
              Text('⭐ ${context.t('status_reviewed')}', style: const TextStyle(color: AppColors.muted)),
            ],
            const SizedBox(height: 12),

            // ---- الطرف الآخر
            _PartyCard(r: r, isCustomer: isCustomer, onLaunch: _launch),
            const SizedBox(height: 12),

            // ---- التفاصيل
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _line(Icons.schedule, context.t('scheduled_for', {'time': Fmt.dateTime(r.scheduledAt, lang)})),
                  if (r.status == 'proposed' && r.proposedAt != null)
                    _line(Icons.update, context.t('proposed_time', {'time': Fmt.dateTime(r.proposedAt, lang)}), color: AppColors.warning),
                  if (r.description.isNotEmpty) _line(Icons.description_outlined, r.description),
                  InkWell(
                    onTap: () => _launch(Uri.parse('https://www.google.com/maps/search/?api=1&query=${r.lat},${r.lng}')),
                    child: _line(Icons.location_on_outlined, '${r.address.isEmpty ? context.t('service_location') : r.address} • ${context.t('open_in_maps')}',
                        color: AppColors.navy),
                  ),
                  if (r.images.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 84,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: r.images.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => openImageViewer(context, r.images[i]),
                          child: NetImage(url: r.images[i], width: 84, height: 84),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),

            // ---- المال
            if (r.agreedPrice != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    _money(context.t('agreed_price'), r.agreedPrice),
                    if (asWorker && r.commissionAmount != null)
                      _money(context.t('commission', {'rate': ((r.commissionRate ?? 0) * 100).toStringAsFixed(0)}), r.commissionAmount),
                    if (r.status == 'price_set')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: InfoBox(isCustomer ? context.t('confirm_price_q', {'price': Fmt.money(r.agreedPrice, lang)}) : context.t('price_waiting_customer'),
                            color: AppColors.warning, icon: Icons.hourglass_top),
                      ),
                  ]),
                ),
              ),
            ],

            // ---- الإجراءات
            const SizedBox(height: 16),
            ..._actions(r, isCustomer: isCustomer, isAssignedWorker: isAssignedWorker, isOpenForMe: isOpenForMe),

            // ---- الشات
            if (r.workerId != null && (isCustomer || isAssignedWorker)) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(requestId: r.id))),
                icon: Badge(isLabelVisible: r.unreadFor(uid) > 0, label: Text('${r.unreadFor(uid)}'), child: const Icon(Icons.chat_bubble_outline)),
                label: Text(context.t('chat')),
              ),
            ],

            // ---- السجل
            SectionTitle(context.t('timeline')),
            StreamBuilder<List<HistoryEntry>>(
              stream: RequestRepo.instance.history(r.id),
              builder: (context, h) {
                final items = h.data ?? [];
                return Column(children: [
                  for (var i = 0; i < items.length; i++) _TimelineTile(e: items[i], last: i == items.length - 1),
                ]);
              },
            ),
            if (r.status == 'cancelled' && r.cancelReason != null)
              InfoBox(
                '${context.t('cancel_reason')}: ${context.t('reason_${r.cancelReason}')}${(r.cancelNote ?? '').isNotEmpty ? ' — ${r.cancelNote}' : ''} (${context.t('by_${r.cancelledBy ?? 'customer'}')})',
                color: AppColors.emergency,
              ),
          ]),
        );
      },
    );
  }

  List<Widget> _actions(ServiceRequest r, {required bool isCustomer, required bool isAssignedWorker, required bool isOpenForMe}) {
    final w = <Widget>[];
    Widget primary(String action, String label, VoidCallback onTap, {Color? color, IconData? icon}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: BusyButton(label: label, busy: _busyAction == action, color: color, icon: icon, onPressed: () async => onTap()),
        );
    Widget secondary(String label, VoidCallback onTap, {Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton(
            style: color == null ? null : OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color)),
            onPressed: _busyAction != null ? null : onTap,
            child: Text(label),
          ),
        );

    if (isOpenForMe && r.status == 'new') {
      w.add(primary('accept', context.t('action_accept'), () => _act('accept'), color: AppColors.success, icon: Icons.check));
      return w;
    }

    if (isAssignedWorker) {
      switch (r.status) {
        case 'new':
          w.add(primary('accept', context.t('action_accept'), () => _act('accept'), color: AppColors.success, icon: Icons.check));
          w.add(secondary(context.t('action_propose_time'), _proposeTime));
          w.add(secondary(context.t('action_reject'), () async {
            if (await confirmDialog(context, '${context.t('action_reject')}?', danger: true)) _act('reject');
          }, color: AppColors.emergency));
        case 'accepted':
        case 'confirmed':
          w.add(primary('on_the_way', context.t('action_on_the_way'), () => _act('on_the_way'), icon: Icons.directions_car));
          w.add(secondary(context.t('action_start'), () => _act('start')));
          w.add(secondary(context.t('action_propose_time'), _proposeTime));
        case 'proposed':
          w.add(InfoBox(context.t('proposed_time', {'time': Fmt.dateTime(r.proposedAt, context.lang)}), icon: Icons.hourglass_top));
          w.add(const SizedBox(height: 10));
        case 'on_the_way':
          w.add(primary('start', context.t('action_start'), () => _act('start'), icon: Icons.build));
        case 'started':
          w.add(primary('complete', context.t('action_complete'), () => _act('complete'), color: AppColors.success, icon: Icons.task_alt));
        case 'completed':
          w.add(primary('set_price', context.t('action_set_price'), () => _setPrice(r), icon: Icons.payments_outlined));
        case 'price_set':
          w.add(secondary(context.t('action_edit_price'), () => _setPrice(r)));
      }
      if (r.isCancellable) w.add(secondary(context.t('action_cancel'), () => _cancel(asWorker: true), color: AppColors.emergency));
      if (r.isReviewable && !r.workerReviewed) {
        w.add(primary('review', '⭐ ${context.t('action_rate')} ${r.customerName}', () => _review(r, false)));
      }
    }

    if (isCustomer) {
      switch (r.status) {
        case 'new':
          if (r.open) w.add(InfoBox(r.notifiedWorkerIds.isEmpty ? context.t('waiting_workers') : context.t('notified_workers'), icon: Icons.campaign_outlined));
          if (r.open) w.add(const SizedBox(height: 10));
        case 'proposed':
          w.add(primary('accept_proposal', context.t('action_accept_proposal'), () => _act('accept_proposal'), color: AppColors.success, icon: Icons.check));
          w.add(secondary(context.t('action_decline_proposal'), () => _cancel(asWorker: false, presetReason: 'proposal_declined'), color: AppColors.emergency));
        case 'price_set':
          w.add(primary('confirm_price', context.t('action_confirm_price'), () => _confirmPrice(r), color: AppColors.success, icon: Icons.check_circle_outline));
          w.add(secondary(context.t('action_dispute_price'), () => _act('dispute_price')));
      }
      if (r.isCancellable && r.status != 'proposed') {
        w.add(secondary(context.t('action_cancel'), () => _cancel(asWorker: false), color: AppColors.emergency));
      }
      if (r.isReviewable && !r.customerReviewed && r.workerId != null) {
        w.add(primary('review', '⭐ ${context.t('action_rate')} ${r.workerName ?? ''}', () => _review(r, true), color: AppColors.amber));
      }
    }
    return w;
  }

  Widget _line(IconData icon, String text, {Color color = AppColors.text}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 19, color: color == AppColors.text ? AppColors.muted : color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, height: 1.35))),
        ]),
      );

  Widget _money(String label, double? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
          Text('${Fmt.money(v, context.lang)} ${context.t('egp')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      );
}

class _PartyCard extends StatelessWidget {
  final ServiceRequest r;
  final bool isCustomer;
  final Future<void> Function(Uri) onLaunch;
  const _PartyCard({required this.r, required this.isCustomer, required this.onLaunch});

  @override
  Widget build(BuildContext context) {
    final name = isCustomer ? (r.workerName ?? context.t('waiting_workers')) : r.customerName;
    if (!isCustomer && !['new', 'rejected'].contains(r.status)) {
      // رقم العميل بيظهر للصنايعي بعد قبول الطلب فقط (القواعد بتمنعه قبل كده)
      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.doc('requests/${r.id}/private/contact').get(),
        builder: (context, snap) {
          final p = snap.data?.data()?['customerPhone'] as String?;
          return _card(context, name, p, p);
        },
      );
    }
    final phone = isCustomer ? r.workerPhone : null;
    final wa = isCustomer ? (r.workerWhatsapp ?? r.workerPhone) : null;
    return _card(context, name, phone, wa);
  }

  Widget _card(BuildContext context, String name, String? phone, String? wa) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Avatar(url: isCustomer ? r.workerPhotoUrl : '', name: name, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isCustomer ? context.t('worker') : context.t('customer'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              if (phone == null && !(isCustomer && r.workerId == null))
                Text(context.t('contact_hidden'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
          if (phone != null && phone.isNotEmpty) ...[
            IconButton.filledTonal(onPressed: () => onLaunch(Uri.parse('tel:$phone')), icon: const Icon(Icons.call)),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              onPressed: () => onLaunch(Uri.parse(Fmt.whatsappLink(wa ?? phone))),
              icon: const Icon(Icons.chat, color: Color(0xFF15803D)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final HistoryEntry e;
  final bool last;
  const _TimelineTile({required this.e, required this.last});
  @override
  Widget build(BuildContext context) {
    final label = e.action == 'review'
        ? '⭐ ${context.t('status_reviewed')} ${e.note}'
        : context.t('status_${e.to}');
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          Container(width: 12, height: 12, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: statusColor(e.to), shape: BoxShape.circle)),
          if (!last) Expanded(child: Container(width: 2, color: AppColors.border)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${context.t('by_${e.by}')} • ${Fmt.dateTime(e.at, context.lang)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              if (e.action == 'set_price' && e.note.isNotEmpty) Text('${e.note} ${context.t('egp')}', style: const TextStyle(fontSize: 12.5)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _CancelSheet extends StatefulWidget {
  final List<String> reasons;
  final String? preset;
  const _CancelSheet({required this.reasons, this.preset});
  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  late String? _reason = widget.preset;
  final _note = TextEditingController();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(context.t('cancel_reason'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final r in widget.reasons)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                onTap: () => setState(() => _reason = r),
                leading: Icon(_reason == r ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: AppColors.navy),
                title: Text(context.t('reason_$r')),
              ),
            TextField(controller: _note, maxLength: 300, decoration: InputDecoration(labelText: context.t('cancel_note'))),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.emergency),
              onPressed: _reason == null
                  ? null
                  : () {
                      if (_reason == 'other' && _note.text.trim().length < 3) {
                        showSnack(context, context.t('cancel_note_required'), error: true);
                        return;
                      }
                      Navigator.pop(context, {'reason': _reason!, 'note': _note.text.trim()});
                    },
              child: Text(context.t('action_cancel')),
            ),
          ]),
        ),
      );
}

/// التقييم: نجوم + تعليق
class ReviewSheet extends StatefulWidget {
  final ServiceRequest request;
  final String name;
  final bool commentRequired;
  const ReviewSheet({super.key, required this.request, required this.name, required this.commentRequired});
  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  int _stars = 0;
  final _comment = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    if (_stars == 0) {
      showSnack(context, context.t('rate_stars_required'), error: true);
      return;
    }
    if (widget.commentRequired && _comment.text.trim().length < 2) {
      showSnack(context, '${context.t('rate_comment')}: ${context.t('required')}', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await Backend.instance.submitReview(widget.request, me: context.read<Session>().user!, stars: _stars, comment: _comment.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(context.t('rate_title', {'name': widget.name}), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                iconSize: 40,
                onPressed: () => setState(() => _stars = i),
                icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.amber),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _comment,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(labelText: widget.commentRequired ? context.t('rate_comment') : context.t('rate_comment_optional')),
          ),
          const SizedBox(height: 8),
          BusyButton(label: context.t('rate_submit'), busy: _busy, onPressed: _submit),
        ]),
      );
}
