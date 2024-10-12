import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

/// flutter_map's own default, which makes it warn in debug builds that the app did not identify itself.
const defaultUserAgentPackageName = 'unknown';

const _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _esriImageryUrl = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

const _desaturate = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// Creates the [TileProvider] of a tile layer: [layer] is null for the built-in base map. Each call must return a
/// new provider, since the `TileLayer` disposes it.
typedef TileProviderFactory = TileProvider Function(PlatformTileLayer? layer);

/// flutter_map's `NetworkTileProvider`, sending the headers of [layer].
TileProvider defaultTileProvider(PlatformTileLayer? layer) =>
    NetworkTileProvider(headers: layer == null ? null : Map.of(layer.headers));

/// Where a tile layer reports each tile's outcome; [host] names the tile server of a failed tile.
abstract interface class TileLoadListener {
  void tileLoaded(PlatformTileLayer? layer);

  void tileFailed(PlatformTileLayer? layer, String host, Object error);
}

/// Builds the base map and tile overlay layers with their providers, wired to report tile outcomes. Every call
/// returns a new `TileLayer` with a new provider: a layer disposes its provider when it leaves the tree, so a built
/// layer must not be mounted again after that.
class TileLayerFactory {
  const TileLayerFactory({
    required this.listener,
    this.tileProvider = defaultTileProvider,
    this.userAgentPackageName = defaultUserAgentPackageName,
  });

  final TileLoadListener listener;
  final TileProviderFactory tileProvider;
  final String userAgentPackageName;

  Widget? baseMapLayer(PlatformMapStyle style) => switch (style) {
    PlatformMapStyle.standard => _osm(),
    PlatformMapStyle.muted => ColorFiltered(colorFilter: _desaturate, child: _osm()),
    PlatformMapStyle.satellite ||
    PlatformMapStyle.hybrid => _tileLayer(null, urlTemplate: _esriImageryUrl, maxNativeZoom: 19),
    PlatformMapStyle.none => null,
  };

  Widget _osm() => _tileLayer(null, urlTemplate: _osmUrl, maxNativeZoom: 19);

  /// The tiles of [layer], without its opacity, which does not need new tiles. [highDensity] fills `{r}` with
  /// `@2x`, as the Android and Apple backends do on screens of density 2 or more.
  TileLayer platformTileLayer(PlatformTileLayer layer, {required bool highDensity}) => _tileLayer(
    layer,
    urlTemplate: layer.urlTemplate,
    subdomains: layer.subdomains,
    minZoom: layer.minZoom,
    maxNativeZoom: layer.maxZoom.floor(),
    tileDimension: layer.tileSize,
    zoomOffset: -_levelsAbove256(layer.tileSize).toDouble(),
    retinaMode: highDensity && layer.urlTemplate.contains('{r}'),
  );

  TileLayer _tileLayer(
    PlatformTileLayer? layer, {
    required String urlTemplate,
    List<String> subdomains = const [],
    double minZoom = 0,
    double maxZoom = double.infinity,
    required int maxNativeZoom,
    int tileDimension = 256,
    double zoomOffset = 0,
    bool retinaMode = false,
  }) {
    late final TileLayer tiles;
    return tiles = TileLayer(
      urlTemplate: urlTemplate,
      subdomains: subdomains,
      minZoom: minZoom,
      maxZoom: maxZoom,
      maxNativeZoom: maxNativeZoom,
      tileDimension: tileDimension,
      zoomOffset: zoomOffset,
      retinaMode: retinaMode,
      tileProvider: tileProvider(layer),
      userAgentPackageName: userAgentPackageName,
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
      tileBuilder: (context, tileWidget, tile) =>
          _TileLoadReporter(tile: tile, onLoaded: () => listener.tileLoaded(layer), child: tileWidget),
      errorTileCallback: (tile, error, _) => listener.tileFailed(layer, _host(tiles, tile), error),
    );
  }

  static String _host(TileLayer tiles, TileImage tile) {
    final url = tiles.tileProvider.getTileUrl(tile.coordinates, tiles);
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? url : host;
  }
}

bool showsBaseMap(PlatformMapStyle style, List<PlatformTileLayer> tileLayers) =>
    style != PlatformMapStyle.none && !tileLayers.any((t) => t.replacesBaseMap);

/// A 512 or 1024 tile covers the extent of a 256 tile one or two levels lower (Mapbox convention), which is how
/// MapKit and the Android backend read `tileSize`.
int _levelsAbove256(int tileSize) {
  if (tileSize <= 256 || tileSize % 256 != 0) return 0;
  final ratio = tileSize ~/ 256;
  return ratio & (ratio - 1) == 0 ? ratio.bitLength - 1 : 0;
}

/// Reports a tile once it has an image, whether it loaded before this widget was built (image cache) or after.
class _TileLoadReporter extends StatefulWidget {
  const _TileLoadReporter({required this.tile, required this.onLoaded, required this.child});

  final TileImage tile;
  final VoidCallback onLoaded;
  final Widget child;

  @override
  State<_TileLoadReporter> createState() => _TileLoadReporterState();
}

class _TileLoadReporterState extends State<_TileLoadReporter> {
  TileImage? _listening;

  @override
  void initState() {
    super.initState();
    _watch(widget.tile);
  }

  @override
  void didUpdateWidget(_TileLoadReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tile, widget.tile)) _watch(widget.tile);
  }

  @override
  void dispose() {
    _listening?.removeListener(_check);
    super.dispose();
  }

  void _watch(TileImage tile) {
    _listening?.removeListener(_check);
    _listening = null;
    if (_report(tile)) return;
    _listening = tile..addListener(_check);
  }

  void _check() {
    final tile = _listening;
    if (tile != null && _report(tile)) {
      tile.removeListener(_check);
      _listening = null;
    }
  }

  bool _report(TileImage tile) {
    if (tile.loadFinishedAt == null || tile.loadError) return false;
    widget.onLoaded();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
