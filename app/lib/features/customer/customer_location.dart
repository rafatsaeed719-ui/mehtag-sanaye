import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/location_picker.dart';

/// موقع البحث الحالي للعميل (يُحفظ على الجهاز)
class CustomerLocation extends ChangeNotifier {
  PickedLocation? current;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final lat = p.getDouble('loc_lat');
    final lng = p.getDouble('loc_lng');
    if (lat != null && lng != null) {
      current = PickedLocation(lat: lat, lng: lng, label: p.getString('loc_label') ?? '', governorate: p.getString('loc_gov') ?? '');
      notifyListeners();
    }
  }

  Future<void> set(PickedLocation loc) async {
    current = loc;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('loc_lat', loc.lat);
    await p.setDouble('loc_lng', loc.lng);
    await p.setString('loc_label', loc.label);
    await p.setString('loc_gov', loc.governorate);
  }
}
