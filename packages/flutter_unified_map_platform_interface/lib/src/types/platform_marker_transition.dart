import 'package:flutter/foundation.dart' show listEquals;
import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';

/// An easing curve every backend can evaluate: either a cubic Bézier through (0, 0), ([x1], [y1]), ([x2], [y2]),
/// (1, 1) (CSS `cubic-bezier`, Flutter `Cubic`, Android `PathInterpolator`), or [samples]: values at evenly spaced
/// times from 0 to 1 inclusive (at least 2), linearly interpolated, for curves that are not cubic.
@immutable
class PlatformCurve {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final List<double>? samples;

  const PlatformCurve.cubic(this.x1, this.y1, this.x2, this.y2) : samples = null;

  const PlatformCurve.sampled(List<double> this.samples) : x1 = 0, y1 = 0, x2 = 1, y2 = 1;

  /// The ease-in-out every backend used before curves were configurable (Flutter `Curves.easeInOut`).
  static const easeInOut = PlatformCurve.cubic(0.42, 0, 0.58, 1);

  @override
  bool operator ==(Object other) =>
      other is PlatformCurve &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2 &&
      listEquals(other.samples, samples);

  @override
  int get hashCode => Object.hash(x1, y1, x2, y2, samples == null ? null : Object.hashAll(samples!));

  @override
  String toString() => samples == null ? 'PlatformCurve.cubic($x1, $y1, $x2, $y2)' : 'PlatformCurve.sampled(${samples!.length})';
}

/// Animates a marker update, so clusters can split and merge like flutter_map_marker_cluster's.
///
/// With a transition of [duration]:
/// - an added marker listed in [appearFrom] starts at that position with opacity 0 and moves to its own position
///   while fading in; an added marker not listed fades in at its position;
/// - a changed marker whose position changed moves to its new position;
/// - a removed marker listed in [disappearTo] moves there while fading out, then is removed; a removed marker not
///   listed fades out, then is removed.
///
/// Positions follow [moveCurve], opacities [fadeInCurve] (appearing) and [fadeOutCurve] (disappearing), all
/// interpolated on the Web Mercator plane in time.
///
/// Every backend also guarantees:
/// - a marker already in flight (moving, appearing or disappearing) starts from its current on-screen state;
/// - a marker of an animated update whose target (position, and visible or not) did not change keeps its running
///   timeline: it is not restarted, slowed or re-eased, whatever this update's duration and curves (flutter_map's
///   behaviour: an animation runs to the end unless its target changes);
/// - a disappearing marker that is added again is revived where it is and continues to its new position (its
///   [appearFrom] entry is ignored);
/// - a tap on a disappearing marker falls through to the map (a map tap at the marker's position), never a marker
///   tap;
/// - snapshots leave disappearing markers out and draw the other in-flight markers at their current position and
///   opacity;
/// - an update without a transition puts the in-flight markers it touches (adds, changes or removes) at their target
///   at once;
/// - `dispose` cancels every transition.
@immutable
class PlatformMarkerTransition {
  final Duration duration;
  final Map<String, LatLng> appearFrom;
  final Map<String, LatLng> disappearTo;
  final PlatformCurve moveCurve;
  final PlatformCurve fadeInCurve;
  final PlatformCurve fadeOutCurve;

  const PlatformMarkerTransition({
    required this.duration,
    this.appearFrom = const {},
    this.disappearTo = const {},
    this.moveCurve = PlatformCurve.easeInOut,
    this.fadeInCurve = PlatformCurve.easeInOut,
    this.fadeOutCurve = PlatformCurve.easeInOut,
  });

  @override
  bool operator ==(Object other) =>
      other is PlatformMarkerTransition &&
      other.duration == duration &&
      _sameMap(other.appearFrom, appearFrom) &&
      _sameMap(other.disappearTo, disappearTo) &&
      other.moveCurve == moveCurve &&
      other.fadeInCurve == fadeInCurve &&
      other.fadeOutCurve == fadeOutCurve;

  @override
  int get hashCode =>
      Object.hash(duration, appearFrom.length, disappearTo.length, moveCurve, fadeInCurve, fadeOutCurve);

  @override
  String toString() =>
      'PlatformMarkerTransition($duration, appearFrom ${appearFrom.length}, disappearTo ${disappearTo.length})';
}

bool _sameMap(Map<String, LatLng> a, Map<String, LatLng> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
