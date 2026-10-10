import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
// ignore: deprecated_member_use
import 'package:flutter_map/flutter_map.dart' show LatLngBounds, PolygonLabelPlacement, StrokePattern;
import 'package:latlong2/latlong.dart';

import '../../native/native_params.dart';
import 'label/placement_calculator.dart';

/// flutter_map's `Polygon`, plus [nativeParams]. Per backend:
/// - [pattern], [strokeCap], [strokeJoin]: natively the stroke is dashed or dotted (Google `strokePattern`, MapKit
///   `lineDashPattern`), joined as asked (Google `strokeJointType`, MapKit `lineJoin`); caps only show at dash ends
///   (MapKit `lineCap`, Google draws them butt).
/// - [disableHolesBorder]: drawn by composition natively (the polygon without stroke plus its outer ring as a line).
/// - [label]: natively a marker showing the rasterised text ([labelStyle]) at [labelPosition], hidden while the
///   polygon is narrower on screen than the label (checked when the camera settles); [rotateLabel] true keeps it
///   upright, false turns it with the map, as flutter_map.
@immutable
class Polygon<R extends Object> {
  final List<LatLng> points;
  final List<List<LatLng>>? holePointsList;
  final Color? color;
  final double borderStrokeWidth;
  final Color borderColor;
  final bool disableHolesBorder;
  final StrokePattern pattern;
  final StrokeCap strokeCap;
  final StrokeJoin strokeJoin;
  final String? label;
  final TextStyle labelStyle;

  @Deprecated(
    'Use `labelPlacementCalculator` with the equivalent calculator instead. '
    'Then, remove any arguments to this parameter and allow it to default. '
    'This enables more flexibility and extensibility. '
    'This was deprecated after v8.2.0, and will be removed in a future version.',
  )
  final PolygonLabelPlacement labelPlacement;
  final PolygonLabelPlacementCalculator? _labelPlacementCalculator;
  final bool rotateLabel;
  final R? hitValue;

  /// Native-only settings; ignored by the flutter_map backend. Not in flutter_map.
  final NativePolygonParams? nativeParams;

  const Polygon({
    required this.points,
    this.holePointsList,
    this.color,
    this.borderStrokeWidth = 0,
    this.borderColor = const Color(0xFFFFFF00),
    this.disableHolesBorder = false,
    this.pattern = const StrokePattern.solid(),
    this.strokeCap = StrokeCap.round,
    this.strokeJoin = StrokeJoin.round,
    this.label,
    this.labelStyle = const TextStyle(),
    @Deprecated(
      'Use `labelPlacementCalculator` with the equivalent calculator instead. '
      'Then, remove any arguments to this parameter and allow it to default. '
      'This enables more flexibility and extensibility. '
      'This was deprecated after v8.2.0, and will be removed in a future version.',
    )
    // ignore: deprecated_member_use
    this.labelPlacement = PolygonLabelPlacement.centroid,
    this._labelPlacementCalculator,
    this.rotateLabel = false,
    this.hitValue,
    this.nativeParams,
  });

  PolygonLabelPlacementCalculator get labelPlacementCalculator =>
      _labelPlacementCalculator ??
      // ignore: deprecated_member_use, deprecated_member_use_from_same_package
      switch (labelPlacement) {
        // ignore: deprecated_member_use
        PolygonLabelPlacement.centroid => const PolygonLabelPlacementCalculator.centroid(),
        // ignore: deprecated_member_use
        PolygonLabelPlacement.centroidWithMultiWorld =>
          const PolygonLabelPlacementCalculator.simpleMultiWorldCentroid(),
        // ignore: deprecated_member_use
        PolygonLabelPlacement.polylabel => const PolygonLabelPlacementCalculator.polylabel(),
      };

  LatLng get labelPosition => labelPlacementCalculator(this);

  LatLngBounds get boundingBox => LatLngBounds.fromPoints(points);

  /// The laid out [label] in [labelStyle], or null without a label.
  TextPainter? get textPainter {
    final text = label;
    if (text == null) return null;
    return TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
  }

  static bool isClockwise(List<LatLng> points) {
    double sum = 0;
    for (var i = 0; i < points.length; ++i) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      sum += (b.longitude - a.longitude) * (b.latitude + a.latitude);
    }
    return sum >= 0;
  }

  int get renderHashCode => Object.hash(
    color,
    borderStrokeWidth,
    borderColor,
    disableHolesBorder,
    pattern,
    strokeCap,
    strokeJoin,
    color != null && isClockwise(points),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Polygon &&
          color == other.color &&
          borderStrokeWidth == other.borderStrokeWidth &&
          borderColor == other.borderColor &&
          disableHolesBorder == other.disableHolesBorder &&
          pattern == other.pattern &&
          strokeCap == other.strokeCap &&
          strokeJoin == other.strokeJoin &&
          label == other.label &&
          labelStyle == other.labelStyle &&
          // ignore: deprecated_member_use_from_same_package
          labelPlacement == other.labelPlacement &&
          labelPlacementCalculator == other.labelPlacementCalculator &&
          rotateLabel == other.rotateLabel &&
          hitValue == other.hitValue &&
          nativeParams == other.nativeParams &&
          listEquals(holePointsList, other.holePointsList) &&
          listEquals(points, other.points));

  @override
  int get hashCode => Object.hashAll([
    ...points,
    label,
    labelStyle,
    // ignore: deprecated_member_use_from_same_package
    labelPlacement,
    labelPlacementCalculator,
    rotateLabel,
    renderHashCode,
    nativeParams,
  ]);
}
