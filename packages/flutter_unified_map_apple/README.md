# flutter_unified_map_apple

iOS (15+) and macOS (12+) implementation of [`flutter_unified_map`](https://pub.dev/packages/flutter_unified_map) on
Apple MapKit. No API key required.

This package is endorsed: apps depend on `flutter_unified_map`, which picks this implementation automatically on iOS
and macOS. Do not depend on it directly.

Add `NSLocationWhenInUseUsageDescription` to `Info.plist` when `MapOptions.showsUserLocation` is used.

On macOS the app also needs the `com.apple.security.personal-information.location` entitlement for the user location,
and `com.apple.security.network.client` for tile layers.

Marker transitions are driven at up to 120 Hz. iPhones with ProMotion only run above 60 Hz when the app's
`Info.plist` sets `CADisableMinimumFrameDurationOnPhone` to `true`.

## MapKit specifics

- Zoom is Web Mercator (256-point tiles), measured on the live map; the camera center is the center of the padded
  area, as on Google Maps.
- MapKit keeps the map north up below about zoom 8.
- The map always uses the light appearance, whatever the system appearance.
- Animated camera moves run over `animationMillis` with an ease-in-out curve; `moveCamera` completes when the
  animation ends or is interrupted by a gesture or a newer move. Moves are applied in call order, but the getters
  (`getCamera`, `toScreen`, ...) answer at once, so one sent right after an unawaited move may see the camera before
  that move.
- `fitBounds` resets the tilt to 0, as on Google Maps.
- Changing `padding` keeps the camera target and moves it to the center of the new padded area (camera events follow).
  During an animated move, the move goes on to its target in the new padded area and completes when it ends.
- A tap on a non-tappable marker goes through to the map (`onTap`), as with a non-clickable Google Maps marker. When a
  double tap cannot zoom, taps are reported without waiting for a possible second tap.
- Marker `zIndex` is squeezed monotonically into MapKit's `zPriority` range (0–1000).
- Flat markers rotate with the map but are not foreshortened when the camera is tilted.
- An icon whose bytes cannot be decoded fails `registerIcons` with the `icon-decode-failed` error; the valid icons of
  the same call are registered. Icons no marker uses any more are dropped.
- The `none` map style hides Apple's base map behind an overlay filled with the background color.
- Tile layers: `minZoom` / `maxZoom` are map zooms, also for 512 and 1024 tiles (whose own `z` is one or two levels
  lower). Tiles are cached on disk (200 MB) and in memory (32 MB). Changing only the opacity of a layer keeps its
  tiles; polylines, polygons and circles whose geometry is unchanged are restyled in place.
- `takeSnapshot` composes the base map with the tile layers, polylines, polygons, circles and markers, off the main
  thread. The base map comes from MapKit's snapshotter, or is the background color when the style is `none` or a tile
  layer replaces the base map; then, unless the camera is tilted, Apple's snapshot service is not used at all, so the
  snapshot also works offline. Tiles are fetched again for the snapshot; those that do not arrive within 10 seconds
  are left out. The user location dot is not drawn.
- Disabling double-tap zoom alone is supported on iOS only.
