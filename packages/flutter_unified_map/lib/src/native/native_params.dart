import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/painting.dart' show Alignment, EdgeInsets;
import 'package:flutter/widgets.dart' show immutable;
import 'package:latlong2/latlong.dart';

/// Native base map rendering shared by Google Maps and MapKit. [none] hides the native base map, for apps whose
/// `TileLayer` replaces it.
enum MapStyle { standard, muted, satellite, hybrid, none }

/// Settings that only native maps have, for `MapOptions.nativeParams`.
///
/// Everything flutter_map can express stays on flutter_map's own API (`MapOptions`, `InteractionOptions`, the
/// layers); this class holds the extras of the native SDKs. The flutter_map backend (web, Windows, Linux, tests)
/// ignores it entirely, so code written for flutter_map keeps the same meaning there.
///
/// Every field is nullable: null means the platform default (given in each field's doc). A field of [android] or
/// [apple] refines the shared field it overrides. A shared field exists only when both SDKs implement it with the
/// same meaning.
@immutable
class NativeParams {
  /// Base map type. Default [MapStyle.standard]. Overridden by [AndroidMapParams.mapType] /
  /// [AppleMapParams.mapType].
  final MapStyle? mapType;

  /// The platform's user location dot (needs the location permission). Default false. Google `isMyLocationEnabled`,
  /// MapKit `showsUserLocation`.
  final bool? showsUserLocation;

  /// The platform's compass, shown while the map is rotated. Default false. Google `uiSettings.isCompassEnabled`,
  /// MapKit `showsCompass`.
  final bool? showsCompass;

  /// 3D buildings. Default false. Google `isBuildingsEnabled`, MapKit `showsBuildings`.
  final bool? showsBuildings;

  /// Traffic. Default false. Google `isTrafficEnabled`, MapKit `MKStandardMapConfiguration.showsTraffic`.
  final bool? showsTraffic;

  /// Points of interest of the base map (shops, landmarks). Default true. Google: the backend's POI style rule;
  /// MapKit `pointOfInterestFilter` (refined by [AppleMapParams.pointsOfInterest]).
  final bool? showsPointsOfInterest;

  /// Two-finger tilt. Default false. Google `uiSettings.isTiltGesturesEnabled`, MapKit `isPitchEnabled`. A tilted
  /// camera makes the Dart projections of `MapCamera` (hit tests, `latLngToScreenOffset`, widgets placed over the
  /// map) wrong, because flutter_map's camera has no tilt.
  final bool? tiltGestures;

  /// Inset of the native user interface: logo, legal notice, compass, my-location button. Default zero. Google
  /// `setPadding`, MapKit layout margins. The camera is not shifted: `MapCamera.center` stays the center of the map
  /// widget, as in flutter_map (the core compensates the shift both SDKs apply to their camera target).
  final EdgeInsets? padding;

  /// Google Maps only (Android).
  final AndroidMapParams? android;

  /// MapKit only (iOS and macOS).
  final AppleMapParams? apple;

  const NativeParams({
    this.mapType,
    this.showsUserLocation,
    this.showsCompass,
    this.showsBuildings,
    this.showsTraffic,
    this.showsPointsOfInterest,
    this.tiltGestures,
    this.padding,
    this.android,
    this.apple,
  });

  @override
  bool operator ==(Object other) =>
      other is NativeParams &&
      other.mapType == mapType &&
      other.showsUserLocation == showsUserLocation &&
      other.showsCompass == showsCompass &&
      other.showsBuildings == showsBuildings &&
      other.showsTraffic == showsTraffic &&
      other.showsPointsOfInterest == showsPointsOfInterest &&
      other.tiltGestures == tiltGestures &&
      other.padding == padding &&
      other.android == android &&
      other.apple == apple;

  @override
  int get hashCode => Object.hash(
    mapType,
    showsUserLocation,
    showsCompass,
    showsBuildings,
    showsTraffic,
    showsPointsOfInterest,
    tiltGestures,
    padding,
    android,
    apple,
  );
}

/// Google Maps map types: `GoogleMap.mapType` (`MAP_TYPE_NORMAL`, `SATELLITE`, `HYBRID`, `TERRAIN`, `NONE`); [muted]
/// is the normal map with a desaturated style.
enum AndroidMapType { standard, muted, satellite, hybrid, terrain, none }

/// `GoogleMap.setMapColorScheme`.
enum AndroidMapColorScheme { light, dark, followSystem }

/// Settings of the Google Maps SDK for Android. Every null field keeps the SDK default.
@immutable
class AndroidMapParams {
  /// Overrides [NativeParams.mapType].
  final AndroidMapType? mapType;

  /// Cloud map id (`GoogleMapOptions.mapId`): cloud styling, and the color scheme. Can only be set when the map is
  /// created: changing it recreates the native view.
  final String? mapId;

  /// `GoogleMap.setMapStyle(MapStyleOptions(styleJson))`, merged with the muted and points-of-interest rules.
  /// Ignored by the SDK when [mapId] is set.
  final String? styleJson;

  /// `GoogleMap.setMapColorScheme` (light, dark or following the system).
  final AndroidMapColorScheme? colorScheme;

  /// `GoogleMapOptions.liteMode`: a static bitmap map without gestures or animations. Recreates the native view
  /// when it changes.
  final bool? liteMode;

  /// `GoogleMap.isIndoorEnabled`. Default false.
  final bool? indoorEnabled;

  /// `UiSettings.isIndoorLevelPickerEnabled`. Default false.
  final bool? indoorLevelPickerEnabled;

  /// `UiSettings.isMyLocationButtonEnabled` (with [NativeParams.showsUserLocation]). Default false.
  final bool? myLocationButtonEnabled;

  /// `UiSettings.isZoomControlsEnabled`. Default false.
  final bool? zoomControlsEnabled;

  /// `UiSettings.isMapToolbarEnabled` (shown with a marker's info window). Default false.
  final bool? mapToolbarEnabled;

  const AndroidMapParams({
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
      other is AndroidMapParams &&
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

/// MapKit map types. The flyover types use `elevationStyle: .realistic` (3D terrain); like tilt, they make the Dart
/// projections approximate.
enum AppleMapType { standard, muted, satellite, hybrid, satelliteFlyover, hybridFlyover, none }

/// `MKMapConfiguration.elevationStyle`: [realistic] draws terrain in 3D (iOS 16 / macOS 13).
enum AppleElevationStyle { flat, realistic }

/// Categories of MapKit's points of interest (`MKPointOfInterestCategory`).
enum ApplePoiCategory {
  airport('MKPOICategoryAirport'),
  amusementPark('MKPOICategoryAmusementPark'),
  aquarium('MKPOICategoryAquarium'),
  atm('MKPOICategoryATM'),
  bakery('MKPOICategoryBakery'),
  bank('MKPOICategoryBank'),
  beach('MKPOICategoryBeach'),
  brewery('MKPOICategoryBrewery'),
  cafe('MKPOICategoryCafe'),
  campground('MKPOICategoryCampground'),
  carRental('MKPOICategoryCarRental'),
  evCharger('MKPOICategoryEVCharger'),
  fireStation('MKPOICategoryFireStation'),
  fitnessCenter('MKPOICategoryFitnessCenter'),
  foodMarket('MKPOICategoryFoodMarket'),
  gasStation('MKPOICategoryGasStation'),
  hospital('MKPOICategoryHospital'),
  hotel('MKPOICategoryHotel'),
  laundry('MKPOICategoryLaundry'),
  library('MKPOICategoryLibrary'),
  marina('MKPOICategoryMarina'),
  movieTheater('MKPOICategoryMovieTheater'),
  museum('MKPOICategoryMuseum'),
  nationalPark('MKPOICategoryNationalPark'),
  nightlife('MKPOICategoryNightlife'),
  park('MKPOICategoryPark'),
  parking('MKPOICategoryParking'),
  pharmacy('MKPOICategoryPharmacy'),
  police('MKPOICategoryPolice'),
  postOffice('MKPOICategoryPostOffice'),
  publicTransport('MKPOICategoryPublicTransport'),
  restaurant('MKPOICategoryRestaurant'),
  restroom('MKPOICategoryRestroom'),
  school('MKPOICategorySchool'),
  stadium('MKPOICategoryStadium'),
  store('MKPOICategoryStore'),
  theater('MKPOICategoryTheater'),
  university('MKPOICategoryUniversity'),
  winery('MKPOICategoryWinery'),
  zoo('MKPOICategoryZoo');

  /// The `MKPointOfInterestCategory` raw value.
  final String rawValue;

  const ApplePoiCategory(this.rawValue);
}

/// `MKPointOfInterestFilter`.
@immutable
class ApplePoiFilter {
  /// True: only [categories] are shown; false: every category but [categories].
  final bool including;
  final Set<ApplePoiCategory> categories;

  const ApplePoiFilter.all() : including = false, categories = const {};

  const ApplePoiFilter.none() : including = true, categories = const {};

  const ApplePoiFilter.including(this.categories) : including = true;

  const ApplePoiFilter.excluding(this.categories) : including = false;

  @override
  bool operator ==(Object other) =>
      other is ApplePoiFilter && other.including == including && setEquals(other.categories, categories);

  @override
  int get hashCode => Object.hash(including, Object.hashAllUnordered(categories));
}

/// Settings of MapKit (iOS and macOS share one map view). Every null field keeps the MapKit default.
@immutable
class AppleMapParams {
  /// Overrides [NativeParams.mapType].
  final AppleMapType? mapType;

  /// `MKMapConfiguration.elevationStyle`.
  final AppleElevationStyle? elevationStyle;

  /// Which points of interest show; overrides [NativeParams.showsPointsOfInterest].
  final ApplePoiFilter? pointsOfInterest;

  /// MapKit's own scale bar (`showsScale`). Default false. For a scale bar on every backend, add a `Scalebar` child.
  final bool? showsScale;

  /// macOS only: `MKMapView.showsZoomControls`. Default false.
  final bool? showsZoomControls;

  /// macOS only: `MKMapView.showsPitchControl`. Default false.
  final bool? showsPitchControl;

  const AppleMapParams({
    this.mapType,
    this.elevationStyle,
    this.pointsOfInterest,
    this.showsScale,
    this.showsZoomControls,
    this.showsPitchControl,
  });

  @override
  bool operator ==(Object other) =>
      other is AppleMapParams &&
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

typedef NativeMarkerDragCallback = void Function(LatLng point);

/// Settings of a native marker, for `Marker.nativeParams`. Ignored by the flutter_map backend. Every null field keeps
/// the default given in its doc.
@immutable
class NativeMarkerParams {
  /// Extra clockwise rotation of the bitmap, in degrees, applied natively (Google `Marker.rotation`, MapKit view
  /// transform) without rasterising the child again for each angle. Default 0. Turns with the map unless the marker
  /// is upright (`Marker.rotate`).
  final double? rotation;

  /// Google `Marker.alpha`, MapKit `MKAnnotationView.alpha`. Default 1.
  final double? opacity;

  /// Order among the markers of the same layer (higher above); default 0, then list order, as in flutter_map. It
  /// never lifts a marker above a later layer. Google `zIndex`, MapKit `zPriority`.
  final double? zIndex;

  /// The user can drag the marker after a long press (Google `draggable`, MapKit `isDraggable`). Default false. The
  /// marker stays where it is dropped until the app rebuilds it at another `point`: update the marker's point in
  /// [onDragEnd].
  final bool? draggable;

  final NativeMarkerDragCallback? onDragStart;
  final NativeMarkerDragCallback? onDrag;
  final NativeMarkerDragCallback? onDragEnd;

  /// Shows the platform's info window (Google) or callout (MapKit) on tap. Null shows none.
  final String? title;
  final String? snippet;

  /// A tap on the info window or callout.
  final void Function()? onInfoWindowTap;

  /// Google Maps only.
  final AndroidMarkerParams? android;

  /// MapKit only.
  final AppleMarkerParams? apple;

  const NativeMarkerParams({
    this.rotation,
    this.opacity,
    this.zIndex,
    this.draggable,
    this.onDragStart,
    this.onDrag,
    this.onDragEnd,
    this.title,
    this.snippet,
    this.onInfoWindowTap,
    this.android,
    this.apple,
  });

  @override
  bool operator ==(Object other) =>
      other is NativeMarkerParams &&
      other.rotation == rotation &&
      other.opacity == opacity &&
      other.zIndex == zIndex &&
      other.draggable == draggable &&
      other.onDragStart == onDragStart &&
      other.onDrag == onDrag &&
      other.onDragEnd == onDragEnd &&
      other.title == title &&
      other.snippet == snippet &&
      other.onInfoWindowTap == onInfoWindowTap &&
      other.android == android &&
      other.apple == apple;

  @override
  int get hashCode => Object.hash(
    rotation,
    opacity,
    zIndex,
    draggable,
    onDragStart,
    onDrag,
    onDragEnd,
    title,
    snippet,
    onInfoWindowTap,
    android,
    apple,
  );
}

/// Google Maps marker settings.
@immutable
class AndroidMarkerParams {
  /// Where the info window points, in the bitmap (`MarkerOptions.infoWindowAnchor`), as an [Alignment]. Default top
  /// center.
  final Alignment? infoWindowAnchor;

  /// `MarkerOptions.flat`: overrides what `Marker.rotate` implies (a flat marker lies on a tilted map).
  final bool? flat;

  const AndroidMarkerParams({this.infoWindowAnchor, this.flat});

  @override
  bool operator ==(Object other) =>
      other is AndroidMarkerParams && other.infoWindowAnchor == infoWindowAnchor && other.flat == flat;

  @override
  int get hashCode => Object.hash(infoWindowAnchor, flat);
}

/// `MKAnnotationViewCollisionMode`.
enum AppleCollisionMode { rectangle, circle, none }

/// MapKit marker settings.
@immutable
class AppleMarkerParams {
  /// `MKAnnotationView.displayPriority`, 0–1000. Default 1000 (`.required`): markers never hide each other. Lower
  /// values let MapKit hide colliding markers.
  final double? displayPriority;

  /// `MKAnnotationView.collisionMode`, for markers with a [displayPriority] below 1000.
  final AppleCollisionMode? collisionMode;

  const AppleMarkerParams({this.displayPriority, this.collisionMode});

  @override
  bool operator ==(Object other) =>
      other is AppleMarkerParams && other.displayPriority == displayPriority && other.collisionMode == collisionMode;

  @override
  int get hashCode => Object.hash(displayPriority, collisionMode);
}

/// Settings of a native polyline, for `Polyline.nativeParams`. Ignored by the flutter_map backend.
@immutable
class NativePolylineParams {
  /// Great-circle segments (Google `PolylineOptions.geodesic`, MapKit `MKGeodesicPolyline`). Default false.
  final bool? geodesic;

  const NativePolylineParams({this.geodesic});

  @override
  bool operator ==(Object other) => other is NativePolylineParams && other.geodesic == geodesic;

  @override
  int get hashCode => geodesic.hashCode;
}

/// Settings of a native polygon, for `Polygon.nativeParams`. Ignored by the flutter_map backend.
@immutable
class NativePolygonParams {
  /// Google Maps only.
  final AndroidPolygonParams? android;

  const NativePolygonParams({this.android});

  @override
  bool operator ==(Object other) => other is NativePolygonParams && other.android == android;

  @override
  int get hashCode => android.hashCode;
}

/// Google Maps polygon settings.
@immutable
class AndroidPolygonParams {
  /// Great-circle edges (`PolygonOptions.geodesic`). Default false.
  final bool? geodesic;

  const AndroidPolygonParams({this.geodesic});

  @override
  bool operator ==(Object other) => other is AndroidPolygonParams && other.geodesic == geodesic;

  @override
  int get hashCode => geodesic.hashCode;
}

/// Settings of a tile layer on native maps, for `TileLayer.nativeParams`. Ignored by the flutter_map backend.
@immutable
class NativeTileLayerParams {
  /// Hides the native base map under the tiles (Google `MAP_TYPE_NONE` while the layer is shown, MapKit
  /// `canReplaceMapContent`). Default false.
  final bool? replacesBaseMap;

  /// The layer is not drawn on native maps: only the flutter_map backend draws it. Default false. One code base can
  /// then use OpenStreetMap tiles on the web and the native base map on devices.
  final bool? hidden;

  const NativeTileLayerParams({this.replacesBaseMap, this.hidden});

  @override
  bool operator ==(Object other) =>
      other is NativeTileLayerParams && other.replacesBaseMap == replacesBaseMap && other.hidden == hidden;

  @override
  int get hashCode => Object.hash(replacesBaseMap, hidden);
}
