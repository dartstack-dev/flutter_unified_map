import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_unified_map_flutter_map/src/camera_math.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' show LatLng;

class CameraAnimator {
  CameraAnimator({required TickerProvider vsync, required this.controller})
    : _animation = AnimationController(vsync: vsync) {
    _curved = CurvedAnimation(parent: _animation, curve: Curves.easeInOut)..addListener(_tick);
  }

  final MapController controller;
  final AnimationController _animation;
  late final CurvedAnimation _curved;
  Completer<void>? _completer;
  CameraTarget? _from;
  CameraTarget? _to;

  bool get isAnimating => _completer != null;

  /// Where the running animation ends, or null when none runs.
  CameraTarget? get target => isAnimating ? _to : null;

  /// Completes when the animation ends, or at once when another move interrupts it.
  Future<void> animate(CameraTarget from, CameraTarget to, Duration duration) {
    interrupt();
    final completer = Completer<void>();
    _completer = completer;
    _from = from;
    _to = _unwrapped(from, to);
    _animation
      ..duration = duration
      ..value = 0;
    _animation.forward().whenCompleteOrCancel(() {
      if (!identical(_completer, completer)) return;
      _completer = null;
      completer.complete();
    });
    return completer.future;
  }

  /// Moves the end of the running animation without restarting it.
  void retarget(CameraTarget to) {
    final from = _from;
    if (!isAnimating || from == null) return;
    _to = _unwrapped(from, to);
  }

  void interrupt() {
    final completer = _completer;
    if (completer == null) return;
    _completer = null;
    _animation.stop();
    if (!completer.isCompleted) completer.complete();
  }

  void dispose() {
    interrupt();
    _curved.dispose();
    _animation.dispose();
  }

  /// Longitude and rotation are kept relative to the start, so the camera pans and turns the shorter way (across
  /// the antimeridian when that is shorter), as Google Maps and MapKit do.
  static CameraTarget _unwrapped(CameraTarget from, CameraTarget to) => CameraTarget(
    center: LatLng(
      to.center.latitude,
      from.center.longitude + shortestDelta(from.center.longitude, to.center.longitude),
    ),
    zoom: to.zoom,
    rotation: from.rotation + shortestDelta(from.rotation, to.rotation),
  );

  void _tick() {
    final from = _from;
    final to = _to;
    if (from == null || to == null || _completer == null) return;
    final t = _curved.value;
    controller.moveAndRotate(
      LatLng(
        _lerp(from.center.latitude, to.center.latitude, t),
        wrapLongitude(_lerp(from.center.longitude, to.center.longitude, t)),
      ),
      _lerp(from.zoom, to.zoom, t),
      _lerp(from.rotation, to.rotation, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
