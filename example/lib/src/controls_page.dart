import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

import 'package:flutter_unified_map_example/src/demo_data.dart';
import 'package:flutter_unified_map_example/src/map_widgets.dart';

enum BaseMap {
  standard('Standard', MapStyle.standard),
  muted('Muted', MapStyle.muted),
  satellite('Satellite', MapStyle.satellite),
  hybrid('Hybrid', MapStyle.hybrid),
  none('None', MapStyle.none),
  osmTiles('OSM tiles', MapStyle.none);

  const BaseMap(this.label, this.style);

  final String label;
  final MapStyle style;
}

typedef CameraReading = ({MapCamera camera, bool hasGesture});

class ControlsPage extends StatefulWidget {
  const ControlsPage({super.key});

  @override
  State<ControlsPage> createState() => _ControlsPageState();
}

class _ControlsPageState extends State<ControlsPage> {
  final _reading = ValueNotifier<CameraReading?>(null);
  var _baseMap = BaseMap.standard;
  var _showsUserLocation = false;

  @override
  void dispose() {
    _reading.dispose();
    super.dispose();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) =>
      _reading.value = (camera: camera, hasGesture: hasGesture);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _ControlBar(
        baseMap: _baseMap,
        showsUserLocation: _showsUserLocation,
        onBaseMap: (value) => setState(() => _baseMap = value),
        onUserLocation: (value) => setState(() => _showsUserLocation = value),
      ),
      Expanded(
        child: UnifiedMap(
          options: MapOptions(
            initialCenter: paris,
            initialZoom: 11,
            onPositionChanged: _onPositionChanged, nativeParams: NativeParams(mapType: _baseMap.style, showsUserLocation: _showsUserLocation, apple: AppleMapParams(showsScale: true)),),
          children: [
            if (_baseMap == BaseMap.osmTiles) osmTileLayer,
            const Positioned(
              top: 12,
              right: 12,
              child: Column(children: [CompassButton(), SizedBox(height: 16), ZoomButtons()]),
            ),
            Positioned(left: 12, bottom: 12, child: _CameraReadout(reading: _reading)),
            const OsmAttribution(),
          ],
        ),
      ),
    ],
  );
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.baseMap,
    required this.showsUserLocation,
    required this.onBaseMap,
    required this.onUserLocation,
  });

  final BaseMap baseMap;
  final bool showsUserLocation;
  final ValueChanged<BaseMap> onBaseMap;
  final ValueChanged<bool> onUserLocation;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            for (final value in BaseMap.values) ...[
              ChoiceChip(label: Text(value.label), selected: value == baseMap, onSelected: (_) => onBaseMap(value)),
              const SizedBox(width: 6),
            ],
            const SizedBox(width: 6),
            FilterChip(
              avatar: const Icon(Icons.my_location, size: 18),
              label: const Text('My location'),
              selected: showsUserLocation,
              onSelected: onUserLocation,
            ),
          ],
        ),
      ),
    ),
  );
}

class _CameraReadout extends StatelessWidget {
  const _CameraReadout({required this.reading});

  final ValueNotifier<CameraReading?> reading;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return ValueListenableBuilder<CameraReading?>(
      valueListenable: reading,
      builder: (context, value, _) {
        final camera = value?.camera ?? MapCamera.maybeOf(context);
        if (camera == null) return const SizedBox.shrink();
        return MapCard(
          child: DefaultTextStyle.merge(
            style: style,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatLatLng(camera.center)),
                Text('zoom ${camera.zoom.toStringAsFixed(2)} · rotation ${camera.rotation.toStringAsFixed(0)}°'),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(value?.hasGesture ?? false ? Icons.pan_tool_alt : Icons.smart_toy_outlined, size: 14),
                    const SizedBox(width: 4),
                    Text(value?.hasGesture ?? false ? 'gesture' : 'programmatic'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
