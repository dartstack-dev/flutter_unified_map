import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    as platform
    show Offset;

class MoveCameraCall {
  final int viewId;
  final PlatformCameraUpdate update;
  final Duration? animation;

  const MoveCameraCall(this.viewId, this.update, this.animation);
}

/// Records every call and lets tests emit platform events.
class FakeUnifiedMapsPlatform extends UnifiedMapsPlatform with MockPlatformInterfaceMixin {
  final builtViews = <int, PlatformMapOptions>{};
  final optionUpdates = <PlatformMapOptions>[];
  final disposed = <int>[];
  final markerUpdates = <MapObjectUpdates<PlatformMarker>>[];

  /// The transition passed with each entry of [markerUpdates].
  final markerTransitions = <PlatformMarkerTransition?>[];
  final polylineUpdates = <MapObjectUpdates<PlatformPolyline>>[];
  final polygonUpdates = <MapObjectUpdates<PlatformPolygon>>[];
  final circleUpdates = <MapObjectUpdates<PlatformCircle>>[];
  final tileLayerUpdates = <MapObjectUpdates<PlatformTileLayer>>[];
  final cameraMoves = <MoveCameraCall>[];
  final flutterMapLayerCalls = <List<Widget>>[];

  /// Answer of [supportsFlutterMapLayers], like the flutter_map backend when true.
  bool flutterMapLayersSupported = false;

  /// When set, each marker update waits for it before it is applied, like a native side registering icons first.
  Future<void> Function()? markerUpdateGate;

  /// When set, each polyline, polygon, circle and tile layer update runs it before it is applied (it may throw).
  Future<void> Function()? shapeUpdateGate;

  /// Thrown by the next calls of the corresponding method when set.
  Object? moveCameraError;
  Object? optionsError;
  Object? snapshotError;

  /// Marker updates started and not yet applied, and the most that were ever in flight together.
  int markerUpdatesInFlight = 0;
  int maxMarkerUpdatesInFlight = 0;

  final markers = <String, PlatformMarker>{};
  final polylines = <String, PlatformPolyline>{};
  final polygons = <String, PlatformPolygon>{};
  final circles = <String, PlatformCircle>{};
  final tileLayers = <String, PlatformTileLayer>{};

  final _controllers = <int, StreamController<PlatformMapEvent>>{};

  int get lastViewId => builtViews.keys.last;

  @override
  Widget buildView({
    required int viewId,
    required PlatformMapOptions options,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  }) {
    builtViews[viewId] = options;
    return const SizedBox.expand(key: ValueKey('fake-map'));
  }

  @override
  Stream<PlatformMapEvent> events(int viewId) => _controller(viewId).stream;

  StreamController<PlatformMapEvent> _controller(int viewId) =>
      _controllers.putIfAbsent(viewId, () => StreamController<PlatformMapEvent>.broadcast(sync: true));

  void emit(PlatformMapEvent event) => _controller(event.viewId).add(event);

  void ready({PlatformCamera camera = const PlatformCamera(center: LatLng(0, 0), zoom: 2), int? viewId}) =>
      emit(PlatformMapReadyEvent(viewId ?? lastViewId, camera));

  void moveTo(PlatformCamera camera, {bool byGesture = true}) {
    emit(PlatformCameraMoveStartedEvent(lastViewId, byGesture: byGesture));
    emit(PlatformCameraMoveEvent(lastViewId, camera));
    emit(PlatformCameraIdleEvent(lastViewId, camera));
  }

  void tap(LatLng position, Offset point) =>
      emit(PlatformMapTapEvent(lastViewId, position, platform.Offset(point.dx, point.dy)));

  void tapMarker(String id) => emit(PlatformMarkerTapEvent(lastViewId, id));

  void longPress(LatLng position, Offset point) =>
      emit(PlatformMapLongPressEvent(lastViewId, position, platform.Offset(point.dx, point.dy)));

  @override
  Future<void> dispose(int viewId) async {
    disposed.add(viewId);
    await _controllers.remove(viewId)?.close();
  }

  @override
  Future<void> updateOptions(int viewId, PlatformMapOptions options) async {
    if (optionsError case final error?) throw error;
    optionUpdates.add(options);
  }

  @override
  Future<Uint8List?> takeSnapshot(int viewId) async {
    if (snapshotError case final error?) throw error;
    return Uint8List(4);
  }

  @override
  Future<void> updateMarkers(
    int viewId,
    MapObjectUpdates<PlatformMarker> updates, {
    PlatformMarkerTransition? transition,
  }) async {
    markerUpdatesInFlight++;
    if (markerUpdatesInFlight > maxMarkerUpdatesInFlight) maxMarkerUpdatesInFlight = markerUpdatesInFlight;
    try {
      await markerUpdateGate?.call();
      markerUpdates.add(updates);
      markerTransitions.add(transition);
      _apply(markers, updates);
    } finally {
      markerUpdatesInFlight--;
    }
  }

  @override
  bool get supportsFlutterMapLayers => flutterMapLayersSupported;

  @override
  void setFlutterMapLayers(int viewId, List<Widget> layers) {
    if (!flutterMapLayersSupported) throw StateError('setFlutterMapLayers called on a native platform');
    flutterMapLayerCalls.add(layers);
  }

  @override
  Future<void> updatePolylines(int viewId, MapObjectUpdates<PlatformPolyline> updates) async {
    await shapeUpdateGate?.call();
    polylineUpdates.add(updates);
    _apply(polylines, updates);
  }

  @override
  Future<void> updatePolygons(int viewId, MapObjectUpdates<PlatformPolygon> updates) async {
    await shapeUpdateGate?.call();
    polygonUpdates.add(updates);
    _apply(polygons, updates);
  }

  @override
  Future<void> updateCircles(int viewId, MapObjectUpdates<PlatformCircle> updates) async {
    await shapeUpdateGate?.call();
    circleUpdates.add(updates);
    _apply(circles, updates);
  }

  @override
  Future<void> updateTileLayers(int viewId, MapObjectUpdates<PlatformTileLayer> updates) async {
    await shapeUpdateGate?.call();
    tileLayerUpdates.add(updates);
    _apply(tileLayers, updates);
  }

  @override
  Future<void> moveCamera(int viewId, PlatformCameraUpdate update, {Duration? animation}) async {
    if (moveCameraError case final error?) throw error;
    cameraMoves.add(MoveCameraCall(viewId, update, animation));
  }

  void _apply<T extends PlatformMapObject>(Map<String, T> target, MapObjectUpdates<T> updates) {
    for (final id in updates.removedIds) {
      target.remove(id);
    }
    for (final object in [...updates.added, ...updates.changed]) {
      target[object.id] = object;
    }
  }
}
