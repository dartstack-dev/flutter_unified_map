# flutter_unified_map

Native maps for Flutter with a [flutter_map](https://pub.dev/packages/flutter_map)-style API.

| Platform | Engine | Package |
|---|---|---|
| Android | Google Maps SDK for Android | `flutter_unified_map_android` |
| iOS, macOS | Apple MapKit | `flutter_unified_map_apple` |
| Web, Windows, Linux, tests | flutter_map (OpenStreetMap tiles) | `flutter_unified_map_flutter_map` |

```dart
UnifiedMap(
  mapController: controller,
  options: MapOptions(initialCenter: LatLng(48.8566, 2.3522), initialZoom: 6),
  children: [
    MarkerLayer(markers: [Marker(point: LatLng(48.8566, 2.3522), iconKey: 'pin', child: const Pin())]),
    PolylineLayer(polylines: [Polyline(points: route, color: Colors.blue, strokeWidth: 5, borderStrokeWidth: 2, borderColor: Colors.white)]),
    Positioned(right: 12, bottom: 12, child: CompassButton()),
  ],
)
```

Marker children are ordinary Flutter widgets: the core rasterises them once per `iconKey` and hands the bitmap to the native map. Layers that flutter_map users know (`MarkerLayer`, `PolylineLayer`, `PolygonLayer`, `CircleLayer`, `TileLayer`) keep their names and fields; any other child is drawn above the map in a `Stack`.

`MapCamera.rotation` keeps flutter_map's meaning on every platform. What runs where, what has been verified, and the known limitations are listed in [STATUS.md](STATUS.md).

## Clustering

Marker clustering is a separate package,
[`flutter_unified_map_marker_cluster`](../flutter_unified_map_marker_cluster) (repository
`flutter_unified_map_marker_cluster`), with the API of
[flutter_map_marker_cluster](https://pub.dev/packages/flutter_map_marker_cluster): `MarkerClusterLayerWidget`,
`MarkerClusterLayerOptions`, animated split and merge when the zoom level changes, spiderfy at the maximum zoom. On
Android, iOS and macOS it clusters in Dart and the native map animates the markers; on web, Windows and Linux it runs
flutter_map_marker_cluster itself inside the flutter_map backend.

## Writing your own layers

`package:flutter_unified_map/plugin_api.dart` is the API that extension packages (like the cluster package) build on,
in the spirit of flutter_map's `plugin_api.dart`:

| Piece | Role |
|---|---|
| `MapLayerState` | Base state of a layer: `layerId`, object ids `'<layerId>/<key>'`, `sync()` on widget and map changes, everything unregistered on dispose. Helpers `setPolylines`, `setFlutterMapLayers` |
| `MapLayerHost` (`state.host`) | `camera`, `controller`, `isReady`, `pixelRatio`, `idleCamera` (settled moves), `liveCamera` (every move event, also during gestures), `supportsFlutterMapLayers`, `registry`, `icons` |
| `MarkerPublisher`, `MarkerSpec` | Atomic marker generations: a generation reaches the map only when all its icons are rasterised, the previous one stays untouched meanwhile, a newer one supersedes a pending one. A generation can carry the layer's polylines (spiderfy legs) so that they arrive with its markers. `prepare` rasterises icons ahead of time |
| `MarkerTransition` | Animates a generation: markers sliding from (`appearFrom`) or to (`disappearTo`) a position while fading, moved markers gliding. Only the markers of the layer that set it are animated; shapes never are |
| `LayerRegistry` | Low-level registration of native objects. Marker updates reach the platform in order, one at a time; one the platform failed is sent again. Shapes changed in the same frame as markers wait for an in-flight marker update |
| `integerZoom` | Integer zoom level with a 1e-6 tolerance (MapKit reports zoom 5 as 4.9999999) |

App code can also put a raw flutter_map layer in a `UnifiedMap` with `FlutterMapLayer(child: ...)`: it is drawn
inside the map on web, Windows and Linux and ignored on native maps.

## Setup

### 1. Add the dependency

```yaml
dependencies:
  flutter_unified_map: ^0.6.0
```

The platform packages (`flutter_unified_map_android`, `flutter_unified_map_apple`, `flutter_unified_map_flutter_map`) are endorsed and
picked automatically; do not add them yourself.

> Until the packages are published, depend on a local clone with a path dependency **and** override every federated
> package, otherwise pub looks for them on pub.dev:
>
> ```yaml
> dependencies:
>   flutter_unified_map:
>     path: ../flutter_unified_map/packages/flutter_unified_map
>
> dependency_overrides:
>   flutter_unified_map_platform_interface:
>     path: ../flutter_unified_map/packages/flutter_unified_map_platform_interface
>   flutter_unified_map_android:
>     path: ../flutter_unified_map/packages/flutter_unified_map_android
>   flutter_unified_map_apple:
>     path: ../flutter_unified_map/packages/flutter_unified_map_apple
>   flutter_unified_map_flutter_map:
>     path: ../flutter_unified_map/packages/flutter_unified_map_flutter_map
> ```

### 2. Android: Google Maps API key

Android draws the map with the Google Maps SDK, which needs an API key. Without one the app does not crash: the map
shows **"Map not configured: API key missing"**.

**Create the key** in the [Google Cloud console](https://console.cloud.google.com/google/maps-apis/credentials):

1. Pick or create a project and **link a billing account** (required by Google, even though the "Mobile Native
   Dynamic Maps" SKU used by the Android SDK is free and unlimited).
2. Enable **Maps SDK for Android** (APIs & Services → Library).
3. Create an API key (APIs & Services → Credentials → Create credentials → API key).
4. Recommended: restrict it. Application restrictions → **Android apps** → add your package name (the
   `applicationId` in `android/app/build.gradle.kts`) and the **SHA-1** of every certificate that signs the app
   (debug, release, and the Play App Signing certificate from the Play Console). API restrictions → Maps SDK for
   Android. The debug SHA-1:

   ```sh
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android | grep SHA1
   ```

**Give the key to the app** without committing it:

1. Put it in `android/local.properties` (already git-ignored by Flutter projects):

   ```properties
   maps.apiKey=AIza...
   ```

   or, on CI, in the `MAPS_API_KEY` environment variable.

2. Read it in `android/app/build.gradle.kts` and pass it to the manifest:

   ```kotlin
   import java.util.Properties

   val mapsApiKey: String = Properties()
       .apply { rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use(::load) }
       .getProperty("maps.apiKey")
       ?: System.getenv("MAPS_API_KEY")
       ?: ""

   android {
       defaultConfig {
           // ...
           manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
       }
   }
   ```

3. Declare it in `android/app/src/main/AndroidManifest.xml`, inside `<application>`, and make sure the app may use
   the network:

   ```xml
   <manifest ...>
       <uses-permission android:name="android.permission.INTERNET" />
       <application ...>
           <meta-data
               android:name="com.google.android.geo.API_KEY"
               android:value="${MAPS_API_KEY}" />
       </application>
   </manifest>
   ```

4. Rebuild the app (`flutter run`, not a hot reload: the manifest is fixed at build time).

**Other Android requirements:** `minSdk` 24 or higher (Flutter's default), and a device or emulator with **Google
Play services** (in Android Studio's Device Manager pick a "Google APIs" or "Google Play" system image).

### 3. iOS and macOS

Nothing to configure: MapKit needs no key and no account. iOS 15+ and macOS 12+.

- `MapOptions(showsUserLocation: true)` needs `NSLocationWhenInUseUsageDescription` in `ios/Runner/Info.plist`
  (and `macos/Runner/Info.plist`), plus the location permission granted at runtime.
- macOS apps are sandboxed: add `com.apple.security.network.client` to `macos/Runner/DebugProfile.entitlements` and
  `Release.entitlements` (MapKit and tile layers download over the network), and
  `com.apple.security.personal-information.location` if you show the user location.

### 4. Web, Windows, Linux

Nothing to configure. The map is drawn by flutter_map with OpenStreetMap tiles. Show the attribution
(`RichAttributionWidget`) and follow the [OSM tile usage policy](https://operations.osmfoundation.org/policies/tiles/),
or use your own tiles with `MapStyle.none` and a `TileLayer(replacesBaseMap: true)`.

### When the map does not show

`UnifiedMap` displays the reason over the map (replace it with `UnifiedMap.errorBuilder`, or listen to
`MapOptions.onMapError`):

| Message | Cause | Fix |
|---|---|---|
| Map not configured: API key missing | Android: no `com.google.android.geo.API_KEY` meta-data, or an empty one (`maps.apiKey` not set when building) | Steps 2.1 to 2.4, then rebuild |
| Map services unavailable | Android: Google Play services missing or outdated | Use a Google APIs / Google Play image, update Play services |
| The map did not load | Android: nothing loaded within 15 s. Usually a rejected key (Logcat shows `Authorization failure`): Maps SDK for Android not enabled, no billing account, or the package / SHA-1 restriction does not match. Also no network | Check the key in the Cloud console, the SHA-1 of the certificate actually signing the build, the network |
| The map failed to load | iOS/macOS: MapKit reported an error. Web/desktop: tiles failed (the message names the tile server) | Network, macOS network entitlement, tile URL |

Load errors disappear by themselves when the map loads later (network back).

## Repository

Pub workspace, federated plugin:

```
packages/flutter_unified_map                     app-facing API, layers, controller, rasteriser, plugin API
packages/flutter_unified_map_platform_interface  UnifiedMapsPlatform + Platform* data classes
packages/flutter_unified_map_android             Kotlin + play-services-maps (Pigeon)
packages/flutter_unified_map_apple               Swift + MapKit, shared iOS/macOS source (Pigeon)
packages/flutter_unified_map_flutter_map         Dart implementation on flutter_map
example/                                  demo app
tool/pigeon/messages.dart                 canonical Pigeon schema (tool/pigeon/generate.sh)
```

```sh
flutter pub get            # once, at the root
tool/pigeon/generate.sh    # after editing tool/pigeon/messages.dart
flutter analyze
cd example && flutter run
```

## License

MIT. Successor of the Xamarin.Forms [UnifiedMaps](https://github.com/fivenine-zurich/UnifiedMaps).
