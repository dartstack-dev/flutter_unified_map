import 'package:flutter/painting.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_example/src/demo_data.dart';

/// Pure colors of the geometry scene, distinctive enough to be found in a map snapshot.
abstract final class GeometryColors {
  static const pin = Color(0xFFFF00FF);
  static const badge = Color(0xFF2962FF);
  static const cafe = Color(0xFFFF6D00);
  static const arrow = Color(0xFF263238);
  static const fuel = Color(0xFF6200EA);
  static const route = Color(0xFF00C853);
  static const routeBorder = Color(0xFFFFFFFF);
  static const detour = Color(0xFF2962FF);
  static const dotted = Color(0xFFD50000);
  static const waypoint = Color(0xFFFFFFFF);
  static const meterCircle = Color(0x6600B0FF);
  static const morvanFill = Color(0x88FFD600);
  static const morvanBorder = Color(0xFFFFAB00);
  static const camargueFill = Color(0x6600BFA5);
  static const camargueBorder = Color(0xFF00897B);
}

const geoMarseille = LatLng(43.2965, 5.3698);
const geoAuxerre = LatLng(47.7982, 3.5673);
const geoBeaune = LatLng(47.0260, 4.8400);
const geoDijon = LatLng(47.3220, 5.0415);
const geoValence = LatLng(44.9334, 4.8924);
const geoAvignon = LatLng(43.9493, 4.8055);

const geometryInitialCenter = LatLng(46.2, 4.0);
const geometryInitialZoom = 5.3;

/// Paris → Lyon → Marseille along the A6 and the A7: the demo route, continued.
const itinerary = [
  ...route,
  LatLng(45.5255, 4.8740),
  geoValence,
  LatLng(44.5581, 4.7509),
  LatLng(44.1381, 4.8075),
  geoAvignon,
  LatLng(43.6403, 5.0973),
  LatLng(43.5297, 5.4474),
  geoMarseille,
];

/// Lyon → Grenoble → Sisteron → Aix, drawn dashed.
const detourPoints = [lyon, LatLng(45.1885, 5.7245), LatLng(44.1951, 5.9437), LatLng(43.5297, 5.4474)];
const detourSegments = [12.0, 8.0];

/// Paris → Orléans → Bourges → Clermont-Ferrand, drawn dotted.
const dottedPoints = [paris, LatLng(47.9030, 1.9093), LatLng(47.0810, 2.3988), LatLng(45.7772, 3.0870)];

const waypointPoints = [paris, lyon, geoMarseille];
const waypointRadiusPx = 6.0;

const meterCircleCenter = lyon;
const meterCircleRadius = 2000.0;

const morvanOuter = [
  LatLng(47.55, 3.75),
  LatLng(47.50, 4.25),
  LatLng(47.20, 4.35),
  LatLng(46.85, 4.15),
  LatLng(46.90, 3.80),
  LatLng(47.25, 3.62),
];
const morvanHole = [LatLng(47.30, 3.95), LatLng(47.25, 4.10), LatLng(47.10, 4.08), LatLng(47.12, 3.92)];

/// A point of the Morvan polygon outside its hole.
const morvanInside = LatLng(47.0, 3.95);

const camargue = [LatLng(43.66, 4.40), LatLng(43.62, 4.85), LatLng(43.40, 4.85), LatLng(43.35, 4.45)];

/// Clears the control panel at the bottom of the scene.
const routeFitPadding = EdgeInsets.only(left: 24, top: 24, right: 24, bottom: 200);

final routeCameraFit = CameraFit.bounds(bounds: LatLngBounds.fromPoints(itinerary), padding: routeFitPadding);

/// Marker names; each marker's key is `ValueKey(name)`.
abstract final class GeometryPins {
  static const tip = 'tip';
  static const badgeA = 'badge-A';
  static const badgeB = 'badge-B';
  static const badgeC = 'badge-C';
  static const cafe = 'cafe';
  static const upright = 'upright';
  static const flat = 'flat';
  static const fuel1 = 'fuel-1';
  static const fuel2 = 'fuel-2';
  static const fuel3 = 'fuel-3';

  static const all = [tip, badgeA, badgeB, badgeC, cafe, upright, flat, fuel1, fuel2, fuel3];
  static const fuel = [fuel1, fuel2, fuel3];
  static const fuelIconKey = 'fuel';

  static const points = {
    tip: geoAuxerre,
    badgeA: paris,
    badgeB: lyon,
    badgeC: geoMarseille,
    cafe: geoBeaune,
    upright: geoValence,
    flat: geoAvignon,
    fuel1: LatLng(48.4047, 2.7016),
    fuel2: LatLng(46.3069, 4.8287),
    fuel3: LatLng(44.5581, 4.7509),
  };

  static const tipPoint = geoAuxerre;
  static const tipSize = Size(32, 44);
  static const badgeSize = Size(30, 36);
  static const cafeSize = Size(36, 36);
  static const arrowSize = Size(34, 34);
  static const fuelSize = Size(26, 26);
}
