import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';

/// Camera state shared by every platform.
///
/// [zoom] follows the Web Mercator convention used by flutter_map and Google Maps: at zoom `z` the world is
/// `256 * 2^z` logical pixels wide. MapKit implementations convert from span / altitude.
/// [bearing] is a compass heading in degrees, clockwise from north (Google `bearing`, MapKit `heading`). It is the
/// opposite of flutter_map's `rotation`: `bearing = -rotation mod 360`.
/// [tilt] is in degrees, 0 = looking straight down.
@immutable
class PlatformCamera {
  final LatLng center;
  final double zoom;
  final double bearing;
  final double tilt;

  const PlatformCamera({required this.center, required this.zoom, this.bearing = 0, this.tilt = 0});

  PlatformCamera copyWith({LatLng? center, double? zoom, double? bearing, double? tilt}) => PlatformCamera(
    center: center ?? this.center,
    zoom: zoom ?? this.zoom,
    bearing: bearing ?? this.bearing,
    tilt: tilt ?? this.tilt,
  );

  @override
  bool operator ==(Object other) =>
      other is PlatformCamera &&
      other.center == center &&
      other.zoom == zoom &&
      other.bearing == bearing &&
      other.tilt == tilt;

  @override
  int get hashCode => Object.hash(center, zoom, bearing, tilt);

  @override
  String toString() => 'PlatformCamera($center, zoom $zoom, bearing $bearing, tilt $tilt)';
}

/// Axis-aligned bounds in degrees. [northEast].longitude may be smaller than [southWest].longitude when the
/// bounds cross the antimeridian.
@immutable
class PlatformLatLngBounds {
  final LatLng southWest;
  final LatLng northEast;

  const PlatformLatLngBounds({required this.southWest, required this.northEast});

  @override
  bool operator ==(Object other) =>
      other is PlatformLatLngBounds && other.southWest == southWest && other.northEast == northEast;

  @override
  int get hashCode => Object.hash(southWest, northEast);

  @override
  String toString() => 'PlatformLatLngBounds($southWest, $northEast)';
}

/// A camera change request. Implementations apply it instantly, or animated when the caller gives a duration.
@immutable
sealed class PlatformCameraUpdate {
  const PlatformCameraUpdate();

  /// Moves to the given values; a null field keeps the current value.
  const factory PlatformCameraUpdate.newCamera({LatLng? center, double? zoom, double? bearing, double? tilt}) =
      PlatformCameraUpdateNewCamera;

  /// Fits [bounds] inside the view minus [padding] (logical pixels, may be asymmetric), capped at [maxZoom].
  /// [bearing] null keeps the current bearing.
  const factory PlatformCameraUpdate.fitBounds(
    PlatformLatLngBounds bounds, {
    EdgeInsets padding,
    double? maxZoom,
    double? bearing,
  }) = PlatformCameraUpdateFitBounds;

  /// Scrolls the camera by logical pixels on screen (x to the right, y downwards), after rotation.
  const factory PlatformCameraUpdate.scrollBy(double dx, double dy) = PlatformCameraUpdateScrollBy;

  /// Zooms by [amount] levels around [focus] (screen point, logical pixels) or around the center when null.
  const factory PlatformCameraUpdate.zoomBy(double amount, {Offset? focus}) = PlatformCameraUpdateZoomBy;
}

class PlatformCameraUpdateNewCamera extends PlatformCameraUpdate {
  final LatLng? center;
  final double? zoom;
  final double? bearing;
  final double? tilt;

  const PlatformCameraUpdateNewCamera({this.center, this.zoom, this.bearing, this.tilt});

  @override
  String toString() => 'newCamera($center, $zoom, $bearing, $tilt)';
}

class PlatformCameraUpdateFitBounds extends PlatformCameraUpdate {
  final PlatformLatLngBounds bounds;
  final EdgeInsets padding;
  final double? maxZoom;
  final double? bearing;

  const PlatformCameraUpdateFitBounds(this.bounds, {this.padding = EdgeInsets.zero, this.maxZoom, this.bearing});

  @override
  String toString() => 'fitBounds($bounds, $padding, max $maxZoom)';
}

class PlatformCameraUpdateScrollBy extends PlatformCameraUpdate {
  final double dx;
  final double dy;

  const PlatformCameraUpdateScrollBy(this.dx, this.dy);

  @override
  String toString() => 'scrollBy($dx, $dy)';
}

class PlatformCameraUpdateZoomBy extends PlatformCameraUpdate {
  final double amount;
  final Offset? focus;

  const PlatformCameraUpdateZoomBy(this.amount, {this.focus});

  @override
  String toString() => 'zoomBy($amount, $focus)';
}

/// Screen point in logical pixels, relative to the map view's top-left corner.
@immutable
class Offset {
  final double dx;
  final double dy;

  const Offset(this.dx, this.dy);

  @override
  bool operator ==(Object other) => other is Offset && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => 'Offset($dx, $dy)';
}
