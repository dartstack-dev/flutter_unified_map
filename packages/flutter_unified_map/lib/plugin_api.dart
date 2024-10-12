/// API for packages that add their own layers to `UnifiedMap`, like flutter_map's `plugin_api.dart`.
///
/// A layer is a `StatefulWidget` placed in `UnifiedMap.children` (directly or inside other widgets) whose state
/// extends [MapLayerState]. The order of `UnifiedMap.children` is the layers' z-order. In [MapLayerState.sync] it
/// registers native objects with the map:
///
/// - markers through a [MarkerPublisher]: a list of [MarkerSpec]s is published atomically once all its icons are
///   rasterised, optionally animated by a [MarkerTransition] (this layer's markers sliding from / to a position while
///   fading) and with the layer's polylines (spiderfy legs), which are sent once those markers are applied;
/// - polylines alone with [MapLayerState.setPolylines];
/// - flutter_map layer widgets with [MapLayerState.setFlutterMapLayers], drawn only where
///   [MapLayerHost.supportsFlutterMapLayers] (web, Windows, Linux);
/// - anything else through [MapLayerHost.registry] ([LayerRegistry]).
///
/// [MapLayerState.host] gives the camera ([MapLayerHost.camera], [MapLayerHost.liveCamera] on every move,
/// [MapLayerHost.idleCamera] when settled), the controller, the pixel ratio and the icon cache.
///
/// ```dart
/// class PinsLayer extends StatefulWidget {
///   const PinsLayer({super.key, required this.points});
///   final List<LatLng> points;
///   @override
///   State<PinsLayer> createState() => _PinsLayerState();
/// }
///
/// class _PinsLayerState extends MapLayerState<PinsLayer> {
///   late final _publisher = MarkerPublisher(layerId);
///
///   @override
///   void sync() => _publisher.publish(host, [
///     for (final (i, p) in widget.points.indexed)
///       MarkerSpec(id: objectId(null, i), position: p, iconKey: 'pin', child: const Pin(), size: const Size(24, 24)),
///   ]);
///
///   @override
///   void dispose() {
///     _publisher.dispose();
///     super.dispose();
///   }
/// }
/// ```
library;

export 'flutter_unified_map.dart';
export 'src/layer/marker_layer/marker_publisher.dart' show MarkerPublisher, MarkerSpec;
export 'src/layer/shared/map_layer_state.dart' show MapLayerState;
export 'src/map/camera/zoom.dart' show integerZoom, integerZoomEpsilon;
export 'src/map/layer_registry.dart' show LayerHitTester, LayerRegistry, MarkerTapHandler, MarkerTransition;
export 'src/map/map_layer_host.dart' show MapLayerHost;
export 'src/raster/icon_cache.dart' show IconCache, IconCacheKey;
