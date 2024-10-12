import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

import 'camera/camera_constraint.dart';
import 'camera/map_camera.dart';
import 'options/interaction_options.dart';
import 'options/map_options.dart';

/// flutter_map's own values of [options], for a backend that draws with flutter_map.
PlatformFlutterMapOptions flutterMapPassthrough(MapOptions options) => PlatformFlutterMapOptions(
  crs: options.crs,
  cameraConstraint: flutterMapConstraint(options.cameraConstraint),
  interactionOptions: flutterMapInteraction(options.interactionOptions),
);

/// [constraint] as a flutter_map constraint; equal constraints give equal results.
fm.CameraConstraint flutterMapConstraint(CameraConstraint constraint) => switch (constraint) {
  UnconstrainedCamera() => const fm.CameraConstraint.unconstrained(),
  ContainCameraCenter(:final bounds) => fm.CameraConstraint.containCenter(bounds: bounds),
  ContainCamera(:final bounds) => fm.CameraConstraint.contain(bounds: bounds),
  ContainCameraLatitude(:final a, :final b) => fm.CameraConstraint.containLatitude(a, b),
  _ => _WrappedConstraint(constraint),
};

final _calculators = Expando<double Function(double, fm.MapCamera)>();

/// [options] as flutter_map's; the same calculator function always gives the same wrapper, so equal options give
/// equal results.
fm.InteractionOptions flutterMapInteraction(InteractionOptions options) {
  final calculator = options.doubleTapDragZoomChangeCalculator;
  final wrapped = identical(calculator, InteractionOptions.defaultDoubleTapDragZoomChangeCalculator)
      ? fm.InteractionOptions.defaultDoubleTapDragZoomChangeCalculator
      : _calculators[calculator] ??= (double offset, fm.MapCamera camera) => calculator(offset, fromFlutterMap(camera));
  return fm.InteractionOptions(
    flags: options.flags,
    debugMultiFingerGestureWinner: options.debugMultiFingerGestureWinner,
    enableMultiFingerGestureRace: options.enableMultiFingerGestureRace,
    rotationThreshold: options.rotationThreshold,
    rotationWinGestures: options.rotationWinGestures,
    pinchZoomThreshold: options.pinchZoomThreshold,
    pinchZoomWinGestures: options.pinchZoomWinGestures,
    pinchMoveThreshold: options.pinchMoveThreshold,
    pinchMoveWinGestures: options.pinchMoveWinGestures,
    scrollWheelVelocity: options.scrollWheelVelocity,
    doubleTapDragZoomChangeCalculator: wrapped,
    doubleTapZoomDuration: options.doubleTapZoomDuration,
    doubleTapZoomCurve: options.doubleTapZoomCurve,
    flingAnimationDampingRatio: options.flingAnimationDampingRatio,
    cursorKeyboardRotationOptions: options.cursorKeyboardRotationOptions,
    keyboardOptions: options.keyboardOptions,
  );
}

MapCamera fromFlutterMap(fm.MapCamera camera) => MapCamera(
  crs: camera.crs,
  center: camera.center,
  zoom: camera.zoom,
  rotation: camera.rotation,
  nonRotatedSize: camera.nonRotatedSize,
  minZoom: camera.minZoom,
  maxZoom: camera.maxZoom,
);

fm.MapCamera toFlutterMap(MapCamera camera) => fm.MapCamera(
  crs: camera.crs,
  center: camera.center,
  zoom: camera.zoom,
  rotation: camera.rotation,
  nonRotatedSize: camera.nonRotatedSize,
  minZoom: camera.minZoom,
  maxZoom: camera.maxZoom,
);

class _WrappedConstraint extends fm.CameraConstraint {
  final CameraConstraint constraint;

  const _WrappedConstraint(this.constraint);

  @override
  fm.MapCamera? constrain(fm.MapCamera camera) {
    final constrained = constraint.constrain(fromFlutterMap(camera));
    return constrained == null ? null : toFlutterMap(constrained);
  }

  @override
  bool operator ==(Object other) => other is _WrappedConstraint && other.constraint == constraint;

  @override
  int get hashCode => constraint.hashCode;
}
