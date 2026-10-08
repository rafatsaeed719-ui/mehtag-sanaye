import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repos/catalog_repo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/services/backend.dart';
import '../../data/services/media_service.dart';
import '../../data/session.dart';
import '../shared/location_picker.dart';

/// تسجيل بيانات الصنايعي (أو تعديلها وإعادة التقديم بعد الرفض)
class WorkerApplicationScreen extends StatefulWidget {
  final Worker? existing;
  final bool embedded;
  const WorkerApplicationScreen({super.key, this.existing, this.embedded = false});
  @override
  State<WorkerApplicationScreen> createState() => _WorkerApplicationScreenState();
}

class _WorkerApplicationScreenState extends State<WorkerApplicationScreen> {
  int _step = 0;
  bool _busy = false;

  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _fee = TextEditingController();
  final _whatsapp = TextEditingController();
  final _call = TextEditingController();
  final _city = TextEditingController();
  final _area = TextEditingController();
  final _idNumber = TextEditingController();

  String? _photoUrl;
  File? _photoFile;
  final Set<String> _cats = {};
  final Set<String> _svcs = {};
  String? _gov;
  PickedLocation? _loc;
  final List<String> _workUrls = [];
  final List<File> _workFiles = [];
  File? _idFront, _idBack;

  @override
  void initState() {
    super.initState();
    final s = context.read<Session>();
    final w = widget.existing ?? s.worker;
    _name.text = w?.name ?? s.user?.name ?? '';
    _whatsapp.text = w?.whatsapp ?? s.user?.phone ?? '';
    _call.text = w?.callPhone ?? s.user?.phone ?? '';
    if (w != null) {
      _bio.text = w.bio;
      _fee.text = w.visitFee == null ? '' : w.visitFee!.toStringAsFixed(0);
      _city.text = w.city;
      _area.text = w.area;
      _photoUrl = w.photoUrl.isEmpty ? null : w.photoUrl;
      _cats.addAll(w.categoryIds);
      _svcs.addAll(w.serviceIds);
      _gov = w.governorate.isEmpty ? null : w.governorate;
      if (w.lat != 0) _loc = PickedLocation(lat: w.lat, lng: w.lng, label: context.t('location_set'));
      _workUrls.addAll(w.workImages);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _bio, _fee, _whatsapp, _call, _city, _area, _idNumber]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<File?> _pickOne() async {
    final cam = await pickSourceSheet(context);
    if (cam == null) return null;
    return MediaService.instance.pick(camera: cam);
  }

  bool _validateStep(int step) {
    String? err;
    switch (step) {
      case 0:
        if (_name.text.trim().length < 2) err = '${context.t('your_name')}: ${context.t('required')}';
        if (_whatsapp.text.isNotEmpty && !Fmt.isEgMobile(_whatsapp.text)) err = '${context.t('whatsapp_number')}: ${context.t('invalid_phone')}';
        if (_call.text.isNotEmpty && !Fmt.isEgMobile(_call.text)) err = '${context.t('call_number')}: ${context.t('invalid_phone')}';
      case 1:
        if (_cats.isEmpty) err = context.t('choose_category_first');
      case 2:
        if (_gov == null) err = '${context.t('governorate')}: ${context.t('required')}';
        if (_city.text.trim().isEmpty) err = '${context.t('city')}: ${context.t('required')}';
        if (_loc == null) err = context.t('location_required');
      case 3:
        final id = _idNumber.text.trim();
        if (id.isNotEmpty && !RegExp(r'^[23][0-9]{13}$').hasMatch(id)) {
          err = context.isAr ? 'الرقم القومي لازم يكون 14 رقم' : 'National ID must be 14 digits';
        }
        if (id.isNotEmpty && _idFront == null) err = context.t('id_front');
        if (id.isEmpty && _idFront != null) err = context.t('national_id_number');
    }
    if (err != null) showSnack(context, err, error: true);
    return err == null;
  }

  Future<void> _submit() async {
    for (var i = 0; i < 4; i++) {
      if (!_validateStep(i)) {
        setState(() => _step = i);
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final session = context.read<Session>();
      final catalog = context.read<CatalogRepo>();
      final me = session.user!;
      final uid = me.uid;
      final st = MediaService.instance;
      if (_photoFile != null) _photoUrl = await st.upload(_photoFile!, ownerId: uid, kind: 'public');
      for (final f in _workFiles) {
        _workUrls.add(await st.upload(f, ownerId: uid, kind: 'public'));
      }
      _workFiles.clear();
      String? front, back;
      if (_idFront != null) front = await st.upload(_idFront!, ownerId: uid, kind: 'id');
      if (_idBack != null) back = await st.upload(_idBack!, ownerId: uid, kind: 'id');
      final cats = catalog.categories.where((c) => _cats.contains(c.id)).toList();
      final svcs = catalog.services.where((x) => _svcs.contains(x.id)).toList();

      await Backend.instance.submitWorkerApplication(
        user: me,
        existing: session.worker,
        profile: {
          'name': _name.text.trim(),
          'photoUrl': _photoUrl ?? '',
          'categoryIds': cats.map((c) => c.id).toList(),
          'serviceIds': svcs.map((x) => x.id).toList(),
          'categoryNames': cats.map((c) => <String, dynamic>{'ar': c.nameAr, 'en': c.nameEn}).toList(),
          'serviceNames': svcs.map((x) => <String, dynamic>{'ar': x.nameAr, 'en': x.nameEn}).toList(),
          'governorate': _gov,
          'city': _city.text.trim(),
          'area': _area.text.trim(),
          'lat': _loc!.lat,
          'lng': _loc!.lng,
          'bio': _bio.text.trim(),
          'visitFee': _fee.text.trim().isEmpty ? null : double.tryParse(_fee.text.trim()),
          'whatsapp': Fmt.normalizePhone(_whatsapp.text.isEmpty ? me.phone : _whatsapp.text),
          'callPhone': Fmt.normalizePhone(_call.text.isEmpty ? me.phone : _call.text),
          'workImages': _workUrls.take(8).toList(),
        },
        nationalId: _idNumber.text.trim().isEmpty ? null : _idNumber.text.trim(),
        idFrontRef: front,
        idBackRef: back,
      );
      if (!mounted) return;
      showSnack(context, context.t('application_sent'));
      if (!widget.embedded && Navigator.canPop(context)) Navigator.pop(context);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      // أغلب أسباب الرفض: الرقم القومي مسجل لصنايعي تاني
      showSnack(context, e.code == 'permission-denied' && _idNumber.text.trim().isNotEmpty ? context.t('national_id_in_use') : context.t('error_generic'), error: true);
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
    final services = catalog.servicesOfMany(_cats.toList());

    final steps = [
      Step(
        title: Text(context.t('step_basic')),
        isActive: _step >= 0,
        content: Column(children: [
          GestureDetector(
            onTap: () async {
              final f = await _pickOne();
              if (f != null) setState(() => _photoFile = f);
            },
            child: Stack(children: [
              _photoFile != null
                  ? ClipOval(child: Image.file(_photoFile!, width: 96, height: 96, fit: BoxFit.cover))
                  : Avatar(url: _photoUrl ?? '', name: _name.text, size: 96),
              const PositionedDirectional(bottom: 0, end: 0, child: CircleAvatar(radius: 15, child: Icon(Icons.camera_alt, size: 15))),
            ]),
          ),
          const SizedBox(height: 4),
          Text(context.t('profile_photo'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(controller: _name, maxLength: 60, decoration: InputDecoration(labelText: context.t('your_name'))),
          TextField(
            controller: _whatsapp,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: context.t('whatsapp_number'), prefixIcon: const Icon(Icons.chat_outlined)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _call,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: context.t('call_number'), prefixIcon: const Icon(Icons.call_outlined)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fee,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: '${context.t('visit_fee')} (${context.t('optional')})', suffixText: context.t('egp')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bio,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(labelText: context.t('bio'), hintText: context.t('bio_hint'), alignLabelWithHint: true),
          ),
        ]),
      ),
      Step(
        title: Text(context.t('step_work')),
        isActive: _step >= 1,
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('professions'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in catalog.categories)
              FilterChip(
                avatar: CategoryIcon(category: c, size: 18),
                label: Text(c.name(lang)),
                selected: _cats.contains(c.id),
                onSelected: (v) => setState(() {
                  if (v) {
                    if (_cats.length < 5) _cats.add(c.id);
                  } else {
                    _cats.remove(c.id);
                    _svcs.removeWhere((s) => catalog.services.any((x) => x.id == s && x.categoryId == c.id));
                  }
                }),
              ),
          ]),
          if (services.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(context.t('choose_services'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in services)
                FilterChip(
                  label: Text(s.name(lang)),
                  selected: _svcs.contains(s.id),
                  onSelected: (v) => setState(() => v ? _svcs.add(s.id) : _svcs.remove(s.id)),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          Text(context.t('work_photos'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < _workUrls.length; i++)
              _thumb(NetImage(url: _workUrls[i], width: 80, height: 80, radius: 10), () => setState(() => _workUrls.removeAt(i))),
            for (var i = 0; i < _workFiles.length; i++)
              _thumb(ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(_workFiles[i], width: 80, height: 80, fit: BoxFit.cover)),
                  () => setState(() => _workFiles.removeAt(i))),
            if (_workUrls.length + _workFiles.length < 8)
              InkWell(
                onTap: () async {
                  final fs = await MediaService.instance.pickMany(max: 8 - _workUrls.length - _workFiles.length);
                  setState(() => _workFiles.addAll(fs));
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10), color: Colors.white),
                  child: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.navy),
                ),
              ),
          ]),
        ]),
      ),
      Step(
        title: Text(context.t('step_location')),
        isActive: _step >= 2,
        content: Column(children: [
          DropdownButtonFormField<String>(
            value: _gov,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.t('governorate')),
            items: catalog.governorates.map((g) => DropdownMenuItem(value: g.code, child: Text(g.name(lang)))).toList(),
            onChanged: (v) => setState(() => _gov = v),
          ),
          const SizedBox(height: 12),
          TextField(controller: _city, decoration: InputDecoration(labelText: context.t('city'))),
          const SizedBox(height: 12),
          TextField(controller: _area, decoration: InputDecoration(labelText: '${context.t('area')} (${context.t('optional')})')),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(_loc == null ? Icons.location_off_outlined : Icons.location_on, color: _loc == null ? AppColors.muted : AppColors.success),
              title: Text(_loc == null ? context.t('my_location_on_map') : context.t('location_set')),
              subtitle: _loc == null ? Text(context.t('location_required')) : Text('${_loc!.lat.toStringAsFixed(5)}, ${_loc!.lng.toStringAsFixed(5)}'),
              trailing: const Icon(Icons.edit_location_alt_outlined),
              onTap: () async {
                final p = await Navigator.push<PickedLocation>(
                  context,
                  MaterialPageRoute(builder: (_) => MapPickerScreen(initial: _loc, title: context.t('my_location_on_map'))),
                );
                if (p != null) setState(() => _loc = p);
              },
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final p = await getGpsLocation(context);
              if (p != null) setState(() => _loc = p);
            },
            icon: const Icon(Icons.my_location),
            label: Text(context.t('use_current_location')),
          ),
        ]),
      ),
      Step(
        title: Text('${context.t('step_id')} (${context.t('optional')})'),
        isActive: _step >= 3,
        content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InfoBox(context.t('id_privacy_note'), icon: Icons.lock_outline, color: AppColors.success),
          const SizedBox(height: 8),
          InfoBox(context.t('id_optional_note')),
          const SizedBox(height: 12),
          TextField(
            controller: _idNumber,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)],
            decoration: InputDecoration(labelText: context.t('national_id_number')),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _idPicker(context.t('id_front'), _idFront, (f) => setState(() => _idFront = f))),
            const SizedBox(width: 10),
            Expanded(child: _idPicker(context.t('id_back'), _idBack, (f) => setState(() => _idBack = f))),
          ]),
          if (widget.existing?.hasIdDoc == true && _idFront == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.isAr ? '✓ تم رفع البطاقة من قبل' : '✓ ID already uploaded', style: const TextStyle(color: AppColors.success)),
            ),
        ]),
      ),
    ];

    final body = Stepper(
      currentStep: _step,
      onStepTapped: (i) => setState(() => _step = i),
      onStepContinue: () {
        if (!_validateStep(_step)) return;
        if (_step < steps.length - 1) {
          setState(() => _step++);
        } else {
          _submit();
        }
      },
      onStepCancel: _step == 0 ? null : () => setState(() => _step--),
      controlsBuilder: (context, details) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(children: [
          Expanded(
            child: BusyButton(
              label: _step == steps.length - 1 ? context.t('submit_application') : context.t('next'),
              busy: _busy,
              onPressed: () async => details.onStepContinue?.call(),
            ),
          ),
          if (_step > 0) ...[
            const SizedBox(width: 10),
            TextButton(onPressed: details.onStepCancel, child: Text(context.t('back'))),
          ],
        ]),
      ),
      steps: steps,
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: Text(context.t('worker_application'))), body: body);
  }

  Widget _thumb(Widget child, VoidCallback onRemove) => Stack(children: [
        child,
        PositionedDirectional(
          top: 2,
          end: 2,
          child: InkWell(onTap: onRemove, child: const CircleAvatar(radius: 11, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 13, color: Colors.white))),
        ),
      ]);

  Widget _idPicker(String label, File? file, ValueChanged<File> onPicked) => InkWell(
        onTap: () async {
          final f = await _pickOne();
          if (f != null) onPicked(f);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 110,
          decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12), color: Colors.white),
          clipBehavior: Clip.antiAlias,
          child: file != null
              ? Image.file(file, fit: BoxFit.cover)
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.badge_outlined, color: AppColors.navy, size: 32),
                  const SizedBox(height: 6),
                  Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5)),
                ]),
        ),
      );
}
