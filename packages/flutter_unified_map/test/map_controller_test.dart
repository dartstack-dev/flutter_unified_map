import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

import 'support/fake_platform.dart';
import 'support/harness.dart';

void main() {
  late FakeUnifiedMapsPlatform fake;
  late MapController controller;

  setUp(() {
    fake = installFakePlatform();
    controller = MapController();
  });

  Future<void> pumpReady(WidgetTester tester, {double bearing = 0}) async {
    await tester.pumpWidget(mapApp(controller: controller));
    fake.ready(
      camera: PlatformCamera(center: const LatLng(45, 5), zoom: 10, bearing: bearing),
    );
    await tester.pump();
  }

  T lastUpdate<T extends PlatformCameraUpdate>() => fake.cameraMoves.last.update as T;

  test('camera throws a clear error when unattached', () {
    expect(() => controller.camera, throwsStateError);
  });

  testWidgets('instant methods return false before ready', (tester) async {
    await tester.pumpWidget(mapApp(controller: controller));
    expect(controller.move(const LatLng(1, 1), 3), isFalse);
    expect(controller.rotate(10), isFalse);
    expect(
      controller.fitCamera(CameraFit.bounds(bounds: LatLngBounds(const LatLng(0, 0), const LatLng(1, 1)))),
      isFalse,
    );
    expect(controller.moveAndRotate(const LatLng(1, 1), 3, 10).moveSuccess, isFalse);
    await controller.animateTo(dest: const LatLng(1, 1));
    expect(fake.cameraMoves, isEmpty);
  });

  testWidgets('move sends newCamera without animation', (tester) async {
    await pumpReady(tester);
    expect(controller.move(const LatLng(46, 6), 12), isTrue);
    final update = lastUpdate<PlatformCameraUpdateNewCamera>();
    expect(update.center, const LatLng(46, 6));
    expect(update.zoom, 12);
    expect(update.bearing, isNull);
    expect(fake.cameraMoves.last.animation, isNull);
  });

  for (final bearing in [0.0, 90.0, 37.0]) {
    testWidgets('move with offset puts the point at center + offset (rotation $bearing)', (tester) async {
      await pumpReady(tester, bearing: bearing);
      const point = LatLng(46, 6);
      const offset = Offset(30, -120);
      controller.move(point, 12, offset: offset);
      final update = lastUpdate<PlatformCameraUpdateNewCamera>();
      final camera = controller.camera.copyWith(center: update.center, zoom: 12);
      final screen = camera.latLngToScreenOffset(point);
      expect(screen.dx, closeTo(400 + offset.dx, 1e-6));
      expect(screen.dy, closeTo(300 + offset.dy, 1e-6));
    });
  }

  testWidgets('rotate and moveAndRotate send the bearing', (tester) async {
    await pumpReady(tester);
    controller.rotate(45, id: 'r');
    expect(lastUpdate<PlatformCameraUpdateNewCamera>().bearing, 315, reason: 'bearing is the opposite of rotation');
    final result = controller.moveAndRotate(const LatLng(1, 2), 5, 90);
    expect(result.moveSuccess && result.rotateSuccess, isTrue);
    final update = lastUpdate<PlatformCameraUpdateNewCamera>();
    expect((update.center, update.zoom, update.bearing), (const LatLng(1, 2), 5.0, 270.0));
  });

  testWidgets('fitCamera on a north-up map uses the native fitBounds', (tester) async {
    await pumpReady(tester);
    final bounds = LatLngBounds(const LatLng(40, -5), const LatLng(50, 8));
    expect(
      controller.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(12), maxZoom: 9)),
      isTrue,
    );
    final update = lastUpdate<PlatformCameraUpdateFitBounds>();
    expect(update.bounds, const PlatformLatLngBounds(southWest: LatLng(40, -5), northEast: LatLng(50, 8)));
    expect(update.padding, const EdgeInsets.all(12));
    expect(update.maxZoom, 9);
  });

  testWidgets('fitCamera with coordinates fits their bounds', (tester) async {
    await pumpReady(tester);
    controller.fitCamera(const CameraFit.coordinates(coordinates: [LatLng(1, 1), LatLng(3, -2), LatLng(2, 4)]));
    final update = lastUpdate<PlatformCameraUpdateFitBounds>();
    expect(update.bounds, const PlatformLatLngBounds(southWest: LatLng(1, -2), northEast: LatLng(3, 4)));
  });

  testWidgets('forceIntegerZoomLevel and minZoom are solved in Dart', (tester) async {
    await pumpReady(tester);
    final bounds = LatLngBounds(const LatLng(40, -5), const LatLng(50, 8));
    controller.fitCamera(CameraFit.bounds(bounds: bounds, forceIntegerZoomLevel: true));
    final integer = lastUpdate<PlatformCameraUpdateNewCamera>();
    expect(integer.zoom, integer.zoom!.floorToDouble());
    final fitted = controller.camera.copyWith(center: integer.center, zoom: integer.zoom);
    for (final corner in [bounds.northWest, bounds.southEast]) {
      final p = fitted.latLngToScreenOffset(corner);
      expect(p.dx, inInclusiveRange(-1e-6, 800 + 1e-6));
      expect(p.dy, inInclusiveRange(-1e-6, 600 + 1e-6));
    }

    controller.fitCamera(CameraFit.bounds(bounds: bounds, minZoom: 8));
    expect(lastUpdate<PlatformCameraUpdateNewCamera>().zoom, 8);
  });

  testWidgets('fitCamera on a rotated map keeps every corner inside the padded view', (tester) async {
    await pumpReady(tester, bearing: 30);
    final bounds = LatLngBounds(const LatLng(44, 4), const LatLng(46, 7));
    const padding = EdgeInsets.fromLTRB(10, 20, 30, 140);
    controller.fitCamera(CameraFit.bounds(bounds: bounds, padding: padding));
    final update = lastUpdate<PlatformCameraUpdateNewCamera>();
    final fitted = controller.camera.copyWith(center: update.center, zoom: update.zoom);
    final points = [
      bounds.northWest,
      bounds.northEast,
      bounds.southWest,
      bounds.southEast,
    ].map(fitted.latLngToScreenOffset).toList();
    for (final p in points) {
      expect(p.dx, greaterThanOrEqualTo(10 - 1e-6));
      expect(p.dx, lessThanOrEqualTo(800 - 30 + 1e-6));
      expect(p.dy, greaterThanOrEqualTo(20 - 1e-6));
      expect(p.dy, lessThanOrEqualTo(600 - 140 + 1e-6));
    }
    final touches =
        points.any((p) => (p.dx - 10).abs() < 1e-3 || (p.dx - 770).abs() < 1e-3) ||
        points.any((p) => (p.dy - 20).abs() < 1e-3 || (p.dy - 460).abs() < 1e-3);
    expect(touches, isTrue, reason: 'the fit is tight on one axis');
  });

  testWidgets('insideBounds fills the view with the bounds', (tester) async {
    await pumpReady(tester);
    final bounds = LatLngBounds(const LatLng(40, -5), const LatLng(50, 8));
    controller.fitCamera(CameraFit.insideBounds(bounds: bounds));
    final update = lastUpdate<PlatformCameraUpdateNewCamera>();
    final visible = controller.camera.copyWith(center: update.center, zoom: update.zoom).visibleBounds;
    // visibleBounds is flutter_map's, from the pixel-floored center: up to one pixel off.
    const epsilon = 0.01;
    expect(visible.north, lessThanOrEqualTo(bounds.north + epsilon));
    expect(visible.south, greaterThanOrEqualTo(bounds.south - epsilon));
    expect(visible.east, lessThanOrEqualTo(bounds.east + epsilon));
    expect(visible.west, greaterThanOrEqualTo(bounds.west - epsilon));
    expect(visible.east - visible.west, closeTo(bounds.east - bounds.west, 0.01), reason: 'tight on one axis');
  });

  testWidgets('animateTo and animatedFitCamera animate, 500 ms by default', (tester) async {
    await pumpReady(tester);
    await controller.animateTo(dest: const LatLng(46, 6), zoom: 11, rotation: 20);
    var call = fake.cameraMoves.last;
    expect(call.animation, const Duration(milliseconds: 500));
    final update = call.update as PlatformCameraUpdateNewCamera;
    expect((update.center, update.zoom, update.bearing), (const LatLng(46, 6), 11.0, 340.0));

    await controller.animateTo(zoom: 12, duration: const Duration(seconds: 2));
    call = fake.cameraMoves.last;
    expect(call.animation, const Duration(seconds: 2));
    expect((call.update as PlatformCameraUpdateNewCamera).center, const LatLng(45, 5));

    await controller.animatedFitCamera(
      cameraFit: CameraFit.bounds(bounds: LatLngBounds(const LatLng(40, -5), const LatLng(50, 8))),
    );
    expect(fake.cameraMoves.last.update, isA<PlatformCameraUpdateFitBounds>());
    expect(fake.cameraMoves.last.animation, const Duration(milliseconds: 500));

    await controller.animatedFitCamera(
      cameraFit: CameraFit.bounds(bounds: LatLngBounds(const LatLng(40, -5), const LatLng(50, 8))),
      rotation: 45,
    );
    expect((fake.cameraMoves.last.update as PlatformCameraUpdateNewCamera).bearing, 315);
  });

  testWidgets('animatedFitCamera with rotation 0 on a rotated map turns it back north', (tester) async {
    await pumpReady(tester, bearing: 60);
    await controller.animatedFitCamera(
      cameraFit: CameraFit.bounds(bounds: LatLngBounds(const LatLng(40, -5), const LatLng(50, 8))),
      rotation: 0,
    );
    final update = fake.cameraMoves.last.update as PlatformCameraUpdateFitBounds;
    expect(update.bearing, 0);
  });

  testWidgets('fitting no coordinates does nothing', (tester) async {
    await pumpReady(tester);
    expect(controller.fitCamera(const CameraFit.coordinates(coordinates: [])), isFalse);
    await controller.animatedFitCamera(cameraFit: const CameraFit.coordinates(coordinates: []));
    expect(fake.cameraMoves, isEmpty);
  });

  testWidgets('move, moveAndRotate and animateTo clamp the zoom before applying the offset', (tester) async {
    await tester.pumpWidget(mapApp(controller: controller, options: const MapOptions(minZoom: 3, maxZoom: 15)));
    fake.ready(camera: const PlatformCamera(center: LatLng(45, 5), zoom: 10));
    await tester.pump();
    const point = LatLng(46, 6);
    const offset = Offset(30, -120);
    controller.move(point, 20, offset: offset);
    var update = lastUpdate<PlatformCameraUpdateNewCamera>();
    expect(update.zoom, 15);
    final screen = controller.camera.copyWith(center: update.center, zoom: 15).latLngToScreenOffset(point);
    expect(screen.dx, closeTo(400 + offset.dx, 1e-6));
    expect(screen.dy, closeTo(300 + offset.dy, 1e-6));

    controller.moveAndRotate(point, 1, 10);
    expect(lastUpdate<PlatformCameraUpdateNewCamera>().zoom, 3);
    await controller.animateTo(zoom: 30);
    update = lastUpdate<PlatformCameraUpdateNewCamera>();
    expect(update.zoom, 15);
  });

  testWidgets('MapController.of returns the internal controller when none is given', (tester) async {
    MapController? found;
    await tester.pumpWidget(
      mapApp(
        children: [
          Builder(
            builder: (context) {
              found = MapController.of(context);
              return const SizedBox();
            },
          ),
        ],
      ),
    );
    fake.ready();
    expect(found!.move(const LatLng(1, 1), 4), isTrue);
    expect(fake.cameraMoves, hasLength(1));
  });

  testWidgets('a MapController not created with MapController() is rejected', (tester) async {
    await tester.pumpWidget(mapApp(controller: _OwnController()));
    expect(tester.takeException(), isAssertionError);
  });
}

class _OwnController implements MapController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
