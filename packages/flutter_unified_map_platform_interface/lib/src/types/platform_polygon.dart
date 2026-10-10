import 'package:flutter/painting.dart' show Color;
import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';

import 'platform_map_object.dart';
import 'platform_polyline.dart'
    show PlatformStrokeCap, PlatformStrokeJoin, sameDashPatterns, samePointLists, samePoints;

/// A filled area drawn natively, with optional [holes]. [strokeWidth] is in logical pixels; every ring (outer and
/// holes) is stroked. The core draws flutter_map's `disableHolesBorder` by composition (stroke width 0 plus
/// polylines), so platforms never need to skip hole borders.
///
/// [dashPattern] alternates on/off lengths of the stroke in logical pixels (Google `strokePattern` with `Dash` /
/// `Gap` / `Dot`, MapKit `MKPolygonRenderer.lineDashPattern`); null is solid. [cap] applies to dash ends (MapKit
/// `lineCap`; Google draws dash ends butt, its closest equivalent) and [join] to corners (Google
/// `strokeJointType`: miter → `DEFAULT`, round → `ROUND`, bevel → `BEVEL`; MapKit `lineJoin`).
/// [geodesic] draws great-circle edges (Google `PolygonOptions.geodesic`; MapKit and flutter_map draw straight
/// edges, so the core sets it only from `NativePolygonParams.android`).
@immutable
class PlatformPolygon extends PlatformMapObject {
  @override
  final String id;
  final List<LatLng> points;
  final List<List<LatLng>> holes;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;
  final double zIndex;
  final List<double>? dashPattern;
  final PlatformStrokeCap cap;
  final PlatformStrokeJoin join;
  final bool geodesic;

  const PlatformPolygon({
    required this.id,
    required this.points,
    this.holes = const [],
    this.fillColor = const Color(0x00000000),
    this.strokeColor = const Color(0xFF000000),
    this.strokeWidth = 1,
    this.zIndex = 0,
    this.dashPattern,
    this.cap = PlatformStrokeCap.round,
    this.join = PlatformStrokeJoin.round,
    this.geodesic = false,
  });

  @override
  bool operator ==(Object other) =>
      other is PlatformPolygon &&
      other.id == id &&
      samePoints(other.points, points) &&
      samePointLists(other.holes, holes) &&
      other.fillColor == fillColor &&
      other.strokeColor == strokeColor &&
      other.strokeWidth == strokeWidth &&
      other.zIndex == zIndex &&
      sameDashPatterns(other.dashPattern, dashPattern) &&
      other.cap == cap &&
      other.join == join &&
      other.geodesic == geodesic;

  @override
  int get hashCode => Object.hash(
    id,
    Object.hashAll(points),
    holes.length,
    fillColor,
    strokeColor,
    strokeWidth,
    zIndex,
    cap,
    join,
    geodesic,
  );

  @override
  String toString() => 'PlatformPolygon($id, ${points.length} points, ${holes.length} holes)';
}
