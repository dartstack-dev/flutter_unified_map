import 'package:flutter/painting.dart' show Color, EdgeInsets;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

import 'messages.g.dart';

PLatLng toPLatLng(LatLng value) => PLatLng(latitude: value.latitude, longitude: value.longitude);

LatLng fromPLatLng(PLatLng value) => LatLng(value.latitude, value.longitude);

PPoint toPPoint(Offset value) => PPoint(x: value.dx, y: value.dy);

Offset fromPPoint(PPoint value) => Offset(value.x, value.y);

PCamera toPCamera(PlatformCamera value) =>
    PCamera(center: toPLatLng(value.center), zoom: value.zoom, bearing: value.bearing, tilt: value.tilt);

PlatformCamera fromPCamera(PCamera value) =>
    PlatformCamera(center: fromPLatLng(value.center), zoom: value.zoom, bearing: value.bearing, tilt: value.tilt);

PLatLngBounds toPBounds(PlatformLatLngBounds value) =>
    PLatLngBounds(southWest: toPLatLng(value.southWest), northEast: toPLatLng(value.northEast));

PlatformLatLngBounds fromPBounds(PLatLngBounds value) =>
    PlatformLatLngBounds(southWest: fromPLatLng(value.southWest), northEast: fromPLatLng(value.northEast));

PEdgeInsets toPEdgeInsets(EdgeInsets value) =>
    PEdgeInsets(left: value.left, top: value.top, right: value.right, bottom: value.bottom);

int toArgb(Color value) => value.toARGB32();

PMapStyle toPMapStyle(PlatformMapStyle value) => switch (value) {
  PlatformMapStyle.standard => PMapStyle.standard,
  PlatformMapStyle.muted => PMapStyle.muted,
  PlatformMapStyle.satellite => PMapStyle.satellite,
  PlatformMapStyle.hybrid => PMapStyle.hybrid,
  PlatformMapStyle.none => PMapStyle.none,
};

PInteraction toPInteraction(PlatformInteraction value) =>
    PInteraction(flags: value.flags, tiltEnabled: value.tiltEnabled);

PAndroidMapOptions toPAndroidMapOptions(PlatformAndroidMapOptions value) => PAndroidMapOptions(
  mapType: switch (value.mapType) {
    null => null,
    PlatformAndroidMapType.standard => PAndroidMapType.standard,
    PlatformAndroidMapType.muted => PAndroidMapType.muted,
    PlatformAndroidMapType.satellite => PAndroidMapType.satellite,
    PlatformAndroidMapType.hybrid => PAndroidMapType.hybrid,
    PlatformAndroidMapType.terrain => PAndroidMapType.terrain,
    PlatformAndroidMapType.none => PAndroidMapType.none,
  },
  mapId: value.mapId,
  styleJson: value.styleJson,
  colorScheme: switch (value.colorScheme) {
    null => null,
    PlatformAndroidColorScheme.light => PAndroidColorScheme.light,
    PlatformAndroidColorScheme.dark => PAndroidColorScheme.dark,
    PlatformAndroidColorScheme.followSystem => PAndroidColorScheme.followSystem,
  },
  liteMode: value.liteMode,
  indoorEnabled: value.indoorEnabled,
  indoorLevelPickerEnabled: value.indoorLevelPickerEnabled,
  myLocationButtonEnabled: value.myLocationButtonEnabled,
  zoomControlsEnabled: value.zoomControlsEnabled,
  mapToolbarEnabled: value.mapToolbarEnabled,
);

PAppleMapOptions toPAppleMapOptions(PlatformAppleMapOptions value) => PAppleMapOptions(
  mapType: switch (value.mapType) {
    null => null,
    PlatformAppleMapType.standard => PAppleMapType.standard,
    PlatformAppleMapType.muted => PAppleMapType.muted,
    PlatformAppleMapType.satellite => PAppleMapType.satellite,
    PlatformAppleMapType.hybrid => PAppleMapType.hybrid,
    PlatformAppleMapType.satelliteFlyover => PAppleMapType.satelliteFlyover,
    PlatformAppleMapType.hybridFlyover => PAppleMapType.hybridFlyover,
    PlatformAppleMapType.none => PAppleMapType.none,
  },
  elevationStyle: switch (value.elevationStyle) {
    null => null,
    PlatformAppleElevationStyle.flat => PAppleElevationStyle.flat,
    PlatformAppleElevationStyle.realistic => PAppleElevationStyle.realistic,
  },
  pointsOfInterest: switch (value.pointsOfInterest) {
    null => null,
    final filter => PApplePoiFilter(including: filter.including, categories: filter.categories),
  },
  showsScale: value.showsScale,
  showsZoomControls: value.showsZoomControls,
  showsPitchControl: value.showsPitchControl,
);

PMapOptions toPMapOptions(PlatformMapOptions value) => PMapOptions(
  initialCamera: toPCamera(value.initialCamera),
  minZoom: value.minZoom,
  maxZoom: value.maxZoom,
  style: toPMapStyle(value.style),
  backgroundColorArgb: toArgb(value.backgroundColor),
  interaction: toPInteraction(value.interaction),
  padding: toPEdgeInsets(value.padding),
  showsUserLocation: value.showsUserLocation,
  showsCompass: value.showsCompass,
  showsBuildings: value.showsBuildings,
  showsTraffic: value.showsTraffic,
  showsPointsOfInterest: value.showsPointsOfInterest,
  cameraBoundary: switch (value.cameraBoundary) {
    null => null,
    final bounds => toPBounds(bounds),
  },
  android: switch (value.android) {
    null => null,
    final android => toPAndroidMapOptions(android),
  },
  apple: switch (value.apple) {
    null => null,
    final apple => toPAppleMapOptions(apple),
  },
);

PIcon toPIcon(PlatformIcon value) => PIcon(
  key: value.key,
  pngBytes: value.bytes,
  logicalSize: PSize(width: value.logicalSize.width, height: value.logicalSize.height),
  pixelRatio: value.pixelRatio,
);

PCurve toPCurve(PlatformCurve value) => switch (value.samples) {
  null => PCurve(cubic: [value.x1, value.y1, value.x2, value.y2]),
  final samples => PCurve(samples: samples),
};

PMarkerTransition toPMarkerTransition(PlatformMarkerTransition value) => PMarkerTransition(
  durationMillis: value.duration.inMilliseconds,
  appearFrom: value.appearFrom.map((id, position) => MapEntry(id, toPLatLng(position))),
  disappearTo: value.disappearTo.map((id, position) => MapEntry(id, toPLatLng(position))),
  moveCurve: toPCurve(value.moveCurve),
  fadeInCurve: toPCurve(value.fadeInCurve),
  fadeOutCurve: toPCurve(value.fadeOutCurve),
);

PMarker toPMarker(PlatformMarker value) => PMarker(
  id: value.id,
  position: toPLatLng(value.position),
  iconKey: value.icon.key,
  anchor: toPPoint(value.anchor),
  zIndex: value.zIndex,
  flat: value.flat,
  rotation: value.rotation,
  tappable: value.tappable,
  opacity: value.opacity,
  draggable: value.draggable,
  title: value.title,
  snippet: value.snippet,
  android: switch (value.android) {
    null => null,
    final android => PAndroidMarkerOptions(
      infoWindowAnchor: switch (android.infoWindowAnchor) {
        null => null,
        final anchor => toPPoint(anchor),
      },
      flat: android.flat,
    ),
  },
  apple: switch (value.apple) {
    null => null,
    final apple => PAppleMarkerOptions(
      displayPriority: apple.displayPriority,
      collisionMode: switch (apple.collisionMode) {
        null => null,
        PlatformAppleCollisionMode.rectangle => PAppleCollisionMode.rectangle,
        PlatformAppleCollisionMode.circle => PAppleCollisionMode.circle,
        PlatformAppleCollisionMode.none => PAppleCollisionMode.none,
      },
    ),
  },
);

PStrokeCap toPStrokeCap(PlatformStrokeCap value) => switch (value) {
  PlatformStrokeCap.butt => PStrokeCap.butt,
  PlatformStrokeCap.round => PStrokeCap.round,
  PlatformStrokeCap.square => PStrokeCap.square,
};

PStrokeJoin toPStrokeJoin(PlatformStrokeJoin value) => switch (value) {
  PlatformStrokeJoin.miter => PStrokeJoin.miter,
  PlatformStrokeJoin.round => PStrokeJoin.round,
  PlatformStrokeJoin.bevel => PStrokeJoin.bevel,
};

PPolyline toPPolyline(PlatformPolyline value) => PPolyline(
  id: value.id,
  points: value.points.map(toPLatLng).toList(growable: false),
  colorArgb: toArgb(value.color),
  width: value.width,
  borderColorArgb: toArgb(value.borderColor),
  borderWidth: value.borderWidth,
  dashPattern: value.dashPattern,
  cap: toPStrokeCap(value.cap),
  join: toPStrokeJoin(value.join),
  zIndex: value.zIndex,
  geodesic: value.geodesic,
  gradientColorsArgb: value.gradientColors?.map(toArgb).toList(growable: false),
  widthInMeters: value.widthInMeters,
);

PPolygon toPPolygon(PlatformPolygon value) => PPolygon(
  id: value.id,
  points: value.points.map(toPLatLng).toList(growable: false),
  holes: [for (final hole in value.holes) hole.map(toPLatLng).toList(growable: false)],
  fillColorArgb: toArgb(value.fillColor),
  strokeColorArgb: toArgb(value.strokeColor),
  strokeWidth: value.strokeWidth,
  zIndex: value.zIndex,
  dashPattern: value.dashPattern,
  cap: toPStrokeCap(value.cap),
  join: toPStrokeJoin(value.join),
  geodesic: value.geodesic,
);

PCircle toPCircle(PlatformCircle value) => PCircle(
  id: value.id,
  center: toPLatLng(value.center),
  radiusMeters: value.radiusMeters,
  fillColorArgb: toArgb(value.fillColor),
  strokeColorArgb: toArgb(value.strokeColor),
  strokeWidth: value.strokeWidth,
  zIndex: value.zIndex,
);

PTileLayer toPTileLayer(PlatformTileLayer value) => PTileLayer(
  id: value.id,
  urlTemplate: value.urlTemplate,
  subdomains: value.subdomains,
  minZoom: value.minZoom,
  maxZoom: value.maxZoom,
  tileSize: value.tileSize,
  headers: value.headers,
  replacesBaseMap: value.replacesBaseMap,
  opacity: value.opacity,
  zIndex: value.zIndex,
  minNativeZoom: value.minNativeZoom,
  fallbackUrlTemplate: value.fallbackUrlTemplate,
  tms: value.tms,
  zoomReverse: value.zoomReverse,
  zoomOffset: value.zoomOffset,
  additionalOptions: value.additionalOptions,
  retinaMode: switch (value.retinaMode) {
    PlatformRetinaMode.disabled => PRetinaMode.disabled,
    PlatformRetinaMode.server => PRetinaMode.server,
    PlatformRetinaMode.simulation => PRetinaMode.simulation,
  },
  tileBounds: switch (value.tileBounds) {
    null => null,
    final bounds => toPBounds(bounds),
  },
  dartProvided: value.dartProvided,
  errorIconKey: value.errorImage?.key,
  fadeIn: value.fadeIn,
);

PGroundOverlay toPGroundOverlay(PlatformGroundOverlay value) => PGroundOverlay(
  id: value.id,
  iconKey: value.image.key,
  topLeft: toPLatLng(value.topLeft),
  bottomLeft: toPLatLng(value.bottomLeft),
  bottomRight: toPLatLng(value.bottomRight),
  opacity: value.opacity,
  zIndex: value.zIndex,
);

PCameraUpdate toPCameraUpdate(PlatformCameraUpdate value) => switch (value) {
  PlatformCameraUpdateNewCamera(:final center, :final zoom, :final bearing, :final tilt) => PCameraUpdate(
    newCamera: PNewCamera(center: center == null ? null : toPLatLng(center), zoom: zoom, bearing: bearing, tilt: tilt),
  ),
  PlatformCameraUpdateFitBounds(:final bounds, :final padding, :final maxZoom, :final bearing) => PCameraUpdate(
    fitBounds: PFitBounds(
      bounds: toPBounds(bounds),
      padding: toPEdgeInsets(padding),
      maxZoom: maxZoom,
      bearing: bearing,
    ),
  ),
  PlatformCameraUpdateScrollBy(:final dx, :final dy) => PCameraUpdate(
    scrollBy: PScrollBy(dx: dx, dy: dy),
  ),
  PlatformCameraUpdateZoomBy(:final amount, :final focus) => PCameraUpdate(
    zoomBy: PZoomBy(amount: amount, focus: focus == null ? null : toPPoint(focus)),
  ),
};

PlatformMapErrorCode fromPMapErrorCode(PMapErrorCode code) => switch (code) {
  PMapErrorCode.apiKeyMissing => PlatformMapErrorCode.apiKeyMissing,
  PMapErrorCode.servicesUnavailable => PlatformMapErrorCode.servicesUnavailable,
  PMapErrorCode.loadTimeout => PlatformMapErrorCode.loadTimeout,
  PMapErrorCode.loadFailed => PlatformMapErrorCode.loadFailed,
  PMapErrorCode.unknown => PlatformMapErrorCode.unknown,
};
