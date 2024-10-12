import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' show Crs, Epsg3857, TapPosition;
import 'package:latlong2/latlong.dart';

import '../../native/native_params.dart';
import '../camera/camera_constraint.dart';
import '../camera/camera_fit.dart';
import '../camera/map_camera.dart';
import '../error/map_error.dart';
import '../events/map_events.dart';
import '../inherited_model.dart';
import 'interaction_options.dart';

typedef MapEventCallback = void Function(MapEvent);
typedef TapCallback = void Function(TapPosition tapPosition, LatLng point);
typedef LongPressCallback = void Function(TapPosition tapPosition, LatLng point);
typedef PointerDownCallback = void Function(PointerDownEvent event, LatLng point);
typedef PointerUpCallback = void Function(PointerUpEvent event, LatLng point);
typedef PointerCancelCallback = void Function(PointerCancelEvent event, LatLng point);
typedef PointerHoverCallback = void Function(PointerHoverEvent event, LatLng point);
typedef PointerMoveCallback = void Function(PointerMoveEvent event, LatLng point);
typedef PositionCallback = void Function(MapCamera camera, bool hasGesture);
typedef MapErrorCallback = void Function(MapError error);

/// flutter_map's `MapOptions`, field for field, plus [nativeParams] (native-only settings, ignored by the
/// flutter_map backend) and [onMapLoaded] / [onMapError] (every backend).
///
/// Per backend:
/// - [crs]: any flutter_map `Crs` on the flutter_map backend. Native maps are Web Mercator only: any other value
///   reports [MapErrorCode.unsupportedCrs] through [onMapError] (and `UnifiedMap.errorBuilder`) and the map stays
///   Web Mercator.
/// - [initialCameraFit]: solved in Dart against the widget's size before the native view is created, so the first
///   frame already shows it; solved again once ready if the size changed meanwhile.
/// - [cameraConstraint]: see [CameraConstraint].
/// - [interactionOptions]: see [InteractionOptions].
/// - [onTap], [onLongPress], [onSecondaryTap]: native gesture recognisers (Android context click, iPadOS / macOS
///   secondary click for [onSecondaryTap]); a tap on a marker with an `onTap` does not reach them, as in
///   flutter_map. The layers' hit notifiers are set before these callbacks run.
/// - [onPointerDown], [onPointerUp], [onPointerCancel], [onPointerMove], [onPointerHover]: a `Listener` around the
///   map sees every pointer before the native view does, on every backend; the point is
///   `MapCamera.screenOffsetToLatLng(event.localPosition)`. Hover reaches it wherever Flutter delivers hover over
///   platform views (Android mouse, iPadOS pointer, macOS).
/// - [onPositionChanged]: called for every camera move that changes the center or zoom (not for a rotation alone),
///   synchronously inside an instant `MapController` call, as flutter_map.
/// - [onMapReady]: called once the native view accepts calls, which can be a few frames after the first build
///   (flutter_map: after the first frame). Controller calls made before it update the initial camera instead.
/// - [backgroundColor]: shown where the base map has not loaded. Android can only apply it when the native view is
///   created: changing it recreates the view.
/// - [keepAlive]: keeps the native view alive in lazy lists and tab views.
@immutable
class MapOptions {
  final Crs crs;
  final LatLng initialCenter;
  final double initialZoom;

  /// Degrees, clockwise.
  final double initialRotation;
  final CameraFit? initialCameraFit;

  /// Zoom bounds of the camera, for gestures and controller calls alike (0 and 22 natively when null).
  final double? minZoom;
  final double? maxZoom;

  /// Base map style on native maps; ignored by the flutter_map backend. Default [MapStyle.standard]; [MapStyle.none]
  /// hides the native base map, for apps whose `TileLayer` replaces it. Refined by `nativeParams.mapType`.
  final MapStyle mapStyle;

  /// Whether the native base map shows its points of interest (shops, landmarks); ignored by the flutter_map
  /// backend. Default true. Refined by `nativeParams.showsPointsOfInterest`.
  final bool showsPointsOfInterest;

  final Color backgroundColor;
  final TapCallback? onTap;
  final TapCallback? onSecondaryTap;
  final LongPressCallback? onLongPress;
  final PointerDownCallback? onPointerDown;
  final PointerUpCallback? onPointerUp;
  final PointerCancelCallback? onPointerCancel;
  final PointerHoverCallback? onPointerHover;
  final PointerMoveCallback? onPointerMove;
  final PositionCallback? onPositionChanged;

  /// Every [MapEvent], as `MapController.mapEventStream`.
  final MapEventCallback? onMapEvent;
  final CameraConstraint cameraConstraint;
  final VoidCallback? onMapReady;
  final bool keepAlive;
  final InteractionOptions interactionOptions;

  /// The base map finished loading (first time, or again after a load error). Not in flutter_map.
  final VoidCallback? onMapLoaded;

  /// The platform cannot show the base map; see [MapError]. `UnifiedMap` also shows it unless its `errorBuilder`
  /// says otherwise. Not in flutter_map.
  final MapErrorCallback? onMapError;

  /// Settings only native maps have. Ignored by the flutter_map backend. Not in flutter_map.
  final NativeParams? nativeParams;

  const MapOptions({
    this.crs = const Epsg3857(),
    this.initialCenter = const LatLng(50.5, 30.51),
    this.initialZoom = 13.0,
    this.initialRotation = 0.0,
    this.initialCameraFit,
    this.cameraConstraint = const CameraConstraint.unconstrained(),
    this.interactionOptions = const InteractionOptions(),
    this.minZoom,
    this.maxZoom,
    this.mapStyle = MapStyle.standard,
    this.showsPointsOfInterest = true,
    this.backgroundColor = const Color(0xFFE0E0E0),
    this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.onPointerDown,
    this.onPointerUp,
    this.onPointerCancel,
    this.onPointerHover,
    this.onPointerMove,
    this.onPositionChanged,
    this.onMapEvent,
    this.onMapReady,
    this.keepAlive = false,
    this.onMapLoaded,
    this.onMapError,
    this.nativeParams,
  });

  static MapOptions? maybeOf(BuildContext context) => UnifiedMapInheritedModel.maybeOptionsOf(context);

  static MapOptions of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError('`MapOptions.of()` should not be called outside a `UnifiedMap` and its descendants'));

  @override
  bool operator ==(Object other) =>
      other is MapOptions &&
      crs == other.crs &&
      initialCenter == other.initialCenter &&
      initialZoom == other.initialZoom &&
      initialRotation == other.initialRotation &&
      initialCameraFit == other.initialCameraFit &&
      minZoom == other.minZoom &&
      maxZoom == other.maxZoom &&
      mapStyle == other.mapStyle &&
      showsPointsOfInterest == other.showsPointsOfInterest &&
      backgroundColor == other.backgroundColor &&
      onTap == other.onTap &&
      onSecondaryTap == other.onSecondaryTap &&
      onLongPress == other.onLongPress &&
      onPointerDown == other.onPointerDown &&
      onPointerUp == other.onPointerUp &&
      onPointerCancel == other.onPointerCancel &&
      onPointerHover == other.onPointerHover &&
      onPointerMove == other.onPointerMove &&
      onPositionChanged == other.onPositionChanged &&
      onMapEvent == other.onMapEvent &&
      cameraConstraint == other.cameraConstraint &&
      onMapReady == other.onMapReady &&
      keepAlive == other.keepAlive &&
      interactionOptions == other.interactionOptions &&
      onMapLoaded == other.onMapLoaded &&
      onMapError == other.onMapError &&
      nativeParams == other.nativeParams;

  @override
  int get hashCode => Object.hashAll([
    crs,
    initialCenter,
    initialZoom,
    initialRotation,
    initialCameraFit,
    minZoom,
    maxZoom,
    mapStyle,
    showsPointsOfInterest,
    backgroundColor,
    onTap,
    onSecondaryTap,
    onLongPress,
    onPointerDown,
    onPointerUp,
    onPointerCancel,
    onPointerHover,
    onPointerMove,
    onPositionChanged,
    onMapEvent,
    cameraConstraint,
    onMapReady,
    keepAlive,
    interactionOptions,
    onMapLoaded,
    onMapError,
    nativeParams,
  ]);
}
