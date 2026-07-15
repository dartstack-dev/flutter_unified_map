## 0.8.0 (2026-07-15)

- Upgrade packages: flutter_map 8.3.1, latlong2 0.10.

## 0.7.0 (2026-04-28)

- Upgrade packages: flutter_map 8.3.0.

## 0.6.0 (2026-01-17)

- Hit-testing and camera fixes; example polish.

## 0.5.0 (2025-10-08)

- BREAKING: flutter_map 8.2.2 (from 7.0.2); Dart 3.6 / Flutter 3.27.
- Polygon labels through `dart_polylabel2`.
- Marker updates reach the platform in order, one at a time (a later diff could overtake an earlier one on Android and Apple). A marker whose new icon is still rendering now stays exactly as it was until the whole update is ready, instead of moving with its old icon. Layers stack in the order they are mounted.
- A marker transition animates only the markers of the layer that set it: the other layers' markers go out first in an update without transition. A marker update the platform failed is sent again instead of being lost. `MarkerPublisher.publish(polylines:)` sends a layer's polylines with its markers, and shapes changed with markers wait for an in-flight marker update.

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
