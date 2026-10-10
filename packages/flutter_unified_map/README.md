# flutter_unified_map

Native maps for Flutter with a [flutter_map](https://pub.dev/packages/flutter_map)-style API: Google Maps on Android, Apple MapKit on iOS and macOS, flutter_map on web and desktop.

See the [repository README](https://github.com/dartstack-dev/flutter_unified_map) for the full guide.

<img src="https://raw.githubusercontent.com/dartstack-dev/flutter_unified_map/main/screenshots/stations.png" alt="The example app's stations scene over Apple MapKit" width="230" height="500">
<img src="https://raw.githubusercontent.com/dartstack-dev/flutter_unified_map/main/screenshots/europe.png" alt="The example app's Europe scene over Apple MapKit" width="230" height="500">

```dart
import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

UnifiedMap(
  options: MapOptions(initialCenter: LatLng(48.8566, 2.3522), initialZoom: 6),
  children: [
    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example'),
    MarkerLayer(markers: [Marker(point: LatLng(48.8566, 2.3522), child: const Icon(Icons.place))]),
  ],
)
```

As in flutter_map, the order of `children` is the layers' z-order. Native maps cannot host widgets, so each marker
child is rasterised to a bitmap, once per `iconKey` (the child itself by default, so a `const` child is rendered
once) and again when the theme, text scale or brightness changes. Give a child built anew on every rebuild an
`iconKey` describing what it looks like, e.g. `Marker(iconKey: ('pin', color), child: Pin(color: color))`; in
debug builds the package warns when it sees markers re-rasterised on every rebuild.

Differences from flutter_map worth knowing: `MapEvent`s carry the subset of `MapEventSource` that native maps can
tell apart (`onDrag`, `onMultiFinger`, `mapController`, …); `MapController.animateTo` and `animatedFitCamera`
(from `flutter_map_animations`) ignore `curve`; `crs`, `cameraConstraint` and pointer callbacks are not provided.

Clustering is in the separate package `flutter_unified_map_marker_cluster` (API of flutter_map_marker_cluster,
animated split and merge). Packages that add their own layers build on `package:flutter_unified_map/plugin_api.dart`
(`MapLayerState`, `MapLayerHost`, `MarkerPublisher`, `MarkerTransition`, `integerZoom`); see the repository README.
`FlutterMapLayer(child: ...)` draws a raw flutter_map layer on web, Windows and Linux and nothing on native maps.

## Setup

### 1. Add the dependency

```yaml
dependencies:
  flutter_unified_map: ^1.0.0
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
