import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:latlong2/latlong.dart';

import 'camera_fit.dart';
import 'map_camera.dart';

/// Platform bearings are compass headings (the direction the top of the view faces, as on Google Maps and MapKit),
/// while flutter_map's rotation turns the map content clockwise: each is the other's opposite.
double bearingFromRotation(double rotation) => _negatedDegrees(rotation);

/// The rotation for [bearing], in [0, 360), or the one of its equivalents nearest [near] when given, so that the
/// rotation stays continuous as the map turns through north.
double rotationFromBearing(double bearing, {double? near}) {
  final rotation = _negatedDegrees(bearing);
  if (near == null) return rotation;
  final nearest = near + ((rotation - near + 540) % 360) - 180;
  return nearest == 0 ? 0 : nearest;
}

double _negatedDegrees(double degrees) {
  final normalized = (-degrees) % 360;
  return normalized == 0 ? 0 : normalized;
}

Offset rotateOffset(Offset p, double rad) {
  if (rad == 0) return p;
  final cos = math.cos(rad);
  final sin = math.sin(rad);
  return Offset(p.dx * cos - p.dy * sin, p.dx * sin + p.dy * cos);
}

/// The camera center that puts [point] at the view center plus [offset] (screen pixels) at [zoom] and
/// [rotation] degrees.
LatLng centerForOffset(MapCamera camera, LatLng point, double zoom, double rotation, Offset offset) {
  if (offset == Offset.zero) return point;
  final shift = rotateOffset(offset, -rotation * math.pi / 180);
  return camera.unprojectAtZoom(camera.projectAtZoom(point, zoom) - shift, zoom);
}

/// [camera] moved to satisfy one of the built-in fits.
MapCamera fitCameraTo(MapCamera camera, CameraFit fit) {
  final solved = solveCameraFit(camera, fit);
  return camera.withPosition(center: solved.center, zoom: solved.zoom);
}

/// Camera center and zoom for a [CameraFit], computed in Dart with [rotation] (defaults to the camera's). A custom
/// fit is solved by its own [CameraFit.fit].
({LatLng center, double zoom}) solveCameraFit(MapCamera camera, CameraFit fit, {double? rotation}) {
  if (fit is! FitBounds && fit is! FitInsideBounds && fit is! FitCoordinates) {
    final fitted = fit.fit(rotation == null ? camera : camera.withRotation(rotation));
    return (center: fitted.center, zoom: fitted.zoom);
  }
  final (points, inside, padding, maxZoom, minZoom, forceInteger) = switch (fit) {
    FitBounds f => (
      _corners(f.bounds.southWest, f.bounds.northEast),
      false,
      f.padding,
      f.maxZoom,
      f.minZoom,
      f.forceIntegerZoomLevel,
    ),
    FitInsideBounds f => (
      _corners(f.bounds.southWest, f.bounds.northEast),
      true,
      f.padding,
      f.maxZoom,
      f.minZoom,
      f.forceIntegerZoomLevel,
    ),
    FitCoordinates f => (f.coordinates, false, f.padding, f.maxZoom, f.minZoom, f.forceIntegerZoomLevel),
    _ => throw ArgumentError.value(fit, 'fit'),
  };
  final rad = (rotation ?? camera.rotation) * math.pi / 180;
  final topLeft = Offset(padding.left, padding.top);
  final bottomRight = Offset(padding.right, padding.bottom);

  var available = (camera.nonRotatedSize - (topLeft + bottomRight)) as Size;
  var centerShift = (bottomRight - topLeft) / 2;
  if (available.width <= 0 || available.height <= 0) {
    available = camera.nonRotatedSize;
    centerShift = Offset.zero;
  }
  final referenceZoom = camera.zoom;
  final box = _rotatedBox(camera, points, referenceZoom, rad);
  final scaleX = box.width == 0 ? double.infinity : available.width / box.width;
  final scaleY = box.height == 0 ? double.infinity : available.height / box.height;
  final scale = inside ? math.max(scaleX, scaleY) : math.min(scaleX, scaleY);
  var zoom = scale.isFinite ? referenceZoom + math.log(scale) / math.ln2 : double.infinity;
  if (forceInteger && zoom.isFinite) zoom = inside ? zoom.ceilToDouble() : zoom.floorToDouble();
  zoom = math.min(zoom, math.min(maxZoom ?? double.infinity, camera.maxZoom ?? defaultMaxZoom));
  zoom = math.max(zoom, math.max(minZoom, camera.minZoom ?? 0));

  final projected = _rotatedBox(camera, points, zoom, rad);
  final rotatedCenter = projected.center + centerShift;
  final center = camera.unprojectAtZoom(rotateOffset(rotatedCenter, -rad), zoom);
  return (center: center, zoom: zoom);
}

/// Upper zoom used when nothing else caps a fit, like the platforms' default maximum.
const double defaultMaxZoom = 22;

List<LatLng> _corners(LatLng southWest, LatLng northEast) => [
  southWest,
  northEast,
  LatLng(southWest.latitude, northEast.longitude),
  LatLng(northEast.latitude, southWest.longitude),
];

Rect _rotatedBox(MapCamera camera, List<LatLng> points, double zoom, double rad) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final point in points) {
    final p = rotateOffset(camera.projectAtZoom(point, zoom), rad);
    minX = math.min(minX, p.dx);
    minY = math.min(minY, p.dy);
    maxX = math.max(maxX, p.dx);
    maxY = math.max(maxY, p.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}
