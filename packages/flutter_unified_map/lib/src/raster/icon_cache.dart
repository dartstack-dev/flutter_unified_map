import 'package:flutter/widgets.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

import 'widget_rasterizer.dart';

typedef IconCacheKey = (Object key, Size size, double pixelRatio);

/// Per-map cache of rasterised marker icons, keyed by icon key, logical size and pixel ratio.
///
/// Keeps the [maxEntries] most recently used icons. Every rasterised image gets a unique [PlatformIcon.key],
/// so a diff only re-sends a marker when its image really changed.
class IconCache {
  static int _nextIconKey = 0;
  static int _rendersInFlight = 0;

  /// Icons being rasterised by every cache, for tests that wait for them.
  @visibleForTesting
  static int get rendersInFlight => _rendersInFlight;

  final int maxEntries;
  final _icons = <IconCacheKey, PlatformIcon>{};
  final _pending = <IconCacheKey, Future<PlatformIcon>>{};
  int _epoch = 0;

  IconCache({this.maxEntries = 500});

  int get length => _icons.length;

  /// Incremented by every [clear]: an icon obtained before is no longer the one the map would rasterise.
  int get epoch => _epoch;

  /// The cached icon, if any, which becomes the most recently used.
  PlatformIcon? lookup(Object key, Size size, double pixelRatio) {
    final cacheKey = (key, size, pixelRatio);
    final icon = _icons.remove(cacheKey);
    if (icon != null) _icons[cacheKey] = icon;
    return icon;
  }

  Future<PlatformIcon> resolve({
    required Object key,
    required Widget child,
    required Size size,
    required double pixelRatio,
    BuildContext? context,
  }) {
    final cached = lookup(key, size, pixelRatio);
    if (cached != null) return Future.value(cached);
    final cacheKey = (key, size, pixelRatio);
    return _pending[cacheKey] ??= _render(cacheKey, child, context);
  }

  Future<PlatformIcon> _render(IconCacheKey cacheKey, Widget child, BuildContext? context) async {
    final (_, size, pixelRatio) = cacheKey;
    final epoch = _epoch;
    _rendersInFlight++;
    try {
      final bytes = await WidgetRasterizer.render(child, logicalSize: size, pixelRatio: pixelRatio, context: context);
      final icon = PlatformIcon(key: 'i${_nextIconKey++}', bytes: bytes, logicalSize: size, pixelRatio: pixelRatio);
      if (epoch == _epoch) {
        _icons[cacheKey] = icon;
        while (_icons.length > maxEntries) {
          _icons.remove(_icons.keys.first);
        }
      }
      return icon;
    } finally {
      _rendersInFlight--;
      if (epoch == _epoch) {
        final _ = _pending.remove(cacheKey);
      }
    }
  }

  /// Empties the cache. Renders still in flight complete for their callers but are not cached.
  void clear() {
    _epoch++;
    _icons.clear();
    _pending.clear();
  }
}
