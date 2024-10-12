import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../raster/icon_cache.dart';
import 'camera/map_camera.dart';
import 'controller/map_controller.dart';
import 'layer_registry.dart';

/// What a layer needs from the map it lives in. A `MapLayerState` reaches it through `host`.
abstract class MapLayerHost {
  /// Where the layer registers its native objects.
  LayerRegistry get registry;

  /// The map's cache of rasterised marker icons.
  IconCache get icons;

  /// The camera as last reported by the platform, sized to the map widget.
  MapCamera get camera;

  MapController get controller;

  /// Context whose themes are captured when rasterising icons.
  BuildContext get context;

  double get pixelRatio;

  /// Whether the platform reported the map ready. Objects registered before are sent once it is.
  bool get isReady;

  /// The camera once the map is ready, then after every settled move.
  ValueListenable<MapCamera?> get idleCamera;

  /// The camera on every platform move event (at most once per frame, during gestures and animations too), on
  /// ready, and when the map widget is resized.
  ValueListenable<MapCamera> get liveCamera;

  /// Whether the platform draws the map with flutter_map, so that flutter_map layer widgets passed to
  /// `LayerRegistry.setFlutterMapLayers` are drawn (web, Windows, Linux). False on native maps.
  bool get supportsFlutterMapLayers;
}

/// Gives layers their map. Layers depend on it, so they sync again when the pixel ratio or the [appearance] their
/// rasterised icons depend on changes.
class MapLayerScope extends InheritedWidget {
  final MapLayerHost host;
  final double pixelRatio;
  final Object? appearance;

  /// `UnifiedMap.children`, whose order is the layers' z-order.
  final List<Widget> children;

  const MapLayerScope({
    super.key,
    required this.host,
    required this.pixelRatio,
    required this.appearance,
    required this.children,
    required super.child,
  });

  static MapLayerHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MapLayerScope>()?.host;

  static MapLayerHost of(BuildContext context) =>
      maybeOf(context) ?? (throw StateError('Map layers must be placed in UnifiedMap.children'));

  static List<Widget>? childrenOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MapLayerScope>()?.children;

  static bool isChildrenStack(Widget widget) => widget is MapChildrenStack;

  @override
  bool updateShouldNotify(MapLayerScope oldWidget) =>
      host != oldWidget.host || pixelRatio != oldWidget.pixelRatio || appearance != oldWidget.appearance;
}

/// The `Stack` holding the platform view and `UnifiedMap.children`; layers find their position below it.
class MapChildrenStack extends Stack {
  const MapChildrenStack({super.key, super.children});
}
