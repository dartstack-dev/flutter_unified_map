import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' as pi show Offset;
import 'package:integration_test/integration_test.dart';

import 'apple_native_probe.dart';
import 'apple_test_support.dart';

void _log(String message) => debugPrint('[contract] $message');

/// Remembers the view the core builds, so the test can call the platform for it directly.
class _ViewPlatform extends DelegatingPlatform {
  _ViewPlatform(super.delegate);

  int? viewId;
  PlatformMapOptions? options;

  @override
  Widget buildView({
    required int viewId,
    required PlatformMapOptions options,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  }) {
    this.viewId = viewId;
    this.options = options;
    return super.buildView(viewId: viewId, options: options, gestureRecognizers: gestureRecognizers);
  }
}

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = color);
  final image = await recorder.endRecording().toImage(8, 8);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Platform calls the core does not make itself (padding, invalid values, undecodable icons), checked on MapKit.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  AppleNativeProbe.holdTestWindowInFront();

  late UnifiedMapsPlatform real;
  late _ViewPlatform platform;

  setUp(() {
    real = UnifiedMapsPlatform.instance;
    platform = _ViewPlatform(real);
    UnifiedMapsPlatform.instance = platform;
  });

  tearDown(() => UnifiedMapsPlatform.instance = real);

  Future<int> mountMap(WidgetTester tester) async {
    var ready = false;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: UnifiedMap(
            options: MapOptions(
              initialCenter: const LatLng(48.14, 11.58),
              initialZoom: 8,
              onMapReady: () => ready = true,
            ),
            children: const [],
          ),
        ),
      ),
    );
    expect(await pumpUntil(tester, () => ready, const Duration(seconds: 30)), isTrue, reason: 'map ready');
    await pumpFor(tester, const Duration(milliseconds: 500));
    return platform.viewId!;
  }

  testWidgets('a padding change during an animated move keeps animating to the target', (tester) async {
    final viewId = await mountMap(tester);
    const target = LatLng(48.86, 2.35);
    final clock = Stopwatch()..start();
    var done = false;
    final move = real.moveCamera(
      viewId,
      const PlatformCameraUpdate.newCamera(center: target, zoom: 9),
      animation: const Duration(milliseconds: 1200),
    );
    unawaited(move.then((_) => done = true, onError: (Object _) => done = true));
    await pumpFor(tester, const Duration(milliseconds: 300));
    await real.updateOptions(viewId, platform.options!.copyWith(padding: const EdgeInsets.only(bottom: 200)));
    expect(await pumpUntil(tester, () => done, const Duration(seconds: 8)), isTrue, reason: 'the move completes');
    final took = clock.elapsed;
    await move;
    final camera = await real.getCamera(viewId);
    _log('padding during the move: completed after ${took.inMilliseconds}ms at ${camera.center} z${camera.zoom}');
    expect(took, greaterThan(const Duration(milliseconds: 900)), reason: 'completes when the animation ends');
    expect(camera.center.latitude, closeTo(target.latitude, 1e-3), reason: 'the target, in the new padded center');
    expect(camera.center.longitude, closeTo(target.longitude, 1e-3));
    expect(camera.zoom, closeTo(9, 0.01));
  }, skip: !AppleNativeProbe.isAvailable);

  testWidgets('padding keeps the camera target, and moves land in the center of the padded area', (tester) async {
    final viewId = await mountMap(tester);
    void expectAt(PlatformCamera camera, LatLng center, double zoom, String reason) {
      expect(camera.center.latitude, closeTo(center.latitude, 1e-4), reason: reason);
      expect(camera.center.longitude, closeTo(center.longitude, 1e-4), reason: reason);
      expect(camera.zoom, closeTo(zoom, 0.01), reason: reason);
    }

    await real.updateOptions(viewId, platform.options!.copyWith(padding: const EdgeInsets.only(bottom: 200)));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expectAt(await real.getCamera(viewId), const LatLng(48.14, 11.58), 8, 'the padding change keeps the target');

    const paris = LatLng(48.86, 2.35);
    await real.moveCamera(viewId, const PlatformCameraUpdate.newCamera(center: paris, zoom: 9));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expectAt(await real.getCamera(viewId), paris, 9, 'instant move');
    final onScreen = await real.toScreen(viewId, paris);
    final size = tester.getSize(find.byType(UnifiedMap));
    _log('target on screen at $onScreen in $size');
    expect(onScreen.dy, closeTo((size.height - 200) / 2, 1), reason: 'drawn at the center of the padded area');

    await real.moveCamera(
      viewId,
      const PlatformCameraUpdate.newCamera(center: LatLng(48.14, 11.58), zoom: 8),
      animation: const Duration(milliseconds: 400),
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    expectAt(await real.getCamera(viewId), const LatLng(48.14, 11.58), 8, 'animated move');
  }, skip: !AppleNativeProbe.isAvailable);

  testWidgets('a camera update with a non-finite value completes and leaves the camera', (tester) async {
    final viewId = await mountMap(tester);
    final before = await real.getCamera(viewId);
    await real.moveCamera(viewId, const PlatformCameraUpdate.newCamera(zoom: double.nan));
    await real.moveCamera(
      viewId,
      const PlatformCameraUpdate.newCamera(bearing: double.infinity),
      animation: const Duration(milliseconds: 300),
    );
    await pumpFor(tester, const Duration(milliseconds: 500));
    final after = await real.getCamera(viewId);
    _log('non-finite moves: $before -> $after');
    expect(after.zoom, closeTo(before.zoom, 1e-6));
    expect(after.center.latitude, closeTo(before.center.latitude, 1e-6));
    expect(after.bearing.isFinite, isTrue);
  }, skip: !AppleNativeProbe.isAvailable);

  testWidgets('an icon that cannot be decoded fails the update, and is sent again by the next one', (tester) async {
    final viewId = await mountMap(tester);
    PlatformMarker marker(Uint8List bytes) => PlatformMarker(
      id: 'contract/broken',
      position: const LatLng(48.14, 11.58),
      icon: PlatformIcon(key: 'contract-icon', bytes: bytes, logicalSize: const Size(8, 8), pixelRatio: 1),
      anchor: const pi.Offset(0.5, 0.5),
    );
    await expectLater(
      real.updateMarkers(
        viewId,
        MapObjectUpdates(
          added: [
            marker(Uint8List.fromList([1, 2, 3])),
          ],
        ),
      ),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'icon-decode-failed')),
    );
    final png = (await tester.runAsync(() => _png(const Color(0xFFFF00FF))))!;
    await real.updateMarkers(viewId, MapObjectUpdates(added: [marker(png)]));
    await pumpFor(tester, const Duration(milliseconds: 300));
    final snapshot = await tester.runAsync(() => real.takeSnapshot(viewId));
    expect(snapshot, isNotNull);
    final opacities = AppleNativeProbe.instance.annotationOpacities().single;
    _log('after the retry: annotation opacities $opacities');
    expect(opacities, [1.0], reason: 'the marker is on the map with its icon');
  }, skip: !AppleNativeProbe.isAvailable);
}
