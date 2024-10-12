// Ported from flutter_map 8.3.2 (`CameraConstraint`), BSD-3-Clause, Copyright (c) 2018 the flutter_map authors.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';

import 'map_camera.dart';

/// Limits where the camera can go. Same API as flutter_map's (`MapOptions.cameraConstraint`).
///
/// Controller moves are constrained in Dart on every backend, with [constrain], exactly as flutter_map. Gestures:
/// - flutter_map backend: flutter_map itself;
/// - [ContainCameraCenter]: exact natively (Google `setLatLngBoundsForCameraTarget`, MapKit `cameraBoundary`);
/// - [ContainCamera] / [ContainCameraLatitude]: natively the core turns the bounds into a center boundary shrunk by
///   half the view at the current zoom and rotation (recomputed when the camera settles and when the zoom level
///   changes) and raises the minimum zoom so the view fits; during a pinch an edge can show briefly until the next
///   update;
/// - a custom subclass: when a gesture ends, the core animates the camera to [constrain]'s result (or back to the last
///   valid camera when it returns null), a snap-back where flutter_map stops the gesture.
@immutable
abstract class CameraConstraint {
  const CameraConstraint();

  const factory CameraConstraint.unconstrained() = UnconstrainedCamera._;

  /// Keeps the camera center inside [bounds].
  const factory CameraConstraint.containCenter({required LatLngBounds bounds}) = ContainCameraCenter._;

  /// Keeps the whole view inside [bounds].
  const factory CameraConstraint.contain({required LatLngBounds bounds}) = ContainCamera._;

  /// Keeps the whole view between latitudes [a] and [b] (in any order).
  const factory CameraConstraint.containLatitude([double a, double b]) = ContainCameraLatitude._;

  /// The camera closest to [camera] that satisfies the constraint, or null when none does at its zoom.
  MapCamera? constrain(MapCamera camera);
}

@immutable
class UnconstrainedCamera extends CameraConstraint {
  const UnconstrainedCamera._();

  @override
  MapCamera constrain(MapCamera camera) => camera;
}

@immutable
class ContainCameraCenter extends CameraConstraint {
  const ContainCameraCenter._({required this.bounds});

  final LatLngBounds bounds;

  @override
  MapCamera constrain(MapCamera camera) => camera.withPosition(
    center: LatLng(
      camera.center.latitude.clamp(bounds.south, bounds.north),
      camera.center.longitude.clamp(bounds.west, bounds.east),
    ),
  );

  @override
  bool operator ==(Object other) => other is ContainCameraCenter && other.bounds == bounds;

  @override
  int get hashCode => bounds.hashCode;
}

@immutable
class ContainCamera extends CameraConstraint {
  const ContainCamera._({required this.bounds});

  final LatLngBounds bounds;

  @override
  MapCamera? constrain(MapCamera camera) {
    final testZoom = camera.zoom;
    final testCenter = camera.center;
    final nePixel = camera.projectAtZoom(bounds.northEast, testZoom);
    final swPixel = camera.projectAtZoom(bounds.southWest, testZoom);
    final halfSize = camera.size / 2;
    final leftOkCenter = math.min(swPixel.dx, nePixel.dx) + halfSize.width;
    final rightOkCenter = math.max(swPixel.dx, nePixel.dx) - halfSize.width;
    final topOkCenter = math.min(swPixel.dy, nePixel.dy) + halfSize.height;
    final botOkCenter = math.max(swPixel.dy, nePixel.dy) - halfSize.height;
    if (leftOkCenter > rightOkCenter || topOkCenter > botOkCenter) return null;
    final centerPix = camera.projectAtZoom(testCenter, testZoom);
    final newCenterPix = Offset(
      centerPix.dx.clamp(leftOkCenter, rightOkCenter),
      centerPix.dy.clamp(topOkCenter, botOkCenter),
    );
    if (newCenterPix == centerPix) return camera;
    return camera.withPosition(center: camera.unprojectAtZoom(newCenterPix, testZoom));
  }

  @override
  bool operator ==(Object other) => other is ContainCamera && other.bounds == bounds;

  @override
  int get hashCode => bounds.hashCode;
}

@immutable
class ContainCameraLatitude extends CameraConstraint {
  const ContainCameraLatitude._([this.a = 90, this.b = -90]);

  final double a;
  final double b;

  @override
  MapCamera? constrain(MapCamera camera) {
    final testZoom = camera.zoom;
    final testCenter = camera.center;
    final aPixel = camera.projectAtZoom(LatLng(a, 0), testZoom);
    final bPixel = camera.projectAtZoom(LatLng(b, 0), testZoom);
    final halfSize = camera.size / 2;
    final topOkCenter = math.min(aPixel.dy, bPixel.dy) + halfSize.height;
    final botOkCenter = math.max(aPixel.dy, bPixel.dy) - halfSize.height;
    if (topOkCenter > botOkCenter) return null;
    final centerPix = camera.projectAtZoom(testCenter, testZoom);
    final newCenterPix = Offset(centerPix.dx, centerPix.dy.clamp(topOkCenter, botOkCenter));
    if (newCenterPix == centerPix) return camera;
    return camera.withPosition(center: camera.unprojectAtZoom(newCenterPix, testZoom));
  }

  @override
  bool operator ==(Object other) => other is ContainCameraLatitude && other.a == a && other.b == b;

  @override
  int get hashCode => a.hashCode ^ b.hashCode;
}
