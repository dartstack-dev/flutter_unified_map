import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

import 'conversions.dart';
import 'messages.g.dart';

/// Receives the Pigeon Flutter API callbacks and fans them out to one broadcast stream per view.
class MapEventRelay implements UnifiedMapsFlutterApi {
  final Map<int, StreamController<PlatformMapEvent>> _controllers = {};
  final Map<int, PlatformTileLoader> _tileLoaders = {};

  Stream<PlatformMapEvent> events(int viewId) => _controller(viewId).stream;

  void setTileLoader(int viewId, PlatformTileLoader loader) => _tileLoaders[viewId] = loader;

  void close(int viewId) {
    _tileLoaders.remove(viewId);
    final controller = _controllers.remove(viewId);
    if (controller != null) {
      unawaited(controller.close());
    }
  }

  StreamController<PlatformMapEvent> _controller(int viewId) =>
      _controllers.putIfAbsent(viewId, StreamController<PlatformMapEvent>.broadcast);

  void _emit(PlatformMapEvent event) {
    final controller = _controllers[event.viewId];
    if (controller != null && !controller.isClosed) {
      controller.add(event);
    }
  }

  @override
  void onMapReady(int viewId, PCamera camera, PSize size) {
    _emit(PlatformMapReadyEvent(viewId, fromPCamera(camera)));
    _emit(PlatformViewSizeEvent(viewId, size.width, size.height));
  }

  @override
  void onCameraMoveStarted(int viewId, bool byGesture) =>
      _emit(PlatformCameraMoveStartedEvent(viewId, byGesture: byGesture));

  @override
  void onCameraMove(int viewId, PCamera camera) => _emit(PlatformCameraMoveEvent(viewId, fromPCamera(camera)));

  @override
  void onCameraIdle(int viewId, PCamera camera) => _emit(PlatformCameraIdleEvent(viewId, fromPCamera(camera)));

  @override
  void onTap(int viewId, PLatLng position, PPoint screenPoint) =>
      _emit(PlatformMapTapEvent(viewId, fromPLatLng(position), fromPPoint(screenPoint)));

  @override
  void onLongPress(int viewId, PLatLng position, PPoint screenPoint) =>
      _emit(PlatformMapLongPressEvent(viewId, fromPLatLng(position), fromPPoint(screenPoint)));

  @override
  void onMarkerTap(int viewId, String markerId) => _emit(PlatformMarkerTapEvent(viewId, markerId));

  @override
  void onViewSize(int viewId, PSize size) => _emit(PlatformViewSizeEvent(viewId, size.width, size.height));

  @override
  void onMapLoaded(int viewId) => _emit(PlatformMapLoadedEvent(viewId));

  @override
  void onMapError(int viewId, PMapErrorCode code, String message) =>
      _emit(PlatformMapErrorEvent(viewId, fromPMapErrorCode(code), message));

  @override
  void onSecondaryTap(int viewId, PLatLng position, PPoint screenPoint) =>
      _emit(PlatformMapSecondaryTapEvent(viewId, fromPLatLng(position), fromPPoint(screenPoint)));

  @override
  void onMarkerDragStart(int viewId, String markerId, PLatLng position) =>
      _emit(PlatformMarkerDragEvent(viewId, markerId, fromPLatLng(position), PlatformDragPhase.start));

  @override
  void onMarkerDrag(int viewId, String markerId, PLatLng position) =>
      _emit(PlatformMarkerDragEvent(viewId, markerId, fromPLatLng(position), PlatformDragPhase.update));

  @override
  void onMarkerDragEnd(int viewId, String markerId, PLatLng position) =>
      _emit(PlatformMarkerDragEvent(viewId, markerId, fromPLatLng(position), PlatformDragPhase.end));

  @override
  void onInfoWindowTap(int viewId, String markerId) => _emit(PlatformInfoWindowTapEvent(viewId, markerId));

  @override
  void onMarkerHover(int viewId, String markerId, bool entered) =>
      _emit(PlatformMarkerHoverEvent(viewId, markerId, entered: entered));

  @override
  void onTileError(int viewId, String tileLayerId, int z, int x, int y, String message) =>
      _emit(PlatformTileErrorEvent(viewId, tileLayerId, z, x, y, message));

  @override
  Future<Uint8List?> loadTile(int viewId, String tileLayerId, int z, int x, int y) async {
    final loader = _tileLoaders[viewId];
    if (loader == null) return null;
    try {
      return await loader(tileLayerId, z, x, y);
    } catch (_) {
      return null;
    }
  }
}
