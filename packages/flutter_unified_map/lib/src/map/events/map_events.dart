import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import '../camera/map_camera.dart';

/// Who triggered an event. Same values as flutter_map's.
///
/// Which backend emits which source:
/// - [mapController]: every backend, for `MapController` calls (an instant call is one [MapEventMove] /
///   [MapEventRotate] emitted inside the call; an animated call is a series of moves with its `customId`).
/// - [tap], [secondaryTap], [longPress], [nonRotatedSizeChange]: every backend.
/// - [dragStart], [onDrag], [dragEnd], [multiFingerGestureStart], [onMultiFinger], [multiFingerEnd]: every backend.
///   The flutter_map backend reports flutter_map's own; on native maps the core tells one finger from several by
///   counting the pointers it sees over the map (a gesture that starts with one finger and adds a second stays a
///   drag, as in flutter_map).
/// - [flingAnimationController]: the camera still moving after the last pointer went up (native momentum).
/// - [doubleTap], [doubleTapZoomAnimationController]: a double tap the core saw (two taps within
///   `kDoubleTapTimeout` and `kDoubleTapSlop`), and the zoom the native map then animates.
/// - [doubleTapHold]: a double tap followed by a drag (native one-finger zoom).
/// - [scrollWheel]: camera moves after a pointer scroll event over the map (where the platform view delivers it).
/// - [keyboard], [cursorKeyboardRotation]: the core's keyboard handling (`InteractionOptions.keyboardOptions` /
///   `cursorKeyboardRotationOptions`), on every backend.
/// - [interactiveFlagsChanged]: an options update disabled the running gesture.
/// - [fitCamera]: never emitted (flutter_map 8 emits [mapController] for fits too); kept for compatibility.
/// - [custom]: never emitted by the map; for apps and plugins.
enum MapEventSource {
  mapController,
  tap,
  secondaryTap,
  longPress,
  doubleTap,
  doubleTapHold,
  dragStart,
  onDrag,
  dragEnd,
  multiFingerGestureStart,
  onMultiFinger,
  multiFingerEnd,
  flingAnimationController,
  doubleTapZoomAnimationController,
  interactiveFlagsChanged,
  fitCamera,
  custom,
  scrollWheel,
  nonRotatedSizeChange,
  cursorKeyboardRotation,
  keyboard,
}

/// Base class of every map event, as flutter_map's: apps and plugins may extend it (with [MapEventSource.custom]).
@immutable
abstract class MapEvent {
  final MapEventSource source;
  final MapCamera camera;

  const MapEvent({required this.source, required this.camera});
}

/// An event that changed the camera.
@immutable
abstract class MapEventWithMove extends MapEvent {
  final MapCamera oldCamera;

  const MapEventWithMove({required super.source, required this.oldCamera, required super.camera});

  /// The move event flutter_map emits for [source], or null when that source does not move the camera.
  static MapEventWithMove? fromSource({
    required MapCamera oldCamera,
    required MapCamera camera,
    required bool hasGesture,
    required MapEventSource source,
    String? id,
  }) => switch (source) {
    MapEventSource.flingAnimationController => MapEventFlingAnimation(
      oldCamera: oldCamera,
      camera: camera,
      source: source,
    ),
    MapEventSource.doubleTapZoomAnimationController => MapEventDoubleTapZoom(
      oldCamera: oldCamera,
      camera: camera,
      source: source,
    ),
    MapEventSource.scrollWheel => MapEventScrollWheelZoom(oldCamera: oldCamera, camera: camera, source: source),
    MapEventSource.onDrag ||
    MapEventSource.onMultiFinger ||
    MapEventSource.doubleTapHold ||
    MapEventSource.mapController ||
    MapEventSource.keyboard ||
    MapEventSource.custom => MapEventMove(id: id, oldCamera: oldCamera, camera: camera, source: source),
    _ => null,
  };
}

@immutable
class MapEventTap extends MapEvent {
  final LatLng tapPosition;

  const MapEventTap({required this.tapPosition, required super.source, required super.camera});
}

/// A secondary tap (mouse right click, stylus button, secondary click on iPadOS and macOS).
@immutable
class MapEventSecondaryTap extends MapEvent {
  final LatLng tapPosition;

  const MapEventSecondaryTap({required this.tapPosition, required super.source, required super.camera});
}

@immutable
class MapEventLongPress extends MapEvent {
  final LatLng tapPosition;

  const MapEventLongPress({required this.tapPosition, required super.source, required super.camera});
}

/// The camera moved. [id] is the id given to `MapController.move(id:)` (or `animateTo(customId:)`) when the move
/// comes from that call.
@immutable
class MapEventMove extends MapEventWithMove {
  final String? id;

  const MapEventMove({this.id, required super.source, required super.oldCamera, required super.camera});
}

/// A gesture starts moving the camera. Programmatic moves have no start and end events, as in flutter_map.
@immutable
class MapEventMoveStart extends MapEvent {
  const MapEventMoveStart({required super.source, required super.camera});
}

/// A gesture ended.
@immutable
class MapEventMoveEnd extends MapEvent {
  const MapEventMoveEnd({required super.source, required super.camera});
}

@immutable
class MapEventFlingAnimation extends MapEventWithMove {
  const MapEventFlingAnimation({required super.source, required super.oldCamera, required super.camera});
}

/// A drag ended without momentum.
@immutable
class MapEventFlingAnimationNotStarted extends MapEvent {
  const MapEventFlingAnimationNotStarted({required super.source, required super.camera});
}

@immutable
class MapEventFlingAnimationStart extends MapEvent {
  const MapEventFlingAnimationStart({required super.source, required super.camera});
}

@immutable
class MapEventFlingAnimationEnd extends MapEvent {
  const MapEventFlingAnimationEnd({required super.source, required super.camera});
}

@immutable
class MapEventDoubleTapZoom extends MapEventWithMove {
  const MapEventDoubleTapZoom({required super.source, required super.oldCamera, required super.camera});
}

@immutable
class MapEventScrollWheelZoom extends MapEventWithMove {
  const MapEventScrollWheelZoom({required super.source, required super.oldCamera, required super.camera});
}

@immutable
class MapEventDoubleTapZoomStart extends MapEvent {
  const MapEventDoubleTapZoomStart({required super.source, required super.camera});
}

@immutable
class MapEventDoubleTapZoomEnd extends MapEvent {
  const MapEventDoubleTapZoomEnd({required super.source, required super.camera});
}

/// The rotation changed. Emitted whenever it changes, alongside [MapEventMove] when the center or zoom changed too.
@immutable
class MapEventRotate extends MapEventWithMove {
  final String? id;

  const MapEventRotate({required this.id, required super.source, required super.oldCamera, required super.camera});
}

/// The first rotation change of a gesture.
@immutable
class MapEventRotateStart extends MapEvent {
  const MapEventRotateStart({required super.source, required super.camera});
}

/// The end of a gesture that rotated the map.
@immutable
class MapEventRotateEnd extends MapEvent {
  const MapEventRotateEnd({required super.source, required super.camera});
}

@immutable
class MapEventNonRotatedSizeChange extends MapEventWithMove {
  const MapEventNonRotatedSizeChange({required super.source, required super.oldCamera, required super.camera});
}
