import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:integration_test/integration_test.dart';

import 'apple_native_probe.dart';
import 'apple_test_support.dart';

void _log(String message) => debugPrint('[resize] $message');

/// MapKit keeps the visible span when its view is resized, which changes the zoom; the contract (Google Maps,
/// flutter_map) keeps the center and the zoom, so a window that settles its size after the map is ready does not
/// change the camera.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  AppleNativeProbe.holdTestWindowInFront();

  testWidgets('resizing the map view keeps the center and the zoom', (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    var ready = false;
    final size = ValueNotifier(const Size(240, 200));
    addTearDown(size.dispose);
    const center = LatLng(48.14, 11.58);
    const zoom = 9.3;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder(
              valueListenable: size,
              builder: (context, value, child) => SizedBox.fromSize(size: value, child: child),
              child: UnifiedMap(
                mapController: controller,
                options: MapOptions(initialCenter: center, initialZoom: zoom, onMapReady: () => ready = true),
                children: const [],
              ),
            ),
          ),
        ),
      ),
    );
    expect(await pumpUntil(tester, () => ready, const Duration(seconds: 30)), isTrue, reason: 'map ready');
    await pumpUntil(tester, () => false, const Duration(seconds: 1));
    _log('ready: ${controller.camera.center} z${controller.camera.zoom} ${controller.camera.nonRotatedSize}');
    expect(controller.camera.zoom, closeTo(zoom, 0.01));

    for (final next in const [Size(340, 360), Size(300, 520), Size(240, 200)]) {
      size.value = next;
      expect(
        await pumpUntil(tester, () => controller.camera.nonRotatedSize == next, const Duration(seconds: 5)),
        isTrue,
        reason: 'the map reports the size $next',
      );
      await pumpUntil(tester, () => false, const Duration(milliseconds: 800));
      final camera = controller.camera;
      _log('$next: ${camera.center} z${camera.zoom} ${camera.nonRotatedSize}');
      expect(camera.zoom, closeTo(zoom, 0.01), reason: 'zoom after resizing to $next');
      expect(camera.center.latitude, closeTo(center.latitude, 1e-4), reason: 'latitude after resizing to $next');
      expect(camera.center.longitude, closeTo(center.longitude, 1e-4), reason: 'longitude after resizing to $next');
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  testWidgets('a view that keeps growing while the map starts opens at the initial camera', (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    var ready = false;
    final size = ValueNotifier(const Size(60, 40));
    addTearDown(size.dispose);
    const center = LatLng(52.52, 13.40);
    const zoom = 6.6;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder(
              valueListenable: size,
              builder: (context, value, child) => SizedBox.fromSize(size: value, child: child),
              child: UnifiedMap(
                mapController: controller,
                options: MapOptions(initialCenter: center, initialZoom: zoom, onMapReady: () => ready = true),
                children: const [],
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 1; i <= 30; i++) {
      size.value = Size(60 + i * 11, 40 + i * 14);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 8)));
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(await pumpUntil(tester, () => ready, const Duration(seconds: 30)), isTrue, reason: 'map ready');
    await pumpUntil(tester, () => false, const Duration(seconds: 1));
    final camera = controller.camera;
    _log('grown: ${camera.center} z${camera.zoom} ${camera.nonRotatedSize}');
    expect(camera.zoom, closeTo(zoom, 0.01));
    expect(camera.center.latitude, closeTo(center.latitude, 1e-4));
    expect(camera.center.longitude, closeTo(center.longitude, 1e-4));
  }, timeout: const Timeout(Duration(minutes: 1)));

  testWidgets('a map collapsed to zero height keeps its camera', (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    var ready = false;
    final size = ValueNotifier(const Size(240, 200));
    addTearDown(size.dispose);
    const moved = LatLng(45.76, 4.84);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder(
              valueListenable: size,
              builder: (context, value, child) => SizedBox.fromSize(size: value, child: child),
              child: UnifiedMap(
                mapController: controller,
                options: MapOptions(
                  initialCenter: const LatLng(52.52, 13.40),
                  initialZoom: 6,
                  onMapReady: () => ready = true,
                ),
                children: const [],
              ),
            ),
          ),
        ),
      ),
    );
    expect(await pumpUntil(tester, () => ready, const Duration(seconds: 30)), isTrue, reason: 'map ready');
    controller.move(moved, 8);
    expect(
      await pumpUntil(tester, () => (controller.camera.zoom - 8).abs() < 0.01, const Duration(seconds: 5)),
      isTrue,
      reason: 'moved away from the initial camera',
    );

    for (final next in const [Size(240, 0), Size(240, 200)]) {
      size.value = next;
      await pumpFor(tester, const Duration(seconds: 1));
      final camera = controller.camera;
      _log('collapse $next: ${camera.center} z${camera.zoom} ${camera.nonRotatedSize}');
      expect(camera.zoom, closeTo(8, 0.01), reason: 'zoom at $next');
      expect(camera.center.latitude, closeTo(moved.latitude, 1e-4), reason: 'latitude at $next');
      expect(camera.center.longitude, closeTo(moved.longitude, 1e-4), reason: 'longitude at $next');
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  testWidgets(
    'macOS: resizing the window while the map starts and after it is ready keeps the camera',
    (tester) async {
      final probe = AppleNativeProbe.instance;
      Size windowSize() => tester.view.physicalSize / tester.view.devicePixelRatio;
      Future<void> resizeWindow(Size size) async {
        probe.animateWindowContentSize(size.width, size.height);
        expect(
          await pumpUntil(tester, () => windowSize() == size, const Duration(seconds: 5)),
          isTrue,
          reason: 'the window reaches $size (now ${windowSize()})',
        );
      }

      final initial = windowSize();
      addTearDown(() => probe.animateWindowContentSize(initial.width, initial.height));
      final controller = MapController();
      addTearDown(controller.dispose);
      var ready = false;
      var readyDuringResize = false;
      const center = LatLng(45.76, 4.84);
      const zoom = 7.4;
      const grown = Size(780, 620);

      await resizeWindow(const Size(420, 320));
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: UnifiedMap(
            mapController: controller,
            options: MapOptions(initialCenter: center, initialZoom: zoom, onMapReady: () => ready = true),
            children: const [],
          ),
        ),
      );
      probe.animateWindowContentSize(grown.width, grown.height);
      final sizes = <Size>{};
      expect(
        await pumpUntil(tester, () {
          sizes.add(windowSize());
          if (ready && windowSize() != grown) readyDuringResize = true;
          return windowSize() == grown;
        }, const Duration(seconds: 5)),
        isTrue,
      );
      expect(await pumpUntil(tester, () => ready, const Duration(seconds: 30)), isTrue, reason: 'map ready');
      await pumpUntil(tester, () => false, const Duration(seconds: 1));
      var camera = controller.camera;
      _log(
        'window grown at startup through ${sizes.length} sizes (ready during the resize: $readyDuringResize): '
        '${camera.center} z${camera.zoom} ${camera.nonRotatedSize}',
      );
      expect(sizes.length, greaterThan(2), reason: 'the window grew in several steps');
      expect(camera.nonRotatedSize, grown);
      expect(camera.zoom, closeTo(zoom, 0.01));
      expect(camera.center.latitude, closeTo(center.latitude, 1e-4));
      expect(camera.center.longitude, closeTo(center.longitude, 1e-4));

      for (final next in const [Size(560, 700), Size(900, 480)]) {
        await resizeWindow(next);
        expect(
          await pumpUntil(tester, () => controller.camera.nonRotatedSize == next, const Duration(seconds: 5)),
          isTrue,
          reason: 'the map reports the window size $next',
        );
        await pumpUntil(tester, () => false, const Duration(milliseconds: 800));
        camera = controller.camera;
        _log('window $next: ${camera.center} z${camera.zoom} ${camera.nonRotatedSize}');
        expect(camera.zoom, closeTo(zoom, 0.01), reason: 'zoom after resizing the window to $next');
        expect(camera.center.latitude, closeTo(center.latitude, 1e-4));
        expect(camera.center.longitude, closeTo(center.longitude, 1e-4));
      }
    },
    skip: !Platform.isMacOS,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
