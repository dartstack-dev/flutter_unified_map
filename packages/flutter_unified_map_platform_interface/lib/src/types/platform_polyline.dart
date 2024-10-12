import 'package:flutter/painting.dart' show Color;
import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';

import 'platform_map_object.dart';

enum PlatformStrokeCap { butt, round, square }

enum PlatformStrokeJoin { miter, round, bevel }

/// A line drawn natively. Widths are logical pixels, unless [widthInMeters].
///
/// [borderWidth] > 0 draws a second line of total width `width + borderWidth` (flutter_map's `borderStrokeWidth`)
/// in [borderColor] underneath, at `zIndex - 0.5`. [dashPattern] alternates on/off lengths in logical pixels; null
/// is solid; an on length of 0 with a round [cap] draws round dots (Google `Dot()`, MapKit `lineDashPattern` with a
/// round cap).
///
/// [gradientColors], when not null, has one colour per point and replaces [color]: the line is shaded from vertex to
/// vertex (Google one `StyleSpan(StrokeStyle.gradientBuilder(from, to))` per segment, MapKit
/// `MKGradientPolylineRenderer` with the points' fractional distances as locations). The core computes the colours
/// so that the result matches flutter_map's straight gradient from the first to the last point.
///
/// [widthInMeters]: [width] and [borderWidth] are metres on the ground (flutter_map's `useStrokeWidthInMeter`), so
/// the line keeps its ground width while zooming: MapKit sets the renderer's `lineWidth` from `zoomScale` on every
/// draw; Google converts with the camera's metres per pixel at the line's mean latitude on every camera move; the
/// flutter_map backend passes the flag to flutter_map. [geodesic] draws great-circle segments (Google `geodesic`,
/// MapKit `MKGeodesicPolyline`; flutter_map draws straight lines).
@immutable
class PlatformPolyline extends PlatformMapObject {
  @override
  final String id;
  final List<LatLng> points;
  final Color color;
  final double width;
  final Color borderColor;
  final double borderWidth;
  final List<double>? dashPattern;
  final PlatformStrokeCap cap;
  final PlatformStrokeJoin join;
  final double zIndex;
  final bool geodesic;
  final List<Color>? gradientColors;
  final bool widthInMeters;

  const PlatformPolyline({
    required this.id,
    required this.points,
    required this.color,
    this.width = 1,
    this.borderColor = const Color(0x00000000),
    this.borderWidth = 0,
    this.dashPattern,
    this.cap = PlatformStrokeCap.round,
    this.join = PlatformStrokeJoin.round,
    this.zIndex = 0,
    this.geodesic = false,
    this.gradientColors,
    this.widthInMeters = false,
  });

  @override
  bool operator ==(Object other) =>
      other is PlatformPolyline &&
      other.id == id &&
      _samePoints(other.points, points) &&
      other.color == color &&
      other.width == width &&
      other.borderColor == borderColor &&
      other.borderWidth == borderWidth &&
      _sameDoubles(other.dashPattern, dashPattern) &&
      other.cap == cap &&
      other.join == join &&
      other.zIndex == zIndex &&
      other.geodesic == geodesic &&
      _sameColors(other.gradientColors, gradientColors) &&
      other.widthInMeters == widthInMeters;

  @override
  int get hashCode => Object.hash(
    id,
    Object.hashAll(points),
    color,
    width,
    borderColor,
    borderWidth,
    cap,
    join,
    zIndex,
    geodesic,
    gradientColors == null ? null : Object.hashAll(gradientColors!),
    widthInMeters,
  );

  @override
  String toString() => 'PlatformPolyline($id, ${points.length} points)';
}

bool _samePoints(List<LatLng> a, List<LatLng> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameDoubles(List<double>? a, List<double>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameColors(List<Color>? a, List<Color>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Shared by polygons: on/off length equality.
bool sameDashPatterns(List<double>? a, List<double>? b) => _sameDoubles(a, b);

/// Shared by polygons: ordered point-list equality.
bool samePointLists(List<List<LatLng>> a, List<List<LatLng>> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_samePoints(a[i], b[i])) return false;
  }
  return true;
}

bool samePoints(List<LatLng> a, List<LatLng> b) => _samePoints(a, b);
