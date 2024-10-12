import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/widgets.dart' show immutable;
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';

import 'camera_math.dart';
import 'map_camera.dart';

/// Describes a camera position by what must be visible. Same API as flutter_map's: subclass it and implement [fit]
/// for a custom fit.
///
/// `MapController.fitCamera` uses the native fit when it is exact (north-up [FitBounds] / [FitCoordinates] without
/// an integer or minimum zoom constraint); every other fit, custom ones included, is solved in Dart with [fit] and
/// sent as a camera position.
@immutable
abstract class CameraFit {
  const CameraFit();

  /// Fits [bounds] entirely inside the view minus [padding].
  const factory CameraFit.bounds({
    required LatLngBounds bounds,
    EdgeInsets padding,
    double? maxZoom,
    double minZoom,
    bool forceIntegerZoomLevel,
  }) = FitBounds;

  /// Fits the view inside [bounds] (no area outside the bounds visible).
  const factory CameraFit.insideBounds({
    required LatLngBounds bounds,
    EdgeInsets padding,
    double? maxZoom,
    double minZoom,
    bool forceIntegerZoomLevel,
  }) = FitInsideBounds;

  /// Fits every coordinate inside the view, honouring the current rotation.
  const factory CameraFit.coordinates({
    required List<LatLng> coordinates,
    EdgeInsets padding,
    double? maxZoom,
    double minZoom,
    bool forceIntegerZoomLevel,
  }) = FitCoordinates;

  /// [camera] moved (center and zoom) so that this fit is satisfied, keeping its rotation and size.
  MapCamera fit(MapCamera camera);
}

@immutable
class FitBounds extends CameraFit {
  final LatLngBounds bounds;
  final EdgeInsets padding;
  final double? maxZoom;
  final double minZoom;
  final bool forceIntegerZoomLevel;

  const FitBounds({
    required this.bounds,
    this.padding = EdgeInsets.zero,
    this.maxZoom,
    this.minZoom = 0,
    this.forceIntegerZoomLevel = false,
  });

  @override
  MapCamera fit(MapCamera camera) => fitCameraTo(camera, this);
}

@immutable
class FitInsideBounds extends CameraFit {
  final LatLngBounds bounds;
  final EdgeInsets padding;
  final double? maxZoom;
  final double minZoom;
  final bool forceIntegerZoomLevel;

  const FitInsideBounds({
    required this.bounds,
    this.padding = EdgeInsets.zero,
    this.maxZoom,
    this.minZoom = 0,
    this.forceIntegerZoomLevel = false,
  });

  @override
  MapCamera fit(MapCamera camera) => fitCameraTo(camera, this);
}

@immutable
class FitCoordinates extends CameraFit {
  final List<LatLng> coordinates;
  final EdgeInsets padding;
  final double? maxZoom;
  final double minZoom;
  final bool forceIntegerZoomLevel;

  const FitCoordinates({
    required this.coordinates,
    this.padding = EdgeInsets.zero,
    this.maxZoom,
    this.minZoom = 0,
    this.forceIntegerZoomLevel = false,
  });

  @override
  MapCamera fit(MapCamera camera) => fitCameraTo(camera, this);
}
