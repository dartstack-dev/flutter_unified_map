import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

import 'package:flutter_unified_map_example/src/demo_data.dart';

/// Station pin drawn into a 30×30 marker bitmap. Colors are explicit: the core rasterises it off-screen.
class StationPin extends StatelessWidget {
  const StationPin({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1))],
    ),
    child: const Center(child: Icon(Icons.local_gas_station, size: 15, color: Colors.white)),
  );
}

/// Teardrop pin for the selected station, 30×40 with its tip on the bottom edge.
class SelectedPin extends StatelessWidget {
  const SelectedPin({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: TeardropPainter(color, shadow: true),
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(Icons.local_gas_station, size: 13, color: color),
        ),
      ),
    ),
  );
}

/// Teardrop whose tip is the bottom center of its box, with a drop shadow ([shadow]) or a white dot ([dot]).
class TeardropPainter extends CustomPainter {
  const TeardropPainter(this.color, {this.shadow = false, this.dot = false});

  final Color color;
  final bool shadow;
  final bool dot;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final shoulder = math.acos(r / (size.height - r));
    final path = Path()
      ..moveTo(r, size.height)
      ..arcTo(
        Rect.fromCircle(center: Offset(r, r), radius: r),
        math.pi / 2 + shoulder,
        2 * math.pi - 2 * shoulder,
        false,
      )
      ..close();
    if (shadow) canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, Paint()..color = color);
    if (dot) canvas.drawCircle(Offset(r, r), r * 0.38, Paint()..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(TeardropPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.shadow != shadow || oldDelegate.dot != dot;
}

/// Floating square button used by the map overlays.
class MapButton extends StatelessWidget {
  const MapButton({super.key, required this.tooltip, required this.onPressed, required this.child});

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 2,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 44,
            child: IconTheme.merge(
              data: IconThemeData(color: scheme.onSurface, size: 22),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Needle pointing at north on screen (map content turns clockwise by `rotation`); tapping it animates back to
/// north.
class CompassButton extends StatelessWidget {
  const CompassButton({super.key});

  @override
  Widget build(BuildContext context) {
    final rotation = MapCamera.of(context).rotation;
    return MapButton(
      tooltip: 'Reset bearing',
      onPressed: () => unawaited(MapController.of(context).animateTo(rotation: 0)),
      child: Transform.rotate(
        angle: rotation * math.pi / 180,
        child: const Icon(Icons.navigation, color: Color(0xFFDC2626)),
      ),
    );
  }
}

class ZoomButtons extends StatelessWidget {
  const ZoomButtons({super.key});

  @override
  Widget build(BuildContext context) {
    void zoomBy(double amount) {
      final controller = MapController.of(context);
      unawaited(controller.animateTo(zoom: controller.camera.zoom + amount));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MapButton(tooltip: 'Zoom in', onPressed: () => zoomBy(1), child: const Icon(Icons.add)),
        const SizedBox(height: 8),
        MapButton(tooltip: 'Zoom out', onPressed: () => zoomBy(-1), child: const Icon(Icons.remove)),
      ],
    );
  }
}

class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  @override
  Widget build(BuildContext context) =>
      const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]);
}

/// Small rounded card floating over the map.
class MapCard extends StatelessWidget {
  const MapCard({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 10)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 0.96),
    elevation: 2,
    shadowColor: Colors.black38,
    borderRadius: BorderRadius.circular(16),
    child: Padding(padding: padding, child: child),
  );
}

String formatLatLng(LatLng point) => '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';

const osmTileLayer = TileLayer(
  urlTemplate: osmUrlTemplate,
  subdomains: [],
  userAgentPackageName: userAgentPackageName,
  nativeParams: NativeTileLayerParams(replacesBaseMap: true),
);
