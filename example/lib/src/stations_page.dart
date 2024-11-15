import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

import 'package:flutter_unified_map_example/src/demo_data.dart';
import 'package:flutter_unified_map_example/src/map_widgets.dart';

/// A few hundred stations in a plain `MarkerLayer`. Clustering lives in the `flutter_unified_map_marker_cluster`
/// package (see the README).
class StationsPage extends StatefulWidget {
  const StationsPage({super.key});

  @override
  State<StationsPage> createState() => _StationsPageState();
}

class _StationsPageState extends State<StationsPage> {
  final _stations = generateStations(count: 300);
  late final _markers = [
    for (final station in _stations)
      Marker(
        key: ValueKey(station.id),
        point: station.point,
        iconKey: 'pin-${station.brand.name}',
        onTap: () => _select(station),
        child: StationPin(color: station.brand.color),
      ),
  ];
  Station? _selected;

  void _select(Station station) {
    setState(() => _selected = station);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${station.id} · ${station.brand.label}')));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return UnifiedMap(
      options: MapOptions(
        initialCenter: const LatLng(48.5, 9.0),
        initialZoom: 4.6,
        onTap: (_, _) => setState(() => _selected = null),
      ),
      children: [
        MarkerLayer(markers: _markers),
        if (selected != null)
          MarkerLayer(
            markers: [
              Marker(
                point: selected.point,
                width: 30,
                height: 40,
                alignment: Alignment.topCenter,
                iconKey: 'selected-${selected.brand.name}',
                child: SelectedPin(color: selected.brand.color),
              ),
            ],
          ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          left: 12,
          right: 12,
          child: Align(
            alignment: Alignment.topLeft,
            child: _StationsHeader(count: _stations.length),
          ),
        ),
        const OsmAttribution(),
      ],
    );
  }
}

class _StationsHeader extends StatelessWidget {
  const _StationsHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MapCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count stations', style: text.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (final brand in Brand.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: brand.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(brand.label, style: text.labelSmall),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
