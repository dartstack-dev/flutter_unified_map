# flutter_unified_map_android

Android implementation of [`flutter_unified_map`](https://pub.dev/packages/flutter_unified_map) on the Google Maps SDK for Android (`play-services-maps` 20.0.0).

Apps depend on `flutter_unified_map`; this package is endorsed and picked automatically on Android.

## Setup

Step-by-step guide with the Gradle snippet and troubleshooting:
[repository README](https://github.com/AlphaByte/flutter_unified_map#2-android-google-maps-api-key).

1. Create a key for the **Maps SDK for Android** in the Google Cloud console (the project needs billing enabled; the
   "Mobile Native Dynamic Maps" SKU itself is free and unlimited). Restrict it to your package name and signing
   certificate SHA-1.
2. Declare it in `android/app/src/main/AndroidManifest.xml`, inside `<application>`:

   ```xml
   <application ...>
     <meta-data android:name="com.google.android.geo.API_KEY" android:value="YOUR_KEY" />
   </application>
   ```

   To keep the key out of version control, use a manifest placeholder
   (`android:value="${MAPS_API_KEY}"`) filled from `local.properties` in `android/app/build.gradle.kts`
   (`manifestPlaceholders["MAPS_API_KEY"] = ...`).
3. The device or emulator needs **Google Play services** (use a "Google APIs" or "Google Play" emulator image).
   `minSdk` is 24.

### Error reporting

The plugin reports why the base map cannot be shown as a `PlatformMapErrorEvent`, which `flutter_unified_map` turns into an
error view:

- `apiKeyMissing`: no `com.google.android.geo.API_KEY` (or legacy `com.google.android.maps.v2.API_KEY`) meta-data, or
  an empty one (an unset `${MAPS_API_KEY}` placeholder). The Google `MapView` is not created; the view shows the
  background color, never becomes ready, and every call on it is a no-op.
- `servicesUnavailable`: Google Play services is missing, disabled, outdated or updating (`GoogleApiAvailability`),
  checked once when the view is created. Same handling. The message says when the user can fix it
  (`GoogleApiAvailability.makeGooglePlayServicesAvailable`); the map must then be created again (a new `UnifiedMap`).
- `loadTimeout`: the map did not finish loading within 15 s during which it could load: the time only counts while
  the activity is resumed and the view has a size, and starts again after a pause. This is how a rejected key or a
  missing network shows up (Logcat shows `Authorization failure` for a rejected key). If the map loads later,
  `PlatformMapLoadedEvent` is sent and clears the error.

`PlatformMapLoadedEvent` is sent after the ready event, when the map has finished loading for the first time.

### User location

`MapOptions(showsUserLocation: true)` needs `ACCESS_FINE_LOCATION` or `ACCESS_COARSE_LOCATION` declared in the
manifest **and granted at runtime** (request it with a permission plugin before enabling the option). Without the
permission the option is ignored and a warning is logged.

## Platform notes

- Rendering: the map is an `AndroidView` (texture layer hybrid composition). The plugin forwards the activity
  lifecycle to every `MapView` through `flutter_plugin_android_lifecycle`.
- `PlatformMapStyle.muted` is a built-in grey JSON style; `showsPointsOfInterest: false` adds a POI-hiding style;
  `PlatformMapStyle.none` and tile layers with `replacesBaseMap` switch to `MAP_TYPE_NONE`.
- Not supported by the Google Maps SDK for Android: `showsScale` (no native scale bar), `doubleTapZoomEnabled`
  independently of `zoomEnabled` (Google ties double-tap zoom to zoom gestures), and changing `backgroundColor`
  after the view is created.
- Camera: `fitBounds` always ends with a tilt of 0 (the fit is computed for a flat camera); `newCamera` keeps the
  current value of every field it leaves null. An instant `moveCamera` reports Google's own start, move and idle events.
  A movement has one start event, as on MapKit: a gesture that interrupts an animated move continues that movement.
- Options: `updateOptions` sets only the fields that changed, so a padding that follows a panel does not reload the
  style.
- Density: with `density` in the activity's `android:configChanges`, a display density change keeps the view; padding,
  line widths, dashes and the `{r}` choice of tile layers follow the new density.
- Icons: a marker whose icon is missing (never registered, or a PNG that cannot be decoded) is drawn transparent and
  a warning is logged, rather than Google's default red pin.
- Snapshots: `takeSnapshot` returns null when Google does not deliver the bitmap within 5 s (a paused map).
- Taps: Google consumes every tap on a marker. A tap on a marker with `tappable: false` reaches Dart as a map tap at
  the marker's position, not at the finger, so polyline/polygon hit-testing and `onTap` see that point.
- `getCamera`, `getVisibleRegion`, `toScreen` and `toLatLng` throw a `PlatformException` for a view that cannot
  answer, since they have no value to return: `unknown-view`, `disposed`, `destroyed` (the activity destroyed the
  `MapView`) or `not-ready` (before the ready event, and always for a view without a key or Play services).
- Tile layers: a `tileSize` of 512 or 1024 means each source tile `z/x/y` has the usual Web Mercator extent and is
  drawn `tileSize` logical pixels wide, so the plugin fetches the tile one (or two) zoom levels lower and crops it to
  Google's 256 dp grid. Other sizes only set the image resolution. The plugin fetches every tile itself: HTTP 429 and
  5xx responses and network errors are retried later; other errors leave the tile empty. `{s}` is chosen from the tile
  coordinates, so a tile always has the same URL. Above `maxZoom` (the source's last native level) the tiles of that
  level are cropped and scaled up, as MapKit does. Changing only `opacity` or `zIndex` updates the layer in place;
  other changes fetch its tiles again.
- Tile caching: Google keeps tiles in memory only. Tiles go through `HttpURLConnection` with caches enabled, so an app
  that calls `android.net.http.HttpResponseCache.install(...)` gets a disk cache that honours the servers' caching
  headers (asked for by the OpenStreetMap tile policy). For OpenStreetMap, set `userAgentPackageName` on the
  `TileLayer`: without it the request carries Android's default `Dalvik/...` User-Agent.
