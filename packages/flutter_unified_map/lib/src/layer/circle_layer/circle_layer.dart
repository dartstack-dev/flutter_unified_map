import 'package:flutter/widgets.dart';

import '../../map/conversions.dart';
import '../../map/map_layer_host.dart';
import '../shared/hit_test.dart';
import '../shared/layer_hit_result.dart';
import '../shared/map_layer_state.dart';
import 'circle_marker.dart';

/// flutter_map's `CircleLayer`. [optimizeRadiusInMeters] tunes flutter_map's painter and only applies on the
/// flutter_map backend.
class CircleLayer<R extends Object> extends StatefulWidget {
  final List<CircleMarker<R>> circles;
  final LayerHitNotifier<R>? hitNotifier;
  final bool optimizeRadiusInMeters;

  const CircleLayer({super.key, required this.circles, this.hitNotifier, this.optimizeRadiusInMeters = false});

  @override
  State<CircleLayer<R>> createState() => _CircleLayerState<R>();
}

class _CircleLayerState<R extends Object> extends MapLayerState<CircleLayer<R>> {
  @override
  void attachHost(MapLayerHost host) => host.idleCamera.addListener(_onIdle);

  @override
  void detachHost(MapLayerHost host) => host.idleCamera.removeListener(_onIdle);

  void _onIdle() {
    if (widget.circles.any((c) => !c.useRadiusInMeter)) sync();
  }

  var _synced = <CircleMarker<R>>[];

  @override
  bool updateShouldSync(CircleLayer<R> oldWidget) =>
      !sameItems(_synced, widget.circles) || oldWidget.hitNotifier != widget.hitNotifier;

  @override
  void sync() {
    _synced = List.of(widget.circles);
    final camera = host.camera;
    final ids = [for (final (i, circle) in widget.circles.indexed) objectId(circle.key, i)];
    assert(ids.toSet().length == ids.length, 'CircleLayer: two circles have the same key');
    host.registry.setCircles(layerId, [
      for (var i = 0; i < widget.circles.length; i++)
        toPlatformCircle(
          widget.circles[i],
          ids[i],
          host.registry.shapeZIndexOf(layerId, i, widget.circles.length),
          camera,
        ),
    ]);
    registerHitTester(
      this,
      widget.hitNotifier,
      (camera, point) => [for (final circle in hitCircles(camera, widget.circles, point)) circle.hitValue],
    );
  }
}
