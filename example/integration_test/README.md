# End-to-end tests

`app_test.dart` mounts the Geometry scene (`lib/src/geometry_page.dart`, constants in `lib/src/geometry_data.dart`)
on the real native map and checks what reaches the native side and what it draws. A `RecordingPlatform`
(`support/recording_platform.dart`) wraps the platform registered by the plugin: every call is passed through and
recorded, and every native event is recorded on its way to the core.

| Test | Checks |
|---|---|
| (a) ready / loaded | `onMapReady`, then `onMapLoaded`. On Android without an API key: `MapErrorView` with the title is shown and the other tests are skipped (`SKIPPED: no Google Maps API key`). Any other error fails. |
| (b) custom pins | All 10 markers reach the platform; anchor `(0.5, 1.0)` for `Alignment.topCenter` pins, `(0.5, 0.5)` otherwise; `flat == !rotate`; the three `iconKey: 'fuel'` pins share one `PlatformIcon.key`; icon logical sizes and PNG sizes (× pixel ratio). |
| (c) itinerary | Route sent once with its 19 points, width 6, border 3 white; dashed `[12, 8]`; dotted `[width, …]`; polygon with one hole; 2 km circle = 2000 m; 6 px waypoint circles = 6 × metersPerPixel at the current zoom. |
| (d) camera | `animatedFitCamera(CameraFit.bounds(...))` completes, `mapEventStream` sends MoveStart → Move → MoveEnd, every route point projects inside the padded viewport (24, 24, 24, 200); `rotate(45)` gives `camera.rotation ≈ 45` (bearing 315 sent). |
| (e) snapshot | `takeSnapshot()` is not null, has the view size × pixel ratio, and shows route green `0xFF00C853`, pin magenta `0xFFFF00FF` and the polygon's yellow hue. |
| (f) taps | `nativeTap` (a pointer down/up through `createGesture`, with engine timestamps so the native map accepts it as a tap) on the teardrop pin fires its `Marker.onTap`; a tap inside the polygon reaches `MapOptions.onTap` with the polygon in `hitNotifier`. Skipped on iOS and macOS: UIKit/AppKit platform views only take native touches, so synthetic Flutter pointer events never reach MKMapView. |

The same checks (b) to (f) run without a device against the pure Dart flutter_map backend in
`test/geometry_scene_test.dart` (`cd example && flutter test`).

The `apple_*` files were written for MapKit; except where noted they also run on Android.

| File | Checks |
|---|---|
| `apple_marker_transition_test.dart` | `PlatformMarkerTransition` driven through a plain `MarkerLayer`: a marker appearing from another one is mid-way and mid-fade at about half the duration (screen position on iOS and Android, annotation opacity read natively on iOS and macOS through `apple_native_probe.dart`), a disappearing marker is left out of the snapshot then removed, a removed then re-added marker is revived, and after a burst of updates only the expected markers remain. |
| `apple_transition_load_test.dart` | 100, 300 and 600 markers split from one point and merged back: each `updateMarkers` call stays under 60 ms and the platform thread is never blocked for 50 ms or more at once. |
| `apple_camera_stall_test.dart` | Instant and animated camera moves while the markers are replaced at every step: every move is reported promptly (idle within seconds). On macOS the test keeps its window in front and fails on a frame stall while the window is visible; a second macOS test hides the app and checks that an instant move still comes back while no frame is drawn. |
| `apple_platform_contract_test.dart` | MapKit only (skipped elsewhere), through the platform API: a padding change during an animated move keeps animating to the target, padding keeps the camera target and moves land in the centre of the padded area (MapKit on iOS centres inside `layoutMargins`), a camera update with a non-finite value completes and leaves the camera, an undecodable icon fails the update and is sent again by the next one. |
| `apple_view_resize_test.dart` | Resizing the map view keeps the center and the zoom (MapKit keeps the span); a view that grows while the map starts opens at the initial camera; on macOS, the real window is resized through its animator during startup and after ready. |

`apple_native_probe.dart` and `apple_test_support.dart` are helpers, not tests. The probe reads MKMapView
annotations through the Objective-C runtime and keeps the macOS test window in front (Flutter draws no frame while the
window is off screen). The support file holds what the `apple_*` suites share; their wall-clock budgets (update call
durations, idle latencies, the 60 ms / 50 ms load budgets) are asserted only with `--dart-define=STRICT_PERF=true` and
logged otherwise.

## Running

From `example/`, after `flutter pub get` at the repository root. List devices with `flutter devices`.

```sh
# iOS simulator (boot one first, e.g. `open -a Simulator`)
flutter test integration_test -d "iPhone 17 Pro Max"

# macOS: one `flutter test` per file (see below)
tool/integration_tests.sh macos

# Android emulator (start one first, e.g. `flutter emulators --launch <id>`)
flutter test integration_test -d emulator-5554
```

On macOS a single `flutter test integration_test -d macos` runs the first file only: the Flutter tool cannot launch
the desktop app again for the second file ("Unable to start the app on the device"). `tool/integration_tests.sh
<device> [files...]` runs each file in its own `flutter test` and sums up; it works on every device.

Add `--reporter expanded` to see every progress line (`[geometry] ...`). Each test mounts a fresh map and waits up
to 30 s for ready and 30 s for loaded, so a full run takes a few minutes. The iOS simulator and the Android emulator
need network access for the base map; without it the run fails with a load error.

## Google Maps API key (Android)

Without a key, (a) passes by checking the error view and (b) to (f) are skipped. To run them, create a key with
**Maps SDK for Android** enabled and either add it to `example/android/local.properties` (not committed):

```properties
maps.apiKey=YOUR_KEY
```

or export it in the shell that runs the tests:

```sh
MAPS_API_KEY=YOUR_KEY flutter test integration_test -d emulator-5554
```

The key is baked into the manifest at build time; after changing it, run `flutter clean` if the old value is still
used. A key that Google rejects shows up as a `loadTimeout` error and fails the run with that error.
