import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' show PolygonPainterFillMethod;

import '../../map/conversions.dart';
import '../shared/hit_test.dart';
import '../shared/layer_hit_result.dart';
import '../shared/map_layer_state.dart';
import 'polygon.dart';

/// flutter_map's `PolygonLayer`. Per backend:
/// - [polygonLabels]: the polygons' labels, as markers natively (see `Polygon.label`); [drawLabelsLast] true puts
///   every label above all of the layer's polygons, false right above its own polygon (natively markers always draw
///   above shapes, so false matters only between this layer's labels).
/// - [invertedFill]: natively one world-sized polygon (latitudes ±85, split at the antimeridian) whose holes are
///   the layer's polygons; overlapping polygons are filled where flutter_map's even-odd rule would not.
/// - [useAltRendering], [debugAltRenderer], [painterFillMethod], [polygonCulling], [simplificationTolerance] tune
///   flutter_map's painter and only apply on the flutter_map backend. [drawInSingleWorld] likewise: native maps draw
///   each edge the short way.
class PolygonLayer<R extends Object> extends StatefulWidget {
  final List<Polygon<R>> polygons;
  final bool useAltRendering;
  final bool debugAltRenderer;
  final bool polygonCulling;
  final bool polygonLabels;
  final bool drawLabelsLast;
  final bool drawInSingleWorld;
  final PolygonPainterFillMethod painterFillMethod;
  final Color? invertedFill;
  final LayerHitNotifier<R>? hitNotifier;
  final double simplificationTolerance;

  const PolygonLayer({
    super.key,
    required this.polygons,
    this.useAltRendering = false,
    this.debugAltRenderer = false,
    this.polygonCulling = true,
    this.polygonLabels = true,
    this.drawLabelsLast = false,
    this.drawInSingleWorld = false,
    this.painterFillMethod = kIsWeb ? PolygonPainterFillMethod.evenOdd : PolygonPainterFillMethod.pathCombine,
    this.invertedFill,
    this.hitNotifier,
    this.simplificationTolerance = 0.3,
  }) : assert(simplificationTolerance >= 0, 'simplificationTolerance cannot be negative');

  @override
  State<PolygonLayer<R>> createState() => _PolygonLayerState<R>();
}

class _PolygonLayerState<R extends Object> extends MapLayerState<PolygonLayer<R>> {
  var _synced = <Polygon<R>>[];

  @override
  bool updateShouldSync(PolygonLayer<R> oldWidget) =>
      !sameItems(_synced, widget.polygons) || oldWidget.hitNotifier != widget.hitNotifier;

  @override
  void sync() {
    _synced = List.of(widget.polygons);
    host.registry.setPolygons(layerId, [
      for (var i = 0; i < widget.polygons.length; i++)
        toPlatformPolygon(
          widget.polygons[i],
          objectId(null, i),
          host.registry.shapeZIndexOf(layerId, i, widget.polygons.length),
        ),
    ]);
    registerHitTester(
      this,
      widget.hitNotifier,
      (camera, point) => [for (final polygon in hitPolygons(camera, widget.polygons, point)) polygon.hitValue],
    );
  }
}
