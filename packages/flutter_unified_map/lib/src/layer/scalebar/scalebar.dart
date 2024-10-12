// Ported from flutter_map 8.3.2 (`Scalebar`), BSD-3-Clause, Copyright (c) 2018 the flutter_map authors.
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show Epsg3857;
import 'package:latlong2/latlong.dart';

import '../../map/camera/map_camera.dart';

/// flutter_map's `Scalebar`: a metric scale bar drawn by Flutter over the map, on every backend. Place it in
/// `UnifiedMap.children`. (MapKit's own scale bar is `AppleMapParams.showsScale`.)
class Scalebar extends StatelessWidget {
  final Alignment alignment;
  final TextStyle? textStyle;
  final Color lineColor;
  final double strokeWidth;
  final double lineHeight;
  final EdgeInsets padding;
  final ScalebarLength length;

  const Scalebar({
    super.key,
    this.alignment = Alignment.topRight,
    this.textStyle = const TextStyle(color: Color(0xFF000000), fontSize: 14),
    this.lineColor = const Color(0xFF000000),
    this.strokeWidth = 2,
    this.lineHeight = 5,
    this.padding = const EdgeInsets.all(10),
    this.length = ScalebarLength.m,
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    const dst = Distance();
    final latLngCenter = camera.center;
    final offsetCenter = camera.projectAtZoom(latLngCenter);
    final absLat = latLngCenter.latitude.abs();
    var index = camera.zoom - length.value;
    if (camera.crs is Epsg3857) {
      if (absLat > 85) return const SizedBox.shrink();
      if (absLat > 60) index++;
      if (absLat > 80) index++;
    }
    final metricDst = _metricScale[index.round().clamp(0, _metricScale.length - 1)];
    var latLngOffset = dst.offset(latLngCenter, metricDst.toDouble(), 90);
    if (latLngOffset.longitude < latLngCenter.longitude) {
      latLngOffset = dst.offset(latLngCenter, metricDst.toDouble(), 270);
    }
    final offsetDistance = camera.projectAtZoom(latLngOffset);
    final label = metricDst < 1000 ? '$metricDst m' : '${(metricDst / 1000.0).toStringAsFixed(0)} km';
    final scalebarPainter = _SimpleScalebarPainter(
      scalebarLength: (offsetDistance.dx - offsetCenter.dx).abs(),
      text: TextSpan(style: textStyle, text: label),
      alignment: alignment,
      lineColor: lineColor,
      strokeWidth: strokeWidth,
      lineHeight: lineHeight,
    );
    return Align(
      alignment: alignment,
      child: Padding(
        padding: padding,
        child: CustomPaint(size: scalebarPainter.widgetSize, painter: scalebarPainter),
      ),
    );
  }
}

const _metricScale = <int>[
  15000000,
  8000000,
  4000000,
  2000000,
  1000000,
  500000,
  250000,
  100000,
  50000,
  25000,
  15000,
  8000,
  4000,
  2000,
  1000,
  500,
  250,
  100,
  50,
  25,
  10,
  5,
  2,
  1,
];

/// How long the [Scalebar] is, relative to the default [m].
enum ScalebarLength {
  s(-2),
  m(-1),
  l(0),
  xl(1),
  xxl(2);

  final int value;

  const ScalebarLength(this.value);
}

/// Paints a [Scalebar].
abstract class ScalebarPainter extends CustomPainter {
  Size get widgetSize;
}

class _SimpleScalebarPainter extends ScalebarPainter {
  static const _topPaddingCorr = -5.0;

  final double scalebarLength;
  final double strokeWidth;
  final double lineHeight;
  final Alignment alignment;

  late final _halfStrokeWidth = strokeWidth / 2;
  late final _halfScalebarLength = scalebarLength / 2;
  late final _halfWidgetWidth = widgetSize.width / 2;

  final Paint _linePaint = Paint();
  final TextPainter _textPainter;

  @override
  late final Size widgetSize = Size(
    max(scalebarLength + strokeWidth, _textPainter.width),
    _textPainter.height + _topPaddingCorr + lineHeight,
  );

  _SimpleScalebarPainter({
    required this.scalebarLength,
    required TextSpan text,
    required this.strokeWidth,
    required this.lineHeight,
    required Color lineColor,
    required this.alignment,
  }) : _textPainter = TextPainter(text: text, textDirection: TextDirection.ltr, maxLines: 1) {
    _linePaint
      ..color = lineColor
      ..strokeCap = StrokeCap.square
      ..strokeWidth = strokeWidth;
    _textPainter.layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final labelX = widgetSize.width / 2 - _textPainter.width / 2 + _halfStrokeWidth;
    _textPainter.paint(canvas, Offset(max(0, labelX), _topPaddingCorr));
    final paddingTop = _topPaddingCorr + _textPainter.height;
    final lineBottomY = lineHeight + paddingTop;
    final double lineLeftX;
    final double lineRightX;
    final double lineMiddleX;
    switch (alignment.x) {
      case -1:
        lineLeftX = _halfStrokeWidth;
        lineRightX = lineLeftX + scalebarLength;
        lineMiddleX = lineLeftX + _halfScalebarLength;
      case 1:
        lineRightX = widgetSize.width - _halfStrokeWidth;
        lineLeftX = lineRightX - scalebarLength;
        lineMiddleX = lineRightX - _halfScalebarLength;
      default:
        lineMiddleX = _halfWidgetWidth;
        lineLeftX = lineMiddleX - _halfScalebarLength;
        lineRightX = lineMiddleX + _halfScalebarLength;
    }
    final linePoints = Float32List.fromList(<double>[
      lineLeftX,
      paddingTop,
      lineLeftX,
      lineBottomY,
      lineRightX,
      paddingTop,
      lineRightX,
      lineBottomY,
      lineMiddleX,
      paddingTop + lineHeight / 2,
      lineMiddleX,
      lineBottomY,
      lineLeftX,
      lineBottomY,
      lineRightX,
      lineBottomY,
    ]);
    canvas.drawRawPoints(PointMode.lines, linePoints, _linePaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
