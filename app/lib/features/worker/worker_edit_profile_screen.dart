import 'package:image_picker/image_picker.dart' show XFile;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/geo.dart';
import '../../core/widgets/common.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/services/backend.dart';
import '../../data/services/media_service.dart';
import '../../data/session.dart';
import '../shared/location_picker.dart';

/// تعديل بيانات الصنايعي الموثق:
///  - البيانات العادية (النبذة، الصور، السعر، الأرقام، الموقع، التوفر) → تُحفظ مباشرة
///  - البيانات الحساسة (الاسم، المهنة، الخدمات، الهوية) → تُرسل لمراجعة الإدارة
class WorkerEditProfileScreen extends StatefulWidget {
  const WorkerEditProfileScreen({super.key});
  @override
  State<WorkerEditProfileScreen> createState() => _WorkerEditProfileScreenState();
}

class _WorkerEditProfileScreenState extends State<WorkerEditProfileScreen> {
  late final _w = context.read<Session>().worker!;
  late final _bio = TextEditingController(text: _w.bio);
  late final _fee = TextEditingController(text: _w.visitFee?.toStringAsFixed(0) ?? '');
  late final _wa = TextEditingController(text: _w.whatsapp);
  late final _call = TextEditingController(text: _w.callPhone);
  late final _city = TextEditingController(text: _w.city);
  late final _area = TextEditingController(text: _w.area);
  late String _gov = _w.governorate;
  late PickedLocation _loc = PickedLocation(lat: _w.lat, lng: _w.lng);
  late final List<String> _works = List.of(_w.workImages);
  final List<XFile> _newWorks = [];
  String? _photoUrl;
  XFile? _photoFile;
  bool _busy = false;

  // حساسة
  late final _name = TextEditingController(text: _w.name);
  late final Set<String> _cats = _w.categoryIds.toSet();
  late final Set<String> _svcs = _w.serviceIds.toSet();
  final _idNumber = TextEditingController();
  XFile? _idFront, _idBack;

  Future<void> _saveRegular() async {
    if ((_wa.text.isNotEmpty && !Fmt.isEgMobile(_wa.text)) || (_call.text.isNotEmpty && !Fmt.isEgMobile(_call.text))) {
      showSnack(context, context.t('invalid_phone'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final uid = context.read<Session>().uid!;
      final st = MediaService.instance;
      if (_photoFile != null) _photoUrl = await st.upload(_photoFile!, ownerId: uid, kind: 'public');
      for (final f in _newWorks) {
        _works.add(await st.upload(f, ownerId: uid, kind: 'public'));
      }
      _newWorks.clear();
      await FirebaseFirestore.instance.doc('workers/$uid').update({
        'bio': _bio.text.trim(),
        'visitFee': _fee.text.trim().isEmpty ? null : double.tryParse(_fee.text.trim()),
        'whatsapp': Fmt.normalizePhone(_wa.text),
        'callPhone': Fmt.normalizePhone(_call.text),
        'governorate': _gov,
        'city': _city.text.trim(),
        'area': _area.text.trim(),
        'geo': {'lat': _loc.lat, 'lng': _loc.lng},
        'geohash': Geo.encode(_loc.lat, _loc.lng),
        'workImages': _works.take(8).toList(),
        if (_photoUrl != null) 'photoUrl': _photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) showSnack(context, context.t('saved'));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestChange() async {
    final changes = <String, dynamic>{};
    if (_name.text.trim() != _w.name) changes['name'] = _name.text.trim();
    if (!_sameSet(_cats, _w.categoryIds)) changes['categoryIds'] = _cats.toList();
    if (!_sameSet(_svcs, _w.serviceIds)) changes['serviceIds'] = _svcs.toList();
    final id = _idNumber.text.trim();
    if (id.isNotEmpty && (!RegExp(r'^[23][0-9]{13}$').hasMatch(id) || _idFront == null)) {
      showSnack(context, context.t('national_id_number'), error: true);
      return;
    }
    if (changes.isEmpty && id.isEmpty) return;
    if (_cats.isEmpty) {
      showSnack(context, context.t('choose_category_first'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final uid = context.read<Session>().uid!;
      Map<String, dynamic>? identity;
      if (id.isNotEmpty) {
        identity = {
          'nationalId': id,
          'idFrontRef': await MediaService.instance.upload(_idFront!, ownerId: uid, kind: 'id'),
          if (_idBack != null) 'idBackRef': await MediaService.instance.upload(_idBack!, ownerId: uid, kind: 'id'),
        };
      }
      await Backend.instance.requestWorkerChange(_w, changes, identity: identity);
      if (mounted) showSnack(context, context.t('change_sent'));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _sameSet(Set<String> a, List<String> b) => a.length == b.toSet().length && a.containsAll(b);

  Future<XFile?> _pick() async {
    final cam = await pickSourceSheet(context);
    if (cam == null) return null;
    return MediaService.instance.pick(camera: cam);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogRepo>();
    final w = context.watch<Session>().worker ?? _w;
    final lang = context.lang;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.t('edit_profile')),
          bottom: TabBar(tabs: [Tab(text: context.t('regular_info')), Tab(text: context.t('sensitive_info'))]),
        ),
        body: TabBarView(children: [
          // ---------------- عادية
          ListView(padding: const EdgeInsets.all(16), children: [
            Center(
              child: GestureDetector(
                onTap: () async {
                  final f = await _pick();
                  if (f != null) setState(() => _photoFile = f);
                },
                child: Stack(children: [
                  _photoFile != null
                      ? ClipOval(child: XImage(_photoFile!, width: 96, height: 96, fit: BoxFit.cover))
                      : Avatar(url: _photoUrl ?? w.photoUrl, name: w.name, size: 96),
                  const PositionedDirectional(bottom: 0, end: 0, child: CircleAvatar(radius: 15, child: Icon(Icons.camera_alt, size: 15))),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            TextField(controller: _bio, maxLines: 3, maxLength: 500, decoration: InputDecoration(labelText: context.t('bio'))),
            TextField(
              controller: _fee,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: context.t('visit_fee'), suffixText: context.t('egp')),
            ),
            const SizedBox(height: 12),
            TextField(controller: _wa, textDirection: TextDirection.ltr, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.t('whatsapp_number'))),
            const SizedBox(height: 12),
            TextField(controller: _call, textDirection: TextDirection.ltr, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.t('call_number'))),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: catalog.governorates.any((g) => g.code == _gov) ? _gov : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.t('governorate')),
              items: catalog.governorates.map((g) => DropdownMenuItem(value: g.code, child: Text(g.name(lang)))).toList(),
              onChanged: (v) => setState(() => _gov = v ?? _gov),
            ),
            const SizedBox(height: 12),
            TextField(controller: _city, decoration: InputDecoration(labelText: context.t('city'))),
            const SizedBox(height: 12),
            TextField(controller: _area, decoration: InputDecoration(labelText: context.t('area'))),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final p = await Navigator.push<PickedLocation>(context, MaterialPageRoute(builder: (_) => MapPickerScreen(initial: _loc)));
                if (p != null) setState(() => _loc = p);
              },
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: Text(context.t('my_location_on_map')),
            ),
            SectionTitle(context.t('work_photos')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < _works.length; i++)
                Stack(children: [
                  NetImage(url: _works[i], width: 80, height: 80, radius: 10),
                  PositionedDirectional(
                    top: 2,
                    end: 2,
                    child: InkWell(
                      onTap: () => setState(() => _works.removeAt(i)),
                      child: const CircleAvatar(radius: 11, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 13, color: Colors.white)),
                    ),
                  ),
                ]),
              for (final f in _newWorks) ClipRRect(borderRadius: BorderRadius.circular(10), child: XImage(f, width: 80, height: 80, fit: BoxFit.cover)),
              if (_works.length + _newWorks.length < 8)
                InkWell(
                  onTap: () async {
                    final fs = await MediaService.instance.pickMany(max: 8 - _works.length - _newWorks.length);
                    setState(() => _newWorks.addAll(fs));
                  },
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10), color: Colors.white),
                    child: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.navy),
                  ),
                ),
            ]),
            const SizedBox(height: 20),
            BusyButton(label: context.t('save'), busy: _busy, onPressed: _saveRegular),
          ]),

          // ---------------- حساسة (تحتاج مراجعة)
          ListView(padding: const EdgeInsets.all(16), children: [
            InfoBox(context.t('sensitive_change_note'), icon: Icons.admin_panel_settings_outlined, color: AppColors.warning),
            if (w.pendingChange) ...[const SizedBox(height: 8), InfoBox(context.t('change_pending'), icon: Icons.hourglass_top)],
            const SizedBox(height: 12),
            TextField(controller: _name, maxLength: 60, decoration: InputDecoration(labelText: context.t('your_name'))),
            Text(context.t('professions'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in catalog.categories)
                FilterChip(
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
            const SizedBox(height: 12),
            Text(context.t('choose_services'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in catalog.servicesOfMany(_cats.toList()))
                FilterChip(
                  label: Text(s.name(lang)),
                  selected: _svcs.contains(s.id),
                  onSelected: (v) => setState(() => v ? _svcs.add(s.id) : _svcs.remove(s.id)),
                ),
            ]),
            SectionTitle(context.t('step_id')),
            InfoBox(context.t('id_privacy_note'), icon: Icons.lock_outline, color: AppColors.success),
            const SizedBox(height: 8),
            TextField(
              controller: _idNumber,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)],
              decoration: InputDecoration(labelText: context.t('national_id_number')),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final f = await _pick();
                    if (f != null) setState(() => _idFront = f);
                  },
                  icon: Icon(_idFront == null ? Icons.badge_outlined : Icons.check_circle),
                  label: Text(context.t('id_front')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final f = await _pick();
                    if (f != null) setState(() => _idBack = f);
                  },
                  icon: Icon(_idBack == null ? Icons.badge_outlined : Icons.check_circle),
                  label: Text(context.t('id_back')),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            BusyButton(label: context.t('request_change'), busy: _busy, onPressed: _requestChange),
          ]),
        ]),
      ),
    );
  }
}
