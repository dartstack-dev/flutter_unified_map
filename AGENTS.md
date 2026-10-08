# flutter_unified_map — agent context

`flutter_unified_map`: Flutter rewrite of [UnifiedMaps](https://github.com/fivenine-zurich/UnifiedMaps), originally a Xamarin.Forms library that rendered the devices' native maps. The goal: a public API mirroring [flutter_map](https://pub.dev/packages/flutter_map) 8 (`UnifiedMap`, `MapOptions`, `MapController`, `MapCamera`, layers), but rendered with native maps: Google Maps SDK on Android, MapKit on iOS/macOS, and pure Dart flutter_map on web/Windows/Linux and in tests.

## Current state

Phase 1 (all packages) and the cluster-animation round (marker transitions on every backend, clustering moved to the `flutter_unified_map_marker_cluster` repo, GasMobility's ShellMap migrated) are done and integration-checked on Oct 7 2026 on the iOS simulator, macOS and the Android emulator; see `STATUS.md` for what works per platform, what was verified and with which command, known limitations and open contract gaps.

## Layout

| Package | Role |
|---|---|
| `packages/flutter_unified_map` | Public API: `UnifiedMap`, `MapOptions`, `MapController` (plus the animated methods of `flutter_map_animations.AnimatedMapController`), `MapCamera`, `CameraFit`, layers (incl. `FlutterMapLayer`), `LayerRegistry`, widget rasterising, Dart hit-testing. `lib/plugin_api.dart`: the API for extension packages (`MapLayerState`, `MapLayerHost` with `liveCamera` / `idleCamera`, atomic `MarkerPublisher` + `MarkerSpec`, `MarkerTransition`, `integerZoom`) |
| `packages/flutter_unified_map_platform_interface` | **Frozen**: `UnifiedMapsPlatform` and the `Platform*` data classes. Do not change without updating every implementation |
| `packages/flutter_unified_map_android` | Kotlin + `play-services-maps`, Pigeon bindings (`dartPluginClass: UnifiedMapsAndroid`) |
| `packages/flutter_unified_map_apple` | Swift + MapKit, shared iOS/macOS source in `darwin/` (SwiftPM + podspec), Pigeon bindings |
| `packages/flutter_unified_map_flutter_map` | Pure Dart implementation on `flutter_map ^8.3.1`: web, Windows, Linux, tests |
| `example/` | Demo app (no clustering: that demo is in the cluster repo) |
| `~/Documents/Code/AlphaByte/flutter_unified_map_marker_cluster` | Separate repo: `flutter_unified_map_marker_cluster`, API of flutter_map_marker_cluster, built on `plugin_api.dart` |
| `tool/pigeon/messages.dart` | **Frozen**: canonical Pigeon schema; `tool/pigeon/generate.sh` regenerates both native packages |

## Architecture

Pub workspace (Dart 3.13, `flutter >= 3.47.0`), federated plugin. Data flow:

```
flutter_map-style layers (widgets)
        │  register their objects in LayerRegistry (object ids: '<layerId>/<key>')
        ▼
UnifiedMap state ── per-frame diff ──► UnifiedMapsPlatform (interface)
        │                                    │  Platform* → P* conversions (Dart side of each native package)
        │                                    ▼
        │                              Pigeon (UnifiedMapsHostApi)  ──► GoogleMap / MKMapView / FlutterMap
        │                              UnifiedMapsFlutterApi  ◄──────── native events
        ▼
events → MapCamera → UnifiedMapInheritedModel → dependent widgets (MapController.of, etc.)
```

- The core chooses the `viewId` and passes it with the initial options as platform view creation params, encoded with the Pigeon codec (`UnifiedMapsHostApi.pigeonChannelCodec`) as `[viewId, PMapOptions]` on Android and Apple; every Pigeon call names the view with it.
- The platform emits `onMapReady` before accepting updates. Updates are diffs (`added`, `changed`, `removedIds`); each platform keeps its own id → native object maps per view.
- Icons: the core sends `registerIcons` once per `PlatformIcon.key`; markers reference the `iconKey`. PNG rendered at `pixelRatio`, displayed at `logicalSize`.

## Platform contract

- `anchor` is fractional: `(0.5, 1.0)` = bottom center on the position. The core converts flutter_map's `Marker.alignment` with `anchor = ((1 - a.x) / 2, (1 - a.y) / 2)`.
- Zoom is Web Mercator (256 px tiles). `PlatformCamera.bearing` is a compass heading in degrees (the direction the top of the view faces, as Google `bearing` / MapKit `heading`), the opposite of flutter_map's `rotation`: the core converts with `bearing = -rotation mod 360`, and the flutter_map backend does the same (the frozen doc's "same sign as flutter_map's rotation" is wrong). MapKit converts zoom ↔ span: `longitudeDelta = 360 * viewWidthPx / (256 * 2^zoom)`.
- Camera events: `onCameraMoveStarted(byGesture)` once per movement, `onCameraMove` at most once per frame, `onCameraIdle` when settled. Programmatic moves also produce start → move → idle. A gesture that interrupts a programmatic move continues that movement on Android and Apple (no second start); the flutter_map backend settles the interrupted move first (idle, then a new gesture start). Not yet decided which one is the contract.
- Padding: the padded centre must be measured, not assumed to be the view centre: MapKit on iOS centres its camera inside `layoutMargins`.
- `moveCamera` with `animationMillis` completes when the animation ends or is interrupted.
- Taps on markers are native (`onMarkerTap`, routed back to the layer via the id prefix). Taps on polylines/polygons/circles are resolved in Dart by the core through the layers' hit-testers.
- Polyline borders: draw a second, wider line beneath (`zIndex - 0.5`), `width + borderWidth` wide in total (flutter_map's `borderStrokeWidth` meaning). Dash pattern in logical pixels.
- `tileSize` 512/1024: each `z/x/y` tile covers the extent of a 256 tile one/two levels lower (Mapbox convention; flutter_map `zoomOffset` -1/-2). `PlatformTileLayer.minZoom` / `maxZoom` are map (256-grid) zooms for every `tileSize`. `maxZoom` is the source's last native level (the core sends `TileLayer.maxNativeZoom`, and hides the layer itself above `TileLayer.maxZoom`): above it every backend scales up the tiles of that level (MapKit `maximumZ`, Android crops, flutter_map `maxNativeZoom`).
- `PlatformMapStyle.none` hides the base map (Google `MAP_TYPE_NONE`; MapKit: tile overlay with `canReplaceMapContent`).
- An implementation must accept calls for a view only after it emitted `PlatformMapReadyEvent` for it, and must ignore calls for disposed views.
- Marker updates are applied **in call order** per view: a backend must not let a later `updateMarkers` overtake an earlier one (the Dart sides await `registerIcons` before `updateMarkers`, so they must serialise per view).
- `updateMarkers(..., transition: PlatformMarkerTransition?)` animates an update (Pigeon `PMarkerTransition`): added markers in `appearFrom` slide from that position while fading in, others fade in; changed positions glide; removed markers in `disappearTo` slide there while fading out, then are removed. Ease-in-out (cubic 0.42, 0, 0.58, 1 everywhere), in-flight markers continue from their on-screen state, a disappearing marker added again is revived and continues from where it is (its `appearFrom` is ignored), a tap on a disappearing marker falls through to the map (`onMapTap` at the marker), disappearing markers are left out of snapshots while in-flight markers are drawn at their current position and opacity, an update without a transition puts the in-flight markers it touches at their target at once (checked on Android and Apple). Every backend implements it (Android `MarkerTransitions.kt`, Apple `AnnotationController.swift` with `FrameTicker`, flutter_map `MarkerStore`). See `platform_marker_transition.dart` and the cluster animation spec in the repo memory.
- `supportsFlutterMapLayers` / `setFlutterMapLayers(viewId, widgets)`: only the flutter_map backend draws these flutter_map layer widgets inside its `FlutterMap` (used by `flutter_unified_map_marker_cluster` to run the real `flutter_map_marker_cluster` on web, Windows and Linux).
- Marker updates: layers publish through `MarkerPublisher` (a generation reaches the registry only once all its icons are rasterised); the registry merges the layers' `MarkerTransition`s into one `PlatformMarkerTransition` per push (only ids that push adds or removes, longest duration of the layers it touches) and awaits each `updateMarkers` before sending the next diff. A push with a transition is split in two `updateMarkers` calls: first the markers of layers without a transition (no transition), then the animated layers' markers, since the platform contract animates every marker of an update. A diff is recorded as sent only once applied: a failed update is re-sent (once right away, then with the next change) with its transition hints. Polylines, polygons and circles stay dirty while a marker update is in flight if markers changed in the same frame; `MarkerPublisher.publish(polylines:)` registers a layer's polylines with its marker generation. Layer z-order is the order of `UnifiedMap.children` (layers under the same child: mount order); layers whose z-index changes are synced again. Polyline, polygon, circle and tile updates follow the same rule as markers: a diff is recorded only once applied, a failure is reported and sent again, and shapes changed in the same frame as markers are sent after that marker update is applied.
- Clustering lives in the separate repo `~/Documents/Code/AlphaByte/flutter_unified_map_marker_cluster` (API of flutter_map_marker_cluster), built on this package's plugin API.
- `onMapLoaded` when base map content has loaded (again after a load error, which the core then clears). `onMapError(code, message)` when the base map cannot be shown; with `apiKeyMissing` / `servicesUnavailable` the native map is not created and no ready event follows. `message` is the platform's precise text; the core adds user-facing guidance per code.
- End-to-end: `example/tool/integration_tests.sh <device>` (one `flutter test` per file, required on macOS; see `example/integration_test/README.md`).

## Commands

```sh
flutter pub get            # once, at the root (pub workspace)
tool/pigeon/generate.sh    # after editing tool/pigeon/messages.dart
flutter analyze            # analyses the whole workspace
flutter test packages/flutter_unified_map_android   # tests per package (example; same for the others)
cd example && flutter run # demo app
```

## Style

- Dart 3.13, `flutter_lints`, line length 120 (`dart format --line-length 120`).
- No comments that say what the code does; comment only a non-obvious why.
- No feature flags, no backwards-compat shims.
- Tests next to each package in `test/`. The core is tested against a fake `UnifiedMapsPlatform`; the native packages are tested on their Dart side against a Pigeon `FakeHostApi`.
- Never edit `*.g.dart`, `Messages.g.kt`, `Messages.g.swift`: run `tool/pigeon/generate.sh`.
- API reference: flutter_map 8 (`flutter_map` ^8.3.1 on pub.dev) — layers keep flutter_map's names and fields (`Marker`, `Polyline`, `Polygon`, `CircleMarker`, `TileLayer`).
