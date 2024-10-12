import 'package:flutter/painting.dart' show Color, EdgeInsets, StrokeCap, StrokeJoin;
import 'package:flutter_map/flutter_map.dart' show StrokePattern;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

import '../layer/circle_layer/circle_marker.dart';
import '../layer/polygon_layer/polygon.dart';
import '../layer/polyline_layer/polyline.dart';
import '../native/native_params.dart';
import 'camera/camera_math.dart';
import 'camera/map_camera.dart';
import 'flutter_map_passthrough.dart';
import 'layer_registry.dart';
import 'options/map_options.dart';

/// [MapOptions] as the platform sees them. [flutterMap] adds flutter_map's own values, for a backend that draws
/// with flutter_map.
PlatformMapOptions toPlatformOptions(MapOptions options, {bool flutterMap = false}) {
  final native = options.nativeParams;
  final android = native?.android;
  final apple = native?.apple;
  return PlatformMapOptions(
    initialCamera: PlatformCamera(
      center: options.initialCenter,
      zoom: options.initialZoom,
      bearing: bearingFromRotation(options.initialRotation),
    ),
    minZoom: options.minZoom ?? 0,
    maxZoom: options.maxZoom ?? defaultMaxZoom,
    style: switch (native?.mapType ?? options.mapStyle) {
      MapStyle.standard => PlatformMapStyle.standard,
      MapStyle.muted => PlatformMapStyle.muted,
      MapStyle.satellite => PlatformMapStyle.satellite,
      MapStyle.hybrid => PlatformMapStyle.hybrid,
      MapStyle.none => PlatformMapStyle.none,
    },
    backgroundColor: options.backgroundColor,
    interaction: PlatformInteraction(
      flags: options.interactionOptions.flags,
      tiltEnabled: native?.tiltGestures ?? false,
    ),
    padding: native?.padding ?? EdgeInsets.zero,
    showsUserLocation: native?.showsUserLocation ?? false,
    showsCompass: native?.showsCompass ?? false,
    showsBuildings: native?.showsBuildings ?? false,
    showsTraffic: native?.showsTraffic ?? false,
    showsPointsOfInterest: native?.showsPointsOfInterest ?? options.showsPointsOfInterest,
    android: android == null ? null : toPlatformAndroidOptions(android),
    apple: apple == null ? null : toPlatformAppleOptions(apple),
    flutterMap: flutterMap ? flutterMapPassthrough(options) : null,
  );
}

PlatformAndroidMapOptions toPlatformAndroidOptions(AndroidMapParams params) => PlatformAndroidMapOptions(
  mapType: switch (params.mapType) {
    null => null,
    AndroidMapType.standard => PlatformAndroidMapType.standard,
    AndroidMapType.muted => PlatformAndroidMapType.muted,
    AndroidMapType.satellite => PlatformAndroidMapType.satellite,
    AndroidMapType.hybrid => PlatformAndroidMapType.hybrid,
    AndroidMapType.terrain => PlatformAndroidMapType.terrain,
    AndroidMapType.none => PlatformAndroidMapType.none,
  },
  mapId: params.mapId,
  styleJson: params.styleJson,
  colorScheme: switch (params.colorScheme) {
    null => null,
    AndroidMapColorScheme.light => PlatformAndroidColorScheme.light,
    AndroidMapColorScheme.dark => PlatformAndroidColorScheme.dark,
    AndroidMapColorScheme.followSystem => PlatformAndroidColorScheme.followSystem,
  },
  liteMode: params.liteMode,
  indoorEnabled: params.indoorEnabled,
  indoorLevelPickerEnabled: params.indoorLevelPickerEnabled,
  myLocationButtonEnabled: params.myLocationButtonEnabled,
  zoomControlsEnabled: params.zoomControlsEnabled,
  mapToolbarEnabled: params.mapToolbarEnabled,
);

PlatformAppleMapOptions toPlatformAppleOptions(AppleMapParams params) => PlatformAppleMapOptions(
  mapType: switch (params.mapType) {
    null => null,
    AppleMapType.standard => PlatformAppleMapType.standard,
    AppleMapType.muted => PlatformAppleMapType.muted,
    AppleMapType.satellite => PlatformAppleMapType.satellite,
    AppleMapType.hybrid => PlatformAppleMapType.hybrid,
    AppleMapType.satelliteFlyover => PlatformAppleMapType.satelliteFlyover,
    AppleMapType.hybridFlyover => PlatformAppleMapType.hybridFlyover,
    AppleMapType.none => PlatformAppleMapType.none,
  },
  elevationStyle: switch (params.elevationStyle) {
    null => null,
    AppleElevationStyle.flat => PlatformAppleElevationStyle.flat,
    AppleElevationStyle.realistic => PlatformAppleElevationStyle.realistic,
  },
  pointsOfInterest: switch (params.pointsOfInterest) {
    null => null,
    final filter => PlatformApplePoiFilter(
      including: filter.including,
      categories: [for (final category in filter.categories) category.rawValue]..sort(),
    ),
  },
  showsScale: params.showsScale,
  showsZoomControls: params.showsZoomControls,
  showsPitchControl: params.showsPitchControl,
);

extension StrokePatternDashes on StrokePattern {
  bool get isSolid => segments == null && spacingFactor == null;

  /// On/off lengths of a native line of [strokeWidth], before `patternFit`: dots are on lengths of 0 with a round
  /// cap.
  List<double>? toDashPattern(double strokeWidth) {
    final spacing = spacingFactor;
    if (spacing != null) return [strokeWidth, strokeWidth * spacing];
    return segments;
  }
}

PlatformStrokeCap toPlatformCap(StrokeCap cap) => switch (cap) {
  StrokeCap.butt => PlatformStrokeCap.butt,
  StrokeCap.round => PlatformStrokeCap.round,
  StrokeCap.square => PlatformStrokeCap.square,
};

PlatformStrokeJoin toPlatformJoin(StrokeJoin join) => switch (join) {
  StrokeJoin.miter => PlatformStrokeJoin.miter,
  StrokeJoin.round => PlatformStrokeJoin.round,
  StrokeJoin.bevel => PlatformStrokeJoin.bevel,
};

PlatformPolyline toPlatformPolyline(Polyline polyline, String id, double zIndex) => PlatformPolyline(
  id: id,
  points: polyline.points,
  color: polyline.color,
  width: polyline.strokeWidth,
  borderColor: polyline.borderColor,
  borderWidth: polyline.borderStrokeWidth,
  dashPattern: polyline.pattern.toDashPattern(polyline.strokeWidth),
  cap: toPlatformCap(polyline.strokeCap),
  join: toPlatformJoin(polyline.strokeJoin),
  zIndex: zIndex,
  geodesic: polyline.nativeParams?.geodesic ?? false,
  gradientColors: _vertexColors(polyline),
  widthInMeters: polyline.useStrokeWidthInMeter,
);

/// Contract stub: one colour per vertex is due from the core unit (flutter_map's straight gradient, projected on
/// the first-to-last axis); until then a gradient line is drawn in its first colour.
List<Color>? _vertexColors(Polyline polyline) {
  final colors = polyline.gradientColors;
  if (colors == null || colors.isEmpty) return null;
  return List.filled(polyline.points.length, colors.first);
}

/// [polylines] of [layerId] as platform objects with ids `'<layerId>/<index>'`, stacked in list order.
List<PlatformPolyline> layerPolylines(LayerRegistry registry, String layerId, List<Polyline> polylines) => [
  for (var i = 0; i < polylines.length; i++)
    toPlatformPolyline(polylines[i], '$layerId/$i', registry.shapeZIndexOf(layerId, i, polylines.length)),
];

PlatformPolygon toPlatformPolygon(Polygon polygon, String id, double zIndex) => PlatformPolygon(
  id: id,
  points: polygon.points,
  holes: polygon.holePointsList ?? const [],
  fillColor: polygon.color ?? const Color(0x00000000),
  strokeColor: polygon.borderColor,
  strokeWidth: polygon.borderStrokeWidth,
  zIndex: zIndex,
  dashPattern: polygon.pattern.toDashPattern(polygon.borderStrokeWidth),
  cap: toPlatformCap(polygon.strokeCap),
  join: toPlatformJoin(polygon.strokeJoin),
  geodesic: polygon.nativeParams?.android?.geodesic ?? false,
);

PlatformCircle toPlatformCircle(CircleMarker circle, String id, double zIndex, MapCamera camera) => PlatformCircle(
  id: id,
  center: circle.point,
  radiusMeters: circle.useRadiusInMeter ? circle.radius : circle.radius * camera.metersPerPixel(circle.point.latitude),
  fillColor: circle.color,
  strokeColor: circle.borderColor,
  strokeWidth: circle.borderStrokeWidth,
  zIndex: zIndex,
);
