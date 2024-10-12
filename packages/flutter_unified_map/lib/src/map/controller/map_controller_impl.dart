import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

import '../camera/camera_fit.dart';
import '../camera/camera_math.dart';
import '../camera/map_camera.dart';
import '../events/map_events.dart';
import '../report_error.dart';
import 'map_controller.dart';

/// The map side of a [MapControllerImpl].
abstract class MapControllerHost {
  MapCamera get camera;
  bool get isReady;

  /// Sends [update]; [id] tags the resulting move events.
  Future<void> moveCamera(PlatformCameraUpdate update, {Duration? animation, String? id});

  /// Stops the running camera animations.
  void stopCamera();

  Future<Uint8List?> takeSnapshot();
}

/// Translates controller calls into [PlatformCameraUpdate]s for the attached map and relays its events.
class MapControllerImpl implements MapController {
  static const defaultAnimationDuration = Duration(milliseconds: 500);

  final _events = StreamController<MapEvent>.broadcast();
  MapControllerHost? _host;

  @override
  Stream<MapEvent> get mapEventStream => _events.stream;

  bool get isAttached => _host != null;

  void attach(MapControllerHost host) => _host = host;

  void detach(MapControllerHost host) {
    if (identical(_host, host)) _host = null;
  }

  void emit(MapEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  MapControllerHost get _attached =>
      _host ??
      (throw StateError(
        'MapController is not attached to a UnifiedMap: pass it as UnifiedMap.mapController '
        'and use it once the map is built.',
      ));

  MapControllerHost? get _readyHost {
    final host = _host;
    return host != null && host.isReady ? host : null;
  }

  @override
  MapCamera get camera => _attached.camera;

  @override
  Future<Uint8List?> takeSnapshot() => _readyHost?.takeSnapshot() ?? Future.value();

  @override
  bool move(LatLng center, double zoom, {Offset offset = Offset.zero, String? id}) {
    final host = _readyHost;
    if (host == null) return false;
    final camera = host.camera;
    final z = camera.clampZoom(zoom);
    final target = centerForOffset(camera, center, z, camera.rotation, offset);
    _send(
      host,
      PlatformCameraUpdate.newCamera(center: target, zoom: z),
      id: id,
    );
    return target != camera.center || z != camera.zoom;
  }

  @override
  bool rotate(double degree, {String? id}) {
    final host = _readyHost;
    if (host == null) return false;
    final bearing = bearingFromRotation(degree);
    _send(host, PlatformCameraUpdate.newCamera(bearing: bearing), id: id);
    return bearing != bearingFromRotation(host.camera.rotation);
  }

  @override
  MoveAndRotateResult moveAndRotate(
    LatLng center,
    double zoom,
    double degree, {
    Offset offset = Offset.zero,
    String? id,
  }) {
    final host = _readyHost;
    if (host == null) return (moveSuccess: false, rotateSuccess: false);
    final camera = host.camera;
    final z = camera.clampZoom(zoom);
    final target = centerForOffset(camera, center, z, degree, offset);
    final bearing = bearingFromRotation(degree);
    _send(
      host,
      PlatformCameraUpdate.newCamera(center: target, zoom: z, bearing: bearing),
      id: id,
    );
    return (
      moveSuccess: target != camera.center || z != camera.zoom,
      rotateSuccess: bearing != bearingFromRotation(camera.rotation),
    );
  }

  @override
  MoveAndRotateResult rotateAroundPoint(double degree, {Offset? offset, String? id}) {
    final host = _readyHost;
    if (host == null || degree == host.camera.rotation) return (moveSuccess: false, rotateSuccess: false);
    final camera = host.camera;
    if (offset == null || offset == Offset.zero) return (moveSuccess: true, rotateSuccess: rotate(degree, id: id));
    final rotationDiff = (degree - camera.rotation) * math.pi / 180;
    final centerPoint = camera.projectAtZoom(camera.center);
    final pivot = centerPoint + rotateOffset(offset, -camera.rotationRad);
    final center = camera.unprojectAtZoom(pivot + rotateOffset(centerPoint - pivot, -rotationDiff));
    return moveAndRotate(center, camera.zoom, degree, id: id);
  }

  @override
  bool fitCamera(CameraFit cameraFit) {
    final host = _readyHost;
    if (host == null || _isEmpty(cameraFit)) return false;
    _send(host, _fitUpdate(host.camera, cameraFit, null));
    return true;
  }

  @override
  Future<void> animateTo({
    LatLng? dest,
    double? zoom,
    double? rotation,
    Offset offset = Offset.zero,
    Duration? duration,
    Curve? curve,
    String? customId,
    bool? cancelPreviousAnimations,
  }) {
    final host = _readyHost;
    if (host == null) return Future.value();
    if (cancelPreviousAnimations ?? false) host.stopCamera();
    final camera = host.camera;
    final targetZoom = camera.clampZoom(zoom ?? camera.zoom);
    final targetRotation = rotation ?? camera.rotation;
    final center = centerForOffset(camera, dest ?? camera.center, targetZoom, targetRotation, offset);
    return host.moveCamera(
      PlatformCameraUpdate.newCamera(
        center: center,
        zoom: targetZoom,
        bearing: rotation == null ? null : bearingFromRotation(rotation),
      ),
      animation: duration ?? defaultAnimationDuration,
      id: customId,
    );
  }

  @override
  Future<void> animatedFitCamera({
    required CameraFit cameraFit,
    double? rotation,
    Duration? duration,
    Curve? curve,
    String? customId,
    bool? cancelPreviousAnimations,
  }) {
    final host = _readyHost;
    if (host == null || _isEmpty(cameraFit)) return Future.value();
    if (cancelPreviousAnimations ?? false) host.stopCamera();
    return host.moveCamera(
      _fitUpdate(host.camera, cameraFit, rotation),
      animation: duration ?? defaultAnimationDuration,
      id: customId,
    );
  }

  @override
  Future<void> centerOnPoint(
    LatLng point, {
    double? zoom,
    Curve? curve,
    String? customId,
    Duration? duration,
    bool? cancelPreviousAnimations,
  }) => animateTo(
    dest: point,
    zoom: zoom,
    curve: curve,
    customId: customId,
    duration: duration,
    cancelPreviousAnimations: cancelPreviousAnimations,
  );

  @override
  Future<void> centerOnPoints(List<LatLng> points, {Curve? curve, String? customId}) => animatedFitCamera(
    cameraFit: CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(12)),
    curve: curve,
    customId: customId,
  );

  @override
  Future<void> animatedRotateFrom(
    double degree, {
    Curve? curve,
    String? customId,
    Duration? duration,
    bool? cancelPreviousAnimations,
  }) => animateTo(
    rotation: camera.rotation + degree,
    curve: curve,
    customId: customId,
    duration: duration,
    cancelPreviousAnimations: cancelPreviousAnimations,
  );

  @override
  Future<void> animatedRotateTo(
    double degree, {
    Curve? curve,
    String? customId,
    Duration? duration,
    bool? cancelPreviousAnimations,
  }) => animateTo(
    rotation: degree,
    curve: curve,
    customId: customId,
    duration: duration,
    cancelPreviousAnimations: cancelPreviousAnimations,
  );

  @override
  Future<void> animatedRotateReset({
    Curve? curve,
    String? customId,
    Duration? duration,
    bool? cancelPreviousAnimations,
  }) => animatedRotateTo(
    0,
    curve: curve,
    customId: customId,
    duration: duration,
    cancelPreviousAnimations: cancelPreviousAnimations,
  );

  @override
  Future<void> animatedZoomIn({Curve? curve, String? customId, Duration? duration, bool? cancelPreviousAnimations}) =>
      animatedZoomTo(
        camera.zoom + 1,
        curve: curve,
        customId: customId,
        duration: duration,
        cancelPreviousAnimations: cancelPreviousAnimations,
      );

  @override
  Future<void> animatedZoomOut({
    Curve? curve,
    String? customId,
    Duration? duration,
    bool? cancelPreviousAnimations,
  }) async {
    final newZoom = camera.zoom - 1;
    if (newZoom < 0) return;
    return animatedZoomTo(
      newZoom,
      curve: curve,
      customId: customId,
      duration: duration,
      cancelPreviousAnimations: cancelPreviousAnimations,
    );
  }

  @override
  Future<void> animatedZoomTo(
    double newZoom, {
    Curve? curve,
    String? customId,
    Duration? duration,
    bool? cancelPreviousAnimations,
  }) => animateTo(
    zoom: newZoom,
    curve: curve,
    customId: customId,
    duration: duration,
    cancelPreviousAnimations: cancelPreviousAnimations,
  );

  @override
  void stopAnimations() => _readyHost?.stopCamera();

  static bool _isEmpty(CameraFit fit) => fit is FitCoordinates && fit.coordinates.isEmpty;

  /// Native fit when the platform can do it exactly (north-up, no zoom constraint the platform does not know);
  /// otherwise the camera is solved in Dart.
  PlatformCameraUpdate _fitUpdate(MapCamera camera, CameraFit fit, double? rotation) {
    final effectiveRotation = rotation ?? camera.rotation;
    final bearing = rotation == null ? null : bearingFromRotation(rotation);
    final solved = solveCameraFit(camera, fit, rotation: effectiveRotation);
    final native = switch (fit) {
      final FitBounds f => _nativeFit(
        f.bounds,
        f.padding,
        f.maxZoom,
        f.minZoom,
        f.forceIntegerZoomLevel,
        solved.zoom,
        bearing,
      ),
      final FitCoordinates f => _nativeFit(
        LatLngBounds.fromPoints(f.coordinates),
        f.padding,
        f.maxZoom,
        f.minZoom,
        f.forceIntegerZoomLevel,
        solved.zoom,
        bearing,
      ),
      _ => null,
    };
    if (native != null && effectiveRotation % 360 == 0) return native;
    return PlatformCameraUpdate.newCamera(center: solved.center, zoom: solved.zoom, bearing: bearing);
  }

  PlatformCameraUpdate? _nativeFit(
    LatLngBounds bounds,
    EdgeInsets padding,
    double? maxZoom,
    double minZoom,
    bool forceInteger,
    double solvedZoom,
    double? bearing,
  ) {
    if (forceInteger || solvedZoom <= minZoom) return null;
    return PlatformCameraUpdate.fitBounds(
      PlatformLatLngBounds(southWest: bounds.southWest, northEast: bounds.northEast),
      padding: padding,
      maxZoom: maxZoom,
      bearing: bearing,
    );
  }

  void _send(MapControllerHost host, PlatformCameraUpdate update, {String? id}) {
    host
        .moveCamera(update, id: id)
        .catchError((Object error, StackTrace stack) => reportMapError(error, stack, 'while moving the camera'));
  }

  @override
  void dispose() {
    _host = null;
    _events.close();
  }
}
