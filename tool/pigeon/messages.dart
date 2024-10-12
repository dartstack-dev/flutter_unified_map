// Canonical Pigeon schema shared by flutter_unified_map_android and flutter_unified_map_apple.
// Regenerate with tool/pigeon/generate.sh; never edit the generated files.
import 'package:pigeon/pigeon.dart';

class PLatLng {
  const PLatLng(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class PLatLngBounds {
  const PLatLngBounds(this.southWest, this.northEast);
  final PLatLng southWest;
  final PLatLng northEast;
}

class PCamera {
  const PCamera(this.center, this.zoom, this.bearing, this.tilt);
  final PLatLng center;
  final double zoom;
  final double bearing;
  final double tilt;
}

/// Content inset, logical pixels.
class PEdgeInsets {
  const PEdgeInsets(this.left, this.top, this.right, this.bottom);
  final double left;
  final double top;
  final double right;
  final double bottom;
}

class PPoint {
  const PPoint(this.x, this.y);
  final double x;
  final double y;
}

/// Screen size of the view, logical pixels.
class PSize {
  const PSize(this.width, this.height);
  final double width;
  final double height;
}

enum PMapStyle { standard, muted, satellite, hybrid, none }

enum PMapErrorCode { apiKeyMissing, servicesUnavailable, loadTimeout, loadFailed, unknown }

/// [flags]: flutter_map InteractiveFlag bits (drag 1, flingAnimation 2, pinchMove 4, pinchZoom 8, doubleTapZoom 16,
/// doubleTapDragZoom 32, scrollWheelZoom 64, rotate 128). [tiltEnabled]: native two-finger tilt.
class PInteraction {
  const PInteraction(this.flags, this.tiltEnabled);
  final int flags;
  final bool tiltEnabled;
}

enum PAndroidMapType { standard, muted, satellite, hybrid, terrain, none }

enum PAndroidColorScheme { light, dark, followSystem }

/// Google-only settings; null = platform default. [mapId] and [liteMode] are read when the view is created only.
class PAndroidMapOptions {
  const PAndroidMapOptions({
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
  final PAndroidMapType? mapType;
  final String? mapId;
  final String? styleJson;
  final PAndroidColorScheme? colorScheme;
  final bool? liteMode;
  final bool? indoorEnabled;
  final bool? indoorLevelPickerEnabled;
  final bool? myLocationButtonEnabled;
  final bool? zoomControlsEnabled;
  final bool? mapToolbarEnabled;
}

enum PAppleMapType { standard, muted, satellite, hybrid, satelliteFlyover, hybridFlyover, none }

enum PAppleElevationStyle { flat, realistic }

/// MKPointOfInterestFilter: [including] shows only [categories] (MKPointOfInterestCategory raw values), otherwise
/// every category but them.
class PApplePoiFilter {
  const PApplePoiFilter(this.including, this.categories);
  final bool including;
  final List<String> categories;
}

/// MapKit-only settings; null = platform default. [showsZoomControls] and [showsPitchControl] are macOS only.
class PAppleMapOptions {
  const PAppleMapOptions({
    this.mapType,
    this.elevationStyle,
    this.pointsOfInterest,
    this.showsScale,
    this.showsZoomControls,
    this.showsPitchControl,
  });
  final PAppleMapType? mapType;
  final PAppleElevationStyle? elevationStyle;
  final PApplePoiFilter? pointsOfInterest;
  final bool? showsScale;
  final bool? showsZoomControls;
  final bool? showsPitchControl;
}

class PMapOptions {
  const PMapOptions({
    required this.initialCamera,
    required this.minZoom,
    required this.maxZoom,
    required this.style,
    required this.backgroundColorArgb,
    required this.interaction,
    required this.padding,
    required this.showsUserLocation,
    required this.showsCompass,
    required this.showsBuildings,
    required this.showsTraffic,
    required this.showsPointsOfInterest,
    this.cameraBoundary,
    this.android,
    this.apple,
  });
  final PCamera initialCamera;
  final double minZoom;
  final double maxZoom;
  final PMapStyle style;
  final int backgroundColorArgb;
  final PInteraction interaction;
  final PEdgeInsets padding;
  final bool showsUserLocation;
  final bool showsCompass;
  final bool showsBuildings;
  final bool showsTraffic;
  final bool showsPointsOfInterest;
  /// Keeps the camera center inside these bounds during gestures (Google setLatLngBoundsForCameraTarget, MapKit
  /// cameraBoundary).
  final PLatLngBounds? cameraBoundary;
  final PAndroidMapOptions? android;
  final PAppleMapOptions? apple;
}

/// PNG bytes rendered at [pixelRatio], displayed at [logicalSize]. Sent once per [key]; markers refer to the key.
class PIcon {
  const PIcon(this.key, this.pngBytes, this.logicalSize, this.pixelRatio);
  final String key;
  final Uint8List pngBytes;
  final PSize logicalSize;
  final double pixelRatio;
}

class PMarker {
  const PMarker({
    required this.id,
    required this.position,
    required this.iconKey,
    required this.anchor,
    required this.zIndex,
    required this.flat,
    required this.rotation,
    required this.tappable,
    this.opacity,
    this.draggable,
    this.title,
    this.snippet,
    this.android,
    this.apple,
  });
  final String id;
  final PLatLng position;
  final String iconKey;
  /// Fractional anchor: (0.5, 1.0) = bottom center on the position.
  final PPoint anchor;
  final double zIndex;
  final bool flat;
  final double rotation;
  final bool tappable;
  /// Null = 1.
  final double? opacity;
  /// Null = false.
  final bool? draggable;
  /// Info window (Google) / callout (MapKit) shown on tap when not null.
  final String? title;
  final String? snippet;
  final PAndroidMarkerOptions? android;
  final PAppleMarkerOptions? apple;
}

/// Google-only marker settings: fractional info window anchor, and a flat override.
class PAndroidMarkerOptions {
  const PAndroidMarkerOptions({this.infoWindowAnchor, this.flat});
  final PPoint? infoWindowAnchor;
  final bool? flat;
}

enum PAppleCollisionMode { rectangle, circle, none }

/// MapKit-only marker settings: displayPriority (0-1000, null = required) and collisionMode.
class PAppleMarkerOptions {
  const PAppleMarkerOptions({this.displayPriority, this.collisionMode});
  final double? displayPriority;
  final PAppleCollisionMode? collisionMode;
}

enum PStrokeCap { butt, round, square }

enum PStrokeJoin { miter, round, bevel }

class PPolyline {
  const PPolyline({
    required this.id,
    required this.points,
    required this.colorArgb,
    required this.width,
    required this.borderColorArgb,
    required this.borderWidth,
    required this.dashPattern,
    required this.cap,
    required this.join,
    required this.zIndex,
    required this.geodesic,
    this.gradientColorsArgb,
    this.widthInMeters,
  });
  final String id;
  final List<PLatLng> points;
  final int colorArgb;
  final double width;
  final int borderColorArgb;
  final double borderWidth;
  final List<double>? dashPattern;
  final PStrokeCap cap;
  final PStrokeJoin join;
  final double zIndex;
  final bool geodesic;
  /// One colour per point, replacing colorArgb.
  final List<int>? gradientColorsArgb;
  /// Null = false: width and borderWidth are logical pixels.
  final bool? widthInMeters;
}

class PPolygon {
  const PPolygon({
    required this.id,
    required this.points,
    required this.holes,
    required this.fillColorArgb,
    required this.strokeColorArgb,
    required this.strokeWidth,
    required this.zIndex,
    this.dashPattern,
    this.cap,
    this.join,
    this.geodesic,
  });
  final String id;
  final List<PLatLng> points;
  final List<List<PLatLng>> holes;
  final int fillColorArgb;
  final int strokeColorArgb;
  final double strokeWidth;
  final double zIndex;
  /// Stroke on/off lengths in logical pixels; null = solid.
  final List<double>? dashPattern;
  /// Null = round.
  final PStrokeCap? cap;
  final PStrokeJoin? join;
  /// Null = false.
  final bool? geodesic;
}

class PCircle {
  const PCircle({
    required this.id,
    required this.center,
    required this.radiusMeters,
    required this.fillColorArgb,
    required this.strokeColorArgb,
    required this.strokeWidth,
    required this.zIndex,
  });
  final String id;
  final PLatLng center;
  final double radiusMeters;
  final int fillColorArgb;
  final int strokeColorArgb;
  final double strokeWidth;
  final double zIndex;
}

class PTileLayer {
  const PTileLayer({
    required this.id,
    required this.urlTemplate,
    required this.subdomains,
    required this.minZoom,
    required this.maxZoom,
    required this.tileSize,
    required this.headers,
    required this.replacesBaseMap,
    required this.opacity,
    required this.zIndex,
    this.minNativeZoom,
    this.fallbackUrlTemplate,
    this.tms,
    this.zoomReverse,
    this.zoomOffset,
    this.additionalOptions,
    this.retinaMode,
    this.tileBounds,
    this.dartProvided,
    this.errorIconKey,
    this.fadeIn,
  });
  final String id;
  final String urlTemplate;
  final List<String> subdomains;
  final double minZoom;
  final double maxZoom;
  final int tileSize;
  final Map<String, String> headers;
  final bool replacesBaseMap;
  final double opacity;
  final double zIndex;
  /// See PlatformTileLayer for the meaning of every field below; null = the PlatformTileLayer default.
  final int? minNativeZoom;
  final String? fallbackUrlTemplate;
  final bool? tms;
  final bool? zoomReverse;
  final double? zoomOffset;
  final Map<String, String>? additionalOptions;
  final PRetinaMode? retinaMode;
  final PLatLngBounds? tileBounds;
  /// Tiles come from UnifiedMapsFlutterApi.loadTile instead of urlTemplate.
  final bool? dartProvided;
  /// Registered icon drawn in place of failed tiles.
  final String? errorIconKey;
  final bool? fadeIn;
}

enum PRetinaMode { disabled, server, simulation }

/// An image pinned to the ground by three corners (see PlatformGroundOverlay); the image is a registered icon.
class PGroundOverlay {
  const PGroundOverlay({
    required this.id,
    required this.iconKey,
    required this.topLeft,
    required this.bottomLeft,
    required this.bottomRight,
    required this.opacity,
    required this.zIndex,
  });
  final String id;
  final String iconKey;
  final PLatLng topLeft;
  final PLatLng bottomLeft;
  final PLatLng bottomRight;
  final double opacity;
  final double zIndex;
}

/// Easing: cubic Bézier control points [x1, y1, x2, y2] in [cubic], or [samples] at evenly spaced times in [0, 1].
class PCurve {
  const PCurve({this.cubic, this.samples});
  final List<double>? cubic;
  final List<double>? samples;
}

/// Animated marker update (see PlatformMarkerTransition): appearFrom / disappearTo map marker ids to positions.
/// Null curves = ease-in-out cubic (0.42, 0, 0.58, 1).
class PMarkerTransition {
  const PMarkerTransition(
    this.durationMillis,
    this.appearFrom,
    this.disappearTo, {
    this.moveCurve,
    this.fadeInCurve,
    this.fadeOutCurve,
  });
  final int durationMillis;
  final Map<String, PLatLng> appearFrom;
  final Map<String, PLatLng> disappearTo;
  final PCurve? moveCurve;
  final PCurve? fadeInCurve;
  final PCurve? fadeOutCurve;
}

/// One of the four fields is set.
class PCameraUpdate {
  const PCameraUpdate({this.newCamera, this.fitBounds, this.scrollBy, this.zoomBy});
  final PNewCamera? newCamera;
  final PFitBounds? fitBounds;
  final PScrollBy? scrollBy;
  final PZoomBy? zoomBy;
}

class PNewCamera {
  const PNewCamera(this.center, this.zoom, this.bearing, this.tilt);
  final PLatLng? center;
  final double? zoom;
  final double? bearing;
  final double? tilt;
}

class PFitBounds {
  const PFitBounds(this.bounds, this.padding, this.maxZoom, this.bearing);
  final PLatLngBounds bounds;
  final PEdgeInsets padding;
  final double? maxZoom;
  final double? bearing;
}

class PScrollBy {
  const PScrollBy(this.dx, this.dy);
  final double dx;
  final double dy;
}

class PZoomBy {
  const PZoomBy(this.amount, this.focus);
  final double amount;
  final PPoint? focus;
}

/// Dart → native. Every call names the view by [viewId] (chosen by Dart and passed as platform view creation
/// params under the key "viewId").
@HostApi()
abstract class UnifiedMapsHostApi {
  void dispose(int viewId);
  void updateOptions(int viewId, PMapOptions options);
  /// Icons must be registered before the markers that use them; keys are stable for the view's lifetime.
  void registerIcons(int viewId, List<PIcon> icons);
  void updateMarkers(
    int viewId,
    List<PMarker> added,
    List<PMarker> changed,
    List<String> removedIds,
    PMarkerTransition? transition,
  );
  void updatePolylines(int viewId, List<PPolyline> added, List<PPolyline> changed, List<String> removedIds);
  void updatePolygons(int viewId, List<PPolygon> added, List<PPolygon> changed, List<String> removedIds);
  void updateCircles(int viewId, List<PCircle> added, List<PCircle> changed, List<String> removedIds);
  void updateTileLayers(int viewId, List<PTileLayer> added, List<PTileLayer> changed, List<String> removedIds);
  /// Ground overlay images are registered with registerIcons first.
  void updateGroundOverlays(
    int viewId,
    List<PGroundOverlay> added,
    List<PGroundOverlay> changed,
    List<String> removedIds,
  );
  /// Drops the cached tiles of a tile layer and reloads the visible ones.
  void resetTileLayer(int viewId, String tileLayerId);
  /// Icons no marker, ground overlay or tile layer uses any more.
  void unregisterIcons(int viewId, List<String> keys);
  /// [animationMillis] null = instant. Completes when the move ends. A gesture or another moveCamera during an
  /// animation stops it (onCameraIdle for it, then the new start).
  @async
  void moveCamera(int viewId, PCameraUpdate update, int? animationMillis);
  /// Stops a camera animation or fling where it is, then onCameraIdle.
  void stopCamera(int viewId);
  PCamera getCamera(int viewId);
  PLatLngBounds getVisibleRegion(int viewId);
  PPoint toScreen(int viewId, PLatLng position);
  PLatLng toLatLng(int viewId, PPoint screenPoint);
  @async
  Uint8List? takeSnapshot(int viewId);
}

/// Native → Dart events.
@FlutterApi()
abstract class UnifiedMapsFlutterApi {
  void onMapReady(int viewId, PCamera camera, PSize size);
  void onCameraMoveStarted(int viewId, bool byGesture);
  void onCameraMove(int viewId, PCamera camera);
  void onCameraIdle(int viewId, PCamera camera);
  void onTap(int viewId, PLatLng position, PPoint screenPoint);
  void onLongPress(int viewId, PLatLng position, PPoint screenPoint);
  /// Mouse right click, stylus button, or iPadOS / macOS secondary click on the map.
  void onSecondaryTap(int viewId, PLatLng position, PPoint screenPoint);
  void onMarkerTap(int viewId, String markerId);
  void onMarkerDragStart(int viewId, String markerId, PLatLng position);
  void onMarkerDrag(int viewId, String markerId, PLatLng position);
  void onMarkerDragEnd(int viewId, String markerId, PLatLng position);
  void onInfoWindowTap(int viewId, String markerId);
  /// macOS and iPadOS pointers only.
  void onMarkerHover(int viewId, String markerId, bool entered);
  /// A tile failed for good (after the fallback URL).
  void onTileError(int viewId, String tileLayerId, int z, int x, int y, String message);
  /// Bytes of a dartProvided tile (z/x/y in the layer's own grid), or null when it cannot be loaded.
  @async
  Uint8List? loadTile(int viewId, String tileLayerId, int z, int x, int y);
  void onViewSize(int viewId, PSize size);
  /// Base map content loaded (first time, or again after a load error).
  void onMapLoaded(int viewId);
  /// The base map cannot be shown. May come instead of onMapReady when the native map cannot be created.
  void onMapError(int viewId, PMapErrorCode code, String message);
}
