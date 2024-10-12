import 'package:flutter/painting.dart' show Color;
import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';

import 'platform_map_object.dart';

/// A circle drawn natively. [radiusMeters] is geographic; the core converts pixel radii at the current zoom.
@immutable
class PlatformCircle extends PlatformMapObject {
  @override
  final String id;
  final LatLng center;
  final double radiusMeters;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;
  final double zIndex;

  const PlatformCircle({
    required this.id,
    required this.center,
    required this.radiusMeters,
    this.fillColor = const Color(0x00000000),
    this.strokeColor = const Color(0xFF000000),
    this.strokeWidth = 1,
    this.zIndex = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is PlatformCircle &&
      other.id == id &&
      other.center == center &&
      other.radiusMeters == radiusMeters &&
      other.fillColor == fillColor &&
      other.strokeColor == strokeColor &&
      other.strokeWidth == strokeWidth &&
      other.zIndex == zIndex;

  @override
  int get hashCode => Object.hash(id, center, radiusMeters, fillColor, strokeColor, strokeWidth, zIndex);

  @override
  String toString() => 'PlatformCircle($id, $center, $radiusMeters m)';
}
