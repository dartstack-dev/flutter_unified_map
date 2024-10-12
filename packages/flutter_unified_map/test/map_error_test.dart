import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

import 'support/fake_platform.dart';
import 'support/harness.dart';

void main() {
  late FakeUnifiedMapsPlatform fake;

  setUp(() => fake = installFakePlatform());

  testWidgets('an api key error before ready shows the default error view and calls onMapError', (tester) async {
    final errors = <MapError>[];
    await tester.pumpWidget(mapApp(options: MapOptions(onMapError: errors.add)));
    fake.emit(
      PlatformMapErrorEvent(
        fake.lastViewId,
        PlatformMapErrorCode.apiKeyMissing,
        'No com.google.android.geo.API_KEY meta-data in AndroidManifest.xml',
      ),
    );
    await tester.pump();

    expect(errors.single.code, MapErrorCode.apiKeyMissing);
    expect(find.byType(MapErrorView), findsOneWidget);
    expect(find.text('Map not configured: API key missing'), findsOneWidget);
    expect(find.textContaining('com.google.android.geo.API_KEY'), findsWidgets);
  });

  testWidgets('a load timeout is cleared by a later loaded event, an api key error is not', (tester) async {
    var loaded = 0;
    await tester.pumpWidget(mapApp(options: MapOptions(onMapLoaded: () => loaded++)));
    final viewId = fake.lastViewId;
    fake.emit(PlatformMapReadyEvent(viewId, const PlatformCamera(center: LatLng(0, 0), zoom: 2)));
    fake.emit(PlatformMapErrorEvent(viewId, PlatformMapErrorCode.loadTimeout, 'Map not loaded after 15 s'));
    await tester.pump();
    expect(find.text('The map did not load'), findsOneWidget);

    fake.emit(PlatformMapLoadedEvent(viewId));
    await tester.pump();
    expect(find.byType(MapErrorView), findsNothing);
    expect(loaded, 1);

    fake.emit(PlatformMapErrorEvent(viewId, PlatformMapErrorCode.apiKeyMissing, 'missing'));
    await tester.pump();
    fake.emit(PlatformMapLoadedEvent(viewId));
    await tester.pump();
    expect(find.byType(MapErrorView), findsOneWidget);
  });

  testWidgets('errorBuilder replaces the default view', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedMap(errorBuilder: (context, error) => Text('custom ${error.code.name}'), children: const []),
      ),
    );
    fake.emit(PlatformMapErrorEvent(fake.lastViewId, PlatformMapErrorCode.servicesUnavailable, 'SERVICE_MISSING'));
    await tester.pump();
    expect(find.text('custom servicesUnavailable'), findsOneWidget);
    expect(find.byType(MapErrorView), findsNothing);
  });

  testWidgets('a load error after the first load is a compact banner, not a full-screen panel', (tester) async {
    await tester.pumpWidget(mapApp());
    final viewId = fake.lastViewId;
    fake.emit(PlatformMapReadyEvent(viewId, const PlatformCamera(center: LatLng(0, 0), zoom: 2)));
    fake.emit(PlatformMapLoadedEvent(viewId));
    fake.emit(PlatformMapErrorEvent(viewId, PlatformMapErrorCode.loadFailed, 'offline'));
    await tester.pump();
    final view = tester.widget<MapErrorView>(find.byType(MapErrorView));
    expect(view.compact, isTrue);
    expect(find.text('The map failed to load'), findsOneWidget);
    expect(find.text('offline'), findsNothing);
  });
}
