import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer;
import 'package:flutter/widgets.dart' show Widget;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

@immutable
class RecordedMove {
  final int viewId;
  final PlatformCameraUpdate update;
  final Duration? animation;

  const RecordedMove(this.viewId, this.update, this.animation);

  @override
  String toString() => 'RecordedMove($viewId, $update, $animation)';
}

/// Passes every call through to [delegate] (the platform registered by the plugin, or any implementation) and
/// records what the core sent and what the platform reported, so tests can assert what reached the native side.
class RecordingPlatform extends UnifiedMapsPlatform with MockPlatformInterfaceMixin {
  RecordingPlatform(this.delegate);

  final UnifiedMapsPlatform delegate;

  final builtViews = <int, PlatformMapOptions>{};
  final optionUpdates = <PlatformMapOptions>[];
  final markerUpdates = <MapObjectUpdates<PlatformMarker>>[];
  final polylineUpdates = <MapObjectUpdates<PlatformPolyline>>[];
  final polygonUpdates = <MapObjectUpdates<PlatformPolygon>>[];
  final circleUpdates = <MapObjectUpdates<PlatformCircle>>[];
  final tileLayerUpdates = <MapObjectUpdates<PlatformTileLayer>>[];
  final markerTransitions = <PlatformMarkerTransition?>[];
  final cameraMoves = <RecordedMove>[];
  final flutterMapLayerCalls = <List<Widget>>[];
  final receivedEvents = <PlatformMapEvent>[];

  final markers = <String, PlatformMarker>{};
  final polylines = <String, PlatformPolyline>{};
  final polygons = <String, PlatformPolygon>{};
  final circles = <String, PlatformCircle>{};

  final _eventsController = StreamController<PlatformMapEvent>.broadcast(sync: true);

  /// Every platform event, as the core receives it.
  Stream<PlatformMapEvent> get onEvent => _eventsController.stream;

  /// The marker published by a `Marker(key: ValueKey(name))`: object ids are `'<layerId>/k:<key>'`.
  PlatformMarker? markerNamed(String name) => markers.values.where((m) => m.id.endsWith('/k:$name')).firstOrNull;

  @override
  Widget buildView({
    required int viewId,
    required PlatformMapOptions options,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  }) {
    builtViews[viewId] = options;
    return delegate.buildView(viewId: viewId, options: options, gestureRecognizers: gestureRecognizers);
  }

  @override
  Future<void> dispose(int viewId) => delegate.dispose(viewId);

  @override
  Future<void> updateOptions(int viewId, PlatformMapOptions options) {
    optionUpdates.add(options);
    return delegate.updateOptions(viewId, options);
  }

  @override
  Future<void> updateMarkers(
    int viewId,
    MapObjectUpdates<PlatformMarker> updates, {
    PlatformMarkerTransition? transition,
  }) {
    markerUpdates.add(updates);
    markerTransitions.add(transition);
    _apply(markers, updates);
    return delegate.updateMarkers(viewId, updates, transition: transition);
  }

  @override
  Future<void> updatePolylines(int viewId, MapObjectUpdates<PlatformPolyline> updates) {
    polylineUpdates.add(updates);
    _apply(polylines, updates);
    return delegate.updatePolylines(viewId, updates);
  }

  @override
  Future<void> updatePolygons(int viewId, MapObjectUpdates<PlatformPolygon> updates) {
    polygonUpdates.add(updates);
    _apply(polygons, updates);
    return delegate.updatePolygons(viewId, updates);
  }

  @override
  Future<void> updateCircles(int viewId, MapObjectUpdates<PlatformCircle> updates) {
    circleUpdates.add(updates);
    _apply(circles, updates);
    return delegate.updateCircles(viewId, updates);
  }

  @override
  Future<void> updateTileLayers(int viewId, MapObjectUpdates<PlatformTileLayer> updates) {
    tileLayerUpdates.add(updates);
    return delegate.updateTileLayers(viewId, updates);
  }

  @override
  Future<void> moveCamera(int viewId, PlatformCameraUpdate update, {Duration? animation}) {
    cameraMoves.add(RecordedMove(viewId, update, animation));
    return delegate.moveCamera(viewId, update, animation: animation);
  }

  @override
  Future<PlatformCamera> getCamera(int viewId) => delegate.getCamera(viewId);

  @override
  Future<PlatformLatLngBounds> getVisibleRegion(int viewId) => delegate.getVisibleRegion(viewId);

  @override
  Future<Offset> toScreen(int viewId, LatLng position) => delegate.toScreen(viewId, position);

  @override
  Future<LatLng> toLatLng(int viewId, Offset screenPoint) => delegate.toLatLng(viewId, screenPoint);

  @override
  Future<Uint8List?> takeSnapshot(int viewId) => delegate.takeSnapshot(viewId);

  @override
  bool get supportsFlutterMapLayers => delegate.supportsFlutterMapLayers;

  @override
  void setFlutterMapLayers(int viewId, List<Widget> layers) {
    flutterMapLayerCalls.add(layers);
    delegate.setFlutterMapLayers(viewId, layers);
  }

  @override
  Stream<PlatformMapEvent> events(int viewId) {
    final recorded = delegate.events(viewId).map((event) {
      receivedEvents.add(event);
      _eventsController.add(event);
      return event;
    });
    return recorded.isBroadcast ? recorded : recorded.asBroadcastStream();
  }

  static void _apply<T extends PlatformMapObject>(Map<String, T> store, MapObjectUpdates<T> updates) {
    for (final id in updates.removedIds) {
      store.remove(id);
    }
    for (final object in [...updates.added, ...updates.changed]) {
      store[object.id] = object;
    }
  }
}
