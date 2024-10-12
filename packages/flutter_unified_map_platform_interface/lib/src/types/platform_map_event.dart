import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';

import 'platform_camera.dart';

/// Events a platform view reports to the core. Every event carries the [viewId] it belongs to.
@immutable
sealed class PlatformMapEvent {
  final int viewId;

  const PlatformMapEvent(this.viewId);
}

/// The native view exists and accepts updates; sent once, after which the core pushes its layers.
class PlatformMapReadyEvent extends PlatformMapEvent {
  final PlatformCamera camera;

  const PlatformMapReadyEvent(super.viewId, this.camera);
}

/// What moved the camera, with flutter_map's `MapEventSource` names. Only a backend that knows it exactly sets it
/// (the flutter_map backend forwards flutter_map's own sources); native backends leave it null and the core infers
/// the source from the pointers it sees over the view.
enum PlatformGestureSource {
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
  scrollWheel,
  cursorKeyboardRotation,
  keyboard,
}

/// The camera starts moving; [byGesture] is true for user gestures, false for API moves and animations.
///
/// A gesture that starts while a programmatic animation (`moveCamera` with an animation) runs stops that animation
/// first: the platform sends [PlatformCameraIdleEvent] for the animation (and completes its `moveCamera` future),
/// then this event with `byGesture: true`, as flutter_map does. It never continues the animation's movement under
/// the same start.
class PlatformCameraMoveStartedEvent extends PlatformMapEvent {
  final bool byGesture;
  final PlatformGestureSource? source;

  const PlatformCameraMoveStartedEvent(super.viewId, {required this.byGesture, this.source});
}

/// Continuous camera change (gesture, momentum, animation). Sent at most once per frame.
class PlatformCameraMoveEvent extends PlatformMapEvent {
  final PlatformCamera camera;
  final PlatformGestureSource? source;

  const PlatformCameraMoveEvent(super.viewId, this.camera, {this.source});
}

/// The camera has settled.
class PlatformCameraIdleEvent extends PlatformMapEvent {
  final PlatformCamera camera;
  final PlatformGestureSource? source;

  const PlatformCameraIdleEvent(super.viewId, this.camera, {this.source});
}

/// Single tap on the map that hit no marker. [screenPoint] is relative to the view, logical pixels.
class PlatformMapTapEvent extends PlatformMapEvent {
  final LatLng position;
  final Offset screenPoint;

  const PlatformMapTapEvent(super.viewId, this.position, this.screenPoint);
}

class PlatformMapLongPressEvent extends PlatformMapEvent {
  final LatLng position;
  final Offset screenPoint;

  const PlatformMapLongPressEvent(super.viewId, this.position, this.screenPoint);
}

/// Secondary tap on the map (mouse right click, stylus button, iPadOS / macOS secondary click): Android
/// `View.setOnContextClickListener`, iOS `UITapGestureRecognizer.buttonMaskRequired = .secondary`, macOS
/// `NSClickGestureRecognizer(buttonMask: 0x2)`, flutter_map `onSecondaryTap`. Markers do not catch it.
class PlatformMapSecondaryTapEvent extends PlatformMapEvent {
  final LatLng position;
  final Offset screenPoint;

  const PlatformMapSecondaryTapEvent(super.viewId, this.position, this.screenPoint);
}

/// Tap on a tappable marker.
class PlatformMarkerTapEvent extends PlatformMapEvent {
  final String markerId;

  const PlatformMarkerTapEvent(super.viewId, this.markerId);
}

enum PlatformDragPhase { start, update, end }

/// A draggable marker ([PlatformMarker.draggable]) is being dragged; [position] is where its anchor is now.
class PlatformMarkerDragEvent extends PlatformMapEvent {
  final String markerId;
  final LatLng position;
  final PlatformDragPhase phase;

  const PlatformMarkerDragEvent(super.viewId, this.markerId, this.position, this.phase);
}

/// Tap on the info window (Google) or callout (MapKit) of a marker with a title.
class PlatformInfoWindowTapEvent extends PlatformMapEvent {
  final String markerId;

  const PlatformInfoWindowTapEvent(super.viewId, this.markerId);
}

/// A mouse or trackpad pointer [entered] or left a marker (macOS `NSTrackingArea`, iPadOS
/// `UIHoverGestureRecognizer`, flutter_map `MouseRegion`). Google Maps has no marker hover: Android never sends it.
class PlatformMarkerHoverEvent extends PlatformMapEvent {
  final String markerId;
  final bool entered;

  const PlatformMarkerHoverEvent(super.viewId, this.markerId, {required this.entered});
}

/// A tile of a tile layer could not be loaded (after its fallback URL, if any).
class PlatformTileErrorEvent extends PlatformMapEvent {
  final String tileLayerId;
  final int z;
  final int x;
  final int y;
  final String message;

  const PlatformTileErrorEvent(super.viewId, this.tileLayerId, this.z, this.x, this.y, this.message);
}

/// The native view size changed (rotation, split view). The core measures its own size, so it ignores this event.
class PlatformViewSizeEvent extends PlatformMapEvent {
  final double width;
  final double height;

  const PlatformViewSizeEvent(super.viewId, this.width, this.height);
}

/// The base map finished loading its content for the current camera at least once (Google `onMapLoaded`,
/// MapKit `mapViewDidFinishLoadingMap`, flutter_map: first tile loaded). Sent again after a recovery from a
/// [PlatformMapErrorEvent] with a load code, which tells the core the error is gone.
class PlatformMapLoadedEvent extends PlatformMapEvent {
  const PlatformMapLoadedEvent(super.viewId);
}

/// Why a map cannot show its base map.
enum PlatformMapErrorCode {
  /// The platform needs an API key and none is configured (Google Maps on Android: no or blank
  /// `com.google.android.geo.API_KEY` meta-data). The native map is not created.
  apiKeyMissing,

  /// The platform's map services are missing or outdated (Google Play services).
  servicesUnavailable,

  /// The map did not finish loading in time. On Google Maps this is how a rejected API key or a missing network
  /// shows up: the SDK reports neither.
  loadTimeout,

  /// The platform reported a load failure ([PlatformMapErrorEvent.message] carries its description).
  loadFailed,

  unknown,
}

/// The map cannot show its base map. Overlays may still be accepted. [message] is the platform's own, precise
/// description (key name, native error text); the core turns [code] into user-facing guidance.
class PlatformMapErrorEvent extends PlatformMapEvent {
  final PlatformMapErrorCode code;
  final String message;

  const PlatformMapErrorEvent(super.viewId, this.code, this.message);
}
