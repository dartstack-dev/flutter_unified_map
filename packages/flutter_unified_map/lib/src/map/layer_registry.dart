import 'dart:async';

import 'package:flutter/animation.dart' show Cubic, Curve, Curves;
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/widgets.dart' show KeyedSubtree, Offset, ValueKey, Widget;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;
import 'package:meta/meta.dart';

import 'camera/map_camera.dart';
import 'report_error.dart';

typedef MarkerTapHandler = void Function(String markerId);
typedef LayerHitTester = void Function(MapCamera camera, LatLng position, Offset screenPoint);

enum MapObjectKind { markers, polylines, polygons, circles, tileLayers, flutterMapLayers }

/// How a layer wants its next marker update animated (see `PlatformMarkerTransition` for what every backend does).
///
/// [appearFrom]: object id of an added marker → position it slides from while fading in.
/// [disappearTo]: object id of a removed marker → position it slides to while fading out.
/// The layer's other added markers fade in, its other removed markers fade out, and its moved markers glide.
/// Positions follow [moveCurve], opacities [fadeInCurve] / [fadeOutCurve] (flutter_map_marker_cluster's
/// `clusterExpandCurve` / `clusterCollapseCurve`, `fadeInCurve`, `fadeOutCurve`). A [Cubic] reaches every backend
/// exactly; any other curve is sampled.
@immutable
class MarkerTransition {
  final Duration duration;
  final Map<String, LatLng> appearFrom;
  final Map<String, LatLng> disappearTo;
  final Curve moveCurve;
  final Curve fadeInCurve;
  final Curve fadeOutCurve;

  const MarkerTransition({
    required this.duration,
    this.appearFrom = const {},
    this.disappearTo = const {},
    this.moveCurve = Curves.easeInOut,
    this.fadeInCurve = Curves.easeInOut,
    this.fadeOutCurve = Curves.easeInOut,
  });

  /// [other] applied after this one: its entries and curves win, the longer duration is kept.
  MarkerTransition merge(MarkerTransition other) => MarkerTransition(
    duration: other.duration > duration ? other.duration : duration,
    appearFrom: {...appearFrom, ...other.appearFrom},
    disappearTo: {...disappearTo, ...other.disappearTo},
    moveCurve: other.moveCurve,
    fadeInCurve: other.fadeInCurve,
    fadeOutCurve: other.fadeOutCurve,
  );

  @override
  bool operator ==(Object other) =>
      other is MarkerTransition &&
      other.duration == duration &&
      _sameMap(other.appearFrom, appearFrom) &&
      _sameMap(other.disappearTo, disappearTo) &&
      other.moveCurve == moveCurve &&
      other.fadeInCurve == fadeInCurve &&
      other.fadeOutCurve == fadeOutCurve;

  @override
  int get hashCode =>
      Object.hash(duration, appearFrom.length, disappearTo.length, moveCurve, fadeInCurve, fadeOutCurve);

  @override
  String toString() =>
      'MarkerTransition($duration, appearFrom ${appearFrom.length}, disappearTo ${disappearTo.length})';
}

bool _sameMap(Map<String, LatLng> a, Map<String, LatLng> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

/// Objects contributed by every layer of one map, grouped by kind and keyed by layer id.
///
/// Layers call `set…` whenever their objects change; the map flushes the merged state to the platform as a
/// diff, once per frame. Object ids are `'<layerId>/<key-or-index>'`, so a marker tap is routed back to the
/// layer by its id prefix.
///
/// Layers stack like flutter_map's: in the order of `UnifiedMap.children` (layers under the same child in the order
/// they were mounted). Each layer gets an integer z-index; when a layer is inserted below others, the layers whose
/// z-index changes are synced again.
///
/// Updates of each kind reach the platform one at a time: a push waits for the previous one of its kind to
/// complete, and the changes made meanwhile go out as a single diff. A diff is recorded as sent only once applied; a
/// failed update is reported, sent again once right away, then with the next change. A transition only animates the
/// markers of the layers that asked for one: the markers of the other layers go out first in an update without
/// transition. Polylines, polygons and circles that change in the same frame as markers are sent once that marker
/// update is applied, so a layer's shapes and markers reach the map together; shapes are never animated.
class LayerRegistry {
  static int _nextLayerId = 0;

  static String newLayerId() => 'l${_nextLayerId++}';

  final void Function() onChanged;

  final _markers = <String, List<PlatformMarker>>{};
  var _markerTransitions = <String, MarkerTransition>{};
  final _polylines = <String, List<PlatformPolyline>>{};
  final _polygons = <String, List<PlatformPolygon>>{};
  final _circles = <String, List<PlatformCircle>>{};
  final _tileLayers = <String, List<PlatformTileLayer>>{};
  final _flutterMapLayers = <String, List<Widget>>{};
  final _markerTaps = <String, MarkerTapHandler>{};
  final _hitTesters = <String, LayerHitTester>{};
  final _layers = <String, _Layer>{};
  final _dirty = <MapObjectKind>{};
  int _nextSeq = 0;
  bool _orderStale = false;

  final _sentMarkers = _Sent<PlatformMarker>(MapObjectKind.markers);
  final _sentPolylines = _Sent<PlatformPolyline>(MapObjectKind.polylines);
  final _sentPolygons = _Sent<PlatformPolygon>(MapObjectKind.polygons);
  final _sentCircles = _Sent<PlatformCircle>(MapObjectKind.circles);
  final _sentTileLayers = _Sent<PlatformTileLayer>(MapObjectKind.tileLayers);
  var _sentFlutterMapLayers = false;

  @internal
  LayerRegistry({required this.onChanged});

  /// Registers [layerId] (`MapLayerState` does it when the layer is attached). [slot] returns the layer's position
  /// among `UnifiedMap.children`; it is read again before each push while the order may have changed. [resync]
  /// registers the layer's objects again when its z-index changes.
  @internal
  void addLayer(String layerId, {int Function()? slot, VoidCallback? resync}) {
    if (_layers.containsKey(layerId)) return;
    _layers[layerId] = _Layer(_nextSeq++, slot, resync);
    _orderStale = true;
    _reorder();
  }

  bool hasLayer(String layerId) => _layers.containsKey(layerId);

  /// z-index of a registered layer: an integer, higher for layers later in `UnifiedMap.children`.
  double zIndexOf(String layerId) {
    final layer = _layers[layerId];
    assert(layer != null, 'Layer $layerId is not registered with this map: MapLayerState registers it on attach');
    return (layer?.z ?? 0).toDouble();
  }

  /// z-index of the [index]-th of [count] shapes of a layer. flutter_map paints a layer's shapes in list order;
  /// native maps only order by z-index, so later shapes get a slightly higher one. The spread stays below 0.4 so a
  /// shape never rises above the next layer, nor above the borders (`zIndex - 0.5`) drawn for that layer.
  double shapeZIndexOf(String layerId, int index, int count) => zIndexOf(layerId) + 0.4 * index / count;

  @internal
  bool get isDirty => _dirty.isNotEmpty || _orderStale;

  /// The layers' positions among `UnifiedMap.children` may have changed: they are read again before the next push.
  @internal
  void markOrderStale() {
    _orderStale = true;
    onChanged();
  }

  /// Replaces the markers of [layerId]. [transition] animates this layer's markers in the next marker push (the
  /// other layers' markers are not animated); transitions set before that push are merged, and only the entries of
  /// markers that the push really adds or removes are sent.
  void setMarkers(
    String layerId,
    List<PlatformMarker> markers, {
    MarkerTapHandler? onTap,
    MarkerTransition? transition,
  }) {
    _markers[layerId] = markers;
    if (onTap == null) {
      _markerTaps.remove(layerId);
    } else {
      _markerTaps[layerId] = onTap;
    }
    if (transition != null) {
      final pending = _markerTransitions[layerId];
      _markerTransitions[layerId] = pending == null ? transition : pending.merge(transition);
    }
    _mark(MapObjectKind.markers);
  }

  void setPolylines(String layerId, List<PlatformPolyline> polylines) {
    _polylines[layerId] = polylines;
    _mark(MapObjectKind.polylines);
  }

  void setPolygons(String layerId, List<PlatformPolygon> polygons) {
    _polygons[layerId] = polygons;
    _mark(MapObjectKind.polygons);
  }

  void setCircles(String layerId, List<PlatformCircle> circles) {
    _circles[layerId] = circles;
    _mark(MapObjectKind.circles);
  }

  void setTileLayers(String layerId, List<PlatformTileLayer> tileLayers) {
    _tileLayers[layerId] = tileLayers;
    _mark(MapObjectKind.tileLayers);
  }

  /// flutter_map layer widgets of [layerId], drawn inside the map by platforms that draw it with flutter_map
  /// (`UnifiedMapsPlatform.supportsFlutterMapLayers`) and ignored by the others.
  void setFlutterMapLayers(String layerId, List<Widget> layers) {
    _flutterMapLayers[layerId] = layers;
    _mark(MapObjectKind.flutterMapLayers);
  }

  void setHitTester(String layerId, LayerHitTester? tester) {
    if (tester == null) {
      _hitTesters.remove(layerId);
    } else {
      _hitTesters[layerId] = tester;
    }
  }

  void removeLayer(String layerId) {
    if (_markers.remove(layerId) != null) _mark(MapObjectKind.markers);
    if (_polylines.remove(layerId) != null) _mark(MapObjectKind.polylines);
    if (_polygons.remove(layerId) != null) _mark(MapObjectKind.polygons);
    if (_circles.remove(layerId) != null) _mark(MapObjectKind.circles);
    if (_tileLayers.remove(layerId) != null) _mark(MapObjectKind.tileLayers);
    if (_flutterMapLayers.remove(layerId) != null) _mark(MapObjectKind.flutterMapLayers);
    _markerTransitions.remove(layerId);
    _markerTaps.remove(layerId);
    _hitTesters.remove(layerId);
    _layers.remove(layerId);
  }

  Map<String, PlatformMarker> get markers => _merge(_markers);
  Map<String, PlatformPolyline> get polylines => _merge(_polylines);
  Map<String, PlatformPolygon> get polygons => _merge(_polygons);
  Map<String, PlatformCircle> get circles => _merge(_circles);
  Map<String, PlatformTileLayer> get tileLayers => _merge(_tileLayers);

  /// Every layer's flutter_map layer widgets, bottom layer first.
  /// Keyed by layer id and position so that a stateful flutter_map layer keeps its state when another layer is
  /// added or removed before it.
  List<Widget> get flutterMapLayers {
    final layerIds = _flutterMapLayers.keys.toList()..sort((a, b) => zIndexOf(a).compareTo(zIndexOf(b)));
    return [
      for (final id in layerIds)
        for (final (index, layer) in _flutterMapLayers[id]!.indexed)
          KeyedSubtree(key: ValueKey((id, index)), child: layer),
    ];
  }

  @internal
  void handleMarkerTap(String markerId) {
    final slash = markerId.indexOf('/');
    if (slash < 0) return;
    _markerTaps[markerId.substring(0, slash)]?.call(markerId);
  }

  /// Runs every layer's hit tester, top-most layer first.
  @internal
  void hitTest(MapCamera camera, LatLng position, Offset screenPoint) {
    final testers = _hitTesters.entries.toList()
      ..sort((a, b) => (_layers[b.key]?.z ?? 0).compareTo(_layers[a.key]?.z ?? 0));
    for (final entry in testers) {
      entry.value(camera, position, screenPoint);
    }
  }

  /// Marks every kind dirty so the next [pushTo] re-sends everything (used once the platform is ready).
  @internal
  void markAllDirty() {
    _dirty.addAll(MapObjectKind.values);
  }

  /// Sends the diff since the last applied update for every dirty kind. A kind stays dirty while its previous update
  /// is in flight, and so do the shapes when a marker update is; [onChanged] is called when an update completes with
  /// changes left, so that the map flushes them.
  @internal
  void pushTo(UnifiedMapsPlatform platform, int viewId) {
    if (_orderStale) _refreshOrder();
    final dirty = Set.of(_dirty);
    _dirty.clear();
    if (dirty.contains(MapObjectKind.markers)) _pushMarkers(platform, viewId);
    final holdShapes = dirty.contains(MapObjectKind.markers) && _sentMarkers.inFlight && _sentMarkers.failures == 0;
    for (final kind in dirty) {
      switch (kind) {
        case MapObjectKind.markers:
          break;
        case MapObjectKind.polylines || MapObjectKind.polygons || MapObjectKind.circles when holdShapes:
          _dirty.add(kind);
        case MapObjectKind.polylines:
          _push(_sentPolylines, polylines, (u) => platform.updatePolylines(viewId, u));
        case MapObjectKind.polygons:
          _push(_sentPolygons, polygons, (u) => platform.updatePolygons(viewId, u));
        case MapObjectKind.circles:
          _push(_sentCircles, circles, (u) => platform.updateCircles(viewId, u));
        case MapObjectKind.tileLayers:
          _push(_sentTileLayers, tileLayers, (u) => platform.updateTileLayers(viewId, u));
        case MapObjectKind.flutterMapLayers:
          if (!platform.supportsFlutterMapLayers) break;
          final current = flutterMapLayers;
          if (current.isEmpty && !_sentFlutterMapLayers) break;
          platform.setFlutterMapLayers(viewId, current);
          _sentFlutterMapLayers = current.isNotEmpty;
      }
    }
  }

  void _pushMarkers(UnifiedMapsPlatform platform, int viewId) {
    if (_sentMarkers.inFlight) {
      _dirty.add(MapObjectKind.markers);
      return;
    }
    final updates = MapObjectUpdates.from(_sentMarkers.objects, markers);
    final transitions = _markerTransitions;
    _markerTransitions = {};
    if (updates.isEmpty) return;
    final animated = _only(updates, (id) => transitions.containsKey(_layerOf(id)));
    final transition = _transitionFor(animated, transitions);
    final batches = transition == null
        ? [(updates, null)]
        : [(_only(updates, (id) => !transitions.containsKey(_layerOf(id))), null), (animated, transition)];
    _sentMarkers.inFlight = true;
    unawaited(_sendMarkers(platform, viewId, batches, transitions));
  }

  /// Sends [batches] in order, each once the previous one is applied. On failure the unsent diff stays unsent and
  /// [transitions] (the hints this push consumed) are restored for the next push.
  Future<void> _sendMarkers(
    UnifiedMapsPlatform platform,
    int viewId,
    List<(MapObjectUpdates<PlatformMarker>, PlatformMarkerTransition?)> batches,
    Map<String, MarkerTransition> transitions,
  ) async {
    final sent = _sentMarkers;
    try {
      for (final (updates, transition) in batches) {
        if (updates.isEmpty) continue;
        await platform.updateMarkers(viewId, updates, transition: transition);
        sent.objects = _applied(sent.objects, updates);
      }
      sent.failures = 0;
    } catch (error, stack) {
      final newer = _markerTransitions;
      _markerTransitions = {
        for (final MapEntry(:key, :value) in transitions.entries)
          if (_markers.containsKey(key)) key: value,
      };
      for (final MapEntry(:key, :value) in newer.entries) {
        final before = _markerTransitions[key];
        _markerTransitions[key] = before == null ? value : before.merge(value);
      }
      _failed(sent, error, stack);
    } finally {
      sent.inFlight = false;
      _afterSend(sent);
    }
  }

  void _push<T extends PlatformMapObject>(
    _Sent<T> sent,
    Map<String, T> current,
    Future<void> Function(MapObjectUpdates<T>) send,
  ) {
    if (sent.inFlight) {
      _dirty.add(sent.kind);
      return;
    }
    final updates = MapObjectUpdates.from(sent.objects, current);
    if (updates.isEmpty) return;
    sent.inFlight = true;
    unawaited(_sendObjects(sent, updates, send));
  }

  Future<void> _sendObjects<T extends PlatformMapObject>(
    _Sent<T> sent,
    MapObjectUpdates<T> updates,
    Future<void> Function(MapObjectUpdates<T>) send,
  ) async {
    try {
      await send(updates);
      sent.objects = _applied(sent.objects, updates);
      sent.failures = 0;
    } catch (error, stack) {
      _failed(sent, error, stack);
    } finally {
      sent.inFlight = false;
      _afterSend(sent);
    }
  }

  /// A disposed view, or a backend that could not apply the update (e.g. an icon it failed to register). The first
  /// failure in a row is reported; the update is retried once right away, then with the next change, so a backend
  /// that keeps failing is not called every frame.
  void _failed(_Sent<PlatformMapObject> sent, Object error, StackTrace stack) {
    if (sent.failures++ == 0) reportMapError(error, stack, 'while updating the ${sent.kind.name} of a UnifiedMap');
    _dirty.add(sent.kind);
  }

  void _afterSend(_Sent<PlatformMapObject> sent) {
    final retry = _dirty.contains(sent.kind) && sent.failures <= 1;
    final held = sent.kind == MapObjectKind.markers && _dirty.any((kind) => kind != MapObjectKind.markers);
    if (retry || held) onChanged();
  }

  static Map<String, T> _applied<T extends PlatformMapObject>(Map<String, T> sent, MapObjectUpdates<T> u) {
    final next = Map.of(sent);
    for (final id in u.removedIds) {
      next.remove(id);
    }
    for (final object in [...u.added, ...u.changed]) {
      next[object.id] = object;
    }
    return next;
  }

  static MapObjectUpdates<PlatformMarker> _only(MapObjectUpdates<PlatformMarker> u, bool Function(String id) test) =>
      MapObjectUpdates(
        added: [
          for (final m in u.added)
            if (test(m.id)) m,
        ],
        changed: [
          for (final m in u.changed)
            if (test(m.id)) m,
        ],
        removedIds: [
          for (final id in u.removedIds)
            if (test(id)) id,
        ],
      );

  static PlatformMarkerTransition? _transitionFor(
    MapObjectUpdates<PlatformMarker> updates,
    Map<String, MarkerTransition> transitions,
  ) {
    if (updates.isEmpty) return null;
    final touchedLayers = <String>{
      for (final marker in updates.added) _layerOf(marker.id),
      for (final marker in updates.changed) _layerOf(marker.id),
      for (final id in updates.removedIds) _layerOf(id),
    };
    Duration? duration;
    MarkerTransition? longest;
    final appearFrom = <String, LatLng>{};
    final disappearTo = <String, LatLng>{};
    for (final MapEntry(key: layerId, value: transition) in transitions.entries) {
      if (!touchedLayers.contains(layerId)) continue;
      if (duration == null || transition.duration > duration) {
        duration = transition.duration;
        longest = transition;
      }
      for (final marker in updates.added) {
        final from = transition.appearFrom[marker.id];
        if (from != null) appearFrom[marker.id] = from;
      }
      for (final id in updates.removedIds) {
        final to = transition.disappearTo[id];
        if (to != null) disappearTo[id] = to;
      }
    }
    if (duration == null || longest == null || duration <= Duration.zero) return null;
    return PlatformMarkerTransition(
      duration: duration,
      appearFrom: appearFrom,
      disappearTo: disappearTo,
      moveCurve: platformCurve(longest.moveCurve),
      fadeInCurve: platformCurve(longest.fadeInCurve),
      fadeOutCurve: platformCurve(longest.fadeOutCurve),
    );
  }

  static const _curveSamples = 33;

  /// [curve] for the platforms: a [Cubic] as is, any other curve sampled at evenly spaced times.
  static PlatformCurve platformCurve(Curve curve) {
    if (identical(curve, Curves.easeInOut)) return PlatformCurve.easeInOut;
    if (curve is Cubic) return PlatformCurve.cubic(curve.a, curve.b, curve.c, curve.d);
    return PlatformCurve.sampled([for (var i = 0; i < _curveSamples; i++) curve.transform(i / (_curveSamples - 1))]);
  }

  static String _layerOf(String objectId) {
    final slash = objectId.indexOf('/');
    return slash < 0 ? objectId : objectId.substring(0, slash);
  }

  void _refreshOrder() {
    _orderStale = false;
    for (final layer in _layers.values) {
      layer.readSlot();
    }
    _reorder();
  }

  /// Gives every layer a z-index following (slot, mount order). Layers keep theirs when a new one fits between its
  /// neighbours; otherwise every layer is renumbered and the layers whose z-index changed are synced again.
  void _reorder() {
    final sorted = _layers.values.toList()
      ..sort((a, b) {
        final bySlot = a.slot.compareTo(b.slot);
        return bySlot != 0 ? bySlot : a.seq.compareTo(b.seq);
      });
    final next = _keepingOrder(sorted) ?? [for (var i = 0; i < sorted.length; i++) i];
    final moved = <_Layer>[];
    for (final (i, layer) in sorted.indexed) {
      if (layer.z != null && layer.z != next[i]) moved.add(layer);
      layer.z = next[i];
    }
    for (final layer in moved) {
      layer.resync?.call();
    }
  }

  static List<int>? _keepingOrder(List<_Layer> sorted) {
    final result = <int>[];
    for (final (i, layer) in sorted.indexed) {
      final previous = result.lastOrNull;
      var z = layer.z;
      if (z == null) {
        final above = sorted.skip(i + 1).map((l) => l.z).nonNulls.firstOrNull;
        z = previous != null ? previous + 1 : (above != null ? above - 1 : 0);
        if (above != null && z >= above) return null;
      }
      if (previous != null && z <= previous) return null;
      result.add(z);
    }
    return result;
  }

  void _mark(MapObjectKind kind) {
    _dirty.add(kind);
    onChanged();
  }

  Map<String, T> _merge<T extends PlatformMapObject>(Map<String, List<T>> byLayer) {
    final merged = <String, T>{};
    for (final objects in byLayer.values) {
      for (final object in objects) {
        merged[object.id] = object;
      }
    }
    return merged;
  }
}

class _Layer {
  final int seq;
  final int Function()? _slotOf;
  final VoidCallback? resync;
  late int slot = _slotOf?.call() ?? _lastSlot;
  int? z;

  static const _lastSlot = 1 << 30;

  _Layer(this.seq, this._slotOf, this.resync);

  void readSlot() => slot = _slotOf?.call() ?? _lastSlot;
}

/// What the platform has applied for one kind of object.
class _Sent<T extends PlatformMapObject> {
  final MapObjectKind kind;
  var objects = <String, T>{};
  bool inFlight = false;
  int failures = 0;

  _Sent(this.kind);
}
