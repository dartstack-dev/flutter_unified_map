import 'package:flutter_unified_map_flutter_map/src/layers/tile_layers.dart' show TileLoadListener, showsBaseMap;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

/// Turns the tile outcomes of the layers that draw the base map into [PlatformMapLoadedEvent] and
/// [PlatformMapErrorEvent].
///
/// The base map is the built-in style layer while it is shown; otherwise every tile layer is (a replacing layer,
/// or any layer over `none`). Single tiles fail routinely while the map still shows, so a failure is reported only
/// when no base tile loaded within [recentLoadWindow], and only once until the next loaded event.
class BaseMapLoadMonitor implements TileLoadListener {
  BaseMapLoadMonitor(this.viewId, this._emit, {this._clock = DateTime.now});

  static const recentLoadWindow = Duration(seconds: 10);

  final int viewId;
  final void Function(PlatformMapEvent event) _emit;
  final DateTime Function() _clock;

  PlatformMapStyle? _style;
  List<PlatformTileLayer> _tileLayers = const [];
  bool _ready = false;
  bool _loadedEmitted = false;
  bool _errorEmitted = false;
  DateTime? _lastLoadAt;
  String? _failureBeforeReady;
  String? _baseContent;

  bool get _expectsTiles => showsBaseMap(_style!, _tileLayers) || _tileLayers.isNotEmpty;

  bool _isBase(PlatformTileLayer? layer) {
    final style = _style;
    if (style == null) return false;
    final builtInShown = showsBaseMap(style, _tileLayers);
    return layer == null ? builtInShown : !builtInShown;
  }

  /// A load of the previous base map says nothing about the new one, so its failures count again at once.
  void contentChanged(PlatformMapStyle style, List<PlatformTileLayer> tileLayers) {
    _style = style;
    _tileLayers = tileLayers;
    final content = showsBaseMap(style, tileLayers) ? '$style' : tileLayers.map((t) => t.urlTemplate).join('\n');
    if (content != _baseContent) {
      _baseContent = content;
      _lastLoadAt = null;
    }
    if (_ready && !_expectsTiles) _emitLoadedIfNeeded();
  }

  /// Loads and failures seen before the ready event (tiles served synchronously from the image cache) are
  /// reported right after it, keeping ready first.
  void ready() {
    if (_ready || _style == null) return;
    _ready = true;
    if (_lastLoadAt != null || !_expectsTiles) {
      _emitLoadedIfNeeded();
    } else if (_failureBeforeReady case final message?) {
      _emitError(message);
    }
    _failureBeforeReady = null;
  }

  @override
  void tileLoaded(PlatformTileLayer? layer) {
    if (!_isBase(layer)) return;
    _lastLoadAt = _clock();
    if (_ready) _emitLoadedIfNeeded();
  }

  @override
  void tileFailed(PlatformTileLayer? layer, String host, Object error) {
    if (!_isBase(layer) || _errorEmitted) return;
    final last = _lastLoadAt;
    if (last != null && _clock().difference(last) < recentLoadWindow) return;
    final message = 'Base map tiles from $host failed to load: ${_withoutUrls(error)}';
    if (_ready) {
      _emitError(message);
    } else {
      _failureBeforeReady ??= message;
    }
  }

  void _emitLoadedIfNeeded() {
    if (_loadedEmitted && !_errorEmitted) return;
    _loadedEmitted = true;
    _errorEmitted = false;
    _emit(PlatformMapLoadedEvent(viewId));
  }

  void _emitError(String message) {
    _errorEmitted = true;
    _emit(PlatformMapErrorEvent(viewId, PlatformMapErrorCode.loadFailed, message));
  }

  /// Tile URLs can carry access tokens (`?access_token=`); the message keeps only their host.
  static String _withoutUrls(Object error) =>
      '$error'.replaceAllMapped(RegExp(r'\w+://[^\s,;)\]]+'), (m) => Uri.tryParse(m[0]!)?.host ?? '');
}
