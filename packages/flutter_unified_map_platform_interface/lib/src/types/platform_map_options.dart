import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart' show Color, EdgeInsets;
import 'package:meta/meta.dart';

import 'platform_camera.dart';

/// Base map rendering shared by every native backend (the core's `NativeParams.mapType`). [none] hides the native
/// base map (for custom tile layers). The flutter_map backend draws no base map of its own: only the app's tile
/// layers, as flutter_map does.
enum PlatformMapStyle { standard, muted, satellite, hybrid, none }

/// Enabled gestures. [flags] are flutter_map's `InteractiveFlag` bits, unchanged (see the constants), so each
/// backend honours each flag on its own as far as its SDK allows. [tiltEnabled] is the native two-finger tilt
/// (`NativeParams.tiltGestures`), which flutter_map does not have.
@immutable
class PlatformInteraction {
  static const int drag = 1 << 0;
  static const int flingAnimation = 1 << 1;
  static const int pinchMove = 1 << 2;
  static const int pinchZoom = 1 << 3;
  static const int doubleTapZoom = 1 << 4;
  static const int doubleTapDragZoom = 1 << 5;
  static const int scrollWheelZoom = 1 << 6;
  static const int rotate = 1 << 7;
  static const int all =
      drag | flingAnimation | pinchMove | pinchZoom | doubleTapZoom | doubleTapDragZoom | scrollWheelZoom | rotate;

  final int flags;
  final bool tiltEnabled;

  const PlatformInteraction({this.flags = all, this.tiltEnabled = false});

  static const none = PlatformInteraction(flags: 0);

  bool has(int flag) => flags & flag != 0;

  @override
  bool operator ==(Object other) =>
      other is PlatformInteraction && other.flags == flags && other.tiltEnabled == tiltEnabled;

  @override
  int get hashCode => Object.hash(flags, tiltEnabled);

  @override
  String toString() => 'PlatformInteraction(flags $flags, tilt $tiltEnabled)';
}

/// Everything a platform needs to create or reconfigure a map view.
///
/// [padding] is the content inset in logical pixels: native controls move inside it and
/// [PlatformCameraUpdate.fitBounds] / camera centering honour it (Google `setPadding`, MapKit layout margins).
///
/// [cameraBoundary] keeps the camera **center** inside these bounds during gestures (Google
/// `setLatLngBoundsForCameraTarget`, MapKit `cameraBoundary`); the core computes it from `MapOptions.cameraConstraint`
/// and also clamps its own camera moves. The flutter_map backend uses [PlatformFlutterMapOptions.cameraConstraint].
///
/// [android] and [apple] carry the native-only settings of one platform (the core's `NativeParams.android` /
/// `.apple`). Each native backend reads its own block and ignores the other; every null field means the platform
/// default; a platform field refines the shared one it overrides ([PlatformAndroidMapOptions.mapType] over [style]).
///
/// [flutterMap] is set by the core only for a backend that draws with flutter_map
/// ([UnifiedMapsPlatform.supportsFlutterMapLayers]): flutter_map's own values, passed through untouched. Native
/// backends always receive null.
@immutable
class PlatformMapOptions {
  final PlatformCamera initialCamera;
  final double minZoom;
  final double maxZoom;
  final PlatformMapStyle style;
  final Color backgroundColor;
  final PlatformInteraction interaction;
  final EdgeInsets padding;
  final bool showsUserLocation;
  final bool showsCompass;
  final bool showsBuildings;
  final bool showsTraffic;
  final bool showsPointsOfInterest;
  final PlatformLatLngBounds? cameraBoundary;
  final PlatformAndroidMapOptions? android;
  final PlatformAppleMapOptions? apple;
  final PlatformFlutterMapOptions? flutterMap;

  const PlatformMapOptions({
    required this.initialCamera,
    this.minZoom = 0,
    this.maxZoom = 22,
    this.style = PlatformMapStyle.standard,
    this.backgroundColor = const Color(0xFFE5E3DF),
    this.interaction = const PlatformInteraction(),
    this.padding = EdgeInsets.zero,
    this.showsUserLocation = false,
    this.showsCompass = false,
    this.showsBuildings = false,
    this.showsTraffic = false,
    this.showsPointsOfInterest = true,
    this.cameraBoundary,
    this.android,
    this.apple,
    this.flutterMap,
  });

  PlatformMapOptions copyWith({
    PlatformCamera? initialCamera,
    double? minZoom,
    double? maxZoom,
    PlatformMapStyle? style,
    Color? backgroundColor,
    PlatformInteraction? interaction,
    EdgeInsets? padding,
    bool? showsUserLocation,
    bool? showsCompass,
    bool? showsBuildings,
    bool? showsTraffic,
    bool? showsPointsOfInterest,
  }) => PlatformMapOptions(
    initialCamera: initialCamera ?? this.initialCamera,
    minZoom: minZoom ?? this.minZoom,
    maxZoom: maxZoom ?? this.maxZoom,
    style: style ?? this.style,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    interaction: interaction ?? this.interaction,
    padding: padding ?? this.padding,
    showsUserLocation: showsUserLocation ?? this.showsUserLocation,
    showsCompass: showsCompass ?? this.showsCompass,
    showsBuildings: showsBuildings ?? this.showsBuildings,
    showsTraffic: showsTraffic ?? this.showsTraffic,
    showsPointsOfInterest: showsPointsOfInterest ?? this.showsPointsOfInterest,
    cameraBoundary: cameraBoundary,
    android: android,
    apple: apple,
    flutterMap: flutterMap,
  );

  @override
  bool operator ==(Object other) =>
      other is PlatformMapOptions &&
      other.initialCamera == initialCamera &&
      other.minZoom == minZoom &&
      other.maxZoom == maxZoom &&
      other.style == style &&
      other.backgroundColor == backgroundColor &&
      other.interaction == interaction &&
      other.padding == padding &&
      other.showsUserLocation == showsUserLocation &&
      other.showsCompass == showsCompass &&
      other.showsBuildings == showsBuildings &&
      other.showsTraffic == showsTraffic &&
      other.showsPointsOfInterest == showsPointsOfInterest &&
      other.cameraBoundary == cameraBoundary &&
      other.android == android &&
      other.apple == apple &&
      other.flutterMap == flutterMap;

  @override
  int get hashCode => Object.hash(
    initialCamera,
    minZoom,
    maxZoom,
    style,
    backgroundColor,
    interaction,
    padding,
    showsUserLocation,
    showsCompass,
    showsBuildings,
    showsTraffic,
    showsPointsOfInterest,
    cameraBoundary,
    android,
    apple,
    flutterMap,
  );
}

/// Google Maps map types (`GoogleMap.mapType`); [muted] is `MAP_TYPE_NORMAL` with the backend's muted style JSON.
enum PlatformAndroidMapType { standard, muted, satellite, hybrid, terrain, none }

/// `GoogleMap.setMapColorScheme` (`MapColorScheme.LIGHT`, `DARK`, `FOLLOW_SYSTEM`).
enum PlatformAndroidColorScheme { light, dark, followSystem }

/// Native-only settings of the Google Maps SDK for Android. Every null field keeps the platform default.
///
/// [mapId] and [liteMode] can only be set when the `MapView` is created (`GoogleMapOptions.mapId` / `.liteMode`):
/// the core recreates the platform view when they change, so a backend reads them at creation only.
/// [styleJson] goes through `GoogleMap.setMapStyle`, merged with the backend's muted / no-POI rules; the SDK ignores
/// it when [mapId] is set (cloud styling).
@immutable
class PlatformAndroidMapOptions {
  final PlatformAndroidMapType? mapType;
  final String? mapId;
  final String? styleJson;
  final PlatformAndroidColorScheme? colorScheme;
  final bool? liteMode;
  final bool? indoorEnabled;
  final bool? indoorLevelPickerEnabled;
  final bool? myLocationButtonEnabled;
  final bool? zoomControlsEnabled;
  final bool? mapToolbarEnabled;

  const PlatformAndroidMapOptions({
    this.mapType,
    this.mapId,
    this.styleJson,
    this.colorScheme,
    this.liteMode,
    this.indoorEnabled,
    this.indoorLevelPickerEnabled,
    this.myLocationButtonEnabled,
    this.zoomControlsEnabled,
    this.mapToolbarEnabled,
  });

  @override
  bool operator ==(Object other) =>
      other is PlatformAndroidMapOptions &&
      other.mapType == mapType &&
      other.mapId == mapId &&
      other.styleJson == styleJson &&
      other.colorScheme == colorScheme &&
      other.liteMode == liteMode &&
      other.indoorEnabled == indoorEnabled &&
      other.indoorLevelPickerEnabled == indoorLevelPickerEnabled &&
      other.myLocationButtonEnabled == myLocationButtonEnabled &&
      other.zoomControlsEnabled == zoomControlsEnabled &&
      other.mapToolbarEnabled == mapToolbarEnabled;

  @override
  int get hashCode => Object.hash(
    mapType,
    mapId,
    styleJson,
    colorScheme,
    liteMode,
    indoorEnabled,
    indoorLevelPickerEnabled,
    myLocationButtonEnabled,
    zoomControlsEnabled,
    mapToolbarEnabled,
  );
}

/// MapKit map types: `MKStandardMapConfiguration` (`emphasisStyle: .muted` for [muted]), `MKImageryMapConfiguration`,
/// `MKHybridMapConfiguration` (`elevationStyle: .realistic` for the flyover types), and [none], a replacing blank
/// overlay.
enum PlatformAppleMapType { standard, muted, satellite, hybrid, satelliteFlyover, hybridFlyover, none }

/// `MKMapConfiguration.elevationStyle`.
enum PlatformAppleElevationStyle { flat, realistic }

/// `MKPointOfInterestFilter`: with [including] the map shows only [categories], otherwise every category but them
/// (`including: false, categories: []` shows all, `including: true, categories: []` none). [categories] are
/// `MKPointOfInterestCategory` raw values (`MKPOICategoryCafe`).
@immutable
class PlatformApplePoiFilter {
  final bool including;
  final List<String> categories;

  const PlatformApplePoiFilter({required this.including, this.categories = const []});

  @override
  bool operator ==(Object other) =>
      other is PlatformApplePoiFilter && other.including == including && listEquals(other.categories, categories);

  @override
  int get hashCode => Object.hash(including, Object.hashAll(categories));
}

/// Native-only settings of MapKit (iOS and macOS share them). Every null field keeps the platform default.
/// [pointsOfInterest] overrides [PlatformMapOptions.showsPointsOfInterest]. [showsZoomControls] and
/// [showsPitchControl] exist on macOS only; iOS ignores them.
@immutable
class PlatformAppleMapOptions {
  final PlatformAppleMapType? mapType;
  final PlatformAppleElevationStyle? elevationStyle;
  final PlatformApplePoiFilter? pointsOfInterest;
  final bool? showsScale;
  final bool? showsZoomControls;
  final bool? showsPitchControl;

  const PlatformAppleMapOptions({
    this.mapType,
    this.elevationStyle,
    this.pointsOfInterest,
    this.showsScale,
    this.showsZoomControls,
    this.showsPitchControl,
  });

  @override
  bool operator ==(Object other) =>
      other is PlatformAppleMapOptions &&
      other.mapType == mapType &&
      other.elevationStyle == elevationStyle &&
      other.pointsOfInterest == pointsOfInterest &&
      other.showsScale == showsScale &&
      other.showsZoomControls == showsZoomControls &&
      other.showsPitchControl == showsPitchControl;

  @override
  int get hashCode =>
      Object.hash(mapType, elevationStyle, pointsOfInterest, showsScale, showsZoomControls, showsPitchControl);
}

/// flutter_map's own values for a backend that draws with flutter_map, typed `Object` so that this interface does
/// not depend on flutter_map. The core builds them with flutter_map's classes:
/// - [crs]: the flutter_map `Crs` of `MapOptions.crs`;
/// - [cameraConstraint]: a flutter_map `CameraConstraint` (a custom constraint of the core's API is wrapped);
/// - [interactionOptions]: a flutter_map `InteractionOptions` with every field of the app's, keyboard and cursor
///   options included (`doubleTapDragZoomChangeCalculator` is wrapped).
/// Equality is the values' own `==`: the core keeps the same instances while the app's options stay equal.
@immutable
class PlatformFlutterMapOptions {
  final Object crs;
  final Object cameraConstraint;
  final Object interactionOptions;

  const PlatformFlutterMapOptions({required this.crs, required this.cameraConstraint, required this.interactionOptions});

  @override
  bool operator ==(Object other) =>
      other is PlatformFlutterMapOptions &&
      other.crs == crs &&
      other.cameraConstraint == cameraConstraint &&
      other.interactionOptions == interactionOptions;

  @override
  int get hashCode => Object.hash(crs, cameraConstraint, interactionOptions);
}
