import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_map/flutter_map.dart'
    show
        ErrorTileCallBack,
        EvictErrorTileStrategy,
        FadeInTileDisplay,
        InstantaneousTileDisplay,
        LatLngBounds,
        NetworkTileProvider,
        RetinaMode,
        TileBuilder,
        TileDisplay,
        TileProvider,
        TileUpdateTransformer,
        WMSTileLayerOptions;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

import '../../map/map_layer_host.dart';
import '../../native/native_params.dart';
import '../shared/map_layer_state.dart';

/// flutter_map's `TileLayer`, plus [nativeParams]. On native maps the tiles are drawn by the platform above its own
/// base map ([NativeTileLayerParams.replacesBaseMap] hides it); on the flutter_map backend this is flutter_map's own
/// layer, built with every parameter.
///
/// Native maps, per parameter:
/// - [urlTemplate], [subdomains], [fallbackUrl], [tms], [zoomReverse], [zoomOffset], [additionalOptions],
///   [tileBounds], [minNativeZoom], [maxNativeZoom], [tileDimension], [retinaMode]: honoured natively as flutter_map
///   (the URL is built and fetched by the platform).
/// - [tileProvider]: a [NetworkTileProvider] (the default) is fetched natively with its `headers` (its caching
///   options are left to the platform's HTTP cache). Any other provider, and [wmsOptions], go through a Dart tile
///   bridge: the platform asks the core for each tile, which loads it with `TileProvider.getImage` and encodes it as
///   PNG. Slower than native fetching. A custom provider whose `getImage` takes flutter_map's own `TileLayer` type
///   needs `import 'package:flutter_map/flutter_map.dart' as fm` for that parameter type.
/// - [tileDisplay]: `TileDisplay.instantaneous(opacity: o)` sets the layer's opacity; `TileDisplay.fadeIn()` fades
///   new tiles in on Google (its duration is ignored) and shows them at once on MapKit.
/// - [errorImage]: drawn natively for failed tiles. [errorTileCallback] is called with a `TileImage` describing the
///   failed tile's coordinates (its image state is not meaningful natively).
/// - [reset]: drops the platform's tile cache and reloads the visible tiles.
/// - [keepBuffer], [panBuffer], [tileBuilder], [evictErrorTileStrategy], [tileUpdateTransformer]: flutter_map's
///   tile engine only (the platform caches, prefetches and retries itself; native tiles are images, not widgets).
/// - [userAgentPackageName]: the `User-Agent` header is `flutter_unified_map (<package>)` unless the provider's
///   headers set one; on the web the browser's is used.
/// - [minZoom] / [maxZoom]: the layer is hidden outside them; above [maxNativeZoom] the last native level is scaled
///   up, below [minNativeZoom] the first one is scaled down.
class TileLayer extends StatefulWidget {
  final String? urlTemplate;
  final String? fallbackUrl;
  final bool tms;
  final WMSTileLayerOptions? wmsOptions;

  @Deprecated('`tileSize` is deprecated. Use `tileDimension` instead.')
  final double? tileSize;
  final int tileDimension;
  final double minZoom;
  final double maxZoom;
  final int minNativeZoom;
  final int maxNativeZoom;
  final bool zoomReverse;
  final double zoomOffset;
  final List<String> subdomains;
  final TileDisplay tileDisplay;
  final TileProvider? _tileProvider;
  final int keepBuffer;
  final int panBuffer;
  final ImageProvider? errorImage;
  final Map<String, String> additionalOptions;
  final bool? _retinaMode;
  final ErrorTileCallBack? errorTileCallback;
  final TileBuilder? tileBuilder;
  final EvictErrorTileStrategy evictErrorTileStrategy;
  final Stream<void>? reset;
  final LatLngBounds? tileBounds;
  final TileUpdateTransformer? _tileUpdateTransformer;
  final String userAgentPackageName;

  /// Hides the native base map under the tiles (Google `MAP_TYPE_NONE` while the layer is shown, MapKit
  /// `canReplaceMapContent`). Default false. Refined by `nativeParams.replacesBaseMap`.
  final bool replacesBaseMap;

  /// Native-only settings; ignored by the flutter_map backend. Not in flutter_map.
  final NativeTileLayerParams? nativeParams;

  const TileLayer({
    super.key,
    this.urlTemplate,
    this.fallbackUrl,
    @Deprecated('`tileSize` is deprecated. Use `tileDimension` instead.') this.tileSize,
    this.tileDimension = 256,
    this.minZoom = 0,
    this.maxZoom = double.infinity,
    this.minNativeZoom = 0,
    this.maxNativeZoom = 19,
    this.zoomReverse = false,
    this.zoomOffset = 0.0,
    this.additionalOptions = const {},
    this.subdomains = const ['a', 'b', 'c'],
    this.keepBuffer = 2,
    this.panBuffer = 1,
    this.errorImage,
    this._tileProvider,
    this.tms = false,
    this.wmsOptions,
    this.tileDisplay = const TileDisplay.fadeIn(),
    this._retinaMode,
    this.errorTileCallback,
    this.tileBuilder,
    this.evictErrorTileStrategy = EvictErrorTileStrategy.none,
    this.reset,
    this.tileBounds,
    this._tileUpdateTransformer,
    this.userAgentPackageName = 'unknown',
    this.replacesBaseMap = false,
    this.nativeParams,
  }) : assert(urlTemplate == null || wmsOptions == null, 'Cannot specify both `urlTemplate` and `wmsOptions`');

  static final _defaultProviders = Expando<TileProvider>();

  /// The tile provider: the given one, or a [NetworkTileProvider] (one per layer widget).
  TileProvider get tileProvider => _tileProvider ?? (_defaultProviders[this] ??= NetworkTileProvider());

  TileUpdateTransformer get tileUpdateTransformer =>
      _tileUpdateTransformer ?? fm.TileUpdateTransformers.ignoreTapEvents;

  /// flutter_map's resolution of the `retinaMode` argument: [RetinaMode.server] when the URL has `{r}`,
  /// [RetinaMode.simulation] otherwise, [RetinaMode.disabled] when not asked.
  RetinaMode get resolvedRetinaMode => (_retinaMode ?? false)
      ? wmsOptions == null && (urlTemplate?.contains('{r}') ?? false)
            ? RetinaMode.server
            : RetinaMode.simulation
      : RetinaMode.disabled;

  /// Request headers of a [NetworkTileProvider], with a `User-Agent` naming [userAgentPackageName] unless they set
  /// one.
  Map<String, String> get effectiveHeaders {
    final headers = tileProvider.headers;
    if (kIsWeb || headers.keys.any((k) => k.toLowerCase() == 'user-agent')) return headers;
    return {...headers, 'User-Agent': 'flutter_unified_map ($userAgentPackageName)'};
  }

  @override
  State<TileLayer> createState() => _TileLayerState();
}

class _TileLayerState extends MapLayerState<TileLayer> {
  bool? _shown;
  fm.TileLayer? _flutterMapLayer;
  TileLayer? _flutterMapSource;

  @override
  void attachHost(MapLayerHost host) => host.liveCamera.addListener(_onCamera);

  @override
  void detachHost(MapLayerHost host) => host.liveCamera.removeListener(_onCamera);

  bool get _visible => host.camera.zoom <= widget.maxZoom && host.camera.zoom >= widget.minZoom;

  void _onCamera() {
    if (_visible != _shown) sync();
  }

  @override
  void sync() {
    final shown = _shown = _visible;
    final flutterMap = host.supportsFlutterMapLayers;
    final hidden = !flutterMap && (widget.nativeParams?.hidden ?? false);
    host.registry.setTileLayers(layerId, [
      if (shown && !hidden)
        toPlatformTileLayer(
          widget,
          objectId(null, 0),
          host.registry.zIndexOf(layerId),
          flutterMapLayer: flutterMap ? _flutterMapLayerOf(widget) : null,
        ),
    ]);
  }

  fm.TileLayer _flutterMapLayerOf(TileLayer layer) {
    if (identical(layer, _flutterMapSource)) return _flutterMapLayer!;
    _flutterMapSource = layer;
    return _flutterMapLayer = toFlutterMapTileLayer(layer);
  }
}

/// [layer] as the platform sees it. Contract stub for the core unit: the Dart tile bridge ([PlatformTileLayer.dartProvided]
/// layers need `UnifiedMapsPlatform.setTileLoader`) and [PlatformTileLayer.errorImage] are not wired yet.
PlatformTileLayer toPlatformTileLayer(TileLayer layer, String id, double zIndex, {Widget? flutterMapLayer}) {
  final retina = layer.resolvedRetinaMode;
  final simulated = retina == RetinaMode.simulation;
  final reverse = layer.zoomReverse;
  final native = layer.tileProvider is NetworkTileProvider && layer.wmsOptions == null && layer.urlTemplate != null;
  final display = layer.tileDisplay;
  final bounds = layer.tileBounds;
  // ignore: deprecated_member_use_from_same_package
  final tileSize = layer.tileSize?.toInt() ?? layer.tileDimension;
  return PlatformTileLayer(
    id: id,
    urlTemplate: native ? layer.urlTemplate! : '',
    subdomains: layer.subdomains,
    minZoom: simulated && reverse ? (layer.minZoom + 1).clamp(0, double.infinity) : layer.minZoom,
    maxZoom: (simulated && !reverse ? layer.maxNativeZoom - 1 : layer.maxNativeZoom).toDouble(),
    minNativeZoom: simulated && reverse ? layer.minNativeZoom + 1 : layer.minNativeZoom,
    tileSize: simulated ? tileSize ~/ 2 : tileSize,
    headers: native ? layer.effectiveHeaders : const {},
    replacesBaseMap: layer.replacesBaseMap || (layer.nativeParams?.replacesBaseMap ?? false),
    opacity: display is InstantaneousTileDisplay ? display.opacity : 1,
    zIndex: zIndex,
    fallbackUrlTemplate: layer.fallbackUrl,
    tms: layer.tms,
    zoomReverse: reverse,
    zoomOffset: simulated ? (reverse ? layer.zoomOffset - 1 : layer.zoomOffset + 1) : layer.zoomOffset,
    additionalOptions: layer.additionalOptions,
    retinaMode: switch (retina) {
      RetinaMode.disabled => PlatformRetinaMode.disabled,
      RetinaMode.server => PlatformRetinaMode.server,
      RetinaMode.simulation => PlatformRetinaMode.simulation,
    },
    tileBounds: bounds == null ? null : PlatformLatLngBounds(southWest: bounds.southWest, northEast: bounds.northEast),
    dartProvided: !native,
    fadeIn: display is FadeInTileDisplay,
    flutterMapLayer: flutterMapLayer,
  );
}

/// [layer] as flutter_map's own `TileLayer`, for a backend that draws with flutter_map.
fm.TileLayer toFlutterMapTileLayer(TileLayer layer) => fm.TileLayer(
  urlTemplate: layer.urlTemplate,
  fallbackUrl: layer.fallbackUrl,
  // ignore: deprecated_member_use, deprecated_member_use_from_same_package
  tileSize: layer.tileSize,
  tileDimension: layer.tileDimension,
  minZoom: layer.minZoom,
  maxZoom: layer.maxZoom,
  minNativeZoom: layer.minNativeZoom,
  maxNativeZoom: layer.maxNativeZoom,
  zoomReverse: layer.zoomReverse,
  zoomOffset: layer.zoomOffset,
  additionalOptions: layer.additionalOptions,
  subdomains: layer.subdomains,
  keepBuffer: layer.keepBuffer,
  panBuffer: layer.panBuffer,
  errorImage: layer.errorImage,
  tileProvider: layer.tileProvider,
  tms: layer.tms,
  wmsOptions: layer.wmsOptions,
  tileDisplay: layer.tileDisplay,
  retinaMode: layer.resolvedRetinaMode != RetinaMode.disabled,
  errorTileCallback: layer.errorTileCallback,
  tileBuilder: layer.tileBuilder,
  evictErrorTileStrategy: layer.evictErrorTileStrategy,
  reset: layer.reset,
  tileBounds: layer.tileBounds,
  tileUpdateTransformer: layer.tileUpdateTransformer,
  userAgentPackageName: layer.userAgentPackageName,
);
