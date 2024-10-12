# flutter_unified_map_flutter_map

Pure Dart implementation of [`flutter_unified_map`](https://pub.dev/packages/flutter_unified_map) on [flutter_map](https://pub.dev/packages/flutter_map). Used automatically on web, Windows and Linux, and in widget tests.

Default base map: OpenStreetMap raster tiles (`standard`, and `muted` desaturated), Esri World Imagery (`satellite`, `hybrid`), nothing for `none`. Show the attribution with `RichAttributionWidget` or `SimpleAttributionWidget`.

## Configuration

The package registers a default instance. To configure it, depend on `flutter_unified_map_flutter_map` and `flutter_unified_map_platform_interface`, and install your own instance before `runApp` on the platforms that use it:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_unified_map_flutter_map/flutter_unified_map_flutter_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

void main() {
  if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux) {
    UnifiedMapsPlatform.instance = UnifiedMapsFlutterMap(userAgentPackageName: 'com.example.app');
  }
  runApp(const MyApp());
}
```

- `userAgentPackageName`: on Windows and Linux every tile request is sent with `User-Agent: flutter_map (<userAgentPackageName>)` (browsers send their own). The [OpenStreetMap tile usage policy](https://operations.osmfoundation.org/policies/tiles/) asks every app to identify itself: set it to your app's package name. With the default, `unknown`, flutter_map warns in debug builds.
- `tileProvider` creates the flutter_map `TileProvider` of every tile layer, the base map included (`layer` is `null` for it), for caching or offline tiles. Return a new provider on each call, since a `TileLayer` disposes its provider. Pass `layer.headers` on to it, as `defaultTileProvider` does, or the tile layers' headers (an `Authorization` header, for example) are not sent.

## Behaviour

- `bearing` is a compass heading, as on Google Maps and MapKit: it is the opposite of flutter_map's `rotation` (bearing 90 puts north on the left).
- Animated camera moves pan and turn the shorter way, across the antimeridian when that is shorter. `getVisibleRegion` returns bounds that cross the antimeridian as `northEast.longitude < southWest.longitude`, and the whole world (-180 to 180) when the view is wider than it.
- Padding applies from the first frame. A padding change keeps the camera target, the target of a running animation too. Narrowing `minZoom` / `maxZoom` moves the camera into the new range, with start, move and idle events.
- Any user input stops a running camera animation, the scroll wheel and arrow keys included. Arrow-key panning follows `scrollEnabled` and ctrl-drag rotation follows `rotateEnabled`. The map never takes the keyboard focus on its own: it gets it through focus traversal (Tab).
- A `tileSize` of 512 or 1024 follows the Mapbox convention (`zoomOffset` of -1 or -2), as on Android and MapKit. `{r}` becomes `@2x` on screens with a pixel ratio of 2 or more, as on Android and MapKit. A tile overlay is hidden below its `minZoom` and scaled up above its `maxZoom` (the core hides it above `TileLayer.maxZoom`), as on MapKit. Changing a tile overlay's `opacity` or `zIndex` keeps its loaded tiles.
- A polyline border adds `borderWidth` to the line's total width (`borderWidth / 2` on each side), as flutter_map's `borderStrokeWidth`; the Android and Apple packages draw it the same way. Dash lengths are logical pixels, not stretched to fit the line, and a pattern with an odd number of lengths repeats whole (`[10]` is 10 on, 10 off), as on Android and Apple. Polylines and polygons without points are skipped.
- Tile overlays, polygons, polylines and circles are stacked together by `zIndex`; markers are always above them.
- Marker transitions (`updateMarkers(..., transition:)`) use `Curves.easeInOut` and move markers in a straight line on the Web Mercator plane (as flutter_map_marker_cluster's screen-space tweens), along the shorter way across the antimeridian. Each marker keeps its own timeline: a transition restarts only the markers it adds, removes or moves, from where they are on screen; markers already in flight that it does not touch finish on their own schedule. An update without a transition puts the markers it touches at their target at once, in flight or not. The time is driven by a ticker of the mounted view, so a re-parented view continues its transitions, and an unmounted view (or one sent a transition before it mounts) applies them at once. Snapshots leave disappearing markers out without any change on screen.
- When the view is about as wide as the world, flutter_map draws a marker once per visible world copy.
- `supportsFlutterMapLayers` is true: the widgets given to `setFlutterMapLayers` are drawn inside the `FlutterMap`, above shapes and markers, in list order, so they see `MapCamera.of` and `MapController.of` (`flutter_unified_map_marker_cluster` draws flutter_map_marker_cluster's layer this way). They are children of one `Stack`, matched to the previous list by key: the core wraps each layer's widgets in a `KeyedSubtree` keyed by layer id and position, so a stateful layer (such as `MarkerClusterLayerWidget`) keeps its state when another layer is added or removed. A list set while another widget builds is drawn at the latest on the next frame.
- Load events: `PlatformMapLoadedEvent` follows the first base map tile, where the base map is the style's own layer or, when that is hidden (`none`, or a `replacesBaseMap` layer), the tile layers; with `none` and no tile layer it follows the ready event. When base tiles fail and no tile of the current base map loaded in the last 10 s, one `PlatformMapErrorEvent` (`loadFailed`, naming the tile host and the exception, any URL reduced to its host) is sent until a tile loads again, which sends a new loaded event. A failed tile is requested again once it has left the view and comes back.
- Camera queries (`getCamera`, `getVisibleRegion`, `toScreen`, `toLatLng`) on a disposed view answer from its last camera (`getCamera` from its initial camera if the view never became ready). Before the view is ready, `getCamera` returns the initial camera and the others throw a `StateError`. A view removed from the tree mid-movement ends the movement with an idle event.
- `takeSnapshot` captures the last painted frame: after an update, wait for a frame before taking it.

## Not rendered

`showsUserLocation`, `showsCompass`, `showsBuildings`, `showsTraffic`, `showsPointsOfInterest`, camera tilt and `PlatformPolyline.geodesic`. `hybrid` shows imagery without labels. The `gestureRecognizers` argument of `buildView` is ignored: the map is a regular widget, not a platform view. The camera is not constrained: the map can be dragged past the poles.
