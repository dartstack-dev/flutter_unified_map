import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';

import 'platform_icon.dart';
import 'platform_map_object.dart';

/// An image pinned to the ground (flutter_map's `OverlayImage` / `RotatedOverlayImage`), stretched so that its
/// top-left, bottom-left and bottom-right corners land on [topLeft], [bottomLeft] and [bottomRight]; the fourth
/// corner completes the parallelogram.
///
/// Google: `GroundOverlay` with `positionFromBounds` when the corners form a north-up rectangle, otherwise
/// `position(center, width)` + `bearing` + `dimensions(width, height)` (exact for a rotated rectangle, approximated
/// by the closest rectangle for a skewed parallelogram); `transparency = 1 - opacity`. MapKit: a custom `MKOverlay`
/// whose renderer draws the image with the affine transform of the three corners (exact). [image] is registered once
/// per key, like marker icons.
@immutable
class PlatformGroundOverlay extends PlatformMapObject {
  @override
  final String id;
  final PlatformIcon image;
  final LatLng topLeft;
  final LatLng bottomLeft;
  final LatLng bottomRight;
  final double opacity;
  final double zIndex;

  const PlatformGroundOverlay({
    required this.id,
    required this.image,
    required this.topLeft,
    required this.bottomLeft,
    required this.bottomRight,
    this.opacity = 1,
    this.zIndex = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is PlatformGroundOverlay &&
      other.id == id &&
      other.image == image &&
      other.topLeft == topLeft &&
      other.bottomLeft == bottomLeft &&
      other.bottomRight == bottomRight &&
      other.opacity == opacity &&
      other.zIndex == zIndex;

  @override
  int get hashCode => Object.hash(id, image, topLeft, bottomLeft, bottomRight, opacity, zIndex);

  @override
  String toString() => 'PlatformGroundOverlay($id, ${image.key})';
}
