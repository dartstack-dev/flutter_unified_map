import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' show TapPosition;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

import '../raster/icon_cache.dart';
import 'camera/camera_math.dart';
import 'camera/map_camera.dart';
import 'controller/map_controller.dart';
import 'controller/map_controller_impl.dart';
import 'conversions.dart';
import 'error/map_error.dart';
import 'error/map_error_view.dart';
import 'events/map_events.dart';
import 'inherited_model.dart';
import 'layer_registry.dart';
import 'map_layer_host.dart';
import 'options/map_options.dart';
import 'report_error.dart';

/// flutter_map's name for [UnifiedMap], so that `FlutterMap(options: ..., children: [...])` compiles unchanged.
typedef FlutterMap = UnifiedMap;

/// The map. Same shape as flutter_map's `FlutterMap` (also available under that name), plus [errorBuilder].
///
/// [children] mixes layers (`MarkerLayer`, `PolylineLayer`, `PolygonLayer`, `CircleLayer`, `TileLayer`,
/// `FlutterMapLayer`, and layers of other packages built on `package:flutter_unified_map/plugin_api.dart`, such as
/// `flutter_unified_map_marker_cluster`), which register their objects with the native view, and any other widget,
/// which is drawn above the map in a `Stack` in the same order. As in flutter_map, the order of [children] is the
/// layers' z-order: a layer later in the list is drawn above the ones before it.
///
/// Objects are diffed and pushed to the platform once per frame after it reported ready; marker widgets are
/// rasterised once per icon key, and again when the theme, the text scale or the brightness changes. Platform events
/// become [MapEvent]s on the controller's stream and the [MapOptions] callbacks, and keep [MapCamera.of] current.
///
/// [mapController] must be created with `MapController()`; other implementations of [MapController] are not
/// supported.
///
/// When the platform reports a [MapError] (e.g. no Google Maps API key on Android), [errorBuilder] is drawn above
/// the map and its children; it defaults to [MapErrorView]. Return `SizedBox.shrink()` to show nothing.
class UnifiedMap extends StatefulWidget {
  final MapController? mapController;
  final MapOptions options;
  final List<Widget> children;
  final Widget Function(BuildContext context, MapError error)? errorBuilder;

  const UnifiedMap({
    super.key,
    this.mapController,
    this.options = const MapOptions(),
    required this.children,
    this.errorBuilder,
  });

  @override
  State<UnifiedMap> createState() => _UnifiedMapState();
}

class _UnifiedMapState extends State<UnifiedMap>
    with AutomaticKeepAliveClientMixin<UnifiedMap>
    implements MapLayerHost, MapControllerHost {
  static int _nextViewId = 0;

  final int _viewId = _nextViewId++;
  @override
  late final LayerRegistry registry = LayerRegistry(onChanged: _scheduleFlush);
  @override
  final IconCache icons = IconCache();
  final _idleCamera = ValueNotifier<MapCamera?>(null);
  late final ValueNotifier<MapCamera> _liveCamera = ValueNotifier(_camera);

  MapControllerImpl? _ownController;
  late MapControllerImpl _driver;
  late MapCamera _camera;
  late PlatformMapOptions _platformOptions;
  late PlatformMapOptions _appliedOptions;
  late final Widget _platformView;
  StreamSubscription<PlatformMapEvent>? _subscription;

  double _pixelRatio = 1;
  Object? _appearance;
  bool _ready = false;
  bool _disposed = false;
  bool _flushScheduled = false;
  MapError? _error;
  bool _loadedOnce = false;

  bool _moving = false;
  bool _moveByGesture = false;
  MapEventSource _moveSource = MapEventSource.mapController;
  String? _moveId;

  /// Id of the last programmatic move not started yet: it tags that move's events, then is consumed by its start.
  String? _pendingId;

  UnifiedMapsPlatform get _platform => UnifiedMapsPlatform.instance;

  MapController get _controller => widget.mapController ?? _ownController!;

  @override
  MapCamera get camera => _camera;

  @override
  MapController get controller => _controller;

  @override
  double get pixelRatio => _pixelRatio;

  @override
  bool get isReady => _ready && !_disposed;

  @override
  ValueListenable<MapCamera?> get idleCamera => _idleCamera;

  @override
  ValueListenable<MapCamera> get liveCamera => _liveCamera;

  @override
  bool get supportsFlutterMapLayers => _platform.supportsFlutterMapLayers;

  @override
  bool get wantKeepAlive => widget.options.keepAlive;

  @override
  void initState() {
    super.initState();
    final options = widget.options;
    _camera = MapCamera(
      crs: options.crs,
      center: options.initialCenter,
      zoom: options.initialZoom,
      rotation: options.initialRotation,
      minZoom: options.minZoom,
      maxZoom: options.maxZoom,
      nonRotatedSize: Size.zero,
    );
    _bindController();
    _platformOptions = _appliedOptions = toPlatformOptions(options, flutterMap: _platform.supportsFlutterMapLayers);
    _subscription = _platform.events(_viewId).listen(_onEvent);
    _platformView = _platform.buildView(
      viewId: _viewId,
      options: _platformOptions,
      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)},
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? View.of(context).devicePixelRatio;
    final appearance = _appearanceOf(context);
    if (_appearance != null && appearance != _appearance) icons.clear();
    _appearance = appearance;
  }

  /// What rasterised icons may depend on: the themes captured from this context, the text scale and brightness.
  static Object _appearanceOf(BuildContext context) => (
    Theme.of(context),
    IconTheme.of(context),
    DefaultTextStyle.of(context).style,
    Directionality.maybeOf(context),
    MediaQuery.maybePlatformBrightnessOf(context),
    MediaQuery.maybeTextScalerOf(context),
  );

  @override
  void didUpdateWidget(UnifiedMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mapController != widget.mapController) {
      _driver.detach(this);
      _bindController();
    }
    final options = widget.options;
    final old = oldWidget.options;
    if (options.minZoom != old.minZoom || options.maxZoom != old.maxZoom || options.crs != old.crs) {
      _camera = _camera.withOptions(options);
      _publishLiveCamera();
    }
    if (options != old) {
      _platformOptions = toPlatformOptions(options, flutterMap: _platform.supportsFlutterMapLayers);
      _applyOptions();
    }
    if (options.keepAlive != old.keepAlive) updateKeepAlive();
    if (!listEquals(oldWidget.children, widget.children)) registry.markOrderStale();
  }

  void _bindController() {
    final external = widget.mapController;
    assert(
      external == null || external is MapControllerImpl,
      'UnifiedMap.mapController must be created with MapController(); other implementations are not supported.',
    );
    if (external is MapControllerImpl) {
      _ownController?.dispose();
      _ownController = null;
      _driver = external;
    } else {
      _driver = _ownController ??= MapControllerImpl();
    }
    _driver.attach(this);
  }

  void _applyOptions() {
    if (!isReady) return;
    final next = _platformOptions.copyWith(initialCamera: _appliedOptions.initialCamera);
    if (next == _appliedOptions) return;
    final previous = _appliedOptions;
    _appliedOptions = next;
    _platform.updateOptions(_viewId, next).catchError((Object error, StackTrace stack) {
      if (identical(_appliedOptions, next)) _appliedOptions = previous;
      reportMapError(error, stack, 'while updating the options of a UnifiedMap');
    });
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    _driver.detach(this);
    _ownController?.dispose();
    _idleCamera.dispose();
    _liveCamera.dispose();
    icons.clear();
    try {
      unawaited(_platform.dispose(_viewId).catchError((Object _) {}));
    } on UnimplementedError {
      // Platforms without native resources may not implement dispose.
    }
    super.dispose();
  }

  void _onEvent(PlatformMapEvent event) {
    if (!mounted || _disposed) return;
    switch (event) {
      case PlatformMapReadyEvent(:final camera):
        _onReady(camera);
      case PlatformCameraMoveStartedEvent(:final byGesture):
        if (_moving) _emit(MapEventMoveEnd(source: _moveSource, camera: _camera));
        _moving = true;
        _moveByGesture = byGesture;
        _moveSource = byGesture ? MapEventSource.onDrag : MapEventSource.mapController;
        _moveId = byGesture ? null : _pendingId;
        if (!byGesture) _pendingId = null;
        _emit(MapEventMoveStart(source: _moveSource, camera: _camera));
      case PlatformCameraMoveEvent(:final camera):
        _onCamera(camera, idle: false);
      case PlatformCameraIdleEvent(:final camera):
        _onCamera(camera, idle: true);
      case PlatformMapTapEvent(:final position, :final screenPoint):
        final point = Offset(screenPoint.dx, screenPoint.dy);
        registry.hitTest(_camera, position, point);
        _emit(MapEventTap(tapPosition: position, source: MapEventSource.tap, camera: _camera));
        widget.options.onTap?.call(_tapPosition(point), position);
      case PlatformMapLongPressEvent(:final position, :final screenPoint):
        final point = Offset(screenPoint.dx, screenPoint.dy);
        registry.hitTest(_camera, position, point);
        _emit(MapEventLongPress(tapPosition: position, source: MapEventSource.longPress, camera: _camera));
        widget.options.onLongPress?.call(_tapPosition(point), position);
      case PlatformMarkerTapEvent(:final markerId):
        registry.handleMarkerTap(markerId);
      case PlatformMapSecondaryTapEvent() ||
          PlatformMarkerDragEvent() ||
          PlatformInfoWindowTapEvent() ||
          PlatformMarkerHoverEvent() ||
          PlatformTileErrorEvent():
        break;
      case PlatformViewSizeEvent():
        break;
      case PlatformMapLoadedEvent():
        _loadedOnce = true;
        if (_error?.isLoadError ?? false) setState(() => _error = null);
        widget.options.onMapLoaded?.call();
      case PlatformMapErrorEvent(:final code, :final message):
        final error = MapError(_errorCode(code), message);
        if (error != _error) setState(() => _error = error);
        widget.options.onMapError?.call(error);
    }
  }

  void _onReady(PlatformCamera platformCamera) {
    final first = !_ready;
    _ready = true;
    setState(() => _camera = _fromPlatform(platformCamera));
    _liveCamera.value = _camera;
    _idleCamera.value = _camera;
    if (!first) return;
    _applyOptions();
    final fit = widget.options.initialCameraFit;
    if (fit != null) _driver.fitCamera(fit);
    registry.markAllDirty();
    _flush();
    widget.options.onMapReady?.call();
  }

  void _onCamera(PlatformCamera platformCamera, {required bool idle}) {
    final next = _fromPlatform(platformCamera);
    final old = _camera;
    if (next != old) {
      final hasGesture = _moving && _moveByGesture;
      final source = !_moving
          ? MapEventSource.mapController
          : hasGesture && (next.zoom != old.zoom || next.rotation != old.rotation)
          ? MapEventSource.onMultiFinger
          : _moveSource;
      final id = _moving ? _moveId : _pendingId;
      setState(() => _camera = next);
      _liveCamera.value = next;
      final rotateOnly = next.rotation != old.rotation && next.center == old.center && next.zoom == old.zoom;
      _emit(
        rotateOnly
            ? MapEventRotate(id: id, source: source, oldCamera: old, camera: next)
            : MapEventMove(id: id, source: source, oldCamera: old, camera: next),
      );
      widget.options.onPositionChanged?.call(next, hasGesture);
    }
    if (!idle) return;
    if (_moving) {
      _emit(MapEventMoveEnd(source: _moveSource, camera: next));
    } else {
      _pendingId = null;
    }
    _moving = false;
    _moveId = null;
    _idleCamera.value = next;
  }

  void _emit(MapEvent event) {
    _driver.emit(event);
    widget.options.onMapEvent?.call(event);
  }

  TapPosition _tapPosition(Offset relative) {
    final box = context.findRenderObject();
    final global = box is RenderBox && box.hasSize ? box.localToGlobal(relative) : relative;
    return TapPosition(global, relative);
  }

  MapCamera _fromPlatform(PlatformCamera camera) => _camera.copyWith(
    center: camera.center,
    zoom: camera.zoom,
    rotation: rotationFromBearing(camera.bearing, near: _camera.rotation),
  );

  static MapErrorCode _errorCode(PlatformMapErrorCode code) => switch (code) {
    PlatformMapErrorCode.apiKeyMissing => MapErrorCode.apiKeyMissing,
    PlatformMapErrorCode.servicesUnavailable => MapErrorCode.servicesUnavailable,
    PlatformMapErrorCode.loadTimeout => MapErrorCode.loadTimeout,
    PlatformMapErrorCode.loadFailed => MapErrorCode.loadFailed,
    PlatformMapErrorCode.unknown => MapErrorCode.unknown,
  };

  @override
  Future<Uint8List?> takeSnapshot() async {
    if (!isReady) return null;
    try {
      return await _platform.takeSnapshot(_viewId);
    } on UnimplementedError {
      return null;
    } catch (error, stack) {
      reportMapError(error, stack, 'while taking a snapshot of a UnifiedMap');
      return null;
    }
  }

  @override
  Future<void> moveCamera(PlatformCameraUpdate update, {Duration? animation, String? id}) {
    if (!isReady) return Future.value();
    _pendingId = id;
    return _platform.moveCamera(_viewId, update, animation: animation);
  }

  @override
  void stopCamera() {
    if (!isReady) return;
    _platform.stopCamera(_viewId).catchError((Object error, StackTrace stack) {
      if (error is! UnimplementedError) reportMapError(error, stack, 'while stopping the camera');
    });
  }

  void _scheduleFlush() {
    if (_flushScheduled || _disposed) return;
    _flushScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      _flush();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _flush() {
    if (!isReady || !registry.isDirty) return;
    registry.pushTo(_platform, _viewId);
  }

  void _onSize(Size size) {
    final old = _camera;
    if (old.nonRotatedSize == size) return;
    _camera = old.copyWith(nonRotatedSize: size);
    final changed = _camera;
    _publishLiveCamera();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed || old.nonRotatedSize == Size.zero) return;
      _emit(MapEventNonRotatedSizeChange(source: MapEventSource.nonRotatedSizeChange, oldCamera: old, camera: changed));
    });
  }

  /// Updates [liveCamera] after the frame: called while building, where its listeners may not mark widgets dirty.
  void _publishLiveCamera() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) _liveCamera.value = _camera;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.isFinite) {
          throw FlutterError(
            'UnifiedMap needs bounded constraints, got $constraints.\n'
            'Give it a size, e.g. with SizedBox or Expanded.',
          );
        }
        _onSize(size);
        return UnifiedMapInheritedModel(
          camera: _camera,
          controller: _controller,
          options: widget.options,
          child: MapLayerScope(
            host: this,
            pixelRatio: _pixelRatio,
            appearance: _appearance,
            children: widget.children,
            child: SizedBox.fromSize(
              size: size,
              child: MapChildrenStack(
                children: [
                  Positioned.fill(child: _platformView),
                  ...widget.children,
                  if (_error case final error?)
                    Positioned.fill(
                      child:
                          widget.errorBuilder?.call(context, error) ??
                          MapErrorView(error: error, compact: _loadedOnce && error.isLoadError),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
