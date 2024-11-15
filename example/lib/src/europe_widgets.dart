import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

import 'package:flutter_unified_map_example/src/europe_data.dart';

/// A capital pin: a green teardrop with a white disc, holding a gold star for EU capitals and a plain
/// dot for the rest. Rasterised once per [iconKey].
class CapitalPin extends StatelessWidget {
  const CapitalPin({super.key, required this.eu});

  final bool eu;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CapitalPinPainter(eu));
}

class _CapitalPinPainter extends CustomPainter {
  const _CapitalPinPainter(this.eu);

  final bool eu;

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
    canvas.drawShadow(path, const Color(0x8A000000), 2.5, false);
    canvas.drawPath(path, Paint()..color = const Color(0xFF2F9E44));
    canvas.drawCircle(Offset(r, r), r * 0.68, Paint()..color = const Color(0xFFFFFFFF));
    if (eu) {
      _star(canvas, Offset(r, r), r * 0.42, Paint()..color = const Color(0xFFF5B800));
    } else {
      canvas.drawCircle(Offset(r, r), r * 0.22, Paint()..color = const Color(0xFF758C75));
    }
  }

  void _star(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final outer = i * 2 * math.pi / 5 - math.pi / 2;
      final inner = outer + math.pi / 5;
      if (i == 0) {
        path.moveTo(center.dx + radius * math.cos(outer), center.dy + radius * math.sin(outer));
      } else {
        path.lineTo(center.dx + radius * math.cos(outer), center.dy + radius * math.sin(outer));
      }
      path.lineTo(
        center.dx + radius * 0.4 * math.cos(inner),
        center.dy + radius * 0.4 * math.sin(inner),
      );
    }
    canvas.drawPath(path..close(), paint);
  }

  @override
  bool shouldRepaint(_CapitalPinPainter oldDelegate) => oldDelegate.eu != eu;
}

/// A five-point star path with one point up, used by the flag and the pins.
Path starPath(Offset center, double radius) {
  final path = Path();
  for (var i = 0; i < 5; i++) {
    final outer = i * 2 * math.pi / 5 - math.pi / 2;
    final inner = outer + math.pi / 5;
    if (i == 0) {
      path.moveTo(center.dx + radius * math.cos(outer), center.dy + radius * math.sin(outer));
    } else {
      path.lineTo(center.dx + radius * math.cos(outer), center.dy + radius * math.sin(outer));
    }
    path.lineTo(center.dx + radius * 0.382 * math.cos(inner), center.dy + radius * 0.382 * math.sin(inner));
  }
  return path..close();
}

/// The European flag painted onto `width` × `height`: 12 gold stars on a blue field, official geometry
/// (circle radius ⅓ of the height, star radius 1/18 of the height).
class EuFlagPainter extends CustomPainter {
  const EuFlagPainter({this.opacity = 1});

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF003399).withValues(alpha: opacity));
    final center = size.center(Offset.zero);
    final starRadius = size.height / 18;
    final circleRadius = size.height / 3;
    final star = Paint()..color = const Color(0xFFFFCC00).withValues(alpha: opacity);
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6 - math.pi / 2;
      canvas.drawPath(
        starPath(center + Offset(circleRadius * math.cos(angle), circleRadius * math.sin(angle)), starRadius),
        star,
      );
    }
  }

  @override
  bool shouldRepaint(EuFlagPainter oldDelegate) => oldDelegate.opacity != opacity;
}

/// Renders the flag once at [scale] for the map overlay: painting straight to the canvas would be
/// re-done on every camera event, while a rasterised image blits in one call.
Future<ui.Image> renderEuFlagImage(double scale) async {
  const flag = Size(810, 540);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, Offset.zero & (flag * scale));
  EuFlagPainter().paint(canvas, flag * scale);
  return recorder.endRecording().toImage((flag.width * scale).round(), (flag.height * scale).round());
}

/// The flag draped over the EU member states, clipped to their outline: it keeps its 3:2 ratio
/// (no distortion), covers the whole union and is cut at the borders instead. The real ground-overlay
/// layer is not wired through the platform yet, so this overlay is a plain widget that follows the camera.
class EuFlagOverlay extends StatefulWidget {
  const EuFlagOverlay({super.key, this.opacity = 0.92});

  final double opacity;

  @override
  State<EuFlagOverlay> createState() => _EuFlagOverlayState();
}

class _EuFlagOverlayState extends State<EuFlagOverlay> {
  late final Future<ui.Image> _image = renderEuFlagImage(2);

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: FutureBuilder(
      future: _image,
      builder: (context, snapshot) => snapshot.data == null
          ? const SizedBox.shrink()
          : CustomPaint(
              painter: _FlagClipPainter(MapCamera.of(context), snapshot.data!, widget.opacity),
              child: const SizedBox.expand(),
            ),
    ),
  );
}

class _FlagClipPainter extends CustomPainter {
  const _FlagClipPainter(this.camera, this.image, this.opacity);

  final MapCamera camera;
  final ui.Image image;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final clip = Path()..fillType = PathFillType.evenOdd;
    for (final country in euCountries) {
      for (final ring in country.rings) {
        for (final (i, point) in ring.indexed) {
          final offset = camera.getOffsetFromOrigin(point);
          if (i == 0) {
            clip.moveTo(offset.dx, offset.dy);
          } else {
            clip.lineTo(offset.dx, offset.dy);
          }
        }
        clip.close();
      }
    }

    final northWest = camera.getOffsetFromOrigin(LatLng(euBounds.north, euBounds.west));
    final southEast = camera.getOffsetFromOrigin(LatLng(euBounds.south, euBounds.east));
    final europeRect = Rect.fromLTRB(
      math.min(northWest.dx, southEast.dx),
      math.min(northWest.dy, southEast.dy),
      math.max(northWest.dx, southEast.dx),
      math.max(northWest.dy, southEast.dy),
    );

    final scale = math.max(europeRect.width / image.width, europeRect.height / image.height);
    final destination = Rect.fromCenter(
      center: europeRect.center,
      width: image.width * scale,
      height: image.height * scale,
    );

    canvas.save();
    canvas.clipPath(clip);
    canvas.saveLayer(destination, Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: opacity));
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      destination,
      Paint(),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlagClipPainter oldDelegate) =>
      oldDelegate.camera != camera || oldDelegate.image != image || oldDelegate.opacity != opacity;
}

/// The classic location dot: a blue disc with a white ring and a lighter core.
class LocationDot extends StatelessWidget {
  const LocationDot({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _LocationDotPainter(), size: Size(26, 26));
}

class _LocationDotPainter extends CustomPainter {
  const _LocationDotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawCircle(center, 12, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(center, 9, Paint()..color = const Color(0xFF1A73E8));
    canvas.drawCircle(center, 4, Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(_LocationDotPainter oldDelegate) => false;
}
