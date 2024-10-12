import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_unified_map_flutter_map/src/camera_animator.dart';
import 'package:flutter_unified_map_flutter_map/src/camera_math.dart';
import 'package:flutter_unified_map_flutter_map/src/layers/marker_layer.dart';
import 'package:flutter_unified_map_flutter_map/src/layers/z_ordered_layers.dart';
import 'package:flutter_unified_map_flutter_map/src/map_options_builder.dart';
import 'package:flutter_unified_map_flutter_map/src/movement_tracker.dart';
import 'package:flutter_unified_map_flutter_map/src/view_entry.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    as platform
    show Offset;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

/// Draws the view of [entry]; its options are `entry.options`, which `buildView` sets before the widget exists.
class FlutterMapView extends StatefulWidget {
  const FlutterMapView({super.key, required this.entry});

  final ViewEntry entry;

  @override
  State<FlutterMapView> createState() => FlutterMapViewState();
}

const _nonGestureSources = {
  MapEventSource.mapController,
  MapEventSource.custom,
  MapEventSource.fitCamera,
  MapEventSource.nonRotatedSizeChange,
  MapEventSource.interactiveFlagsChanged,
};

class FlutterMapViewState extends State<FlutterMapView> with TickerProviderStateMixin implements ViewHost {
  final _controller = MapController();
  final _boundaryKey = GlobalKey();
  late final CameraAnimator _animator;
  late final MovementTracker _tracker;
  final _snapshotExclusions = SnapshotExclusions();
  bool _ready = false;
  late PlatformMapOptions _applied;

  ViewEntry get _entry => widget.entry;

  int get _viewId => _entry.viewId;

  PlatformMapOptions get _options => _entry.options.value!;

  EdgeInsets get _padding => _options.padding;

  MapCamera get _mapCamera => _controller.camera;

  PlatformCamera get _camera => toPlatformCamera(_mapCamera, _padding);

  @override
  void initState() {
    super.initState();
    _animator = CameraAnimator(vsync: this, controller: _controller);
    _tracker = MovementTracker(viewId: _viewId, emit: _entry.emit, currentCamera: () => _camera);
    _applied = _options;
    _attach(_entry);
  }

  void _attach(ViewEntry entry) {
    entry.attach(this);
    entry.markers.attach(this);
    entry.options.addListener(_onOptionsChanged);
  }

  void _detach(ViewEntry entry) {
    entry.options.removeListener(_onOptionsChanged);
    if (!entry.isReleased) entry.markers.detach(this);
    entry.detach(this);
  }

  @override
  void didUpdateWidget(FlutterMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entry, widget.entry)) {
      _detach(oldWidget.entry);
      _attach(widget.entry);
    }
  }

  @override
  void dispose() {
    _animator.dispose();
    if (_ready) _tracker.settleNow();
    _detach(_entry);
    _tracker.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  bool get isReady => _ready && mounted;

  @override
  Future<void> moveCamera(PlatformCameraUpdate update, {Duration? animation}) async {
    final target = resolveCameraUpdate(_mapCamera, update, _padding);
    final token = _tracker.beginProgrammatic();
    if (animation == null || animation <= Duration.zero) {
      _animator.interrupt();
      _controller.moveAndRotate(target.center, target.zoom, target.rotation);
      _tracker.endProgrammatic(token);
      return;
    }
    await _animator.animate(CameraTarget.of(_mapCamera), target, animation);
    if (mounted) _tracker.endProgrammatic(token);
  }

  @override
  Future<Uint8List?> takeSnapshot() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    try {
      final pixelRatio = mounted ? MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0 : 1.0;
      final image = await _snapshotExclusions.capture(() => boundary.toImage(pixelRatio: pixelRatio));
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } catch (error, stack) {
      debugPrint('UnifiedMapsFlutterMap: snapshot of view $_viewId failed: $error\n$stack');
      return null;
    }
  }

  void _onMapReady() {
    if (!mounted) return;
    final last = _entry.lastCamera;
    if (last != null) _controller.moveAndRotate(last.center, last.zoom, last.rotation);
    _entry.lastCamera = _mapCamera;
    _ready = true;
    _entry.emitReadyOnce(_camera);
    _entry.loadMonitor.ready();
    _emitSize();
  }

  void _onOptionsChanged() {
    final options = _options;
    final previous = _applied;
    _applied = options;
    if (!_ready || !hasLayout(_mapCamera)) return;
    if (options.padding != previous.padding) _keepTarget(previous.padding);
    if (options.minZoom != previous.minZoom || options.maxZoom != previous.maxZoom) {
      // flutter_map takes the new range when the map rebuilds, without moving the camera into it.
      SchedulerBinding.instance.addPostFrameCallback((_) => _clampZoom());
    }
  }

  /// Like Google's `setPadding`, a padding change keeps the camera target (that of a running animation too) and
  /// shifts the content instead.
  void _keepTarget(EdgeInsets previous) {
    final padding = _padding;
    final animated = _animator.target;
    if (animated != null) {
      final end = _mapCamera.withPosition(center: animated.center, zoom: animated.zoom).withRotation(animated.rotation);
      final target = toPlatformCamera(end, previous).center;
      _animator.retarget(
        CameraTarget(
          center: viewCenterFor(_mapCamera, target, animated.zoom, animated.rotation, padding),
          zoom: animated.zoom,
          rotation: animated.rotation,
        ),
      );
      return;
    }
    final center = toPlatformCamera(_mapCamera, previous).center;
    runOutsideBuild(() {
      if (isReady) unawaited(moveCamera(PlatformCameraUpdate.newCamera(center: center)));
    });
  }

  void _clampZoom() {
    if (!isReady) return;
    final zoom = _mapCamera.zoom;
    final clamped = zoom.clamp(_options.minZoom, _options.maxZoom);
    if (clamped != zoom) unawaited(moveCamera(PlatformCameraUpdate.newCamera(zoom: clamped)));
  }

  void _onTap(TapPosition tapPosition, LatLng point) =>
      _entry.emit(PlatformMapTapEvent(_viewId, point, _screenPoint(tapPosition, point)));

  void _onLongPress(TapPosition tapPosition, LatLng point) =>
      _entry.emit(PlatformMapLongPressEvent(_viewId, point, _screenPoint(tapPosition, point)));

  void _onMarkerTap(String markerId) => _entry.emit(PlatformMarkerTapEvent(_viewId, markerId));

  void _onMapEvent(MapEvent event) {
    if (!_ready) return;
    // The controller's camera, not the event's: the size change that follows a move in onMapReady carries a camera
    // from before that move.
    if (event is MapEventWithMove) _entry.lastCamera = _mapCamera;
    final byGesture = !_nonGestureSources.contains(event.source);
    switch (event) {
      case MapEventNonRotatedSizeChange():
        _emitSize();
      case MapEventWithMove():
        if (byGesture && _animator.isAnimating) {
          _animator.interrupt();
          _tracker.onInputInterrupted();
        }
        _tracker.onMoved(byGesture: byGesture);
      case MapEventMoveStart() || MapEventRotateStart() when byGesture:
        _animator.interrupt();
        _tracker.onGestureStarted();
      case MapEventDoubleTapZoomStart() when byGesture:
        _animator.interrupt();
      case MapEventMoveEnd() || MapEventRotateEnd():
        _tracker.onGestureReleased();
      case MapEventFlingAnimationEnd() || MapEventFlingAnimationNotStarted() || MapEventDoubleTapZoomEnd():
        _tracker.onGestureEnded();
      default:
        break;
    }
  }

  void _emitSize() {
    if (hasLayout(_mapCamera)) _entry.reportSize(_mapCamera.nonRotatedSize);
  }

  platform.Offset _screenPoint(TapPosition tapPosition, LatLng point) {
    final relative = tapPosition.relative ?? _mapCamera.latLngToScreenOffset(point);
    return platform.Offset(relative.dx, relative.dy);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PlatformMapOptions?>(
    valueListenable: _entry.options,
    builder: (context, value, _) {
      final options = value!;
      return RepaintBoundary(
        key: _boundaryKey,
        child: FlutterMap(
          mapController: _controller,
          options: buildMapOptions(
            options,
            onTap: _onTap,
            onLongPress: _onLongPress,
            onMapEvent: _onMapEvent,
            onMapReady: _onMapReady,
          ),
          children: [
            ListenableBuilder(
              listenable: _entry.shapesAndTiles,
              builder: (_, _) => ZOrderedLayers(
                factory: _entry.tiles,
                style: options.style,
                tileLayers: _entry.tileLayers.value,
                polygons: _entry.polygons.value,
                polylines: _entry.polylines.value,
                circles: _entry.circles.value,
              ),
            ),
            ListenableBuilder(
              listenable: _entry.markers,
              builder: (_, _) => MarkerFramesLayer(
                frames: _entry.markers.frames(),
                exclusions: _snapshotExclusions,
                onTap: _onMarkerTap,
              ),
            ),
            ListenableBuilder(
              listenable: _entry.flutterMapLayers,
              builder: (_, _) => Stack(fit: StackFit.expand, children: _entry.flutterMapLayers.value),
            ),
          ],
        ),
      );
    },
  );
}
