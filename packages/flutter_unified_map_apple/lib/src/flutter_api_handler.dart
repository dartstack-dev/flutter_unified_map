import 'dart:typed_data';

import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

import 'conversions.dart';
import 'messages.g.dart';

/// Receives native events and hands them to [emit]; routing per view happens in the platform class.
class FlutterApiHandler implements UnifiedMapsFlutterApi {
  FlutterApiHandler(this.emit, this.tileLoader);

  final void Function(PlatformMapEvent event) emit;
  final PlatformTileLoader? Function(int viewId) tileLoader;

  @override
  void onMapReady(int viewId, PCamera camera, PSize size) {
    emit(PlatformMapReadyEvent(viewId, fromPCamera(camera)));
    emit(PlatformViewSizeEvent(viewId, size.width, size.height));
  }

  @override
  void onCameraMoveStarted(int viewId, bool byGesture) =>
      emit(PlatformCameraMoveStartedEvent(viewId, byGesture: byGesture));

  @override
  void onCameraMove(int viewId, PCamera camera) => emit(PlatformCameraMoveEvent(viewId, fromPCamera(camera)));

  @override
  void onCameraIdle(int viewId, PCamera camera) => emit(PlatformCameraIdleEvent(viewId, fromPCamera(camera)));

  @override
  void onTap(int viewId, PLatLng position, PPoint screenPoint) =>
      emit(PlatformMapTapEvent(viewId, fromPLatLng(position), fromPPoint(screenPoint)));

  @override
  void onLongPress(int viewId, PLatLng position, PPoint screenPoint) =>
      emit(PlatformMapLongPressEvent(viewId, fromPLatLng(position), fromPPoint(screenPoint)));

  @override
  void onMarkerTap(int viewId, String markerId) => emit(PlatformMarkerTapEvent(viewId, markerId));

  @override
  void onViewSize(int viewId, PSize size) => emit(PlatformViewSizeEvent(viewId, size.width, size.height));

  @override
  void onMapLoaded(int viewId) => emit(PlatformMapLoadedEvent(viewId));

  @override
  void onMapError(int viewId, PMapErrorCode code, String message) =>
      emit(PlatformMapErrorEvent(viewId, fromPMapErrorCode(code), message));

  @override
  void onSecondaryTap(int viewId, PLatLng position, PPoint screenPoint) =>
      emit(PlatformMapSecondaryTapEvent(viewId, fromPLatLng(position), fromPPoint(screenPoint)));

  @override
  void onMarkerDragStart(int viewId, String markerId, PLatLng position) =>
      emit(PlatformMarkerDragEvent(viewId, markerId, fromPLatLng(position), PlatformDragPhase.start));

  @override
  void onMarkerDrag(int viewId, String markerId, PLatLng position) =>
      emit(PlatformMarkerDragEvent(viewId, markerId, fromPLatLng(position), PlatformDragPhase.update));

  @override
  void onMarkerDragEnd(int viewId, String markerId, PLatLng position) =>
      emit(PlatformMarkerDragEvent(viewId, markerId, fromPLatLng(position), PlatformDragPhase.end));

  @override
  void onInfoWindowTap(int viewId, String markerId) => emit(PlatformInfoWindowTapEvent(viewId, markerId));

  @override
  void onMarkerHover(int viewId, String markerId, bool entered) =>
      emit(PlatformMarkerHoverEvent(viewId, markerId, entered: entered));

  @override
  void onTileError(int viewId, String tileLayerId, int z, int x, int y, String message) =>
      emit(PlatformTileErrorEvent(viewId, tileLayerId, z, x, y, message));

  @override
  Future<Uint8List?> loadTile(int viewId, String tileLayerId, int z, int x, int y) async {
    final loader = tileLoader(viewId);
    if (loader == null) return null;
    try {
      return await loader(tileLayerId, z, x, y);
    } catch (_) {
      return null;
    }
  }
}
