import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// خرايط OpenStreetMap — مجانية ومن غير مفتاح ولا كارت
TileLayer get osmTiles => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.mehtagsanaye.app',
  maxZoom: 19,
);

const osmAttribution = _OsmAttribution();

class _OsmAttribution extends StatelessWidget {
  const _OsmAttribution();
  @override
  Widget build(BuildContext context) => RichAttributionWidget(
        alignment: AttributionAlignment.bottomLeft,
        attributions: [
          TextSourceAttribution('OpenStreetMap contributors',
              onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright'), mode: LaunchMode.externalApplication)),
        ],
      );
}
