import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;
import 'package:integration_test/integration_test.dart';

import 'apple_native_probe.dart';
import 'apple_test_support.dart';
import 'support/pixels.dart';

final _clock = Stopwatch()..start();

void _log(String message) => debugPrint('[transition] +${_clock.elapsedMilliseconds}ms $message');

/// Attaches [next] to the following marker update, so the test drives `PlatformMarkerTransition` on MapKit with a
/// plain MarkerLayer. Transitions name markers by their key; the real ids are `'<layerId>/k:<key>'`.
class _TransitionPlatform extends DelegatingPlatform {
  _TransitionPlatform(super.delegate);

  ({Duration duration, Map<String, LatLng> appearFrom, Map<String, LatLng> disappearTo})? next;
  Duration? lastSentAt;
  int published = 0;

  @override
  Future<void> updateMarkers(
    int viewId,
    MapObjectUpdates<PlatformMarker> updates, {
    PlatformMarkerTransition? transition,
  }) async {
    final hint = next;
    next = null;
    String? idOf(String key, Iterable<String> ids) => ids.where((id) => id.endsWith('/k:$key')).firstOrNull;
    final applied = hint == null
        ? transition
        : PlatformMarkerTransition(
            duration: hint.duration,
            appearFrom: {
              for (final MapEntry(:key, :value) in hint.appearFrom.entries)
                ?idOf(key, updates.added.map((m) => m.id)): value,
            },
            disappearTo: {
              for (final MapEntry(:key, :value) in hint.disappearTo.entries) ?idOf(key, updates.removedIds): value,
            },
          );
    _log(
      'updateMarkers +${updates.added.length} ~${updates.changed.length} -${updates.removedIds.length} '
      'transition $applied',
    );
    lastSentAt = _clock.elapsed;
    await delegate.updateMarkers(viewId, updates, transition: applied);
    published++;
  }
}

const _magenta = Color(0xFFFF00FF);
const _green = Color(0xFF00C853);
const _cyan = Color(0xFF00B0FF);
const _markerSize = 24.0;

Marker _dot(String key, LatLng point, Color color) => Marker(
  key: ValueKey(key),
  point: point,
  width: _markerSize,
  height: _markerSize,
  iconKey: 'dot-${color.toARGB32()}',
  child: DecoratedBox(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  ),
);

extension on RgbaImage {
  ({Offset centroid, int count}) _centroid(Rect region, bool Function(int r, int g, int b, int a) test) {
    final area = region.intersect(bounds);
    var count = 0;
    var sx = 0.0;
    var sy = 0.0;
    if (!area.isEmpty) {
      for (var y = area.top.floor(); y < area.bottom.ceil(); y++) {
        for (var x = area.left.floor(); x < area.right.ceil(); x++) {
          final i = (y * width + x) * 4;
          if (!test(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])) continue;
          count++;
          sx += x;
          sy += y;
        }
      }
    }
    return (centroid: count == 0 ? Offset.zero : Offset(sx / count, sy / count), count: count);
  }

  /// Centroid (in this image's pixels) and count of the pixels within [tolerance] of [color] inside [region].
  ({Offset centroid, int count}) find(Color color, {int tolerance = 40, Rect? region}) {
    final argb = color.toARGB32();
    final (r0, g0, b0) = ((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
    return _centroid(
      region ?? bounds,
      (r, g, b, a) =>
          a >= 200 && (r - r0).abs() <= tolerance && (g - g0).abs() <= tolerance && (b - b0).abs() <= tolerance,
    );
  }

  /// Pixels whose hue is magenta's (a magenta marker faded over the base map keeps its hue).
  int countMagentaHue(Rect region) => _magentaHue(region).count;

  Offset magentaHueCentroid(Rect region) => _magentaHue(region).centroid;

  ({Offset centroid, int count}) _magentaHue(Rect region) =>
      _centroid(region, (r, g, b, _) => r - g > 50 && b - g > 50 && (r - b).abs() < 40);
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) => pumpFor(tester, duration);

Future<bool> _pumpUntil(WidgetTester tester, bool Function() condition, Duration timeout) =>
    pumpUntil(tester, condition, timeout);

double _ease(double t) {
  double bezier(double s, double a, double b) => 3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s;
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < 40; i++) {
    final mid = (lo + hi) / 2;
    if (bezier(mid, 0.42, 0.58) < t) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return bezier((lo + hi) / 2, 0, 1);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  AppleNativeProbe.holdTestWindowInFront();

  late UnifiedMapsPlatform real;
  late _TransitionPlatform platform;

  setUp(() {
    real = UnifiedMapsPlatform.instance;
    platform = _TransitionPlatform(real);
    UnifiedMapsPlatform.instance = platform;
  });

  tearDown(() => UnifiedMapsPlatform.instance = real);

  testWidgets('marker transitions move, fade, revive and remove markers on MapKit', (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    var ready = false;
    const center = LatLng(48.14, 11.58);
    const degreesPerPixel = 360 / (256 * 1024);
    LatLng shifted(LatLng point, double dx) => LatLng(point.latitude, point.longitude + dx * degreesPerPixel);
    final target = shifted(center, 60);
    final parent = shifted(center, -100);
    final greenStart = shifted(center, -60);
    final greenEnd = shifted(center, 80);
    final markers = ValueNotifier(<Marker>[_dot('green', greenStart, _green)]);
    addTearDown(markers.dispose);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: UnifiedMap(
            mapController: controller,
            options: MapOptions(initialCenter: center, initialZoom: 10, onMapReady: () => ready = true),
            children: [
              ValueListenableBuilder(
                valueListenable: markers,
                builder: (context, value, _) => MarkerLayer(markers: value),
              ),
            ],
          ),
        ),
      ),
    );
    expect(await _pumpUntil(tester, () => ready, const Duration(seconds: 30)), isTrue, reason: 'map ready');
    await _pumpFor(tester, const Duration(seconds: 2));
    final origin = tester.getTopLeft(find.byType(UnifiedMap));

    Future<RgbaImage> snapshot() async {
      final bytes = await tester.runAsync(controller.takeSnapshot);
      return (await tester.runAsync(() => decodePng(bytes!)))!;
    }

    Future<RgbaImage?> screen(String name) async {
      if (!Platform.isIOS) return null;
      final bytes = Uint8List.fromList(await binding.takeScreenshot(name));
      return tester.runAsync(() => decodePng(bytes));
    }

    Offset logical(RgbaImage image, Offset pixel) {
      final scale = image.width / controller.camera.nonRotatedSize.width;
      return pixel / scale;
    }

    Rect snapshotBand(RgbaImage image, LatLng a, LatLng b) {
      final scale = image.width / controller.camera.nonRotatedSize.width;
      return Rect.fromPoints(
        controller.camera.latLngToScreenOffset(a) * scale,
        controller.camera.latLngToScreenOffset(b) * scale,
      ).inflate(20 * scale);
    }

    /// The opacities of the annotation views MapKit holds right now (null: no view, off-screen); null off Apple.
    List<double?>? onMap() =>
        AppleNativeProbe.isAvailable ? AppleNativeProbe.instance.annotationOpacities().single : null;

    void expectOnMap(Object? actual, Object? matcher, {String? reason}) {
      if (actual != null) expect(actual, matcher, reason: reason);
    }

    bool inFade(double? alpha) => alpha != null && alpha > 0.05 && alpha < 0.95;

    double screenScale(RgbaImage image) =>
        image.width / (tester.view.physicalSize.width / tester.view.devicePixelRatio);

    Offset onScreen(RgbaImage image, LatLng point) =>
        (controller.camera.latLngToScreenOffset(point) + origin) * screenScale(image);

    Rect around(RgbaImage image, LatLng point) => Rect.fromCenter(
      center: onScreen(image, point),
      width: 40 * screenScale(image),
      height: 40 * screenScale(image),
    );

    Future<void> publish(List<Marker> next) async {
      final before = platform.published;
      markers.value = next;
      expect(
        await _pumpUntil(tester, () => platform.published > before, const Duration(seconds: 5)),
        isTrue,
        reason: 'markers published',
      );
    }

    final targetX = controller.camera.latLngToScreenOffset(target).dx;
    final parentX = controller.camera.latLngToScreenOffset(parent).dx;

    // Appear from the parent position.
    platform.next = (
      duration: const Duration(milliseconds: 2400),
      appearFrom: {'a': parent},
      disappearTo: const <String, LatLng>{},
    );
    await publish([_dot('green', greenStart, _green), _dot('a', target, _magenta)]);
    final sentAt = platform.lastSentAt!;
    await _pumpFor(tester, const Duration(milliseconds: 900));
    final midAt = _clock.elapsed - sentAt;
    final appearing = onMap();
    final mid = await snapshot();
    final midBand = snapshotBand(mid, parent, target);
    final midX = logical(mid, mid.magentaHueCentroid(midBand)).dx;
    final expectedFraction = _ease(midAt.inMilliseconds / 2400);
    _log(
      'appear: x $midX at ${midAt.inMilliseconds}ms, parent $parentX, target $targetX, '
      'expected about ${parentX + (targetX - parentX) * expectedFraction}; native opacities $appearing',
    );
    expectOnMap(appearing, hasLength(2));
    expectOnMap(appearing?.where(inFade), hasLength(1), reason: 'the appearing view is fading in');
    expect(mid.countMagentaHue(midBand), greaterThan(0), reason: 'an appearing marker is in the snapshot');
    expect(mid.find(_magenta, tolerance: 12, region: midBand).count, 0, reason: 'drawn translucent in the snapshot');
    expect(midX, greaterThan(parentX + (targetX - parentX) * 0.1), reason: 'left the parent position');
    expect(midX, lessThan(targetX - (targetX - parentX) * 0.1), reason: 'not at its position yet');
    final midScreen = await screen('transition-appearing');
    if (midScreen != null) {
      final band = Rect.fromPoints(
        onScreen(midScreen, parent),
        onScreen(midScreen, target),
      ).inflate(20 * screenScale(midScreen));
      final x = (midScreen.magentaHueCentroid(band) / screenScale(midScreen)).dx - origin.dx;
      _log('appear on screen: x $x at ${(_clock.elapsed - sentAt).inMilliseconds}ms');
      expect(x, greaterThan(parentX + (targetX - parentX) * 0.1), reason: 'the view left the parent position');
      expect(x, lessThan(targetX - (targetX - parentX) * 0.05), reason: 'the view is not at its position yet');
    }

    await _pumpUntil(
      tester,
      () => _clock.elapsed - sentAt > const Duration(milliseconds: 2700),
      const Duration(seconds: 5),
    );
    final landed = await snapshot();
    expect((logical(landed, landed.find(_magenta).centroid).dx - targetX).abs(), lessThan(2), reason: 'landed');
    final landedScreen = await screen('transition-landed');
    if (landedScreen != null) {
      final found = landedScreen.find(_magenta, tolerance: 12, region: around(landedScreen, target)).count;
      expect(found, greaterThan(100), reason: 'opaque on screen');
    }

    // Disappear into the parent position.
    platform.next = (
      duration: const Duration(milliseconds: 1600),
      appearFrom: const <String, LatLng>{},
      disappearTo: {'a': parent},
    );
    await publish([_dot('green', greenStart, _green)]);
    final removedAt = platform.lastSentAt!;
    expectOnMap(onMap(), hasLength(2), reason: 'a disappearing marker stays on the map while it fades');
    final leaving = await snapshot();
    expect(
      leaving.countMagentaHue(snapshotBand(leaving, parent, target)),
      0,
      reason: 'a disappearing marker is left out of snapshots',
    );
    await _pumpUntil(
      tester,
      () => _clock.elapsed - removedAt > const Duration(milliseconds: 700),
      const Duration(seconds: 5),
    );
    final fadingOut = onMap();
    _log('fading out: native opacities $fadingOut');
    expectOnMap(fadingOut?.where(inFade), hasLength(1), reason: 'the disappearing view is fading out');
    final fading = await screen('transition-fading');
    if (fading != null) {
      final band = Rect.fromPoints(
        onScreen(fading, parent),
        onScreen(fading, target),
      ).inflate(30 * screenScale(fading));
      final hue = fading.countMagentaHue(band);
      final opaque = fading.find(_magenta, tolerance: 12, region: band).count;
      _log('fading: magenta hue $hue px, opaque magenta $opaque px');
      expect(hue, greaterThan(50), reason: 'still on screen while fading');
    }
    await _pumpUntil(
      tester,
      () => _clock.elapsed - removedAt > const Duration(milliseconds: 2000),
      const Duration(seconds: 5),
    );
    expectOnMap(onMap(), [1.0], reason: 'removed from the MKMapView once faded out');
    final gone = await screen('transition-gone');
    if (gone != null) {
      final band = Rect.fromPoints(onScreen(gone, parent), onScreen(gone, target)).inflate(30 * screenScale(gone));
      expect(gone.countMagentaHue(band), lessThan(20), reason: 'removed from the map at the end');
    }

    // Revive: removed with a long transition, added back while it is still fading.
    await publish([_dot('green', greenStart, _green), _dot('a', target, _magenta)]);
    await _pumpFor(tester, const Duration(milliseconds: 300));
    platform.next = (
      duration: const Duration(milliseconds: 2000),
      appearFrom: const <String, LatLng>{},
      disappearTo: {'a': parent},
    );
    await publish([_dot('green', greenStart, _green)]);
    await _pumpFor(tester, const Duration(milliseconds: 700));
    platform.next = (
      duration: const Duration(milliseconds: 800),
      appearFrom: {'a': parent},
      disappearTo: const <String, LatLng>{},
    );
    await publish([_dot('green', greenStart, _green), _dot('a', target, _magenta)]);
    final revived = await snapshot();
    final revivedBand = snapshotBand(revived, parent, target);
    final revivedX = logical(revived, revived.magentaHueCentroid(revivedBand)).dx;
    _log('revived at x $revivedX (parent $parentX, target $targetX); native opacities ${onMap()}');
    expectOnMap(onMap(), hasLength(2), reason: 'one annotation for the revived marker');
    expect(revived.countMagentaHue(revivedBand), greaterThan(0), reason: 'a revived marker is published again');
    expect(revivedX, greaterThan(parentX + 5), reason: 'continues from where it was, not from appearFrom');
    expect(revivedX, lessThan(targetX - 5), reason: 'was on its way to the parent');
    await _pumpFor(tester, const Duration(milliseconds: 1500));
    expectOnMap(onMap(), [1.0, 1.0], reason: 'the revived marker is opaque again');
    final back = await snapshot();
    expect((logical(back, back.find(_magenta).centroid).dx - targetX).abs(), lessThan(2), reason: 'back in place');
    final backScreen = await screen('transition-revived');
    if (backScreen != null) {
      final found = backScreen.find(_magenta, tolerance: 12, region: around(backScreen, target)).count;
      expect(found, greaterThan(100), reason: 'revived marker is opaque');
    }

    // A changed position glides.
    platform.next = (
      duration: const Duration(milliseconds: 1500),
      appearFrom: const <String, LatLng>{},
      disappearTo: const <String, LatLng>{},
    );
    await publish([_dot('green', greenEnd, _green), _dot('a', target, _magenta)]);
    final glideAt = platform.lastSentAt!;
    await _pumpFor(tester, const Duration(milliseconds: 650));
    final gliding = await snapshot();
    final glideX = logical(gliding, gliding.find(_green).centroid).dx;
    final startX = controller.camera.latLngToScreenOffset(greenStart).dx;
    final endX = controller.camera.latLngToScreenOffset(greenEnd).dx;
    _log('glide: x $glideX between $startX and $endX at ${(_clock.elapsed - glideAt).inMilliseconds}ms');
    expect(glideX, greaterThan(startX + 10));
    expect(glideX, lessThan(endX - 10));
    await _pumpUntil(
      tester,
      () => _clock.elapsed - glideAt > const Duration(milliseconds: 1800),
      const Duration(seconds: 5),
    );
    final glided = await snapshot();
    expect((logical(glided, glided.find(_green).centroid).dx - endX).abs(), lessThan(2));

    // Quick churn: updates overtake running transitions; nothing may be left behind.
    final keep = [_dot('green', greenEnd, _green)];
    List<Marker> ring(int round) => [
      for (var i = 0; i < 12; i++)
        if ((i + round) % 3 != 0) _dot('c$i', LatLng(center.latitude + (i - 6) * 0.01, center.longitude), _cyan),
    ];
    for (var round = 0; round < 10; round++) {
      final next = ring(round);
      platform.next = (
        duration: const Duration(milliseconds: 400),
        appearFrom: {for (final m in next) (m.key! as ValueKey<String>).value: center},
        disappearTo: {for (var i = 0; i < 12; i++) 'c$i': center},
      );
      await publish([...keep, ...next]);
      await _pumpFor(tester, const Duration(milliseconds: 120));
    }
    platform.next = (
      duration: const Duration(milliseconds: 400),
      appearFrom: const <String, LatLng>{},
      disappearTo: {for (var i = 0; i < 12; i++) 'c$i': center},
    );
    await publish(keep);
    await _pumpFor(tester, const Duration(milliseconds: 1200));
    expectOnMap(onMap(), [1.0], reason: 'only the green marker is left on the MKMapView after the churn');
    expect((await snapshot()).find(_cyan).count, 0, reason: 'snapshot after churn');
    final churned = await screen('transition-churn');
    if (churned != null) {
      final mapRect = origin & controller.camera.nonRotatedSize;
      final scale = screenScale(churned);
      final region = Rect.fromLTRB(
        mapRect.left * scale,
        mapRect.top * scale,
        mapRect.right * scale,
        mapRect.bottom * scale,
      );
      expect(churned.find(_cyan, tolerance: 20, region: region).count, lessThan(30), reason: 'no leaked markers');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
