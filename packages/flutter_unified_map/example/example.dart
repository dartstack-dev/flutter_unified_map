import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

void main() => runApp(const MaterialApp(home: Scaffold(body: OsmMap())));

/// An OpenStreetMap centered on Paris with two tappable markers.
class OsmMap extends StatelessWidget {
  const OsmMap({super.key});

  @override
  Widget build(BuildContext context) => UnifiedMap(
    options: const MapOptions(initialCenter: LatLng(48.85, 2.35), initialZoom: 10),
    children: [
      const TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        subdomains: [],
        userAgentPackageName: 'dev.alphabyte.flutter_unified_map_example',
        nativeParams: NativeTileLayerParams(replacesBaseMap: true),
      ),
      MarkerLayer(
        markers: [
          Marker(
            key: const ValueKey('paris'),
            point: const LatLng(48.85, 2.35),
            width: 30,
            height: 42,
            alignment: Alignment.topCenter,
            iconKey: 'pin',
            onTap: () => debugPrint('tapped Paris'),
            child: const Icon(Icons.place, color: Color(0xFF52616F)),
          ),
          const Marker(
            key: ValueKey('versailles'),
            point: LatLng(48.80, 2.13),
            width: 30,
            height: 42,
            alignment: Alignment.topCenter,
            iconKey: 'pin',
            child: Icon(Icons.place, color: Color(0xFF52616F)),
          ),
        ],
      ),
    ],
  );
}
