import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer;
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Wall-clock budgets (call durations, idle latencies) were measured on one Mac and its simulators: they fail only
/// with `--dart-define=STRICT_PERF=true` and are logged otherwise, so a loaded machine does not fail the suites.
const strictPerf = bool.fromEnvironment('STRICT_PERF');

/// Pumps frames until [condition] holds; false after [timeout]. Real time passes between frames, so native events
/// arrive while it waits.
Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() condition,
  Duration timeout, {
  Future<void> Function(WidgetTester tester)? pumpFrame,
}) async {
  final clock = Stopwatch()..start();
  while (!condition()) {
    if (clock.elapsed > timeout) return false;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 16)));
    await (pumpFrame?.call(tester) ?? tester.pump(const Duration(milliseconds: 16)));
  }
  return true;
}

Future<void> pumpFor(WidgetTester tester, Duration duration) => pumpUntil(tester, () => false, duration);

/// Passes every call through to [delegate]; tests override only what they observe or change.
class DelegatingPlatform extends UnifiedMapsPlatform with MockPlatformInterfaceMixin {
  DelegatingPlatform(this.delegate);

  final UnifiedMapsPlatform delegate;

  @override
  Widget buildView({
    required int viewId,
    required PlatformMapOptions options,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  }) => delegate.buildView(viewId: viewId, options: options, gestureRecognizers: gestureRecognizers);

  @override
  Future<void> dispose(int viewId) => delegate.dispose(viewId);

  @override
  Future<void> updateOptions(int viewId, PlatformMapOptions options) => delegate.updateOptions(viewId, options);

  @override
  Future<void> updateMarkers(
    int viewId,
    MapObjectUpdates<PlatformMarker> updates, {
    PlatformMarkerTransition? transition,
  }) => delegate.updateMarkers(viewId, updates, transition: transition);

  @override
  Future<void> updatePolylines(int viewId, MapObjectUpdates<PlatformPolyline> updates) =>
      delegate.updatePolylines(viewId, updates);

  @override
  Future<void> updatePolygons(int viewId, MapObjectUpdates<PlatformPolygon> updates) =>
      delegate.updatePolygons(viewId, updates);

  @override
  Future<void> updateCircles(int viewId, MapObjectUpdates<PlatformCircle> updates) =>
      delegate.updateCircles(viewId, updates);

  @override
  Future<void> updateTileLayers(int viewId, MapObjectUpdates<PlatformTileLayer> updates) =>
      delegate.updateTileLayers(viewId, updates);

  @override
  Future<void> moveCamera(int viewId, PlatformCameraUpdate update, {Duration? animation}) =>
      delegate.moveCamera(viewId, update, animation: animation);

  @override
  Future<PlatformCamera> getCamera(int viewId) => delegate.getCamera(viewId);

  @override
  Future<PlatformLatLngBounds> getVisibleRegion(int viewId) => delegate.getVisibleRegion(viewId);

  @override
  Future<Offset> toScreen(int viewId, LatLng position) => delegate.toScreen(viewId, position);

  @override
  Future<LatLng> toLatLng(int viewId, Offset screenPoint) => delegate.toLatLng(viewId, screenPoint);

  @override
  Future<Uint8List?> takeSnapshot(int viewId) => delegate.takeSnapshot(viewId);

  @override
  bool get supportsFlutterMapLayers => delegate.supportsFlutterMapLayers;

  @override
  void setFlutterMapLayers(int viewId, List<Widget> layers) => delegate.setFlutterMapLayers(viewId, layers);

  @override
  Stream<PlatformMapEvent> events(int viewId) => delegate.events(viewId);
}
