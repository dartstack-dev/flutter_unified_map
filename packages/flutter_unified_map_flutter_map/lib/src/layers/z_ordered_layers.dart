import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' show TileLayer;
import 'package:flutter_unified_map_flutter_map/src/layers/shape_layers.dart';
import 'package:flutter_unified_map_flutter_map/src/layers/tile_layers.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

enum _Kind { tiles, polygons, polylines, circles }

/// Google Maps orders tile overlays, polygons, polylines and circles together by zIndex, so each run of
/// consecutive objects of one kind becomes its own flutter_map layer, stacked in zIndex order.
///
/// Built tile layers are kept while the fields that decide which tiles to fetch are unchanged, so an opacity or
/// zIndex change keeps the loaded tiles. A built layer that leaves the tree is dropped: its state disposed its tile
/// provider.
class ZOrderedLayers extends StatefulWidget {
  const ZOrderedLayers({
    super.key,
    required this.factory,
    required this.style,
    required this.tileLayers,
    required this.polygons,
    required this.polylines,
    required this.circles,
  });

  final TileLayerFactory factory;
  final PlatformMapStyle style;
  final List<PlatformTileLayer> tileLayers;
  final List<PlatformPolygon> polygons;
  final List<PlatformPolyline> polylines;
  final List<PlatformCircle> circles;

  @override
  State<ZOrderedLayers> createState() => _ZOrderedLayersState();
}

class _ZOrderedLayersState extends State<ZOrderedLayers> {
  PlatformMapStyle? _baseStyle;
  Widget? _base;
  var _tiles = <(PlatformTileLayer, bool), TileLayer>{};
  var _highDensity = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final showsBase = showsBaseMap(style, widget.tileLayers);
    if (!showsBase) {
      _baseStyle = null;
      _base = null;
    } else if (style != _baseStyle) {
      _baseStyle = style;
      final base = widget.factory.baseMapLayer(style);
      _base = base == null ? null : KeyedSubtree(key: ValueKey(style), child: base);
    }
    _highDensity = (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1) >= 2;
    _tiles = {
      for (final layer in widget.tileLayers)
        if (_fetchKey(layer) case final key) key: _tiles[key] ?? _buildTiles(layer, key),
    };
    return Stack(fit: StackFit.expand, children: [if (showsBase) ?_base, ..._layers()]);
  }

  (PlatformTileLayer, bool) _fetchKey(PlatformTileLayer layer) => (
    PlatformTileLayer(
      id: layer.id,
      urlTemplate: layer.urlTemplate,
      subdomains: layer.subdomains,
      minZoom: layer.minZoom,
      maxZoom: layer.maxZoom,
      tileSize: layer.tileSize,
      headers: layer.headers,
    ),
    _highDensity && layer.urlTemplate.contains('{r}'),
  );

  TileLayer _buildTiles(PlatformTileLayer layer, (PlatformTileLayer, bool) key) =>
      widget.factory.platformTileLayer(layer, highDensity: key.$2);

  Widget _tileOverlay(PlatformTileLayer layer) => KeyedSubtree(
    key: ValueKey(('tiles', layer.id)),
    child: Opacity(
      opacity: layer.opacity.clamp(0, 1),
      child: KeyedSubtree(key: ValueKey(_fetchKey(layer)), child: _tiles[_fetchKey(layer)]!),
    ),
  );

  Iterable<Widget> _layers() sync* {
    final objects =
        <(double, _Kind, int, PlatformMapObject)>[
          for (final (i, t) in widget.tileLayers.indexed) (t.zIndex, _Kind.tiles, i, t),
          for (final (i, p) in widget.polygons.indexed) (p.zIndex, _Kind.polygons, i, p),
          for (final (i, p) in widget.polylines.indexed) (p.zIndex, _Kind.polylines, i, p),
          for (final (i, c) in widget.circles.indexed) (c.zIndex, _Kind.circles, i, c),
        ]..sort((a, b) {
          final byZ = a.$1.compareTo(b.$1);
          if (byZ != 0) return byZ;
          final byKind = a.$2.index.compareTo(b.$2.index);
          return byKind != 0 ? byKind : a.$3.compareTo(b.$3);
        });
    final runCounts = <_Kind, int>{};
    var start = 0;
    while (start < objects.length) {
      final kind = objects[start].$2;
      var end = start + 1;
      while (end < objects.length && objects[end].$2 == kind) {
        end++;
      }
      final run = [for (final o in objects.sublist(start, end)) o.$4];
      start = end;
      Widget keyed(Widget layer) {
        final index = runCounts[kind] = (runCounts[kind] ?? 0) + 1;
        return KeyedSubtree(key: ValueKey((kind, index)), child: layer);
      }

      switch (kind) {
        case _Kind.tiles:
          yield* run.cast<PlatformTileLayer>().map(_tileOverlay);
        case _Kind.polygons:
          yield keyed(polygonLayer(run.cast<PlatformPolygon>().toList()));
        case _Kind.polylines:
          yield keyed(polylineLayer(run.cast<PlatformPolyline>().toList()));
        case _Kind.circles:
          yield keyed(circleLayer(run.cast<PlatformCircle>().toList()));
      }
    }
  }
}
