import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_example/src/geometry_data.dart';
import 'package:flutter_unified_map_example/src/geometry_page.dart';

import 'recording_platform.dart';

void log(String message) => debugPrint('[geometry] $message');

/// Waits until [condition] holds, at most [timeout] of wall-clock time. Each step lets real async work run
/// (icon rasterising, platform channels) and then pumps a frame, which also advances a fake clock by [step].
/// Works under both `flutter test` (fake async) and `integration_test` (live binding).
Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  Duration step = const Duration(milliseconds: 20),
}) async {
  final clock = Stopwatch()..start();
  while (!condition()) {
    if (clock.elapsed > timeout) return false;
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump(step);
  }
  return true;
}

/// Pumps for [duration] of wall-clock time.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  await pumpUntil(tester, () => false, timeout: duration);
}

enum SceneOutcome {
  /// The map is ready and its base map loaded.
  loaded,

  /// The map is ready but reported no load in time; overlays and camera still work.
  notLoaded,

  /// The platform reported a [MapError] (see [SceneStatus.error]).
  error,

  /// No ready and no error event in time.
  notReady,
}

@immutable
class SceneStatus {
  const SceneStatus(this.outcome, {this.error, required this.ready});

  final SceneOutcome outcome;
  final MapError? error;
  final bool ready;

  bool get apiKeyMissing => error?.code == MapErrorCode.apiKeyMissing;

  @override
  String toString() => 'SceneStatus($outcome, ready: $ready, error: $error)';
}

/// Mounts a [GeometryScene] alone and records its callbacks.
class SceneHarness {
  SceneHarness(this.recorder);

  final RecordingPlatform recorder;
  final controller = MapController();

  int readyCount = 0;
  int loadedCount = 0;
  MapError? error;
  final markerTaps = <String>[];
  final polygonTaps = <String?>[];

  MapCamera get camera => controller.camera;

  Widget build({MapStyle mapStyle = MapStyle.standard}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: GeometryScene(
        controller: controller,
        mapStyle: mapStyle,
        onMapReady: () => readyCount++,
        onMapLoaded: () => loadedCount++,
        onMapError: (e) => error = e,
        onMarkerTap: markerTaps.add,
        onPolygonTap: polygonTaps.add,
      ),
    ),
  );

  /// Mounts the scene and waits for ready (or an error), then for loaded (or an error).
  Future<SceneStatus> start(
    WidgetTester tester, {
    MapStyle mapStyle = MapStyle.standard,
    Duration readyTimeout = const Duration(seconds: 30),
    Duration loadTimeout = const Duration(seconds: 30),
  }) async {
    await tester.pumpWidget(build(mapStyle: mapStyle));
    final readyOrError = await pumpUntil(tester, () => readyCount > 0 || error != null, timeout: readyTimeout);
    if (!readyOrError) return const SceneStatus(SceneOutcome.notReady, ready: false);
    log('ready: ${readyCount > 0}, camera: ${readyCount > 0 ? camera : '-'}');
    if (error != null) return SceneStatus(SceneOutcome.error, error: error, ready: readyCount > 0);
    final loaded = await pumpUntil(tester, () => loadedCount > 0 || error != null, timeout: loadTimeout);
    if (error != null) return SceneStatus(SceneOutcome.error, error: error, ready: true);
    return SceneStatus(loaded ? SceneOutcome.loaded : SceneOutcome.notLoaded, ready: true);
  }

  /// Runs `animatedFitCamera(routeCameraFit)` and waits for the future and the final idle.
  Future<List<MapEvent>> fitRoute(WidgetTester tester, {Duration timeout = const Duration(seconds: 20)}) async {
    final events = <MapEvent>[];
    final subscription = controller.mapEventStream.listen(events.add);
    var done = false;
    Object? failure;
    unawaited(
      controller
          .animatedFitCamera(cameraFit: routeCameraFit)
          .then(
            (_) => done = true,
            onError: (Object e) {
              failure = e;
              done = true;
            },
          ),
    );
    final completed = await pumpUntil(tester, () => done, timeout: timeout);
    await pumpUntil(tester, () => events.any((e) => e is MapEventMoveEnd), timeout: const Duration(seconds: 10));
    await pumpFor(tester, const Duration(milliseconds: 200));
    unawaited(subscription.cancel());
    if (failure != null) fail('animatedFitCamera failed: $failure');
    if (!completed) fail('animatedFitCamera did not complete within $timeout');
    return events;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpFor(tester, const Duration(milliseconds: 100));
  }
}
