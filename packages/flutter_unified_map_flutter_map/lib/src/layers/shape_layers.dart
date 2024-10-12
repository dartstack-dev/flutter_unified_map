import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

Widget polylineLayer(List<PlatformPolyline> polylines) => PolylineLayer(
  polylines: [
    for (final line in polylines)
      if (line.points.isNotEmpty)
        Polyline(
          points: line.points,
          color: line.color,
          strokeWidth: line.width,
          borderColor: line.borderColor,
          borderStrokeWidth: line.borderWidth,
          pattern: _pattern(line.dashPattern),
          strokeCap: _cap(line.cap),
          strokeJoin: _join(line.join),
        ),
  ],
);

Widget polygonLayer(List<PlatformPolygon> polygons) => PolygonLayer(
  polygons: [
    for (final polygon in polygons)
      if (polygon.points.isNotEmpty)
        Polygon(
          points: polygon.points,
          holePointsList: polygon.holes.isEmpty ? null : polygon.holes,
          color: polygon.fillColor,
          borderColor: polygon.strokeColor,
          borderStrokeWidth: polygon.strokeWidth,
        ),
  ],
);

Widget circleLayer(List<PlatformCircle> circles) => CircleLayer(
  circles: [
    for (final circle in circles)
      CircleMarker(
        point: circle.center,
        radius: circle.radiusMeters,
        useRadiusInMeter: true,
        color: circle.fillColor,
        borderColor: circle.strokeColor,
        borderStrokeWidth: circle.strokeWidth,
      ),
  ],
);

/// As on Android and Apple: an odd pattern repeats whole (`[10]` is 10 on, 10 off) and lengths stay in logical
/// pixels, where flutter_map would stretch them to fit each line.
StrokePattern _pattern(List<double>? dashPattern) {
  if (dashPattern == null || dashPattern.isEmpty) return const StrokePattern.solid();
  final segments = dashPattern.length.isEven ? dashPattern : [...dashPattern, ...dashPattern];
  return StrokePattern.dashed(segments: segments, patternFit: PatternFit.none);
}

StrokeCap _cap(PlatformStrokeCap cap) => switch (cap) {
  PlatformStrokeCap.butt => StrokeCap.butt,
  PlatformStrokeCap.round => StrokeCap.round,
  PlatformStrokeCap.square => StrokeCap.square,
};

StrokeJoin _join(PlatformStrokeJoin join) => switch (join) {
  PlatformStrokeJoin.miter => StrokeJoin.miter,
  PlatformStrokeJoin.round => StrokeJoin.round,
  PlatformStrokeJoin.bevel => StrokeJoin.bevel,
};
