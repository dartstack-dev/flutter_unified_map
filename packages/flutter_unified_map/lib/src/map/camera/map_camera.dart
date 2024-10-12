// Ported from flutter_map 8.3.2 (`MapCamera`), BSD-3-Clause, Copyright (c) 2018 the flutter_map authors.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' show Crs, Epsg3857, LatLngBounds;
import 'package:latlong2/latlong.dart';

import '../inherited_model.dart';
import '../options/map_options.dart';

/// The view of a map: same API as flutter_map's `MapCamera`, refreshed on every platform camera event.
///
/// Projections run in Dart with [crs]. Native maps are always Web Mercator ([Epsg3857], 256 px tiles at zoom 0):
/// there the Dart projections match the native ones to the pixel while the camera is not tilted (`NativeParams`
/// can enable tilt gestures; projections then ignore the tilt). On the flutter_map backend every flutter_map `Crs`
/// works as in flutter_map.
///
/// [rotation] is in degrees, clockwise, as flutter_map's. It stays continuous: turning through north goes from 359
/// to 360 or from 1 to -1 rather than wrapping, starting from `MapOptions.initialRotation`.
///
/// Additions to flutter_map's API: [metersPerPixel] and [copyWith].
class MapCamera {
  /// The size before the map is laid out, as flutter_map's.
  static const kImpossibleSize = Size(double.negativeInfinity, double.negativeInfinity);

  final Crs crs;
  final double? minZoom;
  final double? maxZoom;
  final LatLng center;
  final double zoom;
  final double rotation;

  /// Size of the map widget in logical pixels, before rotation.
  final Size nonRotatedSize;

  Size? _cameraSize;
  Rect? _pixelBounds;
  LatLngBounds? _bounds;
  Offset? _pixelOrigin;

  MapCamera({
    required this.crs,
    required this.center,
    required this.zoom,
    required this.rotation,
    required this.nonRotatedSize,
    this.minZoom,
    this.maxZoom,
    Size? size,
    this._pixelBounds,
    this._bounds,
    this._pixelOrigin,
  }) : _cameraSize = size,
       assert(zoom.isFinite, 'Camera `zoom` must be finite');

  /// The camera described by [options], sized [kImpossibleSize].
  MapCamera.initialCamera(MapOptions options)
    : this(
        crs: options.crs,
        minZoom: options.minZoom,
        maxZoom: options.maxZoom,
        center: options.initialCenter,
        zoom: options.initialZoom,
        rotation: options.initialRotation,
        nonRotatedSize: kImpossibleSize,
      );

  static MapCamera? maybeOf(BuildContext context) => UnifiedMapInheritedModel.maybeCameraOf(context);

  static MapCamera of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError('`MapCamera.of()` should not be called outside a `UnifiedMap` and its descendants'));

  /// Bounds covering the four corners of the (possibly rotated) view, world-safe across the antimeridian.
  LatLngBounds get visibleBounds => _bounds ??= _computeVisibleBounds();

  LatLngBounds _computeVisibleBounds() {
    final bottomLeft = unprojectAtZoom(pixelBounds.bottomLeft, zoom);
    final topRight = unprojectAtZoom(pixelBounds.topRight, zoom);
    final worldWidth = getWorldWidthAtZoom(zoom);
    if (worldWidth == 0) return LatLngBounds(bottomLeft, topRight);
    final center = unprojectAtZoom(pixelBounds.center, zoom);
    return LatLngBounds.worldSafe(
      south: bottomLeft.latitude,
      north: topRight.latitude,
      longitudeWidth: pixelBounds.width * 360 / worldWidth,
      longitudeCenter: center.longitude,
    );
  }

  /// Bounding box of the rotated view, in logical pixels.
  Size get size => _cameraSize ??= calculateRotatedSize(rotation, nonRotatedSize);

  /// World pixel position of the top-left corner of [size] (the rotated bounding box).
  Offset get pixelOrigin => _pixelOrigin ??= projectAtZoom(center, zoom) - size.center(Offset.zero);

  MapCamera withNonRotatedSize(Size nonRotatedSize) {
    if (nonRotatedSize == this.nonRotatedSize) return this;
    return MapCamera(
      crs: crs,
      center: center,
      zoom: zoom,
      rotation: rotation,
      nonRotatedSize: nonRotatedSize,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
  }

  MapCamera withRotation(double rotation) {
    if (rotation == this.rotation) return this;
    return MapCamera(
      crs: crs,
      center: center,
      zoom: zoom,
      nonRotatedSize: nonRotatedSize,
      rotation: rotation,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
  }

  MapCamera withOptions(MapOptions options) {
    if (options.crs == crs && options.minZoom == minZoom && options.maxZoom == maxZoom) return this;
    return MapCamera(
      crs: options.crs,
      minZoom: options.minZoom,
      maxZoom: options.maxZoom,
      center: center,
      zoom: zoom,
      rotation: rotation,
      nonRotatedSize: nonRotatedSize,
      size: _cameraSize,
    );
  }

  /// This camera at [center] / [zoom]; a longitude beyond ±180 jumps to the other side of the world, as in
  /// flutter_map.
  MapCamera withPosition({LatLng? center, double? zoom}) => MapCamera(
    crs: crs,
    minZoom: minZoom,
    maxZoom: maxZoom,
    center: _adjustPositionForSeamlessScrolling(center),
    zoom: zoom ?? this.zoom,
    rotation: rotation,
    nonRotatedSize: nonRotatedSize,
    size: _cameraSize,
  );

  /// Any field replaced; an addition to flutter_map's API.
  MapCamera copyWith({
    Crs? crs,
    LatLng? center,
    double? zoom,
    double? rotation,
    double? minZoom,
    double? maxZoom,
    Size? nonRotatedSize,
  }) => MapCamera(
    crs: crs ?? this.crs,
    center: center ?? this.center,
    zoom: zoom ?? this.zoom,
    rotation: rotation ?? this.rotation,
    minZoom: minZoom ?? this.minZoom,
    maxZoom: maxZoom ?? this.maxZoom,
    nonRotatedSize: nonRotatedSize ?? this.nonRotatedSize,
  );

  LatLng _adjustPositionForSeamlessScrolling(LatLng? position) {
    if (!crs.replicatesWorldLongitude) return position ?? center;
    if (position == null) return center;
    var adjustedLongitude = position.longitude;
    if (adjustedLongitude >= 180.0) {
      adjustedLongitude -= 360.0;
    } else if (adjustedLongitude <= -180.0) {
      adjustedLongitude += 360.0;
    }
    return adjustedLongitude == position.longitude ? position : LatLng(position.latitude, adjustedLongitude);
  }

  static Size calculateRotatedSize(double rotation, Size nonRotatedSize) {
    if (rotation == 0.0) return nonRotatedSize;
    final rotationRad = rotation * math.pi / 180;
    final cosAngle = math.cos(rotationRad).abs();
    final sinAngle = math.sin(rotationRad).abs();
    final width = (nonRotatedSize.width * cosAngle) + (nonRotatedSize.height * sinAngle);
    final height = (nonRotatedSize.height * cosAngle) + (nonRotatedSize.width * sinAngle);
    return Size(width, height);
  }

  double get rotationRad => rotation * math.pi / 180;

  /// World pixel coordinates of [latlng] at [zoom] (default: this camera's).
  Offset projectAtZoom(LatLng latlng, [double? zoom]) => crs.latLngToOffset(latlng, zoom ?? this.zoom);

  LatLng unprojectAtZoom(Offset point, [double? zoom]) => crs.offsetToLatLng(point, zoom ?? this.zoom);

  /// Width of the world at [zoom] in pixels, or 0 when [crs] does not repeat the world horizontally.
  double getWorldWidthAtZoom([double? zoom]) {
    if (!crs.replicatesWorldLongitude) return 0;
    final offset0 = projectAtZoom(const LatLng(0, 0), zoom ?? this.zoom);
    final offset180 = projectAtZoom(const LatLng(0, 180), zoom ?? this.zoom);
    return 2 * (offset180.dx - offset0.dx).abs();
  }

  double getZoomScale(double toZoom, double fromZoom) => crs.scale(toZoom) / crs.scale(fromZoom);

  double getScaleZoom(double scale) => crs.zoom(scale * crs.scale(zoom));

  Rect? getPixelWorldBounds(double? zoom) => crs.getProjectedBounds(zoom ?? this.zoom);

  /// Position of [pos] relative to [pixelOrigin].
  Offset getOffsetFromOrigin(LatLng pos) => projectAtZoom(pos) - pixelOrigin;

  Offset getNewPixelOrigin(LatLng center, [double? zoom]) {
    final origin = projectAtZoom(center, zoom) - size.center(Offset.zero);
    return Offset(origin.dx.roundToDouble(), origin.dy.roundToDouble());
  }

  Rect get pixelBounds => _pixelBounds ??= pixelBoundsAtZoom(zoom);

  Rect pixelBoundsAtZoom(double zoom) {
    var cameraSize = size;
    if (zoom != this.zoom) {
      final scale = getZoomScale(this.zoom, zoom);
      cameraSize = size / (scale * 2);
    }
    final projected = projectAtZoom(center, zoom);
    final pixelCenter = Offset(projected.dx.floorToDouble(), projected.dy.floorToDouble());
    return Rect.fromCenter(center: pixelCenter, width: cameraSize.width, height: cameraSize.height);
  }

  /// Position of [latLng] in the map widget, logical pixels from its top-left corner.
  Offset latLngToScreenOffset(LatLng latLng) {
    final nonRotatedPixelOrigin = projectAtZoom(center, zoom) - nonRotatedSize.center(Offset.zero);
    var point = crs.latLngToOffset(latLng, zoom);
    final mapCenter = crs.latLngToOffset(center, zoom);
    if (rotation != 0.0) point = rotatePoint(mapCenter, point, counterRotation: false);
    return point - nonRotatedPixelOrigin;
  }

  LatLng screenOffsetToLatLng(Offset offset) {
    final localPointCenterDistance = nonRotatedSize.center(Offset.zero) - offset;
    final mapCenter = crs.latLngToOffset(center, zoom);
    var point = mapCenter - localPointCenterDistance;
    if (rotation != 0.0) point = rotatePoint(mapCenter, point);
    final worldWidth = getWorldWidthAtZoom(zoom);
    if (worldWidth == 0) return crs.offsetToLatLng(point, zoom);
    // The world repeats horizontally: unproject in the world copy the pixel falls in and add the full turns back,
    // so the longitude continues across the antimeridian instead of clamping to ±180 (native maps repeat the
    // world; the CRS clamps).
    final zero = projectAtZoom(const LatLng(0, 0), zoom).dx;
    final turns = ((point.dx - zero) / worldWidth + 0.5).floor();
    final latLng = crs.offsetToLatLng(Offset(point.dx - turns * worldWidth, point.dy), zoom);
    return LatLng(latLng.latitude, latLng.longitude + turns * 360);
  }

  /// [point] rotated around [mapCenter] by -[rotation] ([counterRotation]) or +[rotation].
  Offset rotatePoint(Offset mapCenter, Offset point, {bool counterRotation = true}) {
    final angle = rotationRad * (counterRotation ? -1 : 1);
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final d = point - mapCenter;
    return mapCenter + Offset(d.dx * cos - d.dy * sin, d.dx * sin + d.dy * cos);
  }

  double clampZoom(double zoom) => zoom.clamp(minZoom ?? double.negativeInfinity, maxZoom ?? double.infinity);

  LatLng offsetToCrs(Offset offset, [double? zoom]) {
    final focalStartPt = projectAtZoom(center, zoom ?? this.zoom);
    final point = _rotate(offset - nonRotatedSize.center(Offset.zero), rotationRad);
    final newCenterPt = focalStartPt + point;
    final worldWidth = getWorldWidthAtZoom(zoom ?? this.zoom);
    var bestX = newCenterPt.dx;
    if (worldWidth != 0) {
      while (bestX > worldWidth) {
        bestX -= worldWidth;
      }
      while (bestX < 0) {
        bestX += worldWidth;
      }
    }
    return unprojectAtZoom(Offset(bestX, newCenterPt.dy), zoom ?? this.zoom);
  }

  /// The center that keeps the map point under [cursorPos] in place when zooming to [zoom].
  LatLng focusedZoomCenter(Offset cursorPos, double zoom) {
    final offset = _rotate(cursorPos - nonRotatedSize.center(Offset.zero), rotationRad);
    final scale = getZoomScale(zoom, this.zoom);
    final newOffset = offset * (1.0 - 1.0 / scale);
    final mapCenter = projectAtZoom(center);
    return unprojectAtZoom(mapCenter + newOffset);
  }

  /// Meters per logical pixel at [latitude] (defaults to the center) and the current zoom, on Web Mercator. An
  /// addition to flutter_map's API.
  double metersPerPixel([double? latitude]) {
    final lat = (latitude ?? center.latitude) * math.pi / 180;
    return 156543.03392 * math.cos(lat) / math.pow(2, zoom);
  }

  static Offset _rotate(Offset offset, double radians) {
    final cosTheta = math.cos(radians);
    final sinTheta = math.sin(radians);
    return Offset(cosTheta * offset.dx + sinTheta * offset.dy, cosTheta * offset.dy - sinTheta * offset.dx);
  }

  @override
  int get hashCode => Object.hash(crs, minZoom, maxZoom, center, zoom, rotation, nonRotatedSize);

  @override
  bool operator ==(Object other) =>
      identical(other, this) ||
      (other is MapCamera &&
          other.crs == crs &&
          other.minZoom == minZoom &&
          other.maxZoom == maxZoom &&
          other.center == center &&
          other.zoom == zoom &&
          other.rotation == rotation &&
          other.nonRotatedSize == nonRotatedSize);

  @override
  String toString() => 'MapCamera($center, zoom $zoom, rotation $rotation, $nonRotatedSize)';
}
