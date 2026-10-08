import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// شات مرتبط بالطلب: نص + صور + موقع الخدمة
class ChatScreen extends StatefulWidget {
  final String requestId;
  const ChatScreen({super.key, required this.requestId});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  bool _sending = false;
  ServiceRequest? _r;
  late final String _uid = context.read<Session>().uid!;

  @override
  void initState() {
    super.initState();
    Backend.instance.markChatRead(widget.requestId, _uid);
  }

  @override
  void dispose() {
    Backend.instance.markChatRead(widget.requestId, _uid);
    _text.dispose();
    super.dispose();
  }

  Future<void> _send({String? text, String? imagePath, double? lat, double? lng}) async {
    final r = _r;
    if (r == null) return;
    setState(() => _sending = true);
    try {
      await Backend.instance.sendMessage(r, _uid, text: text, imageRef: imagePath, lat: lat, lng: lng);
      _text.clear();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    final camera = await pickSourceSheet(context);
    if (camera == null) return;
    final f = await MediaService.instance.pick(camera: camera);
    if (f == null) return;
    setState(() => _sending = true);
    try {
      final path = await MediaService.instance.upload(f, ownerId: _uid, kind: 'chat', requestId: widget.requestId);
      await _send(imagePath: path);
    } catch (e) {
      if (mounted) showError(context, e);
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<Session>().uid!;
    return StreamBuilder<ServiceRequest?>(
      stream: RequestRepo.instance.watch(widget.requestId),
      builder: (context, rs) {
        final r = rs.data;
        _r = r;
        final otherName = r == null ? '' : (r.customerId == uid ? (r.workerName ?? '') : r.customerName);
        final canChat = r != null && r.workerId != null;
        return Scaffold(
          appBar: AppBar(title: Text(context.t('chat_with', {'name': otherName}))),
          body: Column(children: [
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: RequestRepo.instance.messages(widget.requestId),
                builder: (context, snap) {
                  if (snap.hasError) return ErrorView(message: friendlyError(context, snap.error!));
                  if (!snap.hasData) return const LoadingView();
                  final msgs = snap.data!;
                  if (msgs.isEmpty) return EmptyView(text: context.t('type_message'), icon: Icons.chat_bubble_outline);
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) => _Bubble(m: msgs[i], mine: msgs[i].senderId == uid),
                  );
                },
              ),
            ),
            if (!canChat)
              Padding(padding: const EdgeInsets.all(16), child: InfoBox(context.t('chat_not_available')))
            else
              SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
                  child: Row(children: [
                    IconButton(tooltip: context.t('send_image'), onPressed: _sending ? null : _sendImage, icon: const Icon(Icons.image_outlined)),
                    IconButton(
                      tooltip: context.t('send_location'),
                      onPressed: _sending ? null : () => _send(lat: r!.lat, lng: r.lng),
                      icon: const Icon(Icons.location_on_outlined),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(hintText: context.t('type_message'), counterText: '', isDense: true),
                      ),
                    ),
                    IconButton(
                      onPressed: _sending
                          ? null
                          : () {
                              final t = _text.text.trim();
                              if (t.isNotEmpty) _send(text: t);
                            },
                      icon: _sending
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded, color: AppColors.navy),
                    ),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage m;
  final bool mine;
  const _Bubble({required this.m, required this.mine});

  @override
  Widget build(BuildContext context) {
    Widget content;
    switch (m.type) {
      case 'image':
        content = GestureDetector(onTap: () => openImageViewer(context, m.imagePath), child: NetImage(url: m.imagePath, width: 200, height: 200));
      case 'location':
        content = InkWell(
          onTap: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${m.lat},${m.lng}'), mode: LaunchMode.externalApplication),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(context.t('location_message'), style: TextStyle(color: mine ? Colors.white : AppColors.navy, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Icon(Icons.open_in_new, size: 16, color: mine ? Colors.white : AppColors.navy),
          ]),
        );
      default:
        content = Text(m.text, style: TextStyle(color: mine ? Colors.white : AppColors.text, fontSize: 15));
    }
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: mine ? null : Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          content,
          const SizedBox(height: 2),
          Text(m.createdAt == null ? '…' : Fmt.relative(m.createdAt, context.lang),
              style: TextStyle(fontSize: 10.5, color: mine ? Colors.white70 : AppColors.muted)),
        ]),
      ),
    );
  }
}
