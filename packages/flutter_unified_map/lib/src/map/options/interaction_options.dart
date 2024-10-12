import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart' show immutable;
import 'package:flutter_map/flutter_map.dart'
    show CursorKeyboardRotationOptions, InteractiveFlag, KeyboardOptions, MultiFingerGesture;

import '../camera/map_camera.dart';

/// flutter_map's `InteractionOptions`, field for field.
///
/// [flags] ([InteractiveFlag]) per backend:
/// - flutter_map backend: every field is passed to flutter_map unchanged.
/// - `drag`: Google `uiSettings.isScrollGesturesEnabled`, MapKit `isScrollEnabled`.
/// - `pinchMove`: Google `isScrollGesturesEnabledDuringRotateOrZoom`; MapKit always pans during a pinch.
/// - `pinchZoom`: Google `isZoomGesturesEnabled`, MapKit `isZoomEnabled` (which also covers the scroll wheel and
///   the trackpad on macOS: `scrollWheelZoom` alone cannot be told apart there).
/// - `doubleTapZoom`: iOS and macOS (the double-tap recognisers of `MKMapView`); Google has no separate switch, so
///   on Android it follows `pinchZoom`.
/// - `doubleTapDragZoom`: iOS (the one-finger zoom recogniser); Google: part of the zoom gestures.
/// - `flingAnimation`: when it is off, the core stops the native momentum as the last pointer goes up
///   (`UnifiedMapsPlatform.stopCamera`).
/// - `rotate`: Google `isRotateGesturesEnabled`, MapKit `isRotateEnabled`.
///
/// [keyboardOptions] and [cursorKeyboardRotationOptions] are handled by the core on every backend (arrow keys,
/// WASD, QE, RF and the rotation key with the pointer), with flutter_map's velocities. The thresholds, win gestures,
/// [scrollWheelVelocity], [doubleTapDragZoomChangeCalculator], [doubleTapZoomDuration], [doubleTapZoomCurve] and
/// [flingAnimationDampingRatio] tune flutter_map's own gesture engine: natively the platform recognises gestures,
/// so they only apply on the flutter_map backend.
@immutable
class InteractionOptions {
  final int flags;
  final bool debugMultiFingerGestureWinner;
  final bool enableMultiFingerGestureRace;
  final double rotationThreshold;
  final int rotationWinGestures;
  final double pinchZoomThreshold;
  final int pinchZoomWinGestures;
  final double pinchMoveThreshold;
  final int pinchMoveWinGestures;
  final double scrollWheelVelocity;
  final double Function(double verticalOffset, MapCamera camera) doubleTapDragZoomChangeCalculator;
  final Duration doubleTapZoomDuration;
  final Curve doubleTapZoomCurve;
  final double flingAnimationDampingRatio;
  final CursorKeyboardRotationOptions cursorKeyboardRotationOptions;
  final KeyboardOptions keyboardOptions;

  const InteractionOptions({
    this.flags = InteractiveFlag.all,
    this.debugMultiFingerGestureWinner = false,
    this.enableMultiFingerGestureRace = false,
    this.rotationThreshold = 20.0,
    this.rotationWinGestures = MultiFingerGesture.rotate,
    this.pinchZoomThreshold = 0.5,
    this.pinchZoomWinGestures = MultiFingerGesture.pinchZoom | MultiFingerGesture.pinchMove,
    this.pinchMoveThreshold = 40.0,
    this.pinchMoveWinGestures = MultiFingerGesture.pinchZoom | MultiFingerGesture.pinchMove,
    this.scrollWheelVelocity = 0.005,
    this.doubleTapDragZoomChangeCalculator = defaultDoubleTapDragZoomChangeCalculator,
    this.doubleTapZoomDuration = const Duration(milliseconds: 200),
    this.doubleTapZoomCurve = Curves.fastOutSlowIn,
    this.flingAnimationDampingRatio = 5.0,
    this.cursorKeyboardRotationOptions = const CursorKeyboardRotationOptions(),
    this.keyboardOptions = const KeyboardOptions(),
  }) : assert(rotationThreshold >= 0.0, '`rotationThreshold` must be positive'),
       assert(pinchZoomThreshold >= 0.0, '`pinchZoomThreshold` must be positive'),
       assert(pinchMoveThreshold >= 0.0, '`pinchMoveThreshold` must be positive'),
       assert(flingAnimationDampingRatio > 0.0, '`flingAnimationDampingRatio` must be positive');

  static double defaultDoubleTapDragZoomChangeCalculator(double verticalOffset, MapCamera camera) =>
      (1 / 360) * camera.zoom * verticalOffset;

  /// As flutter_map's, [cursorKeyboardRotationOptions] is left out (it has no value equality).
  @override
  bool operator ==(Object other) =>
      other is InteractionOptions &&
      flags == other.flags &&
      debugMultiFingerGestureWinner == other.debugMultiFingerGestureWinner &&
      enableMultiFingerGestureRace == other.enableMultiFingerGestureRace &&
      rotationThreshold == other.rotationThreshold &&
      rotationWinGestures == other.rotationWinGestures &&
      pinchZoomThreshold == other.pinchZoomThreshold &&
      pinchZoomWinGestures == other.pinchZoomWinGestures &&
      pinchMoveThreshold == other.pinchMoveThreshold &&
      pinchMoveWinGestures == other.pinchMoveWinGestures &&
      scrollWheelVelocity == other.scrollWheelVelocity &&
      doubleTapDragZoomChangeCalculator == other.doubleTapDragZoomChangeCalculator &&
      doubleTapZoomDuration == other.doubleTapZoomDuration &&
      doubleTapZoomCurve == other.doubleTapZoomCurve &&
      flingAnimationDampingRatio == other.flingAnimationDampingRatio &&
      keyboardOptions == other.keyboardOptions;

  @override
  int get hashCode => Object.hash(
    flags,
    debugMultiFingerGestureWinner,
    enableMultiFingerGestureRace,
    rotationThreshold,
    rotationWinGestures,
    pinchZoomThreshold,
    pinchZoomWinGestures,
    pinchMoveThreshold,
    pinchMoveWinGestures,
    scrollWheelVelocity,
    doubleTapDragZoomChangeCalculator,
    doubleTapZoomDuration,
    doubleTapZoomCurve,
    flingAnimationDampingRatio,
    keyboardOptions,
  );
}
