import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds, StrokePattern;
import 'package:latlong2/latlong.dart';

import '../../native/native_params.dart';

/// flutter_map's `Polyline`, plus [nativeParams]. Per backend:
/// - [pattern]: dashes and dots natively (Google `Dash` / `Gap` / `Dot`, MapKit `lineDashPattern`); the
///   `patternFit` of a dashed or dotted pattern is applied by the core, which rescales the segments to the line's
///   length on screen when the camera settles (so it drifts slightly during a pinch).
/// - [gradientColors] / [colorsStop]: flutter_map draws a straight linear gradient from the first to the last point;
///   natively the core gives each vertex the colour of its projection on that axis and the platform shades from
///   vertex to vertex (Google style spans, MapKit `MKGradientPolylineRenderer`).
/// - [useStrokeWidthInMeter]: the width (and border) keep their ground size while zooming (MapKit exact, Google
///   updated on every camera move).
/// - culling and simplification are left to the native map.
@immutable
class Polyline<R extends Object> {
  final List<LatLng> points;
  final double strokeWidth;
  final StrokePattern pattern;
  final Color color;
  final double borderStrokeWidth;
  final Color borderColor;
  final List<Color>? gradientColors;
  final List<double>? colorsStop;
  final StrokeCap strokeCap;
  final StrokeJoin strokeJoin;
  final bool useStrokeWidthInMeter;
  final R? hitValue;

  /// Native-only settings; ignored by the flutter_map backend. Not in flutter_map.
  final NativePolylineParams? nativeParams;

  const Polyline({
    required this.points,
    this.strokeWidth = 1.0,
    this.pattern = const StrokePattern.solid(),
    this.color = const Color(0xFF00FF00),
    this.borderStrokeWidth = 0.0,
    this.borderColor = const Color(0xFFFFFF00),
    this.gradientColors,
    this.colorsStop,
    this.strokeCap = StrokeCap.round,
    this.strokeJoin = StrokeJoin.round,
    this.useStrokeWidthInMeter = false,
    this.hitValue,
    this.nativeParams,
  });

  LatLngBounds get boundingBox => LatLngBounds.fromPoints(points);

  int get renderHashCode => Object.hash(
    strokeWidth,
    color,
    borderStrokeWidth,
    borderColor,
    gradientColors,
    colorsStop,
    pattern,
    strokeCap,
    strokeJoin,
    useStrokeWidthInMeter,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Polyline &&
          strokeWidth == other.strokeWidth &&
          color == other.color &&
          borderStrokeWidth == other.borderStrokeWidth &&
          borderColor == other.borderColor &&
          pattern == other.pattern &&
          strokeCap == other.strokeCap &&
          strokeJoin == other.strokeJoin &&
          useStrokeWidthInMeter == other.useStrokeWidthInMeter &&
          hitValue == other.hitValue &&
          nativeParams == other.nativeParams &&
          listEquals(colorsStop, other.colorsStop) &&
          listEquals(gradientColors, other.gradientColors) &&
          listEquals(points, other.points));

  @override
  int get hashCode => Object.hashAll([...points, renderHashCode, nativeParams]);
}
