# flutter_unified_map_example

Demo app for `flutter_unified_map`, built only on `package:flutter_unified_map/flutter_unified_map.dart`. Four tabs:

- **Stations**: 300 deterministic pseudo-random stations over Europe in a plain `MarkerLayer`. Tap a pin to select
  it; the selection is drawn by a separate `MarkerLayer`. For clustering (thousands of pins, animated split and
  merge), see the `flutter_unified_map_marker_cluster` package and its example, in the sibling repository
  [`flutter_unified_map_marker_cluster`](../../flutter_unified_map_marker_cluster).
- **Route**: Paris → Lyon `PolylineLayer` with a white border and a dashed detour, waypoint circles in pixels, a
  500 m circle in meters and two tappable low-emission zones (`PolygonLayer` + `hitNotifier`). The buttons call
  `animatedFitCamera` (bottom padding clears the panel) and `animateTo` with an offset.
- **Geometry**: custom pins and an itinerary written exactly as with flutter_map, and the scene the end-to-end
  tests mount (see [`integration_test/README.md`](integration_test/README.md)): a teardrop pin anchored by its tip,
  letter badges, an icon in a disc, an upright and a flat arrow, three pins sharing one `iconKey`; the Paris → Lyon →
  Marseille route with a border, a dashed and a dotted line, waypoint circles in pixels, a 2 km circle, a polygon
  with a hole and tappable polygons. Buttons: fit route, rotate 45°, reset.
- **Controls**: base map style (including `none` and an OSM `TileLayer` with `replacesBaseMap`), user location,
  compass, zoom buttons and a live readout fed by `onPositionChanged`.

```sh
flutter pub get          # once, from the repository root
cd example && flutter run
```

## Platforms

| Platform | Map | Setup |
|---|---|---|
| Android | Google Maps SDK | API key, see below |
| iOS, macOS | Apple MapKit | none (location usage string and macOS network entitlement are already set) |
| Web, Windows, Linux | flutter_map with OpenStreetMap tiles | none |

### Google Maps API key (Android)

Create a key with **Maps SDK for Android** enabled in the
[Google Cloud console](https://console.cloud.google.com/google/maps-apis/credentials), then either add it to
`example/android/local.properties` (not committed):

```properties
maps.apiKey=YOUR_KEY
```

or export it before building:

```sh
export MAPS_API_KEY=YOUR_KEY
```

`android/app/build.gradle.kts` reads `maps.apiKey` first, then `MAPS_API_KEY`, and injects it into
`AndroidManifest.xml` (`com.google.android.geo.API_KEY`). Without a key the app builds and the map shows "Map not
configured: API key missing". Full steps (Cloud console, SHA-1 restriction, troubleshooting): see the
[repository README](../README.md#2-android-google-maps-api-key).

### Tiles

The OpenStreetMap tile servers are run by volunteers. Follow the
[tile usage policy](https://operations.osmfoundation.org/policies/tiles/) and use your own tile provider for
anything beyond a demo.
