# flutter_unified_map status

Oct 8 2026 (review-and-fix round, final verification), Flutter 3.47.4, Dart 3.13, Pigeon 29.0.6. Nothing is committed.

## Oct 8 2026 review round: final verification

Every package was reviewed and fixed (core, Android, Apple, flutter_map, the cluster repo), then verified together on
the final code. API changes other packages had to follow:
- `MapEventSource.onDrag` / `onMultiFinger` (flutter_map 8 names); the never-emitted values and fling events are gone.
- `TileLayer` has `maxNativeZoom` (default 19, sent as `PlatformTileLayer.maxZoom`), `maxZoom` (the core hides the
  layer above it) and `tileDimension`. Above `maxNativeZoom` every backend scales the last native level up (Android
  crops it, flutter_map `maxNativeZoom`, MapKit `maximumZ`).
- `MapLayerWidget` is removed (layers are recognised by their `MapLayerState`); the `toPlatform…` converters are
  internal. `MapCamera.rotation` is continuous (it can read 360 after a full turn).
- Object ids: `'<layer>/<index>'` without a key, `'<layer>/k:<string>'`, `'<layer>/k<type>:<num or bool>'`
  (`kint:`, `kdouble:`, `kbool:`), and `'<layer>/k#<n>'` for any other key.
- Android and Apple send creation params through the Pigeon codec as `[viewId, PMapOptions]`; Android resets its
  icon book after any failed marker update, as Apple does.

| Check | Result |
|---|---|
| `flutter analyze` (root; also the cluster repo and GasMobility `lib/shell test_support integration_test test/shell`) | No issues found |
| `dart format --line-length 120 --set-exit-if-changed`, non-generated Dart of both repos except the frozen interface and `tool/pigeon` | 0 changed |
| `flutter test`: core / android / apple / flutter_map / example | 98 / 29 / 32 / 80 / 5 passed |
| `./gradlew :flutter_unified_map_android:testDebugUnitTest` | 60 JUnit tests, 0 failures |
| Example builds: `ios --simulator --debug`, `macos --debug`, `apk --debug`, `web` | all built |

Device sweep: the iPhone 17 simulator, macOS and `emulator-5554` ran in parallel (with the cluster repo and
GasMobility on the iPhone 17 Pro Max simulator), one `flutter test` per file.

| File | iPhone 17 simulator | macOS | emulator-5554 |
|---|---|---|---|
| `app_test.dart` | 5 passed, 1 skipped | 5 passed, 1 skipped | 6 passed |
| `apple_camera_stall_test.dart` | 1 passed | 1 passed | 1 passed |
| `apple_marker_transition_test.dart` | 1 passed | 1 passed | 1 passed |
| `apple_platform_contract_test.dart` | 4 passed | 4 passed | 4 skipped (MapKit only) |
| `apple_transition_load_test.dart` | 1 passed | failed, then 1 passed on a lone re-run | 1 passed |
| `apple_view_resize_test.dart` | 3 passed, 1 skipped | 3 passed 1 failed, then 4 passed on a lone re-run | 3 passed, 1 skipped |

The two macOS failures (and the two of the cluster repo in the same stream) are the off-screen window case below:
each of the four runs logged `visible before activation: false` with "Failed to foreground app", while every macOS
run that passed started visible. With the window off screen, MapKit's `NSView.displayLink` stops, so the
`FrameTicker` transitions freeze (600 merged annotations were still there at opacity 1) and the window resize
animation does not run. Re-run alone, without the iOS runs activating Simulator.app, all four passed with no change.

Previous rounds (Oct 7) are kept below.

Oct 7 2026: the cluster-animation round.

This round, the cluster-animation round, delivered four things:
- marker transitions on every backend;
- marker updates applied in order and atomically;
- clustering moved out of the core into `~/Documents/Code/AlphaByte/flutter_unified_map_marker_cluster`;
- GasMobility's ShellMap migrated to that package.

Every integration suite passes on the iPhone 17 simulator, macOS and the Android emulator (with a Maps key). The details are below.

## Per platform

| Platform | Backend | State |
|---|---|---|
| Android | `flutter_unified_map_android` (Google Maps SDK, Kotlin) | Verified on `emulator-5554` (Small_Phone, Google Play image, API key): every integration suite of this repo, the cluster repo and GasMobility's ShellMap passes. Marker transitions use a `ValueAnimator` with the shared ease-in-out cubic; updates are queued per view. |
| iOS | `flutter_unified_map_apple` (MapKit, Swift) | Verified on the iPhone 17 and iPhone 17 Pro Max simulators: every suite passes. Transitions are frame-driven (`FrameTicker`), so markers keep following the camera during a zoom. |
| macOS | `flutter_unified_map_apple` (shared darwin source) | Verified: every suite passes, run one file at a time (`example/tool/integration_tests.sh macos`). |
| Web | `flutter_unified_map_flutter_map` | `flutter build web` builds, and a headless Chrome screenshot of the cluster example shows flutter_map_marker_cluster's clusters. Gestures and animations were not exercised in a browser. |
| Windows, Linux | `flutter_unified_map_flutter_map` | Same Dart code as web. Not built (needs those hosts). |
| Tests | `flutter_unified_map_flutter_map` | The real backend of the headless tests: the core's `flutter_map_integration_test.dart`, the example's `test/`, and GasMobility's `test/shell/shell_map_test.dart`. |

## Marker transitions (contract implemented everywhere)

`updateMarkers(..., transition:)` behaves the same way on every backend:
- Added markers slide from `appearFrom` while fading in; changed positions glide; removed markers slide to `disappearTo` while fading out, then are removed.
- The easing is ease-in-out, cubic (0.42, 0, 0.58, 1).
- In-flight markers continue from their on-screen state. A removed marker that is added again is revived where it is.
- A tap on a disappearing marker reaches the map. On Android, disappearing markers are also drawn behind the live ones.
- Snapshots leave disappearing markers out and draw the other in-flight markers at their current position and opacity. Android now does this too; before, it drew them opaque.
- `dispose` cancels the transitions.

How each backend does it:

| Backend | Implementation |
|---|---|
| Android | `MarkerTransitions.kt`, covered by JUnit. A snapshot waits for the second rendered frame after hiding the disappearing markers, at most 1 s. The limit was 250 ms, which a loaded machine exceeded. |
| Apple | `AnnotationController.swift` + `FrameTicker`. |
| flutter_map | `MarkerStore`: one timeline per marker, interpolated on the Mercator plane. |

Core (`plugin_api.dart`):
- `MarkerPublisher` publishes a generation of markers only once all of its icons are rasterised.
- The registry merges the transitions of the layers in one push and sends layers without a transition in a first, unanimated call.
- Each `updateMarkers` is awaited before the next one is sent.
- A failed update is sent again.
- `integerZoom` absorbs MapKit's 4.9999999 with a 1e-6 epsilon.
- `setFlutterMapLayers` receives each layer's widgets in a `KeyedSubtree` keyed by layer id and position.

## Verified, and how

All commands were run on the final code, on Oct 7 2026.

| Command | Result |
|---|---|
| `flutter pub get`, `flutter analyze` (root) | No issues found (infos included) |
| `dart format --line-length 120 --output=none --set-exit-if-changed` on all non-generated Dart except the frozen platform interface and `tool/pigeon/messages.dart` | 0 changed (`messages.dart` and 6 interface files would change; both frozen) |
| `flutter test` in `packages/flutter_unified_map` | 72 passed |
| `flutter test` in `packages/flutter_unified_map_android` | 28 passed |
| `example/android: ./gradlew :flutter_unified_map_android:testDebugUnitTest` | 59 JUnit tests, 0 failures (incl. 15 `MarkerTransitionsTest`; Oct 8 review round: `LoadWatchdog`, `IconRefs`, `TileUrlTemplate`, `LineStyle`, `CameraUpdates.merge`) |
| `flutter test` in `packages/flutter_unified_map_apple` | 32 passed (Oct 8, after the Apple review fixes) |
| `flutter test` in `packages/flutter_unified_map_flutter_map` | 60 passed |
| `flutter test` in `example` | 5 passed |

Integration suites, final sweep. All devices ran in parallel and each file had its own `flutter test`.

| Suite (files) | iPhone 17 simulator | macOS | emulator-5554 |
|---|---|---|---|
| `example/integration_test/app_test.dart` | 5 passed, 1 skipped (synthetic taps) | 5 passed, 1 skipped | 6 passed |
| `apple_camera_stall_test.dart` | passed (instant moves idle in 2–16 ms, animated about 650 ms) | passed (instant 4–15 ms; hidden-app step: idle 1 ms after the move while hidden) | passed (instant 36–81 ms) |
| `apple_marker_transition_test.dart` | passed (appear x 160.1 vs 158.1 expected; native opacity 0.35 mid-fade) | passed (opacity 0.32, fading out 0.61, revived 0.82) | passed (x 137.8 vs 137.2) |
| `apple_transition_load_test.dart` | passed (600 markers: split call 32 ms) | passed (600: 10 ms) | passed, logs only (600: split 80 ms, merge 89 ms) |
| `apple_view_resize_test.dart` | 2 passed, 1 skipped (macOS only) | 3 passed | 2 passed, 1 skipped |

The cluster repo's and GasMobility's suites passed in the same sweep. They are listed in their own STATUS and in GasMobility's AGENTS.md.

Apple review fixes, Oct 8 2026 (iPhone 17 simulator and macOS, one file per `flutter test`): every file passed on the simulator, including the new `apple_platform_contract_test.dart` (padding during an animated move, padding keeps the target, non-finite camera values, undecodable icons); on macOS every `apple_*` file passed, and `app_test.dart` passed twice when rerun alone after timing out once at its snapshot step in the full run (its window was 800×600 instead of the usual size, and `app_test` does not keep its window in front, so this looks like the off-screen frame stall described below).

The sweep before that one, under the same parallel load, had 4 failures. Each one led to a fix:

| Failure | Fix |
|---|---|
| Android snapshot showed a disappearing marker | The render-wait limit was raised from 250 ms to 1 s |
| Android `loadTimeout` in `app_test` (15 s) | None. The machine was overloaded: `adb am force-stop` timed out at the same moment |
| Android `apple_camera_stall_test`: a 1.3–2 s frame stall while Google Maps created its view | Stalls before ready are no longer counted |
| The cluster repo's macOS visibility test: the 4–5 minute stall (see below) | Its window is now kept in front |

## Fixed during this integration

- **Android ran the Apple-only probe.**
  - `apple_marker_transition_test` and `apple_transition_load_test` called `AppleNativeProbe` (Objective-C runtime, `pthread_main_np`) on Android and crashed. The native checks now run only where `AppleNativeProbe.isAvailable` (iOS, macOS).
  - The load test's 60 ms / 50 ms budgets were measured on MapKit, so they now apply only there. On the emulator, even an unanimated add of 100 markers took 27–188 ms; Android logs its numbers instead.
- **The resize test asked for a 380-dp-wide view on a 360-dp phone** and waited for a size it could never reach. The sizes now fit a small phone.
- **Android snapshot opacity.** Android drew in-flight markers opaque, while Apple and flutter_map draw them at their current opacity, which the shared transition test expects. Android now matches. JUnit was updated.
- **Unkeyed flutter_map layers.** `LayerRegistry.flutterMapLayers` now wraps each layer's widgets in a `KeyedSubtree`, so a stateful flutter_map layer keeps its state when an earlier layer goes away. Covered in `plugin_api_test.dart`.
- **The macOS 4–5 minute camera "stall".**
  - What it is: Flutter draws no frame while the test window is off screen (app hidden, or window on another Space). Every `pump` then blocks, while MapKit keeps answering. The Apple unit measured this: an instant move while the app is hidden comes back in 1–7 ms.
  - When it happens: the iOS runs going on at the same time activate Simulator.app. In the first final sweep this hit the cluster repo's `marker_visibility_test` on macOS (step 1→2: 167 s; step 5→6: 96 s). Its step 1 also reported zoom 2.82 for a z6 move, a camera read while the window was not on screen.
  - The fix: the core example's apple tests keep their window in front (`AppleNativeProbe.holdTestWindowInFront`). The cluster example and GasMobility now do the same through `holdMacOSTestWindowInFront()`.
  - Result: in the next sweep, under the same load, the test took 68 s, and step 1 read zoom 6.00 and step 2 zoom 8.00.
- Added `example/tool/integration_tests.sh <device>`: one `flutter test` per file, because the Flutter tool cannot relaunch a macOS app for a second file. The example's integration README now lists the `apple_*` files.
- No `UMDBG` debug code is left anywhere.

## Error reporting (from phase 1)

| Backend | Detects |
|---|---|
| Android | Missing or blank API key (checked before any `MapView` exists); Google Play services unavailable; no `onMapLoaded` within 15 s (rejected key, no network, or a heavily loaded emulator) |
| Apple | `mapViewDidFailLoadingMap`; a 20 s safety timeout |
| flutter_map | A failed base tile (`loadFailed`), cleared by the next tile |

The core shows `MapErrorView`, or the app's `errorBuilder`.

## Known limitations

- **Android**
  - The emulator's Google Maps SDK is slow with hundreds of animated markers. At 600 markers, the split call took 80 ms and the merge call 89 ms; the platform thread was busy about 55 % of the time; the longest block was 13–19 ms. A real device was not measured.
  - `showsScale` has no effect.
  - Double-tap zoom cannot be turned off separately from zoom.
  - `backgroundColor` is set only at creation.
  - `fitBounds` resets the tilt to 0.
  - A tap on a non-tappable or disappearing marker reaches Dart at the marker's position, not at the finger.
  - `GoogleMap.snapshot()` ignores the map type and style.
  - The camera getters throw for a disposed view or one that is not ready.
- **Apple**
  - MapKit keeps north up below about zoom 8.
  - Double-tap zoom can be turned off on iOS only.
  - Flat markers do not tilt.
  - Marker `zIndex` is squeezed into MapKit's `zPriority` range.
  - Synthetic Flutter taps do not reach UIKit/AppKit platform views, so the tap tests are skipped there and marker taps are checked in code and by injected native events.
  - Performance with 600 animated markers was measured on the simulator and on macOS only, not on a 120 Hz iPhone.
  - `fitBounds` resets the tilt to 0, as on Android.
  - Camera moves are ordered among themselves, but the getters (`getCamera`, `toScreen`, ...) answer at once: one sent right after an unawaited `moveCamera` can see the camera before that move (the async Pigeon handler runs in a later main-actor task; the frozen schema has synchronous getters).
  - The Swift logic (camera math, easing, transitions, snapshot tile picking) has no XCTest coverage; it is checked by the device suites only.
  - The `apple_*` suites assert their wall-clock budgets (update call durations, idle latencies) only with `--dart-define=STRICT_PERF=true`; otherwise they log them.
- **macOS**
  - Tests must run one file per `flutter test`.
  - A test window that is off screen stalls frames, which is why the tests keep it in front.
  - The initial-zoom mismatch while the window resizes did not reproduce with a window that stays on screen (`apple_view_resize_test`, 3 passed).
- **flutter_map**
  - Not rendered: user location, compass, buildings, traffic, POIs, tilt and geodesic lines.
  - A transition sent while no view state is mounted is applied at once.
  - Snapshot exclusion relies on `RenderRepaintBoundary.toImage` building its scene synchronously.
- **Core**
  - The `curve` of `animateTo` / `animatedFitCamera` is ignored.
  - A push that carries a transition is two `updateMarkers` calls, so a native map may draw one frame between them.
  - `updateMarkers` completes when the update is applied, not when its animation ends.
- **Example:** the OpenStreetMap attribution is shown everywhere. Android needs `maps.apiKey` or `MAPS_API_KEY`.

## Open contract gaps (frozen interface or schema; not changed)

1. `platform_camera.dart` contradicts itself on the bearing sign. Every backend reads it as a compass heading.
2. Instant `moveCamera`: the doc says "a single idle event"; every backend sends start → move → idle.
3. `PlatformPolyline.borderWidth` and `PlatformTileLayer.tileSize` have no documented meaning. The meanings implemented everywhere are recorded in AGENTS.md.
4. There is no `unregisterIcons`.
5. Getters cannot "ignore" calls for a disposed view.
6. `fitBounds` cannot express integer zoom, a minimum zoom or fit-inside, and there is no easing curve.
7. The interface's `Offset` clashes with Flutter's. `PlatformViewSizeEvent` is unused. `PlatformInteraction` has no fling flag.
8. The interface sources and `tool/pigeon/messages.dart` are not `dart format`-clean at line length 120.
9. `platform_marker_transition.dart` does not say what is now implemented everywhere (recorded in AGENTS.md):
   - a tap on a disappearing marker falls through to the map;
   - snapshots draw in-flight markers at their current opacity;
   - a revived marker ignores `appearFrom`;
   - an update without a transition settles the in-flight markers it touches.
10. Plugin API (the core, not frozen; candidates for the next round):
    - Layers cannot know when a published generation reached the platform. The cluster package estimates it from its own clock.
    - The layer hit tester gets no event kind (tap or long press).
    - `plugin_api.dart` does not export the `Platform*` types.
    - `PlatformPolygon` has no stroke pattern.

## Next steps

- Measure the transitions on physical devices: a mid-range Android phone and a 120 Hz iPhone, with 300–600 animated markers.
- Run the web build in a browser (gestures, flutter_map_marker_cluster animations). Build on Windows and Linux.
- Not run yet:
  - Android: the load-timeout and recovery paths (the timer now runs only while the map is resumed and laid out, JUnit only), `servicesUnavailable`, `MapStyle.none` (which may never send `onMapLoaded`), and a display density change in place.
  - The activity lifecycle: a config change and add-to-app.
- When the frozen interface is next opened, fix the docs for gaps 1–3, 8 and 9, and decide on gaps 2, 4 and 6.
- macOS: transitions freeze while the window is off screen (display link); a test whose window starts off screen
  can still fail under parallel iOS runs although the window helper activates it. Consider a timer fallback in
  `FrameTicker` while the view's window is occluded, and having the window helpers wait until the window is visible.
- Android tile over-zoom above `maxZoom` (new crop path) and the flutter_map backend's scale-up have unit tests only;
  no device check zooms past 19.
- Plugin API: expose an "applied generation" signal from `MarkerPublisher`, and tap versus long press in the hit tester (gap 10).
