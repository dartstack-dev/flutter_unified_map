import 'package:flutter/painting.dart' show EdgeInsets, Offset, Size;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

class CameraTarget {
  final LatLng center;
  final double zoom;
  final double rotation;

  const CameraTarget({required this.center, required this.zoom, required this.rotation});

  factory CameraTarget.of(MapCamera camera) =>
      CameraTarget(center: camera.center, zoom: camera.zoom, rotation: camera.rotation);
}

/// Platform bearings are compass headings (Google Maps, MapKit) while flutter_map's rotation turns the content
/// clockwise, so each is the other's opposite.
double bearingFromRotation(double rotation) {
  final bearing = (-rotation) % 360;
  return bearing == 0 ? 0 : bearing;
}

double rotationFromBearing(double bearing) => -bearing;

bool hasLayout(MapCamera camera) => camera.nonRotatedSize.width.isFinite && camera.nonRotatedSize.height.isFinite;

/// Screen point of the centre of the view minus [padding]: the point the platform camera reports as centre,
/// like Google Maps `setPadding`.
Offset paddedCenter(MapCamera camera, EdgeInsets padding) => Offset(
  (camera.nonRotatedSize.width + padding.left - padding.right) / 2,
  (camera.nonRotatedSize.height + padding.top - padding.bottom) / 2,
);

PlatformCamera toPlatformCamera(MapCamera camera, EdgeInsets padding) {
  final center = padding == EdgeInsets.zero || !hasLayout(camera)
      ? camera.center
      : camera.screenOffsetToLatLng(paddedCenter(camera, padding));
  return PlatformCamera(center: center, zoom: camera.zoom, bearing: bearingFromRotation(camera.rotation));
}

/// flutter_map clamps its visible bounds at ±180; the contract expresses bounds that cross the antimeridian with
/// `northEast.longitude < southWest.longitude`, as Google Maps does.
PlatformLatLngBounds visibleRegionOf(MapCamera camera) {
  final bounds = camera.visibleBounds;
  final worldWidth = camera.getWorldWidthAtZoom();
  if (worldWidth == 0) return PlatformLatLngBounds(southWest: bounds.southWest, northEast: bounds.northEast);
  final width = camera.pixelBounds.width * 360 / worldWidth;
  if (width >= 360) {
    return PlatformLatLngBounds(southWest: LatLng(bounds.south, -180), northEast: LatLng(bounds.north, 180));
  }
  final center = camera.unprojectAtZoom(camera.pixelBounds.center).longitude;
  return PlatformLatLngBounds(
    southWest: LatLng(bounds.south, wrapLongitude(center - width / 2)),
    northEast: LatLng(bounds.north, -wrapLongitude(-(center + width / 2))),
  );
}

/// View centre that puts [target] on the padded centre, at [zoom] and [rotation].
LatLng viewCenterFor(MapCamera camera, LatLng target, double zoom, double rotation, EdgeInsets padding) {
  if (padding == EdgeInsets.zero || !hasLayout(camera)) return target;
  return _shiftedCenter(camera, target, zoom, rotation, padding);
}

/// [viewCenterFor] before the map has a size, which the shift does not depend on: the first frame is then already
/// centred on the padded area.
LatLng initialViewCenter(LatLng target, double zoom, double rotation, EdgeInsets padding) {
  if (padding == EdgeInsets.zero) return target;
  final camera = MapCamera(
    crs: const Epsg3857(),
    center: target,
    zoom: zoom,
    rotation: rotation,
    nonRotatedSize: Size.zero,
  );
  return _shiftedCenter(camera, target, zoom, rotation, padding);
}

LatLng _shiftedCenter(MapCamera camera, LatLng target, double zoom, double rotation, EdgeInsets padding) {
  final offset = Offset((padding.left - padding.right) / 2, (padding.top - padding.bottom) / 2);
  final rotated = camera.withRotation(rotation);
  final point = rotated.projectAtZoom(target, zoom);
  return rotated.unprojectAtZoom(rotated.rotatePoint(point, point - offset), zoom);
}

CameraTarget resolveCameraUpdate(MapCamera camera, PlatformCameraUpdate update, EdgeInsets padding) => switch (update) {
  PlatformCameraUpdateNewCamera(:final center, :final zoom, :final bearing) => _newCamera(
    camera,
    padding,
    center: center,
    zoom: zoom,
    rotation: bearing == null ? null : rotationFromBearing(bearing),
  ),
  PlatformCameraUpdateFitBounds(:final bounds, padding: final fitPadding, :final maxZoom, :final bearing) => _fitBounds(
    camera,
    padding,
    bounds: bounds,
    contentPadding: fitPadding,
    maxZoom: maxZoom,
    rotation: bearing == null ? null : rotationFromBearing(bearing),
  ),
  PlatformCameraUpdateScrollBy(:final dx, :final dy) => CameraTarget(
    center: hasLayout(camera)
        ? camera.screenOffsetToLatLng(camera.nonRotatedSize.center(Offset.zero) + Offset(dx, dy))
        : camera.center,
    zoom: camera.zoom,
    rotation: camera.rotation,
  ),
  PlatformCameraUpdateZoomBy(:final amount, :final focus) => _zoomAround(
    camera,
    camera.clampZoom(camera.zoom + amount),
    focus == null ? null : Offset(focus.dx, focus.dy),
    padding,
  ),
};

CameraTarget _newCamera(
  MapCamera camera,
  EdgeInsets padding, {
  required LatLng? center,
  required double? zoom,
  required double? rotation,
}) {
  final targetZoom = camera.clampZoom(zoom ?? camera.zoom);
  final targetRotation = rotation ?? camera.rotation;
  final target = center ?? toPlatformCamera(camera, padding).center;
  return CameraTarget(
    center: viewCenterFor(camera, target, targetZoom, targetRotation, padding),
    zoom: targetZoom,
    rotation: targetRotation,
  );
}

CameraTarget _zoomAround(MapCamera camera, double zoom, Offset? focus, EdgeInsets padding) {
  if (!hasLayout(camera)) return CameraTarget(center: camera.center, zoom: zoom, rotation: camera.rotation);
  final focusPoint = focus ?? paddedCenter(camera, padding);
  return CameraTarget(center: camera.focusedZoomCenter(focusPoint, zoom), zoom: zoom, rotation: camera.rotation);
}

CameraTarget _fitBounds(
  MapCamera camera,
  EdgeInsets padding, {
  required PlatformLatLngBounds bounds,
  required EdgeInsets contentPadding,
  required double? maxZoom,
  required double? rotation,
}) {
  final targetRotation = rotation ?? camera.rotation;
  final west = bounds.southWest.longitude;
  final span = _longitudeSpan(bounds);
  final midLongitude = west + span / 2;
  if (!hasLayout(camera)) {
    final center = LatLng((bounds.southWest.latitude + bounds.northEast.latitude) / 2, wrapLongitude(midLongitude));
    return CameraTarget(center: center, zoom: camera.zoom, rotation: targetRotation);
  }
  // Fitted around longitude 0 so that bounds crossing the antimeridian keep their real width, then shifted back.
  final fitted = CameraFit.bounds(
    bounds: LatLngBounds(LatLng(bounds.southWest.latitude, -span / 2), LatLng(bounds.northEast.latitude, span / 2)),
    padding: padding + contentPadding,
    maxZoom: maxZoom,
  ).fit(camera.withRotation(targetRotation));
  final center = LatLng(fitted.center.latitude, wrapLongitude(fitted.center.longitude + midLongitude));
  return CameraTarget(center: center, zoom: fitted.zoom, rotation: targetRotation);
}

/// Width in degrees from west to east; `northEast.longitude < southWest.longitude` means the bounds cross the
/// antimeridian.
double _longitudeSpan(PlatformLatLngBounds bounds) {
  final span = bounds.northEast.longitude - bounds.southWest.longitude;
  return span < 0 ? span + 360 : span;
}

double wrapLongitude(double longitude) => (longitude + 180) % 360 - 180;

/// Signed difference from [from] to [to] in degrees, in [-180, 180): the shorter way round a circle.
double shortestDelta(double from, double to) => ((to - from + 540) % 360) - 180;
