## 0.1.0

- Initial release.
- Review round (Oct 2026):
  - The load timeout counts only while the map is resumed and has a size, so a pause no longer reports `loadTimeout`.
  - The display density is read on each use; padding, polyline/polygon/circle widths and the tile `{r}` choice follow
    a density change made in place.
  - A missing icon draws a transparent marker instead of Google's red pin; the next update of the marker retries it.
  - A movement sends one `onCameraMoveStarted`, also when a gesture interrupts an animated move (as on MapKit).
  - `updateOptions` sets only what changed; tile layers change `opacity` and `zIndex` in place.
  - Every tile goes through the plugin's provider: `{s}` follows the tile coordinates, crops of 512/1024 tiles are
    cached per source tile and re-encoded as JPEG or lossless WebP. Above `maxZoom` the last native level is cropped
    and scaled up instead of leaving the layer empty.
  - `takeSnapshot` gives up after 5 s; the getters throw `not-ready` for a view without a key or Play services and
    `destroyed` once the activity destroyed the `MapView`.
  - A FlutterFragment's ON_DESTROY only stops the `MapView`; it is destroyed with the view.
  - Memory pressure is forwarded from `onTrimMemory`.
  - Creation params use the Pigeon codec (`[viewId, PMapOptions]`); `events` of a disposed view is an empty stream,
    as on Apple; `UnifiedMapsHostApi` and `UnifiedMapsFlutterApi` are exported.
- Reports `onMapLoaded` and `onMapError` (`apiKeyMissing`, `servicesUnavailable`, `loadTimeout`); no `MapView`
  is created without an API key or Google Play services.
- Marker transitions (`PlatformMarkerTransition`) with `ValueAnimator` and the ease-in-out cubic (0.42, 0, 0.58, 1)
  of the other backends; disappearing markers are drawn behind the live ones and taps on them reach the map.
- Marker updates are queued per view and sent in call order; a failed icon registration is retried with the next
  update; updates for a disposed view are dropped.
- Snapshots leave disappearing markers out and draw the other in-flight markers at their current opacity, as MapKit
  and flutter_map do; they wait for the map to render that state (second rendered frame, at most 1 s).
