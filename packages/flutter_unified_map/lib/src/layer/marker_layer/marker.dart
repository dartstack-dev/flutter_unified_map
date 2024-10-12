import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import '../../native/native_params.dart';

/// A widget pinned to a coordinate. flutter_map's `Marker`, plus [iconKey], [onTap] and [nativeParams].
///
/// The native map cannot host a widget, so [child] is rasterised once per [iconKey] at [width] × [height]
/// logical pixels. The default key is the child itself, and widgets compare by identity: only the same instance
/// (typically a `const` child) reuses a bitmap. Give a child built anew on each rebuild (`Icon(.., color: c)`,
/// `Text(name)`) an [iconKey] that captures what it looks like, or it is rasterised again on every rebuild. The
/// bitmap follows the map's theme, text scale and brightness: it is rasterised again when they change. Animated or
/// stateful children are drawn as they look when rasterised.
///
/// Gestures: [onTap] is the reliable way to react to a tap on every backend. A tap handler inside [child]
/// (`GestureDetector.onTap`, `InkWell.onTap`, `IconButton.onPressed`) is also called on a native tap of the marker,
/// but without the position inside the child, so a child with several tap targets is not supported natively. A
/// marker without any tap handler lets taps through to the map, as in flutter_map.
///
/// [alignment] follows flutter_map: `Alignment.topCenter` places the whole child above [point]. [rotate] true keeps
/// the child upright when the map rotates; false lets it rotate with the map.
@immutable
class Marker {
  final Key? key;
  final LatLng point;
  final Widget child;
  final double width;
  final double height;
  final Alignment? alignment;
  final bool? rotate;

  /// What the rasterised [child] looks like; markers with equal keys (and sizes) share one bitmap. Defaults to
  /// [child]. Not in flutter_map.
  final Object? iconKey;

  /// A tap on the marker, on every backend. Not in flutter_map.
  final VoidCallback? onTap;

  /// Native-only settings; ignored by the flutter_map backend. Not in flutter_map.
  final NativeMarkerParams? nativeParams;

  const Marker({
    this.key,
    required this.point,
    required this.child,
    this.width = 30,
    this.height = 30,
    this.alignment,
    this.rotate,
    this.iconKey,
    this.onTap,
    this.nativeParams,
  });

  Object get effectiveIconKey => iconKey ?? child;

  /// The [alignment] that puts the pixel ([left], [top]) of a [width] × [height] child on the point.
  static Alignment computePixelAlignment({
    required double width,
    required double height,
    required double left,
    required double top,
  }) => Alignment(1.0 - 2 * left / width, 1.0 - 2 * top / height);
}
