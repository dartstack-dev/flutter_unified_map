import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

/// flutter_map's `CircleMarker`. A metre radius ([useRadiusInMeter]) is a native circle (Google `Circle`, MapKit
/// `MKCircle`). A pixel radius keeps its size on screen at every moment, as in flutter_map: natively it is drawn as a
/// marker showing a rasterised circle (fill and border), anchored at its center.
@immutable
class CircleMarker<R extends Object> {
  final Key? key;
  final LatLng point;
  final double radius;
  final Color color;
  final double borderStrokeWidth;
  final Color borderColor;
  final bool useRadiusInMeter;
  final R? hitValue;

  const CircleMarker({
    this.key,
    required this.point,
    required this.radius,
    this.color = const Color(0xFF00FF00),
    this.borderStrokeWidth = 0.0,
    this.borderColor = const Color(0xFFFFFF00),
    this.useRadiusInMeter = false,
    this.hitValue,
  });
}
