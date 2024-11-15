import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show PlatformMapReadyEvent, UnifiedMapsPlatform;

import 'support/geometry_checks.dart';
import 'support/recording_platform.dart';
import 'support/scene_harness.dart';

const _timeout = Timeout(Duration(minutes: 3));

const _noApiKey = 'SKIPPED: no Google Maps API key';

String get _platformName => Platform.operatingSystem;

/// UIKit and AppKit platform views take their touches from the native event stream; the pointer events that
/// the test dispatches inside Flutter never reach MKMapView, so marker and map taps cannot be synthesised
/// there. Android forwards Flutter pointer events to the GoogleMap view as MotionEvents.
final _syntheticTapsUnsupported = Platform.isIOS || Platform.isMacOS;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late UnifiedMapsPlatform real;
  late RecordingPlatform recorder;
  late SceneHarness h;

  setUp(() {
    real = UnifiedMapsPlatform.instance;
    recorder = RecordingPlatform(real);
    UnifiedMapsPlatform.instance = recorder;
    h = SceneHarness(recorder);
    log('platform: $_platformName, ${real.runtimeType}');
  });

  tearDown(() {
    UnifiedMapsPlatform.instance = real;
    h.controller.dispose();
  });

  bool noApiKey(SceneStatus status) =>
      status.outcome == SceneOutcome.error && status.apiKeyMissing && Platform.isAndroid;

  /// Mounts the scene and fails on any map error but Android's missing API key, and on a map that is not ready.
  /// A map that does not load fails when [requireLoaded], and only warns otherwise.
  Future<SceneStatus> mount(WidgetTester tester, {required bool requireLoaded}) async {
    final status = await h.start(tester);
    log('$status');
    switch (status.outcome) {
      case SceneOutcome.loaded:
        break;
      case SceneOutcome.notLoaded when requireLoaded:
        fail('ready but onMapLoaded did not arrive within 30 s on $_platformName');
      case SceneOutcome.notLoaded:
        log('WARNING: ready but no onMapLoaded within 30 s; continuing with overlays and camera checks');
      case SceneOutcome.error when noApiKey(status):
        break;
      case SceneOutcome.error:
        fail('map error on $_platformName: ${status.error}');
      case SceneOutcome.notReady:
        fail('the map sent neither onMapReady nor onMapError within 30 s on $_platformName');
    }
    return status;
  }

  /// Mounts the scene; false when the run has no Google Maps API key and the test must be skipped.
  Future<bool> start(WidgetTester tester) async {
    if (!noApiKey(await mount(tester, requireLoaded: false))) return true;
    debugPrint(_noApiKey);
    markTestSkipped(_noApiKey);
    return false;
  }

  testWidgets('(a) the map becomes ready, then loads or reports a missing API key', (tester) async {
    final status = await mount(tester, requireLoaded: true);
    if (noApiKey(status)) {
      await tester.pump();
      expect(find.byType(MapErrorView), findsOneWidget);
      expect(find.text(status.error!.title), findsOneWidget);
      debugPrint('$_noApiKey: MapErrorView shown; the geometry tests below are skipped for this run');
    } else {
      expect(h.readyCount, 1);
      expect(recorder.receivedEvents.whereType<PlatformMapReadyEvent>(), hasLength(1));
      expect(find.byType(MapErrorView), findsNothing);
      log('loaded');
    }
    await h.unmount(tester);
  }, timeout: _timeout);

  testWidgets('(b) custom pins reach the platform with their anchors, flatness and shared icons', (tester) async {
    if (!await start(tester)) return;
    await checkCustomPins(tester, h);
    await h.unmount(tester);
  }, timeout: _timeout);

  testWidgets('(c) the itinerary, patterns, polygon hole and circles reach the platform', (tester) async {
    if (!await start(tester)) return;
    await checkItinerary(tester, h);
    await h.unmount(tester);
  }, timeout: _timeout);

  testWidgets('(d) animatedFitCamera frames the route in the padded viewport, then rotate(45)', (tester) async {
    if (!await start(tester)) return;
    await checkCamera(tester, h);
    await h.unmount(tester);
  }, timeout: _timeout);

  testWidgets('(e) the native snapshot shows the route, the magenta pin and the yellow polygon', (tester) async {
    if (!await start(tester)) return;
    await checkSnapshot(tester, h, platformName: _platformName);
    await h.unmount(tester);
  }, timeout: _timeout);

  testWidgets(
    '(f) synthetic taps reach Marker.onTap and the polygon hitNotifier',
    (tester) async {
      if (!await start(tester)) return;
      await checkTaps(tester, h);
      await h.unmount(tester);
    },
    timeout: _timeout,
    skip: _syntheticTapsUnsupported,
  );
}
