import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../shared/location_picker.dart';
import 'search_screen.dart';
import 'worker_profile_screen.dart';

/// فتح البحث مباشرة على وضع الخريطة
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});
  @override
  Widget build(BuildContext context) => const SearchScreen(startOnMap: true);
}

/// خريطة تفاعلية بالصنايعية القريبين: 📍 سباك — 1 كم
class WorkersMap extends StatefulWidget {
  final PickedLocation center;
  final List<Worker> workers;
  const WorkersMap({super.key, required this.center, required this.workers});
  @override
  State<WorkersMap> createState() => _WorkersMapState();
}

class _WorkersMapState extends State<WorkersMap> {
  Worker? _selected;

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final markers = <Marker>{
      for (final w in widget.workers)
        Marker(
          markerId: MarkerId(w.id),
          position: LatLng(w.lat, w.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(w.available ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: '${w.categoryNames.isNotEmpty ? context.loc(w.categoryNames.first) : ''} — ${Fmt.km(w.distanceKm ?? 0, lang)} ${context.t('km')}',
            snippet: w.name,
          ),
          onTap: () => setState(() => _selected = w),
        ),
    };
    return Stack(children: [
      GoogleMap(
        initialCameraPosition: CameraPosition(target: LatLng(widget.center.lat, widget.center.lng), zoom: 13),
        markers: markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: false,
        circles: {
          Circle(
            circleId: const CircleId('me'),
            center: LatLng(widget.center.lat, widget.center.lng),
            radius: 120,
            fillColor: AppColors.navy.withValues(alpha: 0.15),
            strokeColor: AppColors.navy,
            strokeWidth: 1,
          ),
        },
        onTap: (_) => setState(() => _selected = null),
      ),
      if (widget.workers.isEmpty)
        PositionedDirectional(
          top: 12,
          start: 12,
          end: 12,
          child: Material(
            borderRadius: BorderRadius.circular(12),
            elevation: 2,
            child: Padding(padding: const EdgeInsets.all(12), child: Text(context.t('no_workers_found'), textAlign: TextAlign.center)),
          ),
        ),
      if (_selected != null)
        Positioned(
          left: 12,
          right: 12,
          bottom: 16,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Avatar(url: _selected!.photoUrl, name: _selected!.name, size: 54),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(_selected!.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(_selected!.categoryNames.map((n) => context.loc(n)).join(' • '), style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 4),
                    Row(children: [
                      RatingLine(avg: _selected!.ratingAvg, count: _selected!.ratingCount),
                      const SizedBox(width: 8),
                      Text(context.t('away', {'km': Fmt.km(_selected!.distanceKm ?? 0, lang)}), style: const TextStyle(fontSize: 12.5)),
                    ]),
                  ]),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => WorkerProfileScreen(workerId: _selected!.id, distanceKm: _selected!.distanceKm)),
                  ),
                  child: Text(context.t('view_profile')),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }
}
