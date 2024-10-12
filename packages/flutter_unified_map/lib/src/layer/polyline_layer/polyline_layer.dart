import 'package:flutter/widgets.dart';

import '../shared/hit_test.dart';
import '../shared/layer_hit_result.dart';
import '../shared/map_layer_state.dart';
import 'polyline.dart';

/// flutter_map's `PolylineLayer`. [cullingMargin] and [simplificationTolerance] tune flutter_map's painter: natively
/// the map culls and simplifies itself, so they only apply on the flutter_map backend. [drawInSingleWorld] false
/// (the default) draws each segment the short way across the antimeridian, as native maps do; true is honoured on
/// the flutter_map backend only.
class PolylineLayer<R extends Object> extends StatefulWidget {
  final List<Polyline<R>> polylines;
  final double? cullingMargin;
  final LayerHitNotifier<R>? hitNotifier;

  /// Minimum tap distance to a line, logical pixels.
  final double minimumHitbox;
  final bool drawInSingleWorld;
  final double simplificationTolerance;

  const PolylineLayer({
    super.key,
    required this.polylines,
    this.cullingMargin = 10,
    this.hitNotifier,
    this.minimumHitbox = 10,
    this.drawInSingleWorld = false,
    this.simplificationTolerance = 0.3,
  }) : assert(simplificationTolerance >= 0, 'simplificationTolerance cannot be negative');

  @override
  State<PolylineLayer<R>> createState() => _PolylineLayerState<R>();
}

class _PolylineLayerState<R extends Object> extends MapLayerState<PolylineLayer<R>> {
  var _synced = <Polyline<R>>[];

  @override
  bool updateShouldSync(PolylineLayer<R> oldWidget) =>
      !sameItems(_synced, widget.polylines) || oldWidget.hitNotifier != widget.hitNotifier;

  @override
  void sync() {
    _synced = List.of(widget.polylines);
    setPolylines(widget.polylines);
    registerHitTester(
      this,
      widget.hitNotifier,
      (camera, point) => [
        for (final polyline in hitPolylines(camera, widget.polylines, point, widget.minimumHitbox)) polyline.hitValue,
      ],
    );
  }
}
