import 'dart:typed_data';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer;
import 'package:flutter/painting.dart' as painting show Offset;
import 'package:flutter/widgets.dart' show ValueKey, Widget;
import 'package:flutter_unified_map_flutter_map/src/flutter_map_view.dart';
import 'package:flutter_unified_map_flutter_map/src/layers/tile_layers.dart';
import 'package:flutter_unified_map_flutter_map/src/registrar_stub.dart'
    if (dart.library.js_interop) 'package:flutter_web_plugins/flutter_web_plugins.dart'
    show Registrar;
import 'package:flutter_unified_map_flutter_map/src/view_entry.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

export 'package:flutter_unified_map_flutter_map/src/layers/tile_layers.dart'
    show TileProviderFactory, defaultTileProvider;

/// The `flutter_unified_map` implementation drawn with [flutter_map](https://pub.dev/packages/flutter_map): the
/// default on web, Windows and Linux, and the backend of widget tests.
///
/// It is registered automatically. To configure it, install your own instance before `runApp`:
///
/// ```dart
/// UnifiedMapsPlatform.instance = UnifiedMapsFlutterMap(userAgentPackageName: 'com.example.app');
/// ```
class UnifiedMapsFlutterMap extends UnifiedMapsPlatform {
  /// Installs a default instance as [UnifiedMapsPlatform.instance]; called by the Flutter plugin registrant.
  static void registerWith([Registrar? registrar]) {
    UnifiedMapsPlatform.instance = UnifiedMapsFlutterMap();
  }

  /// [tileProvider] creates the provider of every tile layer; [userAgentPackageName] identifies the app to the tile
  /// servers (flutter_map's `TileLayer.userAgentPackageName`).
  UnifiedMapsFlutterMap({
    this.tileProvider = defaultTileProvider,
    this.userAgentPackageName = defaultUserAgentPackageName,
  });

  /// Creates the provider of every tile layer, the built-in base map included. Defaults to flutter_map's
  /// `NetworkTileProvider` with the layer's headers; replace it to add caching or to serve tiles offline.
  final TileProviderFactory tileProvider;

  /// Sent as `User-Agent: flutter_map (<userAgentPackageName>)` on Windows and Linux (browsers send their own). The
  /// OpenStreetMap tile policy asks every app to identify itself: set it to your app's package name. With the
  /// default (`unknown`) flutter_map warns in debug builds.
  final String userAgentPackageName;

  final _views = <int, ViewEntry>{};

  /// What a disposed view still answers: its last camera, or its initial camera if it never became ready.
  final _disposed = <int, ({CameraSnapshot? snapshot, PlatformCamera? initialCamera})>{};

  ViewEntry? _entry(int viewId) {
    if (_disposed.containsKey(viewId)) return null;
    return _views.putIfAbsent(
      viewId,
      () => ViewEntry(viewId, tileProvider: tileProvider, userAgentPackageName: userAgentPackageName),
    );
  }

  ViewHost? _host(int viewId) => _views[viewId]?.readyHost;

  CameraSnapshot? _snapshot(int viewId) => _views[viewId]?.queries ?? _disposed[viewId]?.snapshot;

  CameraSnapshot _queries(int viewId) =>
      _snapshot(viewId) ?? (throw StateError('UnifiedMapsFlutterMap: view $viewId is not ready yet'));

  @override
  Widget buildView({
    required int viewId,
    required PlatformMapOptions options,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  }) {
    final entry = _entry(viewId);
    if (entry == null) throw StateError('UnifiedMapsFlutterMap: view $viewId was disposed');
    entry.options.value ??= options;
    return FlutterMapView(key: ValueKey(viewId), entry: entry);
  }

  @override
  Future<void> dispose(int viewId) async {
    if (_disposed.containsKey(viewId)) return;
    final entry = _views.remove(viewId);
    _disposed[viewId] = (snapshot: entry?.queries, initialCamera: entry?.options.value?.initialCamera);
    entry?.dispose();
  }

  @override
  Future<void> updateOptions(int viewId, PlatformMapOptions options) async {
    _entry(viewId)?.options.value = options;
  }

  @override
  Future<void> updateMarkers(
    int viewId,
    MapObjectUpdates<PlatformMarker> updates, {
    PlatformMarkerTransition? transition,
  }) async => _entry(viewId)?.markers.apply(updates, transition: transition);

  @override
  bool get supportsFlutterMapLayers => true;

  /// The widgets are children of one `Stack`, matched to the previous list by key: the core keys each layer's widgets
  /// by layer id and position, so a stateful layer keeps its state when a layer before it is added or removed.
  @override
  void setFlutterMapLayers(int viewId, List<Widget> layers) => _entry(viewId)?.flutterMapLayers.value = layers;

  @override
  Future<void> updatePolylines(int viewId, MapObjectUpdates<PlatformPolyline> updates) async =>
      _entry(viewId)?.polylines.apply(updates);

  @override
  Future<void> updatePolygons(int viewId, MapObjectUpdates<PlatformPolygon> updates) async =>
      _entry(viewId)?.polygons.apply(updates);

  @override
  Future<void> updateCircles(int viewId, MapObjectUpdates<PlatformCircle> updates) async =>
      _entry(viewId)?.circles.apply(updates);

  @override
  Future<void> updateTileLayers(int viewId, MapObjectUpdates<PlatformTileLayer> updates) async =>
      _entry(viewId)?.tileLayers.apply(updates);

  // Contract stubs (see AGENTS.md): accepted and ignored until the flutter_map unit implements them.
  @override
  Future<void> updateGroundOverlays(int viewId, MapObjectUpdates<PlatformGroundOverlay> updates) async {}

  @override
  Future<void> resetTileLayer(int viewId, String tileLayerId) async {}

  @override
  void setTileLoader(int viewId, PlatformTileLoader loader) {}

  @override
  Future<void> stopCamera(int viewId) async {}

  @override
  Future<void> moveCamera(int viewId, PlatformCameraUpdate update, {Duration? animation}) async =>
      _host(viewId)?.moveCamera(update, animation: animation);

  @override
  Future<PlatformCamera> getCamera(int viewId) async =>
      _snapshot(viewId)?.camera ??
      _views[viewId]?.options.value?.initialCamera ??
      _disposed[viewId]?.initialCamera ??
      (throw StateError('UnifiedMapsFlutterMap: view $viewId is not ready yet'));

  @override
  Future<PlatformLatLngBounds> getVisibleRegion(int viewId) async => _queries(viewId).visibleRegion;

  @override
  Future<Offset> toScreen(int viewId, LatLng position) async {
    final point = _queries(viewId).toScreen(position);
    return Offset(point.dx, point.dy);
  }

  @override
  Future<LatLng> toLatLng(int viewId, Offset screenPoint) async =>
      _queries(viewId).toLatLng(painting.Offset(screenPoint.dx, screenPoint.dy));

  @override
  Future<Uint8List?> takeSnapshot(int viewId) async => _host(viewId)?.takeSnapshot();

  @override
  Stream<PlatformMapEvent> events(int viewId) => _entry(viewId)?.events ?? const Stream.empty();
}
