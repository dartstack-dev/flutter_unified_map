## 0.4.0 (2025-04-05)

- New `package:flutter_unified_map/plugin_api.dart` for extension packages: `MapLayerState` (with `setPolylines` / `setFlutterMapLayers`), `MapLayerHost` (`liveCamera` on every move event, `idleCamera`, `supportsFlutterMapLayers`), `MarkerPublisher` / `MarkerSpec` (atomic marker generations), `MarkerTransition`, `LayerRegistry`, `IconCache`, `integerZoom`.
- `FlutterMapLayer(child:)`: a raw flutter_map layer drawn inside the map on web, Windows and Linux, ignored on native maps.

## 0.3.0 (2025-02-15)

- `MapCamera` and event-stream fixes; tile-layer behaviour aligned between backends.

## 0.2.0 (2024-12-27)

- The Android and Apple Dart plugins no longer touch the binary messenger in `registerWith`, which the plugin registrant calls before `main()` (the app failed at startup with "UnifiedMapsPlatform.instance is not set").
- Upgrade packages.

## 0.1.0 (2024-10-12)

- Initial federated plugin: `flutter_unified_map`, `flutter_unified_map_platform_interface`, `flutter_unified_map_android` (Google Maps SDK), `flutter_unified_map_apple` (MapKit, iOS + macOS), `flutter_unified_map_flutter_map` (web, Windows, Linux).
- `UnifiedMap`, `MapOptions`, `MapController` (flutter_map 8 methods plus `animateTo` / `animatedFitCamera`), `MapCamera.of`, `MarkerLayer`, `PolylineLayer`, `PolygonLayer`, `CircleLayer`, `TileLayer`, `FlutterMapLayer`, `RichAttributionWidget`, `SimpleAttributionWidget`, Dart hit-testing of polylines, polygons and circles through `LayerHitNotifier`.
- Same conventions on every backend: `MapCamera.rotation` keeps flutter_map's sign (platform bearing is the compass heading, `-rotation`); a polyline border adds `borderStrokeWidth` to the total width, as in flutter_map; a 512/1024 `tileSize` follows the Mapbox convention.
