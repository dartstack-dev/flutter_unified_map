import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_flutter_map/flutter_unified_map_flutter_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show UnifiedMapsPlatform;

import '../integration_test/support/geometry_checks.dart';
import '../integration_test/support/recording_platform.dart';
import '../integration_test/support/scene_harness.dart';

/// The end-to-end checks of `integration_test/` against the pure Dart flutter_map backend, with no base map and
/// no network, so they run in `flutter test`.
void main() {
  late RecordingPlatform recorder;
  late SceneHarness h;

  setUp(() {
    recorder = RecordingPlatform(UnifiedMapsFlutterMap());
    UnifiedMapsPlatform.instance = recorder;
    h = SceneHarness(recorder);
  });

  tearDown(() => h.controller.dispose());

  Future<void> start(WidgetTester tester) async {
    final status = await h.start(tester, mapStyle: MapStyle.none, loadTimeout: const Duration(seconds: 1));
    expect(status.ready, isTrue, reason: '$status');
    expect(status.error, isNull);
  }

  testWidgets('custom pins reach the platform with their anchors, flatness and shared icons', (tester) async {
    await start(tester);
    await checkCustomPins(tester, h);
    await h.unmount(tester);
  });

  testWidgets('the itinerary, patterns, polygon hole and circles reach the platform', (tester) async {
    await start(tester);
    await checkItinerary(tester, h);
    await h.unmount(tester);
  });

  testWidgets('animatedFitCamera frames the route in the padded viewport, then rotate(45)', (tester) async {
    await start(tester);
    await checkCamera(tester, h, tolerance: 1);
    await h.unmount(tester);
  });

  testWidgets('the snapshot shows the route, the magenta pin and the yellow polygon', (tester) async {
    await start(tester);
    await checkSnapshot(tester, h, platformName: 'flutter_map', settle: const Duration(milliseconds: 500));
    await h.unmount(tester);
  });

  testWidgets('taps reach Marker.onTap and the polygon hitNotifier', (tester) async {
    await start(tester);
    await checkTaps(tester, h);
    await h.unmount(tester);
  });
}
