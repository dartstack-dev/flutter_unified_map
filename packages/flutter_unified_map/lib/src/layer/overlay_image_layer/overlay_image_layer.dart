import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';

import '../shared/map_layer_state.dart';

/// flutter_map's `OverlayImageLayer`: images pinned to the ground. Natively each image is a ground overlay (Google
/// `GroundOverlay`, a MapKit overlay drawing the image), resolved from its `ImageProvider` once and registered with
/// the platform like a marker icon; the flutter_map backend draws flutter_map's own layer.
class OverlayImageLayer extends StatefulWidget {
  final List<BaseOverlayImage> overlayImages;

  const OverlayImageLayer({super.key, required this.overlayImages});

  @override
  State<OverlayImageLayer> createState() => _OverlayImageLayerState();
}

/// Contract stub: the overlays are registered by the core unit (`PlatformGroundOverlay`, `updateGroundOverlays`);
/// until then the layer draws nothing.
class _OverlayImageLayerState extends MapLayerState<OverlayImageLayer> {
  @override
  void sync() {}
}

/// An image of an [OverlayImageLayer]. Same fields as flutter_map's.
///
/// [opacity] is native (Google `transparency`, MapKit renderer `alpha`). [gaplessPlayback] keeps the previous image
/// on the map until a new [imageProvider] is resolved. [filterQuality] is flutter_map only (the platform samples the
/// image itself).
abstract class BaseOverlayImage extends StatelessWidget {
  final ImageProvider imageProvider;
  final double opacity;
  final bool gaplessPlayback;
  final FilterQuality filterQuality;

  const BaseOverlayImage({
    super.key,
    required this.imageProvider,
    this.opacity = 1,
    this.gaplessPlayback = false,
    this.filterQuality = FilterQuality.medium,
  });

  /// Over a native map the image is drawn by the platform, not by this widget.
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// An image stretched over [bounds], north up.
class OverlayImage extends BaseOverlayImage {
  final LatLngBounds bounds;

  const OverlayImage({
    super.key,
    required super.imageProvider,
    required this.bounds,
    super.opacity,
    super.gaplessPlayback,
    super.filterQuality,
  });
}

/// An image whose top-left, bottom-left and bottom-right corners land on the given points (rotated or skewed).
/// MapKit draws it exactly; Google Maps can only rotate a rectangle, so a skewed image is drawn as the closest
/// rotated rectangle there.
class RotatedOverlayImage extends BaseOverlayImage {
  final LatLng topLeftCorner;
  final LatLng bottomLeftCorner;
  final LatLng bottomRightCorner;
  final FilterQuality? transformFilterQuality;

  const RotatedOverlayImage({
    super.key,
    required super.imageProvider,
    required this.topLeftCorner,
    required this.bottomLeftCorner,
    required this.bottomRightCorner,
    this.transformFilterQuality = FilterQuality.medium,
    super.filterQuality,
    super.opacity,
    super.gaplessPlayback,
  });
}
