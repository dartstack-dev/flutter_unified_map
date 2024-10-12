import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    as platform
    show Offset;

import '../../map/conversions.dart';
import '../../map/layer_registry.dart';
import '../../map/map_layer_host.dart';
import '../../native/native_params.dart';
import '../polyline_layer/polyline.dart';

/// One native marker to publish: its object id, where it goes, what to rasterise and how to anchor it.
///
/// [id] is an object id of the publishing layer (`MapLayerState.objectId`), so taps are routed back to it.
/// [iconKey] identifies the bitmap of [child] at [size]: markers sharing it share one rasterised icon.
/// [alignment] follows flutter_map's `Marker.alignment`; [rotate] true keeps the icon upright when the map rotates.
/// [zIndex] is added to the layer's z-index; keep it in `[0, 1)` so the marker stays below the next layer's.
/// [tappable] false lets taps on the marker through to the map (`MapOptions.onTap`, the shapes' hit notifiers), as a
/// flutter_map marker without a gesture detector. [nativeParams] carries the native-only settings (rotation,
/// opacity, drag, info window...); its callbacks are called for this marker's native events.
///
/// [child] is rasterised with the map's themes, text scale and brightness: when they change, every icon is
/// rasterised again. Anything else the bitmap depends on must be part of [iconKey].
@immutable
class MarkerSpec {
  final String id;
  final LatLng position;
  final Object iconKey;
  final Widget child;
  final Size size;
  final Alignment alignment;
  final bool rotate;
  final double zIndex;
  final bool tappable;
  final NativeMarkerParams? nativeParams;

  const MarkerSpec({
    required this.id,
    required this.position,
    required this.iconKey,
    required this.child,
    required this.size,
    this.alignment = Alignment.center,
    this.rotate = false,
    this.zIndex = 0,
    this.tappable = true,
    this.nativeParams,
  });

  @override
  String toString() => 'MarkerSpec($id, $position, $iconKey)';
}

typedef _IconKey = (Object, Size);

/// Publishes a layer's markers in atomic generations.
///
/// [publish] hands a whole generation of [MarkerSpec]s to the map at once, as soon as every one of its icons is
/// rasterised. Until then the previous generation stays on the map untouched (no partial update, no gap), and a
/// newer [publish] supersedes a generation still waiting for its icons. The generation's [MarkerTransition] and
/// polylines go out with it. The publisher keeps the icons of the generation on the map, so a full icon cache never
/// evicts an icon still on screen. An icon that fails to rasterise is reported and its markers are left out; it is
/// tried again once a generation without it has been published.
class MarkerPublisher {
  final String layerId;

  var _held = <_IconKey, PlatformIcon>{};
  final _failed = <_IconKey>{};
  List<MarkerSpec> _published = const [];
  double? _pixelRatio;
  int? _iconEpoch;
  _WidgetKeyCheck? _widgetKeyCheck;
  int _generation = 0;
  int _appliedGeneration = 0;
  bool _disposed = false;

  MarkerPublisher(this.layerId);

  static platform.Offset anchorOf(Alignment alignment) => platform.Offset((1 - alignment.x) / 2, (1 - alignment.y) / 2);

  /// The generation last handed to the map (markers whose icon failed are left out).
  List<MarkerSpec> get published => _published;

  /// Whether a generation is waiting for its icons.
  bool get hasPending => _generation != _appliedGeneration;

  /// Publishes [specs] as the layer's new generation. [onTap] receives the object id of a tapped marker of this
  /// generation; it replaces the previous handler when the generation reaches the map. [polylines], when given,
  /// replace the layer's polylines (as `MapLayerState.setPolylines`) at the same time as the markers; when null the
  /// layer's polylines are left as they are.
  void publish(
    MapLayerHost host,
    List<MarkerSpec> specs, {
    MarkerTapHandler? onTap,
    MarkerTransition? transition,
    List<Polyline>? polylines,
  }) {
    if (_disposed) return;
    final generation = ++_generation;
    final pixelRatio = host.pixelRatio;
    _followIcons(host, pixelRatio);
    assert(() {
      (_widgetKeyCheck ??= _WidgetKeyCheck(layerId)).check(specs);
      return true;
    }());
    final icons = <_IconKey, PlatformIcon>{};
    final requested = <_IconKey>{};
    final pending = <Future<void>>[];
    for (final spec in specs) {
      final key = (spec.iconKey, spec.size);
      if (!requested.add(key) || _failed.contains(key)) continue;
      final icon = _held[key] ?? host.icons.lookup(spec.iconKey, spec.size, pixelRatio);
      if (icon != null) {
        icons[key] = icon;
      } else {
        pending.add(
          _resolve(host, spec, pixelRatio).then((icon) {
            if (icon != null) icons[key] = icon;
          }),
        );
      }
    }
    void apply() => _apply(host, generation, specs, requested, icons, onTap, transition, polylines);
    if (pending.isEmpty) {
      apply();
      return;
    }
    unawaited(
      Future.wait(pending).then((_) {
        if (_disposed || generation != _generation) return;
        apply();
      }),
    );
  }

  /// Rasterises the icons of [specs] ahead of time (into the map's icon cache) without publishing anything, so a
  /// later [publish] of them is immediate.
  Future<void> prepare(MapLayerHost host, Iterable<MarkerSpec> specs) {
    final pixelRatio = host.pixelRatio;
    _followIcons(host, pixelRatio);
    final requested = <_IconKey>{};
    final pending = <Future<void>>[];
    for (final spec in specs) {
      final key = (spec.iconKey, spec.size);
      if (!requested.add(key) || _failed.contains(key) || _held.containsKey(key)) continue;
      if (host.icons.lookup(spec.iconKey, spec.size, pixelRatio) != null) continue;
      pending.add(_resolve(host, spec, pixelRatio));
    }
    return Future.wait(pending);
  }

  /// Drops the held icons when they no longer match the map: another pixel ratio, or an icon cache cleared because
  /// the appearance icons are rasterised with changed.
  void _followIcons(MapLayerHost host, double pixelRatio) {
    final epoch = host.icons.epoch;
    if (pixelRatio == _pixelRatio && epoch == _iconEpoch) return;
    _held = {};
    _failed.clear();
    _pixelRatio = pixelRatio;
    _iconEpoch = epoch;
  }

  void dispose() {
    _disposed = true;
    _held = {};
    _published = const [];
  }

  Future<PlatformIcon?> _resolve(MapLayerHost host, MarkerSpec spec, double pixelRatio) async {
    final key = (spec.iconKey, spec.size);
    try {
      return await host.icons.resolve(
        key: spec.iconKey,
        child: spec.child,
        size: spec.size,
        pixelRatio: pixelRatio,
        context: host.context,
      );
    } catch (error, stack) {
      if (_failed.add(key)) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'flutter_unified_map',
            context: ErrorDescription('while rasterising a marker icon'),
          ),
        );
      }
      return null;
    }
  }

  void _apply(
    MapLayerHost host,
    int generation,
    List<MarkerSpec> specs,
    Set<_IconKey> requested,
    Map<_IconKey, PlatformIcon> icons,
    MarkerTapHandler? onTap,
    MarkerTransition? transition,
    List<Polyline>? polylines,
  ) {
    if (!host.registry.hasLayer(layerId)) return;
    final layerZIndex = host.registry.zIndexOf(layerId);
    final markers = <PlatformMarker>[];
    final published = <MarkerSpec>[];
    for (final spec in specs) {
      final icon = icons[(spec.iconKey, spec.size)];
      if (icon == null) continue;
      published.add(spec);
      markers.add(toPlatformMarker(spec, icon, layerZIndex));
    }
    _held = icons;
    _failed.retainAll(requested);
    _published = published;
    _appliedGeneration = generation;
    host.registry.setMarkers(layerId, markers, onTap: onTap, transition: transition);
    if (polylines != null) host.registry.setPolylines(layerId, layerPolylines(host.registry, layerId, polylines));
  }
}

/// [spec] as a platform marker of a layer at [layerZIndex].
PlatformMarker toPlatformMarker(MarkerSpec spec, PlatformIcon icon, double layerZIndex) {
  final native = spec.nativeParams;
  final android = native?.android;
  final apple = native?.apple;
  return PlatformMarker(
    id: spec.id,
    position: spec.position,
    icon: icon,
    anchor: MarkerPublisher.anchorOf(spec.alignment),
    zIndex: layerZIndex + spec.zIndex,
    flat: !spec.rotate,
    rotation: native?.rotation ?? 0,
    tappable: spec.tappable || native?.title != null || (native?.draggable ?? false),
    opacity: native?.opacity ?? 1,
    draggable: native?.draggable ?? false,
    title: native?.title,
    snippet: native?.snippet,
    android: android == null
        ? null
        : PlatformAndroidMarkerOptions(
            infoWindowAnchor: switch (android.infoWindowAnchor) {
              null => null,
              final a => MarkerPublisher.anchorOf(a),
            },
            flat: android.flat,
          ),
    apple: apple == null
        ? null
        : PlatformAppleMarkerOptions(
            displayPriority: apple.displayPriority,
            collisionMode: switch (apple.collisionMode) {
              null => null,
              AppleCollisionMode.rectangle => PlatformAppleCollisionMode.rectangle,
              AppleCollisionMode.circle => PlatformAppleCollisionMode.circle,
              AppleCollisionMode.none => PlatformAppleCollisionMode.none,
            },
          ),
  );
}

/// Debug check: markers whose default icon key (the child widget) is a new instance on every generation are
/// rasterised again each time. Warns once per publisher.
class _WidgetKeyCheck {
  static const _generations = 3;

  final String layerId;
  var _keys = <String, Widget>{};
  int _rekeyedGenerations = 0;
  bool _warned = false;

  _WidgetKeyCheck(this.layerId);

  void check(List<MarkerSpec> specs) {
    if (_warned) return;
    final keys = <String, Widget>{};
    var widgetKeyed = 0;
    var rekeyed = 0;
    for (final spec in specs) {
      final key = spec.iconKey;
      if (key is! Widget) continue;
      widgetKeyed++;
      keys[spec.id] = key;
      final before = _keys[spec.id];
      if (before != null && !identical(before, key) && before.runtimeType == key.runtimeType) rekeyed++;
    }
    _keys = keys;
    _rekeyedGenerations = rekeyed > 0 && rekeyed * 2 >= widgetKeyed ? _rekeyedGenerations + 1 : 0;
    if (_rekeyedGenerations < _generations) return;
    _warned = true;
    debugPrint(
      'flutter_unified_map: the markers of layer $layerId get a new child widget on every rebuild, so their icons '
      'are rasterised again each time. Give them an iconKey describing what they look like (e.g. '
      "Marker(iconKey: ('pin', color), ...)), or build a const child.",
    );
  }
}
