import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;
import 'package:integration_test/integration_test.dart';

import 'apple_native_probe.dart';
import 'apple_test_support.dart';

void _log(String message) => debugPrint('[load] $message');

/// Animates every marker of the next update: added ones from [origin], removed ones into it.
class _SplitPlatform extends DelegatingPlatform {
  _SplitPlatform(super.delegate);

  ({Duration duration, LatLng origin})? next;
  int published = 0;
  Duration lastCall = Duration.zero;

  @override
  Future<void> updateMarkers(
    int viewId,
    MapObjectUpdates<PlatformMarker> updates, {
    PlatformMarkerTransition? transition,
  }) async {
    final hint = next;
    next = null;
    final clock = Stopwatch()..start();
    await delegate.updateMarkers(
      viewId,
      updates,
      transition: hint == null
          ? transition
          : PlatformMarkerTransition(
              duration: hint.duration,
              appearFrom: {for (final m in updates.added) m.id: hint.origin},
              disappearTo: {for (final id in updates.removedIds) id: hint.origin},
            ),
    );
    lastCall = clock.elapsed;
    published++;
  }
}

/// How long the platform thread was unavailable to Dart over [duration]: Dart runs on it (merged threads), so a
/// zero-delay loop only advances between the native work items, such as the frame ticker of the transitions.
Future<({int p50, int p95, int max, double busy})> _mainThreadGaps(Duration duration) async {
  final clock = Stopwatch()..start();
  final gaps = <int>[];
  var last = clock.elapsedMicroseconds;
  while (clock.elapsed < duration) {
    await Future<void>.delayed(Duration.zero);
    final now = clock.elapsedMicroseconds;
    gaps.add(now - last);
    last = now;
  }
  gaps.sort();
  final blocked = gaps.where((g) => g > 2000).fold<int>(0, (sum, g) => sum + g);
  return (
    p50: gaps[gaps.length ~/ 2],
    p95: gaps[(gaps.length * 0.95).floor()],
    max: gaps.last,
    busy: blocked / clock.elapsedMicroseconds,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  AppleNativeProbe.holdTestWindowInFront();

  late UnifiedMapsPlatform real;
  late _SplitPlatform platform;

  setUp(() {
    real = UnifiedMapsPlatform.instance;
    platform = _SplitPlatform(real);
    UnifiedMapsPlatform.instance = platform;
  });

  tearDown(() => UnifiedMapsPlatform.instance = real);

  testWidgets('hundreds of markers split and merge without starving the platform thread', (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    var ready = false;
    const center = LatLng(48.14, 11.58);
    final markers = ValueNotifier(<Marker>[]);
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
    expect(await pumpUntil(tester, () => ready, const Duration(seconds: 30)), isTrue, reason: 'map ready');
    await pumpUntil(tester, () => false, const Duration(seconds: 1));
    final visible = controller.camera.visibleBounds;

    List<Marker> scattered(int count, int seed) {
      final random = math.Random(seed);
      return [
        for (var i = 0; i < count; i++)
          Marker(
            key: ValueKey('s$seed-$i'),
            point: LatLng(
              visible.south + random.nextDouble() * (visible.north - visible.south),
              visible.west + random.nextDouble() * (visible.east - visible.west),
            ),
            width: 24,
            height: 24,
            iconKey: 'load-dot',
            child: const DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFF00B0FF), shape: BoxShape.circle),
            ),
          ),
      ];
    }

    Future<void> publish(List<Marker> next, Duration? duration) async {
      final before = platform.published;
      if (duration != null) platform.next = (duration: duration, origin: center);
      markers.value = next;
      expect(await pumpUntil(tester, () => platform.published > before, const Duration(seconds: 10)), isTrue);
    }

    final idle = (await tester.runAsync(() => _mainThreadGaps(const Duration(milliseconds: 600))))!;
    _log('idle map: gaps p50 ${idle.p50}us p95 ${idle.p95}us max ${idle.max}us, busy ${idle.busy}');

    final results = <String>[];
    for (final count in const [100, 300, 600]) {
      if (markers.value.isNotEmpty) await publish(const [], null);
      await pumpUntil(tester, () => false, const Duration(milliseconds: 300));
      await publish(scattered(count, count), const Duration(milliseconds: 600));
      final split = platform.lastCall;
      final during = (await tester.runAsync(() => _mainThreadGaps(const Duration(milliseconds: 600))))!;
      await pumpUntil(tester, () => false, const Duration(milliseconds: 300));
      if (AppleNativeProbe.isAvailable) {
        expect(AppleNativeProbe.instance.annotationOpacities().single, hasLength(count));
      }

      await publish(const [], const Duration(milliseconds: 600));
      final merge = platform.lastCall;
      final merging = (await tester.runAsync(() => _mainThreadGaps(const Duration(milliseconds: 600))))!;
      await pumpUntil(tester, () => false, const Duration(milliseconds: 300));
      if (AppleNativeProbe.isAvailable) {
        expect(AppleNativeProbe.instance.annotationOpacities().single, isEmpty, reason: 'merged markers are removed');
      }

      await publish(scattered(count, count + 1), null);
      final instant = platform.lastCall;
      await pumpUntil(tester, () => false, const Duration(milliseconds: 300));

      final line =
          '$count markers: split call ${split.inMilliseconds}ms, gaps p50 ${during.p50}us p95 ${during.p95}us '
          'max ${during.max}us busy ${during.busy.toStringAsFixed(2)}; merge call ${merge.inMilliseconds}ms, gaps '
          'p50 ${merging.p50}us p95 ${merging.p95}us max ${merging.max}us busy ${merging.busy.toStringAsFixed(2)}; '
          'instant add call ${instant.inMilliseconds}ms';
      results.add(line);
      _log(line);
      // Budgets measured on MapKit. On the Android emulator the Google Maps SDK alone exceeds them (an unanimated
      // add of 100 markers takes 100-200 ms there), so it only logs.
      if (!AppleNativeProbe.isAvailable || !strictPerf) continue;
      for (final (name, call, gaps) in [('split', split, during), ('merge', merge, merging)]) {
        expect(call, lessThan(const Duration(milliseconds: 60)), reason: '$count markers: $name update call');
        expect(gaps.max, lessThan(50000), reason: '$count markers: longest platform thread block during the $name');
      }
    }
    for (final line in results) {
      _log(line);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpUntil(tester, () => false, const Duration(milliseconds: 200));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
