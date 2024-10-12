## 0.1.0

- Initial release: the `flutter_unified_map` implementation for web, Windows, Linux and widget tests, drawn with flutter_map 8.
- Markers from rasterised icons, with fractional anchors, rotation, `flat`, `tappable`, zIndex order and animated transitions (`updateMarkers(..., transition:)`).
- Polylines (borders, dash patterns, caps, joins), polygons with holes, circles in metres and raster tile overlays (`{s}`, `{r}`, 512/1024 tiles, headers, `replacesBaseMap`, scaled up above `maxZoom`), stacked by zIndex.
- Base map styles: OpenStreetMap (`standard`, `muted`), Esri World Imagery (`satellite`, `hybrid`) and `none`, with loaded and `loadFailed` events.
- Camera: compass bearing, content padding, `newCamera`, `fitBounds` (across the antimeridian too), `scrollBy`, `zoomBy` and animated moves, with start, move and idle events for gestures and programmatic moves.
- `setFlutterMapLayers`: flutter_map layer widgets drawn inside the map.
- `UnifiedMapsFlutterMap(tileProvider:, userAgentPackageName:)` replaces the tile providers and identifies the app to tile servers.
