## 0.1.0

- Initial release.
- Aligned with flutter_map 8 before publishing: `MapEventSource.onDrag` / `onMultiFinger` (were `drag` /
  `multiFinger`; `doubleTap`, `flingAnimation`, `custom` and the fling events, never emitted, are gone); moves made
  with `MapController.move(id:)` carry `MapEventSource.mapController` and the id; `MapCamera.rotation` stays
  continuous instead of wrapping to [0, 360); `TileLayer.maxNativeZoom` (default 19, tiles scaled up above it),
  `maxZoom` (hides the layer above it, default infinity) and `tileDimension` (was `tileSize`); `StrokePattern`
  exposes `segments`, `spacingFactor` and `patternFit` as flutter_map; the polyline hit tolerance is
  `max(strokeWidth / 2 + borderStrokeWidth / 2, minimumHitbox)`; `CameraFit.maxZoom` no longer overrides
  `MapOptions.maxZoom`.
- Layers stack in the order of `UnifiedMap.children`, not in mount order.
- A `Marker` without `onTap` lets taps through to the map (`MarkerSpec.tappable`).
- Marker icons follow theme, text-scale and brightness changes; an icon is captured once unless it is still loading.
- Object ids no longer collide for distinct keys (`ValueKey(1)` vs `ValueKey('1')`, objects without `toString`).
- Failed shape and tile updates are reported and re-sent like marker updates; failures of camera moves, option
  updates and snapshots are reported instead of escaping as uncaught errors.
- Removed: `MapLayerWidget` (layers are recognised by their `MapLayerState`), the exported `toPlatform…`
  converters, `IconCache.peek` (now `lookup`). `RichAttributionWidget.showFlutterMapAttribution` is now
  `showUnifiedMapAttribution`.
