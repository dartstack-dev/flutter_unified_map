import 'package:flutter/widgets.dart';

import '../../map/conversions.dart';
import '../../map/layer_registry.dart';
import '../../map/map_layer_host.dart';
import '../polyline_layer/polyline.dart';

/// Base state of every map layer, built-in or from another package.
///
/// It owns a [layerId], follows the map ([host]) it is placed under, and calls [sync] whenever the widget or the
/// map changes; the layer then registers its objects with `host.registry` (directly, through a `MarkerPublisher`,
/// [setPolylines] or [setFlutterMapLayers]). Everything the layer registered is removed when it is disposed or moves
/// to another map. The widget must be placed (directly or inside other widgets) in `UnifiedMap.children`, whose
/// order is the layers' z-order; [build] returns an empty box, override it to draw Flutter widgets above the map.
abstract class MapLayerState<W extends StatefulWidget> extends State<W> {
  /// Unique per layer; prefix of every object id of this layer.
  final String layerId = LayerRegistry.newLayerId();
  MapLayerHost? _host;
  var _keyIds = <Key, int>{};
  var _previousKeyIds = <Key, int>{};
  int _nextKeyId = 0;

  /// The map this layer lives in. Available from the first [sync] on.
  MapLayerHost get host => _host!;

  /// Registers the layer's current objects with [host]. Called after the layer is attached to a map, when the
  /// widget is updated (unless [updateShouldSync] says otherwise), when an inherited dependency changes (the map's
  /// pixel ratio or theme among them) and when the layer's z-index changes.
  void sync();

  /// Whether an update from [oldWidget] needs a [sync]. Override it to skip rebuilding objects that did not change.
  @protected
  bool updateShouldSync(covariant W oldWidget) => true;

  /// Called before the first [sync] on a map: subscribe to `host.idleCamera` / `host.liveCamera` here.
  void attachHost(MapLayerHost host) {}

  /// Called when the layer leaves [host] (disposed or moved to another map): unsubscribe here.
  void detachHost(MapLayerHost host) {}

  /// Object id for the element at [index], or for its [key] when it has one. Ids of a layer start with
  /// `'<layerId>/'` so that taps come back to it.
  ///
  /// Without a key: `'<layerId>/<index>'`. A `ValueKey<String>`: `'<layerId>/k:<value>'`; a `ValueKey` of a number or
  /// a bool: `'<layerId>/k<type>:<value>'`. Any other key (`ObjectKey`, `UniqueKey`, a `ValueKey` of an object) is
  /// compared with `==`, as Flutter compares keys, and gets `'<layerId>/k#<n>'`; such an id is kept while the key is
  /// asked for at least once between two [sync]s.
  String objectId(Key? key, int index) {
    if (key == null) return '$layerId/$index';
    if (key is ValueKey) {
      switch (key.value) {
        case final String value:
          return '$layerId/k:$value';
        case final num value:
          return '$layerId/k${value.runtimeType}:$value';
        case final bool value:
          return '$layerId/kbool:$value';
      }
    }
    final id = _keyIds[key] ??= _previousKeyIds[key] ?? _nextKeyId++;
    return '$layerId/k#$id';
  }

  /// Replaces the layer's polylines (ids `'<layerId>/<index>'`, painted in list order) right away. Pass them to
  /// `MarkerPublisher.publish` instead when they belong with a generation of markers (spiderfy legs), so that they
  /// reach the map together.
  void setPolylines(List<Polyline> polylines) =>
      host.registry.setPolylines(layerId, layerPolylines(host.registry, layerId, polylines));

  void _sync() {
    _previousKeyIds = _keyIds;
    _keyIds = {};
    sync();
  }

  int _slot() {
    final children = mounted ? MapLayerScope.childrenOf(context) : null;
    if (children == null) return 0;
    var top = context.widget;
    var slot = children.length;
    context.visitAncestorElements((element) {
      if (MapLayerScope.isChildrenStack(element.widget)) {
        final index = children.indexWhere((child) => identical(child, top));
        if (index >= 0) slot = index;
        return false;
      }
      top = element.widget;
      return true;
    });
    return slot;
  }

  /// Replaces the flutter_map layer widgets this layer draws inside the map when `host.supportsFlutterMapLayers`;
  /// ignored on native maps.
  void setFlutterMapLayers(List<Widget> layers) => host.registry.setFlutterMapLayers(layerId, layers);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = MapLayerScope.of(context);
    final previous = _host;
    if (!identical(previous, next)) {
      if (previous != null) {
        detachHost(previous);
        previous.registry.removeLayer(layerId);
      }
      _host = next;
      next.registry.addLayer(layerId, slot: _slot, resync: _resync);
      attachHost(next);
    }
    _sync();
  }

  void _resync() {
    if (mounted) _sync();
  }

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (updateShouldSync(oldWidget)) _sync();
  }

  @override
  void dispose() {
    final host = _host;
    if (host != null) {
      detachHost(host);
      host.registry.removeLayer(layerId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Whether [a] and [b] hold the same objects in the same order. Layers keep a copy of the list they last synced, so
/// a list changed in place is not mistaken for an unchanged one.
bool sameItems(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}
