import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_example/src/demo_data.dart';
import 'package:flutter_unified_map_example/src/geometry_data.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show PlatformCameraUpdateFitBounds, PlatformCameraUpdateNewCamera;

import 'pixels.dart';
import 'scene_harness.dart';

typedef PinExpectation = ({Offset anchor, bool flat, Size size});

const _bottomCenter = Offset(0.5, 1.0);
const _center = Offset(0.5, 0.5);

/// What each pin of the scene must look like on the platform side: anchors follow
/// `anchor = ((1 - a.x) / 2, (1 - a.y) / 2)`, `flat` is `!rotate` (the layer sets `rotate: true`).
const pinExpectations = <String, PinExpectation>{
  GeometryPins.tip: (anchor: _bottomCenter, flat: false, size: GeometryPins.tipSize),
  GeometryPins.badgeA: (anchor: _bottomCenter, flat: false, size: GeometryPins.badgeSize),
  GeometryPins.badgeB: (anchor: _bottomCenter, flat: false, size: GeometryPins.badgeSize),
  GeometryPins.badgeC: (anchor: _bottomCenter, flat: false, size: GeometryPins.badgeSize),
  GeometryPins.cafe: (anchor: _center, flat: false, size: GeometryPins.cafeSize),
  GeometryPins.upright: (anchor: _center, flat: false, size: GeometryPins.arrowSize),
  GeometryPins.flat: (anchor: _center, flat: true, size: GeometryPins.arrowSize),
  GeometryPins.fuel1: (anchor: _center, flat: false, size: GeometryPins.fuelSize),
  GeometryPins.fuel2: (anchor: _center, flat: false, size: GeometryPins.fuelSize),
  GeometryPins.fuel3: (anchor: _center, flat: false, size: GeometryPins.fuelSize),
};

/// (b) Every custom pin reaches the platform with its anchor, flatness, shared icon and icon size.
Future<void> checkCustomPins(WidgetTester tester, SceneHarness h) async {
  final recorder = h.recorder;
  await pumpUntil(tester, () => GeometryPins.all.every((name) => recorder.markerNamed(name) != null));
  final missing = [
    for (final name in GeometryPins.all)
      if (recorder.markerNamed(name) == null) name,
  ];
  expect(
    missing,
    isEmpty,
    reason: 'markers that never reached the platform (${recorder.markerUpdates.length} marker updates)',
  );

  final pixelRatio = tester.view.devicePixelRatio;
  for (final MapEntry(key: name, value: expected) in pinExpectations.entries) {
    final marker = recorder.markerNamed(name)!;
    expect(marker.position, GeometryPins.points[name], reason: '$name position');
    expect(marker.anchor.dx, closeTo(expected.anchor.dx, 1e-9), reason: '$name anchor x');
    expect(marker.anchor.dy, closeTo(expected.anchor.dy, 1e-9), reason: '$name anchor y');
    expect(marker.flat, expected.flat, reason: '$name flat');
    expect(marker.tappable, isTrue, reason: '$name has an onTap');
    expect(marker.icon.logicalSize, expected.size, reason: '$name icon logical size');
    expect(marker.icon.pixelRatio, pixelRatio, reason: '$name icon pixel ratio');
    final png = (await tester.runAsync(() => decodePng(marker.icon.bytes)))!;
    expect(png.width, closeTo(expected.size.width * pixelRatio, 1), reason: '$name icon PNG width');
    expect(png.height, closeTo(expected.size.height * pixelRatio, 1), reason: '$name icon PNG height');
  }
  log('pins: ${pinExpectations.length} markers with the expected anchors, flatness and icon sizes');

  final fuelKeys = {for (final name in GeometryPins.fuel) recorder.markerNamed(name)!.icon.key};
  expect(fuelKeys, hasLength(1), reason: 'markers sharing iconKey "${GeometryPins.fuelIconKey}" share one icon');
  final otherKeys = [
    for (final name in GeometryPins.all)
      if (!GeometryPins.fuel.contains(name)) recorder.markerNamed(name)!.icon.key,
  ];
  expect(otherKeys.toSet(), hasLength(otherKeys.length), reason: 'every other pin has its own icon');
  expect(otherKeys, isNot(contains(fuelKeys.single)));

  final tip = (await tester.runAsync(() => decodePng(recorder.markerNamed(GeometryPins.tip)!.icon.bytes)))!;
  final magenta = countPixelsNear(tip, GeometryColors.pin, tolerance: 8);
  expect(magenta, greaterThan(tip.width * tip.height * 0.3), reason: 'the tip pin bitmap is mostly magenta');
  final tipRow = Rect.fromLTWH(0, tip.height * 0.85, tip.width.toDouble(), tip.height * 0.15);
  final tipCenter = Rect.fromLTWH(tip.width * 0.3, tip.height * 0.85, tip.width * 0.4, tip.height * 0.15);
  expect(
    countPixelsNear(tip, GeometryColors.pin, tolerance: 60, region: tipCenter),
    countPixelsNear(tip, GeometryColors.pin, tolerance: 60, region: tipRow),
    reason: 'the teardrop tip is at the bottom center of its bitmap',
  );
}

/// (c) The itinerary, the patterned lines, the polygon hole and both kinds of circles reach the platform.
Future<void> checkItinerary(WidgetTester tester, SceneHarness h) async {
  final recorder = h.recorder;
  await pumpUntil(
    tester,
    () => recorder.polylines.length == 3 && recorder.polygons.length == 2 && recorder.circles.length == 4,
  );
  expect(recorder.polylines, hasLength(3), reason: 'route, detour and dotted line');
  expect(recorder.polygons, hasLength(2), reason: 'Morvan and Camargue');
  expect(recorder.circles, hasLength(4), reason: 'three waypoints and the 2 km circle');

  final route = recorder.polylines.values.singleWhere((p) => p.color == GeometryColors.route);
  expect(route.points, orderedEquals(itinerary));
  expect(route.width, 6);
  expect(route.borderWidth, 3);
  expect(route.borderColor, GeometryColors.routeBorder);
  expect(route.dashPattern, isNull);
  final routeSends = recorder.polylineUpdates.expand((u) => [...u.added, ...u.changed]).where((p) => p.id == route.id);
  expect(routeSends, hasLength(1), reason: 'the route is sent once (${recorder.polylineUpdates.length} updates)');

  final detour = recorder.polylines.values.singleWhere((p) => p.color == GeometryColors.detour);
  expect(detour.points, orderedEquals(detourPoints));
  expect(detour.dashPattern, orderedEquals(detourSegments));
  final dotted = recorder.polylines.values.singleWhere((p) => p.color == GeometryColors.dotted);
  expect(dotted.dashPattern, isNotNull, reason: 'StrokePattern.dotted() becomes a dash pattern');
  expect(dotted.dashPattern, hasLength(2));
  expect(dotted.dashPattern![0], closeTo(dotted.width, 1e-9), reason: 'dots as long as the stroke is wide');
  expect(dotted.dashPattern![1], greaterThan(0));
  log('polylines: route ${route.points.length} points, detour ${detour.dashPattern}, dotted ${dotted.dashPattern}');

  final morvan = recorder.polygons.values.singleWhere((p) => p.fillColor == GeometryColors.morvanFill);
  expect(morvan.points, orderedEquals(morvanOuter));
  expect(morvan.holes, hasLength(1));
  expect(morvan.holes.single, orderedEquals(morvanHole));
  expect(morvan.strokeColor, GeometryColors.morvanBorder);
  expect(morvan.strokeWidth, 2);
  final camargueShape = recorder.polygons.values.singleWhere((p) => p.fillColor == GeometryColors.camargueFill);
  expect(camargueShape.holes, isEmpty);

  final meter = recorder.circles.values.singleWhere((c) => c.fillColor == GeometryColors.meterCircle);
  expect(meter.center, meterCircleCenter);
  expect(meter.radiusMeters, meterCircleRadius);

  bool pixelRadiiMatch() => recorder.circles.values
      .where((c) => c.fillColor == GeometryColors.waypoint)
      .every((c) => _relativeError(c.radiusMeters, _pixelRadiusMeters(h, c.center)) < 0.02);
  await pumpUntil(tester, pixelRadiiMatch, timeout: const Duration(seconds: 10));
  final waypoints = recorder.circles.values.where((c) => c.fillColor == GeometryColors.waypoint).toList();
  expect(waypoints.map((c) => c.center), unorderedEquals(waypointPoints));
  for (final circle in waypoints) {
    final expected = _pixelRadiusMeters(h, circle.center);
    expect(
      circle.radiusMeters,
      closeTo(expected, expected * 0.02),
      reason: '${circle.center}: $waypointRadiusPx px at zoom ${h.camera.zoom} is ${expected.toStringAsFixed(1)} m',
    );
  }
  log('circles: 2 km circle and ${waypoints.length} waypoints (~${waypoints.first.radiusMeters.round()} m)');
}

double _pixelRadiusMeters(SceneHarness h, LatLng point) => waypointRadiusPx * h.camera.metersPerPixel(point.latitude);

double _relativeError(double actual, double expected) => (actual - expected).abs() / expected;

/// (d) `animatedFitCamera` on the route completes with MoveStart → Move → MoveEnd and leaves every route point
/// inside the padded viewport; at city zoom, `rotate(45)` then turns the camera to 45°.
///
/// The rotation runs at zoom 10 because MapKit keeps north up while zoomed out (below about zoom 8, measured on
/// macOS 27): a heading request at the route's country-scale zoom is silently reset to 0.
Future<void> checkCamera(WidgetTester tester, SceneHarness h, {double tolerance = 3}) async {
  final recorder = h.recorder;
  final movesBefore = recorder.cameraMoves.length;
  final events = await h.fitRoute(tester);
  log('fit events: ${events.map((e) => e.runtimeType).toList()}');

  final moves = recorder.cameraMoves.skip(movesBefore).toList();
  expect(moves, isNotEmpty, reason: 'the fit reached the platform');
  expect(moves.last.update, isA<PlatformCameraUpdateFitBounds>(), reason: 'a north-up bounds fit is native');
  expect(moves.last.animation, isNotNull, reason: 'animatedFitCamera animates');

  final start = events.indexWhere((e) => e is MapEventMoveStart);
  final move = events.indexWhere((e) => e is MapEventMove, start + 1);
  final end = events.indexWhere((e) => e is MapEventMoveEnd, move + 1);
  final types = events.map((e) => e.runtimeType).toList();
  expect(start, isNonNegative, reason: 'MapEventMoveStart in $types');
  expect(move, greaterThan(start), reason: 'MapEventMove after the start in $types');
  expect(end, greaterThan(move), reason: 'MapEventMoveEnd after a move in $types');

  final camera = h.camera;
  final size = camera.nonRotatedSize;
  final viewport = Rect.fromLTRB(
    routeFitPadding.left,
    routeFitPadding.top,
    size.width - routeFitPadding.right,
    size.height - routeFitPadding.bottom,
  );
  final screen = [for (final point in itinerary) camera.latLngToScreenOffset(point)];
  final outside = [
    for (var i = 0; i < itinerary.length; i++)
      if (!viewport.inflate(tolerance).contains(screen[i])) '${itinerary[i]} → ${screen[i]}',
  ];
  log('after fit: $camera, padded viewport $viewport');
  expect(outside, isEmpty, reason: 'route points outside the padded viewport $viewport');
  final routeBox = Rect.fromPoints(
    Offset(screen.map((p) => p.dx).reduce(math.min), screen.map((p) => p.dy).reduce(math.min)),
    Offset(screen.map((p) => p.dx).reduce(math.max), screen.map((p) => p.dy).reduce(math.max)),
  );
  expect(
    routeBox.width >= viewport.width * 0.7 || routeBox.height >= viewport.height * 0.7,
    isTrue,
    reason: 'the fit fills the padded viewport (route box $routeBox, viewport $viewport)',
  );

  h.controller.move(lyon, rotationZoom);
  final zoomed = await pumpUntil(
    tester,
    () => (h.camera.zoom - rotationZoom).abs() < 0.05,
    timeout: const Duration(seconds: 10),
  );
  expect(zoomed, isTrue, reason: 'camera.zoom is ${h.camera.zoom} after move(lyon, $rotationZoom)');
  final rotatesBefore = recorder.cameraMoves.length;
  h.controller.rotate(45);
  final rotated = await pumpUntil(
    tester,
    () => _angleDifference(h.camera.rotation, 45) < 0.5,
    timeout: const Duration(seconds: 10),
  );
  expect(rotated, isTrue, reason: 'camera.rotation is ${h.camera.rotation} after rotate(45)');
  final rotateUpdate = recorder.cameraMoves.skip(rotatesBefore).first.update;
  expect(rotateUpdate, isA<PlatformCameraUpdateNewCamera>());
  expect(
    (rotateUpdate as PlatformCameraUpdateNewCamera).bearing,
    closeTo(315, 1e-9),
    reason: 'rotation 45 is compass bearing 315',
  );
  log('rotate(45): camera.rotation ${h.camera.rotation.toStringAsFixed(2)}');
}

const rotationZoom = 10.0;

double _angleDifference(double a, double b) {
  final d = (a - b) % 360;
  return math.min(d, 360 - d);
}

/// (e) The native snapshot has the view's physical size and shows the route, the magenta pin and the yellow
/// polygon.
Future<void> checkSnapshot(
  WidgetTester tester,
  SceneHarness h, {
  required String platformName,
  Duration settle = const Duration(seconds: 3),
}) async {
  await h.fitRoute(tester);
  await pumpUntil(tester, () => GeometryPins.all.every((name) => h.recorder.markerNamed(name) != null));
  await pumpFor(tester, settle);
  final bytes = await tester.runAsync(h.controller.takeSnapshot);
  if (bytes == null) {
    fail('takeSnapshot() returned null on $platformName: the platform cannot snapshot the map or it is not ready');
  }
  final image = (await tester.runAsync(() => decodePng(bytes)))!;
  final pixelRatio = tester.view.devicePixelRatio;
  final camera = h.camera;
  final size = camera.nonRotatedSize;
  log('snapshot ${image.width}×${image.height} for a ${size.width}×${size.height} view at ${pixelRatio}x');
  expect(image.width, closeTo(size.width * pixelRatio, 2), reason: 'snapshot width = view width × pixel ratio');
  expect(image.height, closeTo(size.height * pixelRatio, 2), reason: 'snapshot height = view height × pixel ratio');

  final scale = image.width / size.width;
  final area = scale * scale;
  final green = countPixelsNear(image, GeometryColors.route, tolerance: 40);
  final magenta = countPixelsNear(image, GeometryColors.pin, tolerance: 50);
  final morvanBox = _screenBox(camera, morvanOuter, scale);
  final yellow = countPixelsWithHue(image, minHue: 35, maxHue: 65, region: morvanBox);
  final morvanArea = morvanBox.width * morvanBox.height;
  log(
    'snapshot pixels: route green $green, pin magenta $magenta, '
    'polygon yellow $yellow of ${morvanArea.round()} (${(100 * yellow / morvanArea).round()} %, about 68 % expected) '
    'in $morvanBox',
  );
  expect(green, greaterThan(150 * area), reason: 'route green 0xFF00C853 visible in the snapshot');
  expect(magenta, greaterThan(100 * area), reason: 'tip pin magenta 0xFFFF00FF visible in the snapshot');
  expect(yellow, greaterThan(morvanArea * 0.2), reason: 'polygon fill 0x88FFD600 visible in the snapshot');
}

Rect _screenBox(MapCamera camera, List<LatLng> points, double scale) {
  final screen = [for (final point in points) camera.latLngToScreenOffset(point) * scale];
  return Rect.fromLTRB(
    screen.map((p) => p.dx).reduce(math.min),
    screen.map((p) => p.dy).reduce(math.min),
    screen.map((p) => p.dx).reduce(math.max),
    screen.map((p) => p.dy).reduce(math.max),
  );
}

/// (f) A tap on the tip pin fires its `Marker.onTap`; a tap inside the Morvan polygon reaches `MapOptions.onTap`
/// with the polygon in the layer's `hitNotifier`.
Future<void> checkTaps(WidgetTester tester, SceneHarness h) async {
  await h.fitRoute(tester);
  await pumpUntil(tester, () => h.recorder.markerNamed(GeometryPins.tip) != null);
  await pumpFor(tester, const Duration(milliseconds: 500));
  final origin = tester.getTopLeft(find.byType(UnifiedMap));

  final body = Offset(0, -(GeometryPins.tipSize.height - GeometryPins.tipSize.width / 2));
  final pin = h.camera.latLngToScreenOffset(GeometryPins.tipPoint) + body;
  log('tapping the tip pin at $pin');
  await nativeTap(tester, origin + pin);
  final markerTapped = await pumpUntil(tester, () => h.markerTaps.isNotEmpty, timeout: const Duration(seconds: 5));
  expect(markerTapped, isTrue, reason: 'Marker.onTap of the tip pin did not fire');
  expect(h.markerTaps, [GeometryPins.tip]);

  final inside = _pointFarFromMarkers(h, morvanOuter, morvanHole) ?? h.camera.latLngToScreenOffset(morvanInside);
  log('tapping the Morvan polygon at $inside');
  await nativeTap(tester, origin + inside);
  final mapTapped = await pumpUntil(tester, () => h.polygonTaps.isNotEmpty, timeout: const Duration(seconds: 5));
  expect(mapTapped, isTrue, reason: 'MapOptions.onTap did not fire');
  expect(h.polygonTaps.last, 'Morvan');
  await tester.pump();
  expect(find.text('Polygon Morvan'), findsOneWidget);
}

/// A tap the native map recognises as a tap. `tester.tapAt` stamps its events with time 0; Android turns that into a
/// MotionEvent whose down time is long past, so Google Maps' gesture detector fires a long press at once. Stamping the
/// events with the engine clock (the frame clock is the same monotonic clock as Android's uptime) keeps it a tap.
Future<void> nativeTap(WidgetTester tester, Offset position) async {
  final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
  final gesture = await tester.createGesture();
  await gesture.down(position, timeStamp: now);
  await tester.pump(const Duration(milliseconds: 60));
  await gesture.up(timeStamp: now + const Duration(milliseconds: 60));
}

/// The point of the polygon (outside its hole) farthest from every marker on screen. Google Maps widens a marker's
/// touch area, so on a narrow phone a fixed point inside the polygon can land on a nearby pin.
Offset? _pointFarFromMarkers(SceneHarness h, List<LatLng> outer, List<LatLng> hole) {
  final camera = h.camera;
  final polygon = [for (final p in outer) camera.latLngToScreenOffset(p)];
  final holeOnScreen = [for (final p in hole) camera.latLngToScreenOffset(p)];
  final markers = [for (final m in h.recorder.markers.values) camera.latLngToScreenOffset(m.position)];
  final bounds = Rect.fromPoints(
    Offset(polygon.map((p) => p.dx).reduce(math.min), polygon.map((p) => p.dy).reduce(math.min)),
    Offset(polygon.map((p) => p.dx).reduce(math.max), polygon.map((p) => p.dy).reduce(math.max)),
  );
  Offset? best;
  var bestDistance = -1.0;
  for (var y = bounds.top; y <= bounds.bottom; y += 4) {
    for (var x = bounds.left; x <= bounds.right; x += 4) {
      final point = Offset(x, y);
      if (!_inside(point, polygon) || _inside(point, holeOnScreen)) continue;
      final distance = markers.isEmpty ? double.infinity : markers.map((m) => (m - point).distance).reduce(math.min);
      if (distance > bestDistance) {
        bestDistance = distance;
        best = point;
      }
    }
  }
  return best;
}

bool _inside(Offset point, List<Offset> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    if ((a.dy > point.dy) != (b.dy > point.dy) && point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}
