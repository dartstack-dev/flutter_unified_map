import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';

import 'platform_camera.dart' show Offset;
import 'platform_icon.dart';
import 'platform_map_object.dart';

/// A marker drawn natively from a [PlatformIcon].
///
/// [anchor] is the fractional point of the icon placed on [position]: `(0.5, 0.5)` centers the icon,
/// `(0.5, 1.0)` puts its bottom-center on the position (Google Maps convention).
/// [flat] markers rotate with the map (like flutter_map `Marker.rotate = false`); non-flat markers always face
/// the screen. [rotation] is an extra clockwise rotation in degrees (Google `Marker.rotation`, MapKit view transform).
/// [opacity] is Google `Marker.alpha` / MapKit `MKAnnotationView.alpha`; a running transition multiplies it.
///
/// [draggable] lets the user drag the marker after a long press (Google `draggable` + `OnMarkerDragListener`,
/// MapKit `isDraggable` + `didChange dragState`); the platform reports [PlatformMarkerDragEvent]s and keeps the
/// marker where it was dropped until the next update moves it.
/// [title] / [snippet] show the platform's info window (Google) or callout (MapKit `canShowCallout`) on tap, whose
/// tap is reported as [PlatformInfoWindowTapEvent]; null shows none.
@immutable
class PlatformMarker extends PlatformMapObject {
  @override
  final String id;
  final LatLng position;
  final PlatformIcon icon;
  final Offset anchor;
  final double zIndex;
  final bool flat;
  final double rotation;
  final bool tappable;
  final double opacity;
  final bool draggable;
  final String? title;
  final String? snippet;
  final PlatformAndroidMarkerOptions? android;
  final PlatformAppleMarkerOptions? apple;

  const PlatformMarker({
    required this.id,
    required this.position,
    required this.icon,
    this.anchor = const Offset(0.5, 0.5),
    this.zIndex = 0,
    this.flat = false,
    this.rotation = 0,
    this.tappable = true,
    this.opacity = 1,
    this.draggable = false,
    this.title,
    this.snippet,
    this.android,
    this.apple,
  });

  @override
  bool operator ==(Object other) =>
      other is PlatformMarker &&
      other.id == id &&
      other.position == position &&
      other.icon == icon &&
      other.anchor == anchor &&
      other.zIndex == zIndex &&
      other.flat == flat &&
      other.rotation == rotation &&
      other.tappable == tappable &&
      other.opacity == opacity &&
      other.draggable == draggable &&
      other.title == title &&
      other.snippet == snippet &&
      other.android == android &&
      other.apple == apple;

  @override
  int get hashCode => Object.hash(
    id,
    position,
    icon,
    anchor,
    zIndex,
    flat,
    rotation,
    tappable,
    opacity,
    draggable,
    title,
    snippet,
    android,
    apple,
  );

  @override
  String toString() => 'PlatformMarker($id, $position, ${icon.key})';
}

/// Google-only marker settings: [infoWindowAnchor] (fractional, `MarkerOptions.infoWindowAnchor`) and [flat], which
/// overrides [PlatformMarker.flat] (`MarkerOptions.flat`, for tilted maps).
@immutable
class PlatformAndroidMarkerOptions {
  final Offset? infoWindowAnchor;
  final bool? flat;

  const PlatformAndroidMarkerOptions({this.infoWindowAnchor, this.flat});

  @override
  bool operator ==(Object other) =>
      other is PlatformAndroidMarkerOptions && other.infoWindowAnchor == infoWindowAnchor && other.flat == flat;

  @override
  int get hashCode => Object.hash(infoWindowAnchor, flat);
}

/// `MKAnnotationViewCollisionMode`.
enum PlatformAppleCollisionMode { rectangle, circle, none }

/// MapKit-only marker settings: [displayPriority] (`MKAnnotationView.displayPriority`, 0–1000; 1000 = `.required`,
/// the default, so markers never hide each other unless asked) and [collisionMode].
@immutable
class PlatformAppleMarkerOptions {
  final double? displayPriority;
  final PlatformAppleCollisionMode? collisionMode;

  const PlatformAppleMarkerOptions({this.displayPriority, this.collisionMode});

  @override
  bool operator ==(Object other) =>
      other is PlatformAppleMarkerOptions &&
      other.displayPriority == displayPriority &&
      other.collisionMode == collisionMode;

  @override
  int get hashCode => Object.hash(displayPriority, collisionMode);
}
