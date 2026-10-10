import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

import 'package:flutter_unified_map_example/src/geometry_data.dart';
import 'package:flutter_unified_map_example/src/map_widgets.dart';

class GeometryPage extends StatelessWidget {
  const GeometryPage({super.key});

  @override
  Widget build(BuildContext context) => GeometryScene(
    onMarkerTap: (name) => _show(context, 'Marker $name'),
    onMapError: (error) => debugPrint('Map error: $error'),
  );

  static void _show(BuildContext context, String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 1)));
}

/// Custom pins, an itinerary and shapes, all written with the flutter_map API. Also mounted alone by the
/// end-to-end tests, which read its colors and coordinates from `geometry_data.dart`.
class GeometryScene extends StatefulWidget {
  const GeometryScene({
    super.key,
    this.controller,
    this.mapStyle = MapStyle.standard,
    this.onMapReady,
    this.onMapLoaded,
    this.onMapError,
    this.onMapEvent,
    this.onMarkerTap,
    this.onPolygonTap,
  });

  final MapController? controller;
  final MapStyle mapStyle;
  final VoidCallback? onMapReady;
  final VoidCallback? onMapLoaded;
  final MapErrorCallback? onMapError;
  final MapEventCallback? onMapEvent;
  final ValueChanged<String>? onMarkerTap;

  /// Called on every map tap with the tapped polygon's name, or null when the tap hit no polygon.
  final ValueChanged<String?>? onPolygonTap;

  @override
  State<GeometryScene> createState() => _GeometrySceneState();
}

class _GeometrySceneState extends State<GeometryScene> {
  MapController? _ownController;
  final _polygonHits = LayerHitNotifier<String>(null);
  String? _status;

  MapController get _controller => widget.controller ?? (_ownController ??= MapController());

  late final List<Marker> _markers = [
    Marker(
      key: const ValueKey(GeometryPins.tip),
      point: GeometryPins.tipPoint,
      width: GeometryPins.tipSize.width,
      height: GeometryPins.tipSize.height,
      alignment: Alignment.topCenter,
      iconKey: GeometryPins.tip,
      onTap: () => _onMarkerTap(GeometryPins.tip),
      child: const TeardropPin(color: GeometryColors.pin),
    ),
    for (final (name, label) in const [
      (GeometryPins.badgeA, 'A'),
      (GeometryPins.badgeB, 'B'),
      (GeometryPins.badgeC, 'C'),
    ])
      Marker(
        key: ValueKey(name),
        point: GeometryPins.points[name]!,
        width: GeometryPins.badgeSize.width,
        height: GeometryPins.badgeSize.height,
        alignment: Alignment.topCenter,
        iconKey: name,
        onTap: () => _onMarkerTap(name),
        child: BadgePin(label: label, color: GeometryColors.badge),
      ),
    Marker(
      key: const ValueKey(GeometryPins.cafe),
      point: GeometryPins.points[GeometryPins.cafe]!,
      width: GeometryPins.cafeSize.width,
      height: GeometryPins.cafeSize.height,
      onTap: () => _onMarkerTap(GeometryPins.cafe),
      child: const IconPin(icon: Icons.local_cafe, color: GeometryColors.cafe),
    ),
    Marker(
      key: const ValueKey(GeometryPins.upright),
      point: GeometryPins.points[GeometryPins.upright]!,
      width: GeometryPins.arrowSize.width,
      height: GeometryPins.arrowSize.height,
      rotate: true,
      iconKey: GeometryPins.upright,
      onTap: () => _onMarkerTap(GeometryPins.upright),
      child: const NorthArrowPin(color: GeometryColors.arrow),
    ),
    Marker(
      key: const ValueKey(GeometryPins.flat),
      point: GeometryPins.points[GeometryPins.flat]!,
      width: GeometryPins.arrowSize.width,
      height: GeometryPins.arrowSize.height,
      rotate: false,
      iconKey: GeometryPins.flat,
      onTap: () => _onMarkerTap(GeometryPins.flat),
      child: const NorthArrowPin(color: GeometryColors.arrow),
    ),
    for (final name in GeometryPins.fuel)
      Marker(
        key: ValueKey(name),
        point: GeometryPins.points[name]!,
        width: GeometryPins.fuelSize.width,
        height: GeometryPins.fuelSize.height,
        iconKey: GeometryPins.fuelIconKey,
        onTap: () => _onMarkerTap(name),
        child: IconPin(icon: Icons.local_gas_station, color: GeometryColors.fuel, size: GeometryPins.fuelSize.width),
      ),
  ];

  @override
  void dispose() {
    _polygonHits.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  void _onMarkerTap(String name) {
    setState(() => _status = 'Marker $name');
    widget.onMarkerTap?.call(name);
  }

  void _onTap(TapPosition tapPosition, LatLng point) {
    final polygon = _polygonHits.value?.hitValues.firstOrNull;
    setState(() => _status = polygon == null ? null : 'Polygon $polygon');
    widget.onPolygonTap?.call(polygon);
  }

  void _fitRoute() => unawaited(_controller.animatedFitCamera(cameraFit: routeCameraFit));

  void _rotate() => unawaited(_controller.animateTo(rotation: 45));

  void _reset() =>
      unawaited(_controller.animateTo(dest: geometryInitialCenter, zoom: geometryInitialZoom, rotation: 0));

  @override
  Widget build(BuildContext context) => UnifiedMap(
    mapController: _controller,
    options: MapOptions(
      initialCenter: geometryInitialCenter,
      initialZoom: geometryInitialZoom,
      onTap: _onTap,
      onMapReady: widget.onMapReady,
      onMapLoaded: widget.onMapLoaded,
      onMapError: widget.onMapError,
      onMapEvent: widget.onMapEvent,
      nativeParams: NativeParams(mapType: widget.mapStyle),
    ),
    children: [
      PolygonLayer<String>(
        hitNotifier: _polygonHits,
        polygons: const [
          Polygon(
            points: morvanOuter,
            holePointsList: [morvanHole],
            color: GeometryColors.morvanFill,
            borderColor: GeometryColors.morvanBorder,
            borderStrokeWidth: 2,
            hitValue: 'Morvan',
          ),
          Polygon(
            points: camargue,
            color: GeometryColors.camargueFill,
            borderColor: GeometryColors.camargueBorder,
            borderStrokeWidth: 2,
            hitValue: 'Camargue',
          ),
        ],
      ),
      PolylineLayer(
        polylines: [
          const Polyline(
            points: itinerary,
            strokeWidth: 6,
            color: GeometryColors.route,
            borderStrokeWidth: 3,
            borderColor: GeometryColors.routeBorder,
          ),
          Polyline(
            points: detourPoints,
            strokeWidth: 4,
            color: GeometryColors.detour,
            pattern: StrokePattern.dashed(segments: detourSegments),
          ),
          const Polyline(
            points: dottedPoints,
            strokeWidth: 5,
            color: GeometryColors.dotted,
            pattern: StrokePattern.dotted(),
          ),
        ],
      ),
      CircleLayer(
        circles: [
          const CircleMarker(
            point: meterCircleCenter,
            radius: meterCircleRadius,
            useRadiusInMeter: true,
            color: GeometryColors.meterCircle,
            borderStrokeWidth: 1,
            borderColor: Color(0xFF0091EA),
          ),
          for (final point in waypointPoints)
            CircleMarker(
              point: point,
              radius: waypointRadiusPx,
              color: GeometryColors.waypoint,
              borderStrokeWidth: 3,
              borderColor: GeometryColors.route,
            ),
        ],
      ),
      MarkerLayer(markers: _markers, rotate: true),
      Positioned(
        left: 12,
        right: 12,
        bottom: 12,
        child: SafeArea(
          top: false,
          child: _Panel(status: _status, onFit: _fitRoute, onRotate: _rotate, onReset: _reset),
        ),
      ),
    ],
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.status, required this.onFit, required this.onRotate, required this.onReset});

  final String? status;
  final VoidCallback onFit;
  final VoidCallback onRotate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MapCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Paris → Lyon → Marseille', style: text.titleMedium),
          const SizedBox(height: 2),
          Text(status ?? 'Tap a pin or a polygon', style: text.bodySmall, key: const ValueKey('geometry-status')),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(onPressed: onFit, icon: const Icon(Icons.fit_screen), label: const Text('Fit route')),
              FilledButton.tonalIcon(
                onPressed: onRotate,
                icon: const Icon(Icons.rotate_right),
                label: const Text('Rotate 45°'),
              ),
              OutlinedButton.icon(onPressed: onReset, icon: const Icon(Icons.restart_alt), label: const Text('Reset')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Teardrop whose tip is the bottom-center of its box: use it with `alignment: Alignment.topCenter`.
class TeardropPin extends StatelessWidget {
  const TeardropPin({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: TeardropPainter(color, dot: true));
}

/// Speech bubble with a letter, pointing down at its coordinate.
class BadgePin extends StatelessWidget {
  const BadgePin({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFFFFFF), width: 2),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 15, fontWeight: FontWeight.w800, height: 1),
            ),
          ),
        ),
      ),
      CustomPaint(size: const Size(12, 7), painter: _PointerPainter(color)),
    ],
  );
}

class _PointerPainter extends CustomPainter {
  const _PointerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) => oldDelegate.color != color;
}

/// Material icon in a colored disc.
class IconPin extends StatelessWidget {
  const IconPin({super.key, required this.icon, required this.color, this.size = 36});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFFFFFFF), width: 2),
    ),
    child: Center(
      child: Icon(icon, size: size * 0.55, color: const Color(0xFFFFFFFF)),
    ),
  );
}

/// Arrow pointing up: north when the pin rotates with the map, the top of the screen when it stays upright.
class NorthArrowPin extends StatelessWidget {
  const NorthArrowPin({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFFFFFF),
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 2),
    ),
    child: Center(child: Icon(Icons.navigation, size: 20, color: color)),
  );
}
