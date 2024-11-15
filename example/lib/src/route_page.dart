import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

import 'package:flutter_unified_map_example/src/demo_data.dart';
import 'package:flutter_unified_map_example/src/map_widgets.dart';

class RoutePage extends StatefulWidget {
  const RoutePage({super.key});

  @override
  State<RoutePage> createState() => _RoutePageState();
}

class _RoutePageState extends State<RoutePage> {
  static const _panelClearance = 200.0;

  final _controller = MapController();
  final _zoneHits = LayerHitNotifier<String>(null);

  @override
  void dispose() {
    _zoneHits.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTap(TapPosition tapPosition, LatLng point) {
    final zone = _zoneHits.value?.hitValues.firstOrNull;
    if (zone == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$zone low-emission zone')));
  }

  void _fitRoute() => unawaited(
    _controller.animatedFitCamera(
      cameraFit: const CameraFit.coordinates(
        coordinates: route,
        padding: EdgeInsets.fromLTRB(48, 48, 48, _panelClearance),
      ),
    ),
  );

  void _goToParis() =>
      unawaited(_controller.animateTo(dest: paris, zoom: 12, offset: const Offset(0, -_panelClearance / 2)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return UnifiedMap(
      mapController: _controller,
      options: MapOptions(initialCenter: const LatLng(47.2, 3.9), initialZoom: 6.2, onTap: _onTap),
      children: [
        PolygonLayer<String>(
          hitNotifier: _zoneHits,
          polygons: const [
            Polygon(
              points: parisZone,
              color: Color(0x332563EB),
              borderColor: Color(0xFF2563EB),
              borderStrokeWidth: 2,
              hitValue: 'Paris',
            ),
            Polygon(
              points: lyonZone,
              color: Color(0x33DB2777),
              borderColor: Color(0xFFDB2777),
              borderStrokeWidth: 2,
              hitValue: 'Lyon',
            ),
          ],
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: detour,
              strokeWidth: 4,
              color: Color(0xFFEA580C),
              pattern: StrokePattern.dashed(segments: [12, 8]),
            ),
            Polyline(
              points: route,
              strokeWidth: 5,
              color: Color(0xFF1D4ED8),
              borderStrokeWidth: 2,
              borderColor: Color(0xFFFFFFFF),
            ),
          ],
        ),
        CircleLayer(
          circles: [
            const CircleMarker(
              point: lyon,
              radius: 500,
              useRadiusInMeter: true,
              color: Color(0x2A1D4ED8),
              borderStrokeWidth: 1.5,
              borderColor: Color(0xFF1D4ED8),
            ),
            for (final point in waypoints)
              CircleMarker(
                point: point,
                radius: 6,
                color: const Color(0xFFFFFFFF),
                borderStrokeWidth: 3,
                borderColor: const Color(0xFF1D4ED8),
              ),
          ],
        ),
        const Positioned.fill(bottom: _panelClearance - 24, child: OsmAttribution()),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: MapCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Paris → Lyon', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  _Legend(color: scheme.primary),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _fitRoute,
                        icon: const Icon(Icons.fit_screen),
                        label: const Text('Fit route'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _goToParis,
                        icon: const Icon(Icons.flight_land),
                        label: const Text('Paris'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    Widget swatch(Color color, String label, {bool dashed = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 4,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          foregroundDecoration: dashed
              ? const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.white, Colors.transparent],
                    stops: [0.45, 0.5, 0.55],
                  ),
                )
              : null,
        ),
        const SizedBox(width: 6),
        Text(label, style: style),
      ],
    );

    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        swatch(const Color(0xFF1D4ED8), 'A6 motorway'),
        swatch(const Color(0xFFEA580C), 'Detour via Dijon', dashed: true),
        Text('Tap a zone for details', style: style?.copyWith(color: color)),
      ],
    );
  }
}
