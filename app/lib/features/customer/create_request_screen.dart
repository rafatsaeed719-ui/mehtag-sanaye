import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/services/api.dart';
import '../../data/services/storage_service.dart';
import '../../data/session.dart';
import '../shared/location_picker.dart';
import '../shared/request_details_screen.dart';
import 'customer_location.dart';

/// إنشاء طلب خدمة: موجّه لصنايعي، أو مفتوح للقريبين، أو طوارئ
class CreateRequestScreen extends StatefulWidget {
  final Worker? worker;
  final String? categoryId;
  final bool emergency;
  const CreateRequestScreen({super.key, this.worker, this.categoryId, this.emergency = false});
  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  String? _categoryId;
  String? _serviceId;
  final _desc = TextEditingController();
  final List<File> _photos = [];
  PickedLocation? _location;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 2)));
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categoryId ?? (widget.worker != null && widget.worker!.categoryIds.length == 1 ? widget.worker!.categoryIds.first : null);
    _location = context.read<CustomerLocation>().current;
    final in2h = DateTime.now().add(const Duration(hours: 2));
    _date = DateTime(in2h.year, in2h.month, in2h.day);
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  List<JobCategory> _allowedCategories(CatalogRepo c) {
    if (widget.worker == null) return c.categories;
    return c.categories.where((x) => widget.worker!.categoryIds.contains(x.id)).toList();
  }

  List<Service> _allowedServices(CatalogRepo c) {
    final s = c.servicesOf(_categoryId);
    if (widget.worker == null || widget.worker!.serviceIds.isEmpty) return s;
    final mine = s.where((x) => widget.worker!.serviceIds.contains(x.id)).toList();
    return mine.isEmpty ? s : mine;
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 6) return;
    final camera = await pickSourceSheet(context);
    if (camera == null) return;
    if (camera) {
      final f = await StorageService.instance.pick(camera: true);
      if (f != null) setState(() => _photos.add(f));
    } else {
      final fs = await StorageService.instance.pickMany(max: 6 - _photos.length);
      setState(() => _photos.addAll(fs));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 60)));
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Future<void> _submit() async {
    if (_categoryId == null) {
      showSnack(context, context.t('choose_category_first'), error: true);
      return;
    }
    if (!widget.emergency && _desc.text.trim().length < 5) {
      showSnack(context, '${context.t('problem_desc')}: ${context.t('required')}', error: true);
      return;
    }
    if (_location == null) {
      showSnack(context, context.t('location_required'), error: true);
      return;
    }
    final scheduled = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    if (!widget.emergency && scheduled.isBefore(DateTime.now().subtract(const Duration(minutes: 5)))) {
      showSnack(context, context.isAr ? 'اختار موعد في المستقبل' : 'Choose a future time', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final uid = context.read<Session>().uid!;
      final urls = <String>[];
      for (final f in _photos) {
        urls.add(await StorageService.instance.uploadUrl(f, 'requestMedia/$uid'));
      }
      final res = await Api.instance.createRequest({
        'workerId': widget.worker?.id,
        'categoryId': _categoryId,
        'serviceId': _serviceId,
        'description': _desc.text.trim(),
        'images': urls,
        'lat': _location!.lat,
        'lng': _location!.lng,
        'address': _location!.label,
        'governorate': _location!.governorate,
        'scheduledAt': scheduled.millisecondsSinceEpoch,
        'isEmergency': widget.emergency,
      });
      if (!mounted) return;
      final n = (res['notifiedCount'] as num?)?.toInt() ?? 0;
      showSnack(
        context,
        widget.emergency ? (n > 0 ? context.t('emergency_sent', {'n': n}) : context.t('emergency_none')) : context.t('request_sent'),
      );
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RequestDetailsScreen(requestId: res['requestId'] as String)));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogRepo>();
    final lang = context.lang;
    final cats = _allowedCategories(catalog);
    final services = _allowedServices(catalog);
    final title = widget.emergency
        ? context.t('emergency_request')
        : widget.worker != null
            ? context.t('request_to', {'name': widget.worker!.name})
            : context.t('new_request');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: widget.emergency ? AppColors.emergency : null,
        foregroundColor: widget.emergency ? Colors.white : null,
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.emergency)
          InfoBox(context.t('emergency_note'), icon: Icons.campaign, color: AppColors.emergency)
        else if (widget.worker == null)
          InfoBox(context.t('open_request_note')),
        const SizedBox(height: 12),

        Text(context.t('filter_category'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in cats)
            ChoiceChip(
              avatar: CategoryIcon(category: c, size: 18),
              label: Text(c.name(lang)),
              selected: _categoryId == c.id,
              onSelected: (_) => setState(() {
                _categoryId = c.id;
                _serviceId = null;
              }),
            ),
        ]),
        if (_categoryId != null && services.isNotEmpty) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            value: _serviceId,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.t('choose_service_optional')),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text('—')),
              ...services.map((s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.name(lang)))),
            ],
            onChanged: (v) => setState(() => _serviceId = v),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _desc,
          maxLines: 4,
          maxLength: 1000,
          decoration: InputDecoration(
            labelText: '${context.t('problem_desc')}${widget.emergency ? ' (${context.t('optional')})' : ''}',
            hintText: context.t('problem_desc_hint'),
            alignLabelWithHint: true,
          ),
        ),
        Text(context.t('problem_photos'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SizedBox(
          height: 92,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < _photos.length; i++)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_photos[i], width: 92, height: 92, fit: BoxFit.cover)),
                  PositionedDirectional(
                    top: 2,
                    end: 2,
                    child: InkWell(
                      onTap: () => setState(() => _photos.removeAt(i)),
                      child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            if (_photos.length < 6)
              InkWell(
                onTap: _addPhoto,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12), color: Colors.white),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.add_a_photo_outlined, color: AppColors.navy),
                    const SizedBox(height: 4),
                    Text(context.t('add_photo'), style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        Text(context.t('service_location'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.location_on, color: AppColors.emergency),
            title: Text(_location == null ? context.t('location_unknown') : (_location!.label.isEmpty ? context.t('your_location') : _location!.label)),
            subtitle: Text(context.t('location_map')),
            trailing: const Icon(Icons.edit_location_alt_outlined),
            onTap: () async {
              final p = await showLocationChooser(context, current: _location);
              if (p != null) setState(() => _location = p);
            },
          ),
        ),
        if (!widget.emergency) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_today_outlined), label: Text(Fmt.date(_date, lang))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.access_time), label: Text(_time.format(context))),
            ),
          ]),
        ],
        const SizedBox(height: 24),
        BusyButton(
          label: widget.emergency ? context.t('emergency_btn') : context.t('submit_request'),
          busy: _busy,
          color: widget.emergency ? AppColors.emergency : null,
          onPressed: _submit,
        ),
      ]),
    );
  }
}
