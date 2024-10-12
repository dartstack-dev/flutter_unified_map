import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_unified_map_flutter_map/src/camera_math.dart' show shortestDelta, wrapLongitude;
import 'package:flutter_unified_map_flutter_map/src/z_order.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

@immutable
class MarkerFrame {
  const MarkerFrame(this.marker, this.position, this.opacity, {required this.disappearing});

  final PlatformMarker marker;
  final LatLng position;
  final double opacity;
  final bool disappearing;
}

class _Track {
  _Track(this.marker) : from = marker.position, to = marker.position;

  PlatformMarker marker;
  LatLng from;
  LatLng to;
  double fromOpacity = 1;
  double toOpacity = 1;
  bool disappearing = false;
  Duration start = Duration.zero;
  Duration duration = Duration.zero;

  bool get moves => from != to || fromOpacity != toOpacity;

  bool get active => disappearing || moves;

  bool doneAt(Duration now) => now - start >= duration;

  double progressAt(Duration now) {
    if (!moves || doneAt(now)) return 1;
    final linear = (now - start).inMicroseconds / duration.inMicroseconds;
    return Curves.easeInOut.transform(linear.clamp(0.0, 1.0));
  }

  LatLng positionAt(Duration now) => lerpLatLng(from, to, progressAt(now));

  double opacityAt(Duration now) {
    final t = progressAt(now);
    return t >= 1 ? toOpacity : fromOpacity + (toOpacity - fromOpacity) * t;
  }

  void restart(Duration now, Duration duration) {
    from = positionAt(now);
    fromOpacity = opacityAt(now);
    start = now;
    this.duration = duration;
  }

  void settle() {
    from = to;
    fromOpacity = toOpacity;
  }
}

const _maxLatitude = 85.05112877980659;

double _mercatorY(double latitude) =>
    math.log(math.tan(math.pi / 4 + latitude.clamp(-_maxLatitude, _maxLatitude) * math.pi / 360));

double _latitudeOf(double mercatorY) => (2 * math.atan(math.exp(mercatorY)) - math.pi / 2) * 180 / math.pi;

/// Straight on the Web Mercator plane, like flutter_map_marker_cluster's screen-space tweens, along the shorter way
/// around the antimeridian.
LatLng lerpLatLng(LatLng a, LatLng b, double t) {
  if (t <= 0) return a;
  if (t >= 1) return b;
  final lng = wrapLongitude(a.longitude + shortestDelta(a.longitude, b.longitude) * t);
  final ya = _mercatorY(a.latitude);
  return LatLng(_latitudeOf(ya + (_mercatorY(b.latitude) - ya) * t), lng);
}

/// The markers of one view and their [PlatformMarkerTransition]s. Updates apply synchronously, so they take
/// effect in call order. Every marker keeps its own timeline: a transition restarts only the markers it touches,
/// from where they are on screen, and the others finish on their own schedule.
///
/// Time belongs to the store and is advanced by a ticker of the attached view state, so a view state attaching
/// while another one is still attached (a re-parented view mounts before the old state is disposed) takes the
/// running transitions over.
class MarkerStore extends ChangeNotifier {
  final _tracks = <String, _Track>{};
  final _active = <String>{};
  List<_Track> _sorted = const [];
  TickerProvider? _vsync;
  Ticker? _ticker;
  Duration _now = Duration.zero;
  Duration _tickerStart = Duration.zero;

  void attach(TickerProvider vsync) {
    _ticker?.dispose();
    _vsync = vsync;
    _ticker = vsync.createTicker(_onTick);
    _startTicking();
  }

  /// Without a ticker there is nothing to animate with: transitions end at once.
  void detach(TickerProvider vsync) {
    if (!identical(_vsync, vsync)) return;
    _ticker?.dispose();
    _ticker = null;
    _vsync = null;
    finishTransitions();
  }

  void finishTransitions() {
    _ticker?.stop();
    if (_active.isEmpty) return;
    for (final id in _active) {
      final track = _tracks[id]!;
      if (track.disappearing) {
        _tracks.remove(id);
      } else {
        track.settle();
      }
    }
    _active.clear();
    _resort();
    notifyListeners();
  }

  List<MarkerFrame> frames() => [
    for (final track in _sorted)
      MarkerFrame(track.marker, track.positionAt(_now), track.opacityAt(_now), disappearing: track.disappearing),
  ];

  void apply(MapObjectUpdates<PlatformMarker> updates, {PlatformMarkerTransition? transition}) {
    if (updates.isEmpty) return;
    if (_ticker == null || transition == null || transition.duration <= Duration.zero) {
      _applyInstantly(updates);
    } else {
      _applyAnimated(updates, transition);
    }
    _resort();
    _startTicking();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    _vsync = null;
    _tracks.clear();
    _active.clear();
    _sorted = const [];
    super.dispose();
  }

  void _startTicking() {
    final ticker = _ticker;
    if (ticker == null || ticker.isActive || _active.isEmpty) return;
    _tickerStart = _now;
    ticker.start();
  }

  void _onTick(Duration elapsed) {
    _now = _tickerStart + elapsed;
    var removed = false;
    for (final id in _active.toList()) {
      final track = _tracks[id]!;
      if (!track.doneAt(_now)) continue;
      _active.remove(id);
      if (track.disappearing) {
        _tracks.remove(id);
        removed = true;
      } else {
        track.settle();
      }
    }
    if (removed) _resort();
    if (_active.isEmpty) _ticker?.stop();
    notifyListeners();
  }

  void _track(String id, _Track track) {
    if (track.active) {
      _active.add(id);
    } else {
      _active.remove(id);
    }
  }

  /// Touched markers land at their target at once, in flight or not; the others keep their timeline.
  void _applyInstantly(MapObjectUpdates<PlatformMarker> updates) {
    for (final id in updates.removedIds) {
      _tracks.remove(id);
      _active.remove(id);
    }
    for (final marker in [...updates.added, ...updates.changed]) {
      final track = _tracks[marker.id];
      if (track == null) {
        _tracks[marker.id] = _Track(marker);
      } else {
        track
          ..marker = marker
          ..disappearing = false
          ..to = marker.position
          ..toOpacity = 1
          ..settle();
        _active.remove(marker.id);
      }
    }
  }

  void _applyAnimated(MapObjectUpdates<PlatformMarker> updates, PlatformMarkerTransition transition) {
    final now = _now;
    final duration = transition.duration;
    for (final id in updates.removedIds) {
      final track = _tracks[id];
      if (track == null || track.disappearing) continue;
      track.restart(now, duration);
      track
        ..disappearing = true
        ..to = transition.disappearTo[id] ?? track.from
        ..toOpacity = 0;
      _track(id, track);
    }
    for (final marker in [...updates.added, ...updates.changed]) {
      final track = _tracks[marker.id];
      if (track == null) {
        final added = _tracks[marker.id] = _Track(marker)
          ..from = transition.appearFrom[marker.id] ?? marker.position
          ..fromOpacity = 0
          ..start = now
          ..duration = duration;
        _track(marker.id, added);
        continue;
      }
      if (!track.disappearing && track.to == marker.position) {
        track.marker = marker;
        continue;
      }
      track.restart(now, duration);
      track
        ..marker = marker
        ..disappearing = false
        ..to = marker.position
        ..toOpacity = 1;
      _track(marker.id, track);
    }
  }

  void _resort() => _sorted = sortedByZ(_tracks.values, (t) => t.marker.zIndex);
}
