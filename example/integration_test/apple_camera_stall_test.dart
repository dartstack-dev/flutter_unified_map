import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;
import 'package:integration_test/integration_test.dart';

import 'apple_native_probe.dart';
import 'apple_test_support.dart';

final _clock = Stopwatch()..start();

void _log(String message) => debugPrint('[stall] +${_clock.elapsedMilliseconds}ms $message');

/// Logs what crosses the platform boundary, with timestamps.
class _TimingPlatform extends DelegatingPlatform {
  _TimingPlatform(super.delegate);

  final idles = <(Duration, PlatformCamera)>[];
  var markerUpdates = 0;

  @override
  Future<void> updateMarkers(
    int viewId,
    MapObjectUpdates<PlatformMarker> updates, {
    PlatformMarkerTransition? transition,
  }) async {
    final started = _clock.elapsedMilliseconds;
    await delegate.updateMarkers(viewId, updates, transition: transition);
    markerUpdates++;
    _log(
      'updateMarkers +${updates.added.length} ~${updates.changed.length} -${updates.removedIds.length} '
      'took ${_clock.elapsedMilliseconds - started}ms',
    );
  }

  @override
  Future<void> moveCamera(int viewId, PlatformCameraUpdate update, {Duration? animation}) async {
    final started = _clock.elapsedMilliseconds;
    _log('moveCamera $update animation $animation');
    await delegate.moveCamera(viewId, update, animation: animation);
    _log('moveCamera done after ${_clock.elapsedMilliseconds - started}ms');
  }

  @override
  Stream<PlatformMapEvent> events(int viewId) => delegate.events(viewId).map((event) {
    switch (event) {
      case PlatformCameraMoveStartedEvent(:final byGesture):
        _log('event moveStarted byGesture $byGesture');
      case PlatformCameraIdleEvent(:final camera):
        idles.add((_clock.elapsed, camera));
        _log('event idle z${camera.zoom.toStringAsFixed(3)} ${camera.center}');
      case PlatformMapReadyEvent(:final camera):
        _log('event ready z${camera.zoom.toStringAsFixed(3)}');
      default:
    }
    return event;
  });
}

typedef _Step = ({String name, LatLng center, double zoom, bool animated});

const _steps = <_Step>[
  (name: 'europe z6', center: LatLng(48.5, 9.0), zoom: 6, animated: false),
  (name: 'munich z8', center: LatLng(48.14, 11.58), zoom: 8, animated: false),
  (name: 'munich z10', center: LatLng(48.14, 11.58), zoom: 10, animated: false),
  (name: 'munich z11', center: LatLng(48.14, 11.58), zoom: 11, animated: false),
  (name: 'pan munich z10', center: LatLng(48.30, 11.20), zoom: 10, animated: true),
  (name: 'z7', center: LatLng(48.30, 11.20), zoom: 7, animated: true),
  (name: 'z5', center: LatLng(47.0, 8.0), zoom: 5, animated: true),
  (name: 'paris z9', center: LatLng(48.86, 2.35), zoom: 9, animated: true),
  (name: 'paris z8 instant', center: LatLng(48.86, 2.35), zoom: 8, animated: false),
  (name: 'berlin z10 instant', center: LatLng(52.52, 13.40), zoom: 10, animated: false),
  (name: 'europe z4.6', center: LatLng(48.5, 9.0), zoom: 4.6, animated: true),
];

/// Markers spread over about one viewport around [center], with new keys every generation (as a recluster replaces
/// clusters) and badge icons keyed by a count that changes with the generation (new icons to register).
List<Marker> _markers(int generation, LatLng center, double zoom) {
  final random = math.Random(generation);
  final spread = 180 / math.pow(2, zoom);
  return [
    for (var i = 0; i < 60; i++)
      Marker(
        key: ValueKey('g$generation-$i'),
        point: LatLng(
          center.latitude + (random.nextDouble() - 0.5) * spread,
          center.longitude + (random.nextDouble() - 0.5) * spread * 1.5,
        ),
        width: 36,
        height: 36,
        iconKey: 'badge-${(generation * 7 + i) % 40}',
        child: _Badge((generation * 7 + i) % 40),
      ),
  ];
}

class _Badge extends StatelessWidget {
  const _Badge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: Color(0xFF00B0FF), shape: BoxShape.circle),
    child: Center(
      child: Text(
        '$count',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

/// Flutter on macOS renders no frame while its window is off screen (app hidden, window on another Space), so a
/// pump then blocks until it shows again, while Dart timers, platform messages and MapKit keep running; a window
/// merely covered by other windows keeps its frames (measured: 20 s under an opaque window, worst pump 27 ms). The
/// test keeps its window in front and samples its occlusion state from a timer: a stall while the window was not
/// visible is reported, a stall while it was visible fails.
class _WindowWatch {
  final _hidden = <Duration>[];
  Timer? _timer;
  final stalls = <String>[];
  var stalled = Duration.zero;

  void start() {
    if (!Platform.isMacOS) return;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!AppleNativeProbe.instance.windowVisible) _hidden.add(_clock.elapsed);
    });
  }

  void stop() => _timer?.cancel();

  /// Creating the native map may hold the platform thread before ready (Google Maps on the Android emulator: about
  /// 1.3 s); the test is about the camera path once the map is ready.
  void forgetStartup() {
    stalls.clear();
    stalled = Duration.zero;
  }

  bool _hiddenBetween(Duration from, Duration to) => _hidden.any((at) => at >= from && at <= to);

  Future<void> pumpFrame(WidgetTester tester) async {
    final started = _clock.elapsed;
    await tester.pump(const Duration(milliseconds: 16));
    final took = _clock.elapsed - started;
    if (took < const Duration(seconds: 1)) return;
    stalled += took;
    if (_hiddenBetween(started, _clock.elapsed)) {
      _log('no frame for ${took.inMilliseconds}ms while the test window was not visible');
    } else {
      stalls.add('no frame for ${took.inMilliseconds}ms at +${started.inMilliseconds}ms with the window visible');
      _log(stalls.last);
    }
  }
}

final _window = _WindowWatch();

Future<void> _pumpFrame(WidgetTester tester) => _window.pumpFrame(tester);

Future<bool> _pumpUntil(WidgetTester tester, bool Function() condition, Duration timeout) =>
    pumpUntil(tester, condition, timeout, pumpFrame: _pumpFrame);

bool _reached(PlatformCamera camera, _Step step) =>
    (camera.zoom - step.zoom).abs() < 0.05 &&
    (camera.center.latitude - step.center.latitude).abs() < 0.01 &&
    (camera.center.longitude - step.center.longitude).abs() < 0.01;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  AppleNativeProbe.holdTestWindowInFront();

  late UnifiedMapsPlatform real;
  late _TimingPlatform timing;

  setUp(() {
    real = UnifiedMapsPlatform.instance;
    timing = _TimingPlatform(real);
    UnifiedMapsPlatform.instance = timing;
  });

  tearDown(() => UnifiedMapsPlatform.instance = real);

  testWidgets('camera moves are reported promptly while the markers are replaced at every step', (tester) async {
    _window.start();
    addTearDown(_window.stop);
    final controller = MapController();
    addTearDown(controller.dispose);
    var ready = false;
    var generation = 0;
    final markers = ValueNotifier(_markers(0, const LatLng(48.5, 9.0), 4.6));
    addTearDown(markers.dispose);
    void recluster(LatLng center, double zoom) => markers.value = _markers(++generation, center, zoom);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: UnifiedMap(
            mapController: controller,
            options: MapOptions(
              initialCenter: const LatLng(48.5, 9.0),
              initialZoom: 4.6,
              onMapReady: () => ready = true,
            ),
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
    _window.forgetStartup();
    final subscription = controller.mapEventStream.listen((event) {
      if (event is MapEventMoveEnd) recluster(controller.camera.center, controller.camera.zoom);
    });
    addTearDown(subscription.cancel);
    await _pumpUntil(tester, () => false, const Duration(seconds: 2));

    final latencies = <String, int>{};
    final failures = <String>[];
    for (final step in _steps) {
      _log('STEP ${step.name}');
      recluster(controller.camera.center, controller.camera.zoom);
      await _pumpFrame(tester);
      final sentAt = _clock.elapsed;
      if (step.animated) {
        unawaited(
          controller.animateTo(dest: step.center, zoom: step.zoom, duration: const Duration(milliseconds: 600)),
        );
      } else {
        controller.move(step.center, step.zoom);
      }
      // Dart receive times: they keep advancing during a frame stall, so a late idle means a late MapKit report.
      bool arrived((Duration, PlatformCamera) idle) => idle.$1 >= sentAt && _reached(idle.$2, step);
      final reached = await _pumpUntil(tester, () => timing.idles.any(arrived), const Duration(seconds: 8));
      final latency = reached ? (timing.idles.firstWhere(arrived).$1 - sentAt).inMilliseconds : -1;
      latencies[step.name] = latency;
      _log('STEP ${step.name} reached $reached after ${latency}ms, camera ${controller.camera.zoom}');
      if (!reached) {
        failures.add('${step.name}: no idle at the target within 8 s (last idle ${timing.idles.lastOrNull?.$2})');
      } else if (strictPerf && latency > (step.animated ? 3000 : 2000)) {
        failures.add('${step.name}: idle after ${latency}ms');
      }
      await _pumpUntil(tester, () => false, const Duration(milliseconds: 700));
      final snapshotStarted = _clock.elapsedMilliseconds;
      final snapshot = await tester.runAsync(controller.takeSnapshot);
      _log('snapshot ${snapshot?.length} bytes after ${_clock.elapsedMilliseconds - snapshotStarted}ms');
    }
    if (Platform.isMacOS) await _moveWhileHidden(tester, controller, timing, failures);
    _log('latencies $latencies, frame stalls ${_window.stalled.inMilliseconds}ms');
    expect(failures, isEmpty);
    expect(_window.stalls, isEmpty, reason: 'Flutter frames stalled while the window was visible');
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpUntil(tester, () => false, const Duration(milliseconds: 200));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// The camera path must not depend on Flutter frames: with the app hidden (no frames), an instant move still
/// reaches MapKit and its idle comes back; frames resume once the app shows again.
Future<void> _moveWhileHidden(
  WidgetTester tester,
  MapController controller,
  _TimingPlatform timing,
  List<String> failures,
) async {
  const step = (name: 'hidden: munich z9', center: LatLng(48.14, 11.58), zoom: 9.0, animated: false);
  final probe = AppleNativeProbe.instance;
  _log('STEP ${step.name}');
  final markersBefore = timing.markerUpdates;
  probe.setAppHidden(true);
  try {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    final sentAt = _clock.elapsed;
    controller.move(step.center, step.zoom);
    bool arrived((Duration, PlatformCamera) idle) => idle.$1 >= sentAt && _reached(idle.$2, step);
    final waited = Stopwatch()..start();
    while (!timing.idles.any(arrived) && waited.elapsed < const Duration(seconds: 3)) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    final idle = timing.idles.where(arrived).firstOrNull;
    _log(
      'STEP ${step.name}: window visible ${probe.windowVisible}, idle after '
      '${idle == null ? 'none' : '${(idle.$1 - sentAt).inMilliseconds}ms'}, '
      'marker updates while hidden ${timing.markerUpdates - markersBefore}',
    );
    if (idle == null) failures.add('${step.name}: no idle within 3 s while the app was hidden');
  } finally {
    probe.setAppHidden(false);
    probe.keepWindowInFront();
  }
  final resumed = Stopwatch()..start();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump(const Duration(milliseconds: 16));
  _log('frames resumed ${resumed.elapsedMilliseconds}ms after showing the app again');
  if (resumed.elapsed > const Duration(seconds: 3)) failures.add('${step.name}: frames did not resume after unhide');
}
