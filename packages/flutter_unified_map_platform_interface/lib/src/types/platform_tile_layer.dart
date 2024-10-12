import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart' show Widget;
import 'package:meta/meta.dart';

import 'platform_camera.dart';
import 'platform_icon.dart';
import 'platform_map_object.dart';

/// flutter_map's `RetinaMode` as resolved by the core.
enum PlatformRetinaMode {
  /// `{r}` is replaced by an empty string.
  disabled,

  /// `{r}` is replaced by `@2x`.
  server,

  /// Tiles one level deeper are requested and drawn at half size (flutter_map's simulated retina). The core already
  /// adjusts [PlatformTileLayer.tileSize], [PlatformTileLayer.zoomOffset] and the zoom bounds like flutter_map's
  /// `TileLayer` constructor, so a backend only fills `{r}` with an empty string.
  simulation,
}

/// Raster tiles drawn by the platform above its base map.
///
/// **Where tiles come from.** Unless [dartProvided], the platform fetches them itself from [urlTemplate] with
/// [headers], filling `{z}`, `{x}`, `{y}`, `{s}` (round-robin over [subdomains]), `{r}` (see [retinaMode]), `{d}`
/// ([tileSize]) and every key of [additionalOptions], and applying flutter_map's coordinate rules: `z` is
/// `zoomReverse ? maxZoom - z : z` plus [zoomOffset]; with [tms], `y` becomes `2^z - 1 - y` (`{-y}` is always the
/// flipped value). When a fetch fails and [fallbackUrlTemplate] is set, the same tile is fetched from it. Tiles
/// outside [tileBounds] are not requested (the platform returns no tile). A tile that fails for good is drawn with
/// [errorImage] when set, and reported as [PlatformTileErrorEvent].
///
/// With [dartProvided], the platform asks the core for each tile through the loader given to
/// [UnifiedMapsPlatform.setTileLoader] (custom flutter_map `TileProvider`s, WMS, assets and files): it blocks a worker
/// thread (Google `TileProvider.getTile`) or waits in `MKTileOverlay.loadTile(at:result:)`, and treats null as a
/// failed tile. [urlTemplate] is then empty.
///
/// **Zoom.** [minZoom] / [maxZoom] are map (256-grid) zooms: the core hides the layer outside `TileLayer.minZoom` /
/// `maxZoom` itself; [maxZoom] is the source's last native level (`TileLayer.maxNativeZoom`), above which every
/// backend scales up that level's tiles (MapKit `maximumZ`, Android crops, flutter_map `maxNativeZoom`); below
/// [minNativeZoom] the tiles of that level are scaled down (MapKit `minimumZ`; Android requests the lower-zoom
/// parent tile and crops it). [tileSize] 512 and 1024 follow the Mapbox convention: a tile at `{z}` covers the area of
/// a 256 px tile at `z + 1` (resp. `z + 2`).
///
/// **Look.** [opacity] is the layer's opacity (flutter_map `TileDisplay.instantaneous(opacity)`; Google
/// `TileOverlay.transparency = 1 - opacity`, MapKit renderer `alpha`). [fadeIn] fades new tiles in (flutter_map
/// `TileDisplay.fadeIn()`; Google `TileOverlayOptions.fadeIn`, MapKit: no fade). [replacesBaseMap] hides the native
/// base map under the tiles where the platform allows it (Google `MAP_TYPE_NONE`, MapKit `canReplaceMapContent`).
///
/// [flutterMapLayer] is set by the core only for a backend that draws with flutter_map: the app's layer as a
/// flutter_map `TileLayer` widget built with every flutter_map parameter (tile provider, tile builder, WMS, update
/// transformer, error callback...). Such a backend draws it in place of the other fields.
@immutable
class PlatformTileLayer extends PlatformMapObject {
  @override
  final String id;
  final String urlTemplate;
  final List<String> subdomains;
  final double minZoom;
  final double maxZoom;
  final int minNativeZoom;
  final int tileSize;
  final Map<String, String> headers;
  final bool replacesBaseMap;
  final double opacity;
  final double zIndex;
  final String? fallbackUrlTemplate;
  final bool tms;
  final bool zoomReverse;
  final double zoomOffset;
  final Map<String, String> additionalOptions;
  final PlatformRetinaMode retinaMode;
  final PlatformLatLngBounds? tileBounds;
  final bool dartProvided;
  final PlatformIcon? errorImage;
  final bool fadeIn;
  final Widget? flutterMapLayer;

  const PlatformTileLayer({
    required this.id,
    required this.urlTemplate,
    this.subdomains = const [],
    this.minZoom = 0,
    this.maxZoom = 19,
    this.minNativeZoom = 0,
    this.tileSize = 256,
    this.headers = const {},
    this.replacesBaseMap = false,
    this.opacity = 1,
    this.zIndex = 0,
    this.fallbackUrlTemplate,
    this.tms = false,
    this.zoomReverse = false,
    this.zoomOffset = 0,
    this.additionalOptions = const {},
    this.retinaMode = PlatformRetinaMode.disabled,
    this.tileBounds,
    this.dartProvided = false,
    this.errorImage,
    this.fadeIn = true,
    this.flutterMapLayer,
  });

  @override
  bool operator ==(Object other) =>
      other is PlatformTileLayer &&
      other.id == id &&
      other.urlTemplate == urlTemplate &&
      other.subdomains.join(',') == subdomains.join(',') &&
      other.minZoom == minZoom &&
      other.maxZoom == maxZoom &&
      other.minNativeZoom == minNativeZoom &&
      other.tileSize == tileSize &&
      mapEquals(other.headers, headers) &&
      other.replacesBaseMap == replacesBaseMap &&
      other.opacity == opacity &&
      other.zIndex == zIndex &&
      other.fallbackUrlTemplate == fallbackUrlTemplate &&
      other.tms == tms &&
      other.zoomReverse == zoomReverse &&
      other.zoomOffset == zoomOffset &&
      mapEquals(other.additionalOptions, additionalOptions) &&
      other.retinaMode == retinaMode &&
      other.tileBounds == tileBounds &&
      other.dartProvided == dartProvided &&
      other.errorImage == errorImage &&
      other.fadeIn == fadeIn &&
      other.flutterMapLayer == flutterMapLayer;

  @override
  int get hashCode => Object.hash(
    id,
    urlTemplate,
    subdomains.join(','),
    minZoom,
    maxZoom,
    minNativeZoom,
    tileSize,
    replacesBaseMap,
    opacity,
    zIndex,
    fallbackUrlTemplate,
    tms,
    zoomReverse,
    zoomOffset,
    retinaMode,
    tileBounds,
    dartProvided,
    errorImage,
    fadeIn,
    flutterMapLayer,
  );

  @override
  String toString() => 'PlatformTileLayer($id, $urlTemplate)';
}
