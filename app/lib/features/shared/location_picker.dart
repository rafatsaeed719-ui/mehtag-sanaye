import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/geo.dart';
import '../../data/models.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/services/location_service.dart';
import 'osm.dart';

/// موقع مختار (للبحث أو لموقع الخدمة أو لموقع الصنايعي)
class PickedLocation {
  final double lat;
  final double lng;
  final String label;
  final String governorate; // كود المحافظة إن عُرف
  const PickedLocation({required this.lat, required this.lng, this.label = '', this.governorate = ''});
}

const _cairo = LatLng(30.0444, 31.2357);

/// يحاول GPS ويعرض رسائل واضحة لو الإذن مرفوض أو الموقع مقفول
Future<PickedLocation?> getGpsLocation(BuildContext context) async {
  final r = await LocationService.instance.current();
  if (r.ok) return PickedLocation(lat: r.lat!, lng: r.lng!, label: context.t('location_gps'));
  if (!context.mounted) return null;
  final msg = r.issue == LocationIssue.disabled ? context.t('location_disabled') : context.t('location_permission_needed');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    action: SnackBarAction(
      label: context.t('open_settings'),
      onPressed: () => r.issue == LocationIssue.disabled
          ? LocationService.instance.openLocationSettings()
          : LocationService.instance.openSettings(),
    ),
  ));
  return null;
}

/// قائمة: GPS / اختيار يدوي / الخريطة
Future<PickedLocation?> showLocationChooser(BuildContext context, {PickedLocation? current}) {
  return showModalBottomSheet<PickedLocation>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.my_location, color: AppColors.navy),
          title: Text(context.t('location_gps')),
          onTap: () async {
            final p = await getGpsLocation(context);
            if (c.mounted) Navigator.pop(c, p);
          },
        ),
        ListTile(
          leading: const Icon(Icons.list_alt, color: AppColors.navy),
          title: Text(context.t('location_manual')),
          subtitle: Text('${context.t('governorate')} → ${context.t('city')} → ${context.t('area')}'),
          onTap: () async {
            final p = await showModalBottomSheet<PickedLocation>(
              context: c,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => const ManualLocationSheet(),
            );
            if (c.mounted) Navigator.pop(c, p);
          },
        ),
        ListTile(
          leading: const Icon(Icons.map_outlined, color: AppColors.navy),
          title: Text(context.t('location_map')),
          onTap: () async {
            final p = await Navigator.push<PickedLocation>(c, MaterialPageRoute(builder: (_) => MapPickerScreen(initial: current)));
            if (c.mounted) Navigator.pop(c, p);
          },
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// اختيار يدوي: المحافظة → المركز/المدينة → المنطقة/القرية
class ManualLocationSheet extends StatefulWidget {
  const ManualLocationSheet({super.key});
  @override
  State<ManualLocationSheet> createState() => _ManualLocationSheetState();
}

class _ManualLocationSheetState extends State<ManualLocationSheet> {
  Place? _gov, _city, _area;

  @override
  Widget build(BuildContext context) {
    final cat = context.watch<CatalogRepo>();
    final lang = context.lang;
    final cities = _gov == null ? <Place>[] : cat.childrenOf(_gov!.id);
    final areas = _city == null ? <Place>[] : cat.childrenOf(_city!.id);

    Widget dd(String label, Place? value, List<Place> items, ValueChanged<Place?> onChanged) => DropdownButtonFormField<Place>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: items.map((p) => DropdownMenuItem(value: p, child: Text(p.name(lang)))).toList(),
          onChanged: onChanged,
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('location_manual'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        dd(context.t('governorate'), _gov, cat.governorates, (p) => setState(() {
              _gov = p;
              _city = null;
              _area = null;
            })),
        if (cities.isNotEmpty) ...[
          const SizedBox(height: 12),
          dd(context.t('city'), _city, cities, (p) => setState(() {
                _city = p;
                _area = null;
              })),
        ],
        if (areas.isNotEmpty) ...[
          const SizedBox(height: 12),
          dd(context.t('area'), _area, areas, (p) => setState(() => _area = p)),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _gov == null
              ? null
              : () {
                  final withCoords = [_area, _city, _gov].firstWhere((p) => p != null && p.lat != null, orElse: () => null);
                  if (withCoords == null) {
                    showSnack(context, context.t('location_required'), error: true);
                    return;
                  }
                  final label = [_area, _city, _gov].whereType<Place>().map((p) => p.name(lang)).join('، ');
                  Navigator.pop(
                    context,
                    PickedLocation(lat: withCoords.lat!, lng: withCoords.lng!, label: label, governorate: _gov!.code),
                  );
                },
          child: Text(context.t('confirm_location')),
        ),
      ]),
    );
  }
}

/// تحديد نقطة على الخريطة (دبوس ثابت في المنتصف والمستخدم يحرك الخريطة)
class MapPickerScreen extends StatefulWidget {
  final PickedLocation? initial;
  final String? title;
  const MapPickerScreen({super.key, this.initial, this.title});
  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _ctrl = MapController();
  bool _ready = false;
  late LatLng _center;

  @override
  void initState() {
    super.initState();
    _center = widget.initial == null ? _cairo : LatLng(widget.initial!.lat, widget.initial!.lng);
    if (widget.initial == null) _goToGps();
  }

  Future<void> _goToGps() async {
    final r = await LocationService.instance.current();
    if (!r.ok || !mounted) return;
    _center = LatLng(r.lat!, r.lng!);
    if (_ready) _ctrl.move(_center, 16);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title ?? context.t('location_map'))),
        body: Stack(children: [
          FlutterMap(
            mapController: _ctrl,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: widget.initial == null ? 12 : 16,
              onMapReady: () {
                _ready = true;
                _ctrl.move(_center, _ctrl.camera.zoom);
              },
              onPositionChanged: (camera, _) => _center = camera.center,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [osmTiles, osmAttribution],
          ),
          const Center(child: Padding(padding: EdgeInsets.only(bottom: 40), child: Icon(Icons.location_pin, size: 48, color: AppColors.emergency))),
          PositionedDirectional(
            top: 12,
            start: 12,
            end: 12,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              elevation: 2,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(context.t('move_map_hint'), textAlign: TextAlign.center)),
            ),
          ),
          PositionedDirectional(
            end: 16,
            bottom: 96,
            child: FloatingActionButton.small(heroTag: 'gps', onPressed: _goToGps, child: const Icon(Icons.my_location)),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: ElevatedButton(
              onPressed: () {
                if (!Geo.isInEgypt(_center.latitude, _center.longitude)) {
                  showSnack(context, context.isAr ? 'الموقع لازم يكون داخل مصر' : 'Location must be inside Egypt', error: true);
                  return;
                }
                Navigator.pop(context, PickedLocation(lat: _center.latitude, lng: _center.longitude, label: context.t('location_map')));
              },
              child: Text(context.t('confirm_location')),
            ),
          ),
        ]),
      );
}
