import 'dart:typed_data';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer;
import 'package:flutter/widgets.dart' show Widget;
import 'package:latlong2/latlong.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'types/map_object_updates.dart';
import 'types/platform_camera.dart';
import 'types/platform_circle.dart';
import 'types/platform_ground_overlay.dart';
import 'types/platform_map_event.dart';
import 'types/platform_map_options.dart';
import 'types/platform_marker.dart';
import 'types/platform_marker_transition.dart';
import 'types/platform_polygon.dart';
import 'types/platform_polyline.dart';
import 'types/platform_tile_layer.dart';

/// Bytes (PNG or JPEG) of tile [z]/[x]/[y] of the tile layer [tileLayerId], in the tile grid the layer declares
/// (after `zoomOffset`, `zoomReverse` and `tms`), or null when it cannot be loaded.
typedef PlatformTileLoader = Future<Uint8List?> Function(String tileLayerId, int z, int x, int y);

/// The interface every platform implements. The core (`flutter_unified_map`) owns the view ids: it passes a fresh
/// [viewId] to [buildView] and uses it in every later call. Implementations must accept calls for a view only
/// after they emitted [PlatformMapReadyEvent] for it, and must ignore calls for disposed views.
///
/// Object updates are declarative diffs ([MapObjectUpdates]); the platform keeps its own id → native object map.
/// Every update of one kind is applied in call order for a view.
abstract class UnifiedMapsPlatform extends PlatformInterface {
  UnifiedMapsPlatform() : super(token: _token);

  static final Object _token = Object();

  static UnifiedMapsPlatform? _instance;

  static UnifiedMapsPlatform get instance {
    final instance = _instance;
    if (instance == null) {
      throw StateError(
        'UnifiedMapsPlatform.instance is not set: no platform implementation registered for this platform.',
      );
    }
    return instance;
  }

  static set instance(UnifiedMapsPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Builds the widget hosting the native map for [viewId] with [options].
  /// The core stacks Flutter widgets above it, so the platform view must not consume the whole gesture arena:
  /// pass [gestureRecognizers] through to the platform view.
  Widget buildView({
    required int viewId,
    required PlatformMapOptions options,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  }) {
    throw UnimplementedError('buildView() has not been implemented.');
  }

  /// Releases native resources. No further calls or events for [viewId].
  Future<void> dispose(int viewId) {
    throw UnimplementedError('dispose() has not been implemented.');
  }

  /// Applies every changed option except `initialCamera`.
  Future<void> updateOptions(int viewId, PlatformMapOptions options) {
    throw UnimplementedError('updateOptions() has not been implemented.');
  }

  /// Applies [updates] in call order: an implementation must not let a later update overtake an earlier one for the
  /// same view (e.g. while icons of the earlier one are still being registered). With [transition] the update is
  /// animated (see [PlatformMarkerTransition]); the future completes once the update is applied, not when the
  /// animation ends.
  Future<void> updateMarkers(
    int viewId,
    MapObjectUpdates<PlatformMarker> updates, {
    PlatformMarkerTransition? transition,
  }) {
    throw UnimplementedError('updateMarkers() has not been implemented.');
  }

  Future<void> updatePolylines(int viewId, MapObjectUpdates<PlatformPolyline> updates) {
    throw UnimplementedError('updatePolylines() has not been implemented.');
  }

  Future<void> updatePolygons(int viewId, MapObjectUpdates<PlatformPolygon> updates) {
    throw UnimplementedError('updatePolygons() has not been implemented.');
  }

  Future<void> updateCircles(int viewId, MapObjectUpdates<PlatformCircle> updates) {
    throw UnimplementedError('updateCircles() has not been implemented.');
  }

  Future<void> updateTileLayers(int viewId, MapObjectUpdates<PlatformTileLayer> updates) {
    throw UnimplementedError('updateTileLayers() has not been implemented.');
  }

  /// Images pinned to the ground (flutter_map's `OverlayImageLayer`). Each [PlatformGroundOverlay.image] is
  /// registered once per key before the overlays that use it, like marker icons.
  Future<void> updateGroundOverlays(int viewId, MapObjectUpdates<PlatformGroundOverlay> updates) {
    throw UnimplementedError('updateGroundOverlays() has not been implemented.');
  }

  /// Drops every cached tile of the tile layer [tileLayerId] and loads the visible ones again (flutter_map's
  /// `TileLayer.reset`): Google `TileOverlay.clearTileCache()`, MapKit `MKTileOverlayRenderer.reloadData()`.
  Future<void> resetTileLayer(int viewId, String tileLayerId) {
    throw UnimplementedError('resetTileLayer() has not been implemented.');
  }

  /// The loader of the view's [PlatformTileLayer.dartProvided] tiles. The core sets it before sending such a layer;
  /// the platform calls it from its tile requests and treats null (or an error) as a failed tile.
  void setTileLoader(int viewId, PlatformTileLoader loader) {
    throw UnimplementedError('setTileLoader() has not been implemented.');
  }

  /// Moves the camera; with [animation] the platform animates and the future completes when the animation
  /// ends or is interrupted. Without it the move is instant. Both produce [PlatformCameraMoveStartedEvent]
  /// (`byGesture: false`), at least one [PlatformCameraMoveEvent] when the camera changed, then
  /// [PlatformCameraIdleEvent]; the core turns them into flutter_map's events (an instant controller move is a single
  /// `MapEventMove`, emitted by the core when the call is made).
  ///
  /// A user gesture during an animation stops it: idle for the animation, then the gesture's own start (see
  /// [PlatformCameraMoveStartedEvent]). A new `moveCamera` during an animation replaces it the same way (idle, then
  /// the new move's start).
  Future<void> moveCamera(int viewId, PlatformCameraUpdate update, {Duration? animation}) {
    throw UnimplementedError('moveCamera() has not been implemented.');
  }

  /// Stops a running camera animation or fling where the camera is now (Google `GoogleMap.stopAnimation()`, MapKit
  /// `setCamera(mapView.camera, animated: false)`, flutter_map: the backend's animator), then sends
  /// [PlatformCameraIdleEvent]. Does nothing when the camera is still.
  Future<void> stopCamera(int viewId) {
    throw UnimplementedError('stopCamera() has not been implemented.');
  }

  Future<PlatformCamera> getCamera(int viewId) {
    throw UnimplementedError('getCamera() has not been implemented.');
  }

  Future<PlatformLatLngBounds> getVisibleRegion(int viewId) {
    throw UnimplementedError('getVisibleRegion() has not been implemented.');
  }

  /// Native projection, for exactness when the Dart projection is not enough (tilted camera).
  Future<Offset> toScreen(int viewId, LatLng position) {
    throw UnimplementedError('toScreen() has not been implemented.');
  }

  Future<LatLng> toLatLng(int viewId, Offset screenPoint) {
    throw UnimplementedError('toLatLng() has not been implemented.');
  }

  /// PNG of the current map, or null when the platform cannot snapshot.
  Future<Uint8List?> takeSnapshot(int viewId) {
    throw UnimplementedError('takeSnapshot() has not been implemented.');
  }

  /// Whether this platform draws the map with flutter_map, so that flutter_map layer widgets (for instance
  /// flutter_map_marker_cluster's `MarkerClusterLayerWidget`) can be drawn inside it. Native backends return false.
  bool get supportsFlutterMapLayers => false;

  /// flutter_map layer widgets to draw inside the view's `FlutterMap`, above the platform's own objects, in list
  /// order. They see flutter_map's `MapCamera.of` / `MapController.of`. Called only when [supportsFlutterMapLayers];
  /// replaces the previous list.
  void setFlutterMapLayers(int viewId, List<Widget> layers) {
    throw UnimplementedError('setFlutterMapLayers() has not been implemented.');
  }

  /// Broadcast stream of events for [viewId], starting with [PlatformMapReadyEvent], or with a
  /// [PlatformMapErrorEvent] when the native map cannot be created at all (then no ready event follows).
  Stream<PlatformMapEvent> events(int viewId) {
    throw UnimplementedError('events() has not been implemented.');
  }
}
