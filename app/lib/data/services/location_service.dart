import 'package:geolocator/geolocator.dart';

enum LocationIssue { disabled, denied, deniedForever }

class LocationResult {
  final double? lat;
  final double? lng;
  final LocationIssue? issue;
  LocationResult.ok(this.lat, this.lng) : issue = null;
  LocationResult.fail(this.issue)
      : lat = null,
        lng = null;
  bool get ok => issue == null && lat != null;
}

/// الموقع: نطلب الإذن فقط عند الحاجة (عند البحث/التسجيل) — مش عند فتح التطبيق
class LocationService {
  LocationService._();
  static final instance = LocationService._();

  Position? _last;

  Future<LocationResult> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationResult.fail(LocationIssue.disabled);
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return LocationResult.fail(LocationIssue.denied);
    if (perm == LocationPermission.deniedForever) return LocationResult.fail(LocationIssue.deniedForever);
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      _last = p;
      return LocationResult.ok(p.latitude, p.longitude);
    } catch (_) {
      final p = _last ?? await Geolocator.getLastKnownPosition();
      if (p != null) return LocationResult.ok(p.latitude, p.longitude);
      return LocationResult.fail(LocationIssue.disabled);
    }
  }

  Future<void> openSettings() => Geolocator.openAppSettings();
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
