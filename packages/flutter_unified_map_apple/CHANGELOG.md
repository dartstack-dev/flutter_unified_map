## 0.1.0

- Initial release: `flutter_unified_map` on Apple MapKit for iOS 15+ and macOS 12+.
- Markers from rasterised icons, with anchor, rotation, flat markers, zIndex and native taps.
- Marker transitions (`PlatformMarkerTransition`): appear from / disappear to a position with a fade, glide on
  position changes, ease-in-out, driven frame by frame so they follow the camera.
- Polylines (borders, dash patterns, geodesic), polygons with holes, circles and URL tile layers in one zIndex order.
- Camera: Web Mercator zoom, padding with Google Maps semantics, animated moves, `fitBounds` with bearing, projections.
- Load and error events, snapshots composed with every layer.
