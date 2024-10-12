// Ported from flutter_map 8.3.2 (`MobileLayerTransformer`), BSD-3-Clause, Copyright (c) 2018 the flutter_map authors.
import 'package:flutter/widgets.dart';

import '../../map/camera/map_camera.dart';

/// flutter_map's `MobileLayerTransformer`: sizes [child] to the rotated view and turns it with the map, for custom
/// layers painted by Flutter. Over a native map such a layer follows the camera one frame late during gestures.
class MobileLayerTransformer extends StatelessWidget {
  const MobileLayerTransformer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return OverflowBox(
      minWidth: camera.size.width,
      maxWidth: camera.size.width,
      minHeight: camera.size.height,
      maxHeight: camera.size.height,
      child: Transform.rotate(angle: camera.rotationRad, child: child),
    );
  }
}
