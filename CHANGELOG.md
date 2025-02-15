## 0.3.0 (2025-02-15)

- `MapCamera` and event-stream fixes; tile-layer behaviour aligned between backends.

## 0.2.0 (2024-12-27)

- The Android and Apple Dart plugins no longer touch the binary messenger in `registerWith`, which the plugin registrant calls before `main()` (the app failed at startup with "UnifiedMapsPlatform.instance is not set").
- Upgrade packages.

## 0.1.0 (2024-10-12)

- Initial federated plugin: `flutter_unified_map`, `flutter_unified_map_platform_interface`, `flutter_unified_map_android` (Google Maps SDK), `flutter_unified_map_apple` (MapKit, iOS + macOS), `flutter_unified_map_flutter_map` (web, Windows, Linux).
- `UnifiedMap`, `MapOptions`, `MapController` (flutter_map 8 methods plus `animateTo` / `animatedFitCamera`), `MapCamera.of`, `MarkerLayer`, `PolylineLayer`, `PolygonLayer`, `CircleLayer`, `TileLayer`, `FlutterMapLayer`, `RichAttributionWidget`, `SimpleAttributionWidget`, Dart hit-testing of polylines, polygons and circles through `LayerHitNotifier`.
- Same conventions on every backend: `MapCamera.rotation` keeps flutter_map's sign (platform bearing is the compass heading, `-rotation`); a polyline border adds `borderStrokeWidth` to the total width, as in flutter_map; a 512/1024 `tileSize` follows the Mapbox convention.
