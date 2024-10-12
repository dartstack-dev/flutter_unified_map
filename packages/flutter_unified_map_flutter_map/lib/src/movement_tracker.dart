import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

/// Gestures have no reliable end event for every path (scroll wheel, drag without fling), so once no finger
/// holds the map a gesture is considered settled [gestureIdleDelay] after its last movement, or at once on an
/// explicit end event. Programmatic moves settle when the caller says so. Move events are coalesced to one per
/// frame.
class MovementTracker {
  MovementTracker({
    required this.viewId,
    required this.emit,
    required this.currentCamera,
    this.gestureIdleDelay = const Duration(milliseconds: 100),
  });

  final int viewId;
  final void Function(PlatformMapEvent event) emit;
  final PlatformCamera Function() currentCamera;
  final Duration gestureIdleDelay;

  bool _moving = false;
  bool _held = false;
  bool _disposed = false;
  Object? _programmatic;
  Timer? _idleTimer;
  bool _movePending = false;
  bool _movedSinceStart = false;

  Object beginProgrammatic() {
    _idleTimer?.cancel();
    final token = Object();
    _programmatic = token;
    _start(byGesture: false);
    return token;
  }

  void endProgrammatic(Object token) {
    if (!identical(_programmatic, token)) return;
    _programmatic = null;
    _settle();
  }

  void onMoved({required bool byGesture}) {
    _start(byGesture: byGesture);
    if (!_movePending) {
      _movePending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => _flushMove());
      SchedulerBinding.instance.ensureVisualUpdate();
    }
    if (_programmatic == null && !_held) _armIdleTimer();
  }

  /// A finger or pointer took hold of the map: an interrupted programmatic move settles first, so the gesture
  /// gets its own start event.
  void onGestureStarted() {
    if (_programmatic != null) {
      _programmatic = null;
      _settle();
    }
    _held = true;
    _idleTimer?.cancel();
  }

  /// The pointer let go; a fling may follow, otherwise the idle timer settles the movement.
  void onGestureReleased() {
    _held = false;
    if (_programmatic == null && _moving) _armIdleTimer();
  }

  void onGestureEnded() {
    _held = false;
    if (_programmatic != null) return;
    _idleTimer?.cancel();
    _settle();
  }

  /// The view is going away mid-movement: the movement ends where the camera is, so the core still gets its idle.
  void settleNow() {
    _held = false;
    _programmatic = null;
    _idleTimer?.cancel();
    _settle();
  }

  /// Input without a start event (scroll wheel, keyboard) took over from a programmatic move.
  void onInputInterrupted() {
    onGestureStarted();
    onGestureReleased();
  }

  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _movePending = false;
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(gestureIdleDelay, _settle);
  }

  void _start({required bool byGesture}) {
    if (_moving || _disposed) return;
    _moving = true;
    _movedSinceStart = false;
    emit(PlatformCameraMoveStartedEvent(viewId, byGesture: byGesture));
  }

  void _flushMove() {
    if (!_movePending || _disposed) return;
    _movePending = false;
    _movedSinceStart = true;
    emit(PlatformCameraMoveEvent(viewId, currentCamera()));
  }

  void _settle() {
    _idleTimer = null;
    if (!_moving || _disposed) return;
    // A move that left the camera where it was still owes the contract's start → move → idle sequence.
    if (!_movedSinceStart) _movePending = true;
    _flushMove();
    _moving = false;
    emit(PlatformCameraIdleEvent(viewId, currentCamera()));
  }
}
