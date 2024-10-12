import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import '../camera/camera_fit.dart';
import '../camera/map_camera.dart';
import '../events/map_events.dart';
import '../inherited_model.dart';
import 'map_controller_impl.dart';

/// The result of [MapController.moveAndRotate] and [MapController.rotateAroundPoint], as flutter_map's.
typedef MoveAndRotateResult = ({bool moveSuccess, bool rotateSuccess});

/// Drives the camera of a [UnifiedMap]. flutter_map's `MapController` API, plus the animated API of
/// `flutter_map_animations.AnimatedMapController`, since native maps animate the camera themselves.
///
/// Instant calls ([move], [rotate], [rotateAroundPoint], [moveAndRotate], [fitCamera]) behave as flutter_map's on
/// every backend: [camera] holds the target as soon as the call returns, the call emits one [MapEventMove] and/or
/// [MapEventRotate] (source [MapEventSource.mapController], with its `id`) and calls `MapOptions.onPositionChanged`
/// before returning, with no start or end event; the camera is clamped to the zoom bounds and the
/// `MapOptions.cameraConstraint`. The native map follows a moment later; its own report of that move is absorbed.
/// Before `MapOptions.onMapReady`, the calls set the camera the map will be created or shown with.
///
/// Animated calls ([animateTo] and the methods built on it) complete when the animation ends or is interrupted (by a
/// gesture, [stopAnimations] or a newer animation when `cancelPreviousAnimations`). Without a curve the platform
/// animates natively (its own ease); with a curve the core drives the camera frame by frame with instant native
/// moves, as flutter_map_animations does.
///
/// Create it with `MapController()` and pass it to one `UnifiedMap`; other implementations are not supported.
abstract class MapController {
  factory MapController() = MapControllerImpl;

  static MapController? maybeOf(BuildContext context) => UnifiedMapInheritedModel.maybeControllerOf(context);

  static MapController of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError('`MapController.of()` should not be called outside a `UnifiedMap` and its children'));

  /// Every [MapEvent] of the map.
  Stream<MapEvent> get mapEventStream;

  /// The camera now. Throws when the controller is not attached to a map.
  MapCamera get camera;

  /// Moves the camera to [center] at [zoom] without animation. [offset] shifts the view in screen pixels so that
  /// [center] lands off-center (e.g. above a bottom panel). [id] is passed to the resulting move event. Returns
  /// whether the camera changed.
  bool move(LatLng center, double zoom, {Offset offset = Offset.zero, String? id});

  /// Turns the map to [degree] (clockwise, as `MapCamera.rotation`) without animation.
  bool rotate(double degree, {String? id});

  /// Turns the map to [degree] around the screen point at [offset] from the view center (the center itself when null
  /// or zero), in one camera update.
  MoveAndRotateResult rotateAroundPoint(double degree, {Offset? offset, String? id});

  /// [move] and [rotate] in one camera update. [offset] is an addition to flutter_map's API.
  MoveAndRotateResult moveAndRotate(LatLng center, double zoom, double degree, {Offset offset = Offset.zero, String? id});

  /// Moves the camera so that [cameraFit] is satisfied, without animation. Returns false when the fit has no
  /// coordinates.
  bool fitCamera(CameraFit cameraFit);

  /// Animates the camera to [dest], [zoom] and [rotation] (each defaults to the current value) over [duration]
  /// (500 ms by default), as flutter_map_animations' `AnimatedMapController.animateTo`. [curve] null uses the native
  /// ease; any curve is followed exactly (driven by the core). [cancelPreviousAnimations] stops the running
  /// animations first (default false: a newer native animation replaces the running one anyway).
  Future<void> animateTo({
    LatLng? dest,
    double? zoom,
    double? rotation,
    Offset offset = Offset.zero,
    Duration? duration,
    Curve? curve,
    String? customId,
    bool? cancelPreviousAnimations,
  });

  /// [fitCamera], animated like [animateTo]; [rotation] also turns the map.
  Future<void> animatedFitCamera({
    required CameraFit cameraFit,
    double? rotation,
    Duration? duration,
    Curve? curve,
    String? customId,
    bool? cancelPreviousAnimations,
  });

  /// [animateTo] [point], optionally at [zoom].
  Future<void> centerOnPoint(
    LatLng point, {
    double? zoom,
    Curve? curve,
    String? customId,
    Duration? duration,
    bool? cancelPreviousAnimations,
  });

  /// [animatedFitCamera] on the bounds of [points] with 12 px of padding (deprecated in flutter_map_animations, kept
  /// for compatibility).
  Future<void> centerOnPoints(List<LatLng> points, {Curve? curve, String? customId});

  /// Turns the map by [degree] from its current rotation.
  Future<void> animatedRotateFrom(
    double degree, {
    Curve? curve,
    String? customId,
    Duration? duration,
    bool? cancelPreviousAnimations,
  });

  /// Turns the map to [degree].
  Future<void> animatedRotateTo(
    double degree, {
    Curve? curve,
    String? customId,
    Duration? duration,
    bool? cancelPreviousAnimations,
  });

  /// Turns the map back to north.
  Future<void> animatedRotateReset({Curve? curve, String? customId, Duration? duration, bool? cancelPreviousAnimations});

  /// One zoom level in.
  Future<void> animatedZoomIn({Curve? curve, String? customId, Duration? duration, bool? cancelPreviousAnimations});

  /// One zoom level out (nothing below zoom 0).
  Future<void> animatedZoomOut({Curve? curve, String? customId, Duration? duration, bool? cancelPreviousAnimations});

  /// Zooms to [newZoom].
  Future<void> animatedZoomTo(
    double newZoom, {
    Curve? curve,
    String? customId,
    Duration? duration,
    bool? cancelPreviousAnimations,
  });

  /// Stops every running camera animation where the camera is (native and core-driven ones); their futures
  /// complete.
  void stopAnimations();

  /// PNG of the map as the platform draws it (base map, shapes and markers), or null when the platform cannot
  /// snapshot or the map is not ready. Not in flutter_map.
  Future<Uint8List?> takeSnapshot();

  /// Closes [mapEventStream]. Call it when the controller is no longer used.
  void dispose();
}
