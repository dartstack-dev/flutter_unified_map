import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map_flutter_map/flutter_unified_map_flutter_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' as p;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

import 'support/harness.dart';

class _Harness {
  _Harness(this.platform, this.viewId);

  final UnifiedMapsFlutterMap platform;
  final int viewId;
  final events = <PlatformMapEvent>[];

  List<T> of<T extends PlatformMapEvent>() => events.whereType<T>().toList();
}

Future<_Harness> _pumpMap(
  WidgetTester tester, {
  int viewId = 1,
  PlatformMapOptions options = noBaseMapOptions,
  UnifiedMapsFlutterMap? platform,
  Future<void> Function(UnifiedMapsFlutterMap platform)? beforeBuild,
}) async {
  final harness = _Harness(platform ?? UnifiedMapsFlutterMap(), viewId);
  final subscription = harness.platform.events(viewId).listen(harness.events.add);
  addTearDown(subscription.cancel);
  await beforeBuild?.call(harness.platform);
  await tester.pumpWidget(
    MaterialApp(
      home: harness.platform.buildView(viewId: viewId, options: options),
    ),
  );
  await tester.pump();
  return harness;
}

void main() {
  test('registerWith installs the platform instance', () {
    UnifiedMapsFlutterMap.registerWith();
    expect(UnifiedMapsPlatform.instance, isA<UnifiedMapsFlutterMap>());
  });

  testWidgets('emits ready then view size', (tester) async {
    final map = await _pumpMap(tester);

    expect(map.events.first, isA<PlatformMapReadyEvent>());
    final ready = map.events.first as PlatformMapReadyEvent;
    expect(ready.viewId, 1);
    expect(ready.camera.zoom, 10);
    expect(ready.camera.center.latitude, closeTo(paris.latitude, 1e-9));
    final sizes = map.of<PlatformViewSizeEvent>();
    expect(sizes, hasLength(1));
    expect((sizes.single.width, sizes.single.height), (800.0, 600.0));
  });

  testWidgets('ready event reaches a listener that subscribes late', (tester) async {
    final platform = UnifiedMapsFlutterMap();
    await tester.pumpWidget(MaterialApp(home: platform.buildView(viewId: 7, options: noBaseMapOptions)));
    await tester.pump();

    final events = <PlatformMapEvent>[];
    final subscription = platform.events(7).listen(events.add);
    addTearDown(subscription.cancel);
    await tester.pump();

    expect(events.first, isA<PlatformMapReadyEvent>());
  });

  testWidgets('markers render as images, sorted by zIndex, including updates sent before the view exists', (
    tester,
  ) async {
    final map = await _pumpMap(
      tester,
      beforeBuild: (platform) =>
          platform.updateMarkers(1, MapObjectUpdates(added: [testMarker('a', paris, zIndex: 2)])),
    );
    await map.platform.updateMarkers(
      1,
      MapObjectUpdates(added: [testMarker('b', const LatLng(48.86, 2.36), zIndex: 1)]),
    );
    await tester.pump();

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    expect(images.first.width, 20);
    expect(images.first.height, 20);
    expect(images.first.gaplessPlayback, isTrue);
    expect(drawnMarkerIds(tester), ['b', 'a']);
    final layer = tester.widget<fm.MarkerLayer>(find.byType(fm.MarkerLayer));
    expect(layer.markers.first.alignment, Alignment.topCenter);
    expect(layer.markers.first.rotate, isTrue);

    await map.platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['a', 'b']));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('marker tap emits MarkerTap and no map tap', (tester) async {
    final map = await _pumpMap(tester);
    await map.platform.updateMarkers(1, MapObjectUpdates(added: [testMarker('m', paris)]));
    await tester.pump();

    await tester.tap(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 500));

    expect(map.of<PlatformMarkerTapEvent>().map((e) => e.markerId), ['m']);
    expect(map.of<PlatformMapTapEvent>(), isEmpty);
  });

  testWidgets('tap on the map emits a tap event with the relative point', (tester) async {
    final map = await _pumpMap(tester);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 500));

    final taps = map.of<PlatformMapTapEvent>();
    expect(taps, hasLength(1));
    expect(taps.single.screenPoint, const p.Offset(400, 300));
    expect(taps.single.position.latitude, closeTo(paris.latitude, 1e-6));
    expect(taps.single.position.longitude, closeTo(paris.longitude, 1e-6));
  });

  testWidgets('long press emits a long-press event', (tester) async {
    final map = await _pumpMap(tester);

    await tester.longPressAt(const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 500));

    final presses = map.of<PlatformMapLongPressEvent>();
    expect(presses, hasLength(1));
    expect(presses.single.screenPoint, const p.Offset(100, 100));
  });

  testWidgets('instant newCamera moves the camera and emits start(api), move, idle', (tester) async {
    final map = await _pumpMap(tester);
    map.events.clear();

    await map.platform.moveCamera(
      1,
      const PlatformCameraUpdate.newCamera(center: LatLng(45.764, 4.8357), zoom: 12, bearing: 30),
    );
    await tester.pump();

    final camera = await map.platform.getCamera(1);
    expect(camera.center.latitude, closeTo(45.764, 1e-6));
    expect(camera.center.longitude, closeTo(4.8357, 1e-6));
    expect(camera.zoom, 12);
    expect(camera.bearing, 30);
    expect(map.events.first, isA<PlatformCameraMoveStartedEvent>());
    expect((map.events.first as PlatformCameraMoveStartedEvent).byGesture, isFalse);
    expect(map.events.last, isA<PlatformCameraIdleEvent>());
    expect(map.of<PlatformCameraIdleEvent>(), hasLength(1));
  });

  testWidgets('bearing is a compass heading: at bearing 90 north is on the left', (tester) async {
    final map = await _pumpMap(
      tester,
      options: noBaseMapOptions.copyWith(initialCamera: const PlatformCamera(center: paris, zoom: 10, bearing: 90)),
    );

    final camera = await map.platform.getCamera(1);
    expect(camera.bearing, closeTo(90, 1e-9));
    expect(tester.widget<fm.FlutterMap>(find.byType(fm.FlutterMap)).options.initialRotation, -90);
    final north = await map.platform.toScreen(1, LatLng(paris.latitude + 0.1, paris.longitude));
    expect(north.dx, lessThan(400 - 50));
    expect(north.dy, closeTo(300, 1));

    await map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(bearing: 270));
    await tester.pump();
    expect((await map.platform.getCamera(1)).bearing, closeTo(270, 1e-9));
    final northAfter = await map.platform.toScreen(1, LatLng(paris.latitude + 0.1, paris.longitude));
    expect(northAfter.dx, greaterThan(400 + 50));
  });

  testWidgets('newCamera honours the content padding', (tester) async {
    final map = await _pumpMap(tester, options: noBaseMapOptions.copyWith(padding: const EdgeInsets.only(bottom: 200)));

    await map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(center: paris, zoom: 12));
    await tester.pump();

    final camera = await map.platform.getCamera(1);
    expect(camera.center.latitude, closeTo(paris.latitude, 1e-6));
    final screen = await map.platform.toScreen(1, paris);
    expect(screen.dx, closeTo(400, 0.01));
    expect(screen.dy, closeTo(200, 0.01));
  });

  testWidgets('fitBounds zooms to the bounds, capped by maxZoom', (tester) async {
    final map = await _pumpMap(tester);
    const bounds = PlatformLatLngBounds(southWest: LatLng(48.84, 2.33), northEast: LatLng(48.87, 2.37));

    await map.platform.moveCamera(1, const PlatformCameraUpdate.fitBounds(bounds, padding: EdgeInsets.all(20)));
    await tester.pump();

    final fitted = await map.platform.getCamera(1);
    expect(fitted.zoom, greaterThan(12));
    expect(fitted.center.latitude, closeTo(48.855, 0.01));
    expect(fitted.center.longitude, closeTo(2.35, 0.01));
    final region = await map.platform.getVisibleRegion(1);
    expect(region.southWest.latitude, lessThanOrEqualTo(48.84));
    expect(region.northEast.longitude, greaterThanOrEqualTo(2.37));

    await map.platform.moveCamera(1, const PlatformCameraUpdate.fitBounds(bounds, maxZoom: 11));
    await tester.pump();
    expect((await map.platform.getCamera(1)).zoom, 11);
  });

  testWidgets('scrollBy and zoomBy move relative to the current camera', (tester) async {
    final map = await _pumpMap(tester);
    final target = await map.platform.toLatLng(1, const p.Offset(500, 300));

    await map.platform.moveCamera(1, const PlatformCameraUpdate.scrollBy(100, 0));
    await tester.pump();
    final scrolled = await map.platform.getCamera(1);
    expect(scrolled.center.longitude, closeTo(target.longitude, 1e-6));

    await map.platform.moveCamera(1, const PlatformCameraUpdate.zoomBy(1.5));
    await tester.pump();
    final zoomed = await map.platform.getCamera(1);
    expect(zoomed.zoom, 11.5);
    expect(zoomed.center.longitude, closeTo(target.longitude, 1e-6));
  });

  testWidgets('animated move completes at the target with a single start and idle', (tester) async {
    final map = await _pumpMap(tester);
    map.events.clear();

    var done = false;
    unawaited(
      map.platform
          .moveCamera(
            1,
            const PlatformCameraUpdate.newCamera(center: LatLng(50.8503, 4.3517), zoom: 8),
            animation: const Duration(milliseconds: 300),
          )
          .then((_) => done = true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(done, isFalse);
    final midway = await map.platform.getCamera(1);
    expect(midway.zoom, inExclusiveRange(8, 10));

    await tester.pumpAndSettle();
    expect(done, isTrue);
    final camera = await map.platform.getCamera(1);
    expect(camera.center.latitude, closeTo(50.8503, 1e-6));
    expect(camera.zoom, 8);
    expect(map.of<PlatformCameraMoveStartedEvent>(), hasLength(1));
    expect(map.of<PlatformCameraMoveEvent>().length, greaterThan(1));
    expect(map.of<PlatformCameraIdleEvent>(), hasLength(1));
    expect(map.events.last, isA<PlatformCameraIdleEvent>());
  });

  testWidgets('a new move interrupts a running animation', (tester) async {
    final map = await _pumpMap(tester);
    map.events.clear();

    var firstDone = false;
    unawaited(
      map.platform
          .moveCamera(1, const PlatformCameraUpdate.newCamera(zoom: 5), animation: const Duration(milliseconds: 500))
          .then((_) => firstDone = true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(zoom: 14));
    await tester.pumpAndSettle();

    expect(firstDone, isTrue);
    expect((await map.platform.getCamera(1)).zoom, 14);
    expect(map.of<PlatformCameraMoveStartedEvent>(), hasLength(1));
    expect(map.of<PlatformCameraIdleEvent>(), hasLength(1));
  });

  testWidgets('a drag emits start(gesture), moves and one idle', (tester) async {
    final map = await _pumpMap(tester);
    map.events.clear();
    final before = await map.platform.getCamera(1);

    await tester.timedDrag(find.byType(fm.FlutterMap), const Offset(-200, 0), const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));

    final after = await map.platform.getCamera(1);
    expect(after.center.longitude, greaterThan(before.center.longitude));
    final starts = map.of<PlatformCameraMoveStartedEvent>();
    expect(starts, hasLength(1));
    expect(starts.single.byGesture, isTrue);
    expect(map.of<PlatformCameraMoveEvent>(), isNotEmpty);
    expect(map.of<PlatformCameraIdleEvent>(), hasLength(1));
    expect(map.events.last, isA<PlatformCameraIdleEvent>());
  });

  testWidgets('polylines, polygons and circles become flutter_map layers', (tester) async {
    final map = await _pumpMap(tester);

    await map.platform.updatePolylines(
      1,
      const MapObjectUpdates(
        added: [
          PlatformPolyline(
            id: 'route',
            points: [paris, LatLng(48.9, 2.4)],
            color: Color(0xFF2962FF),
            width: 5,
            borderColor: Color(0xFFFFFFFF),
            borderWidth: 2,
            dashPattern: [10, 6],
          ),
        ],
      ),
    );
    await map.platform.updatePolygons(
      1,
      const MapObjectUpdates(
        added: [
          PlatformPolygon(
            id: 'zone',
            points: [LatLng(48.8, 2.3), LatLng(48.9, 2.3), LatLng(48.9, 2.4)],
            fillColor: Color(0x552962FF),
          ),
        ],
      ),
    );
    await map.platform.updateCircles(
      1,
      const MapObjectUpdates(
        added: [PlatformCircle(id: 'c', center: paris, radiusMeters: 500)],
      ),
    );
    await tester.pump();

    final polylines = tester.widget<fm.PolylineLayer>(find.byType(fm.PolylineLayer)).polylines;
    expect(polylines, hasLength(1));
    expect(polylines.single.strokeWidth, 5);
    expect(polylines.single.borderStrokeWidth, 2);
    expect(polylines.single.pattern, fm.StrokePattern.dashed(segments: const [10, 6], patternFit: fm.PatternFit.none));
    expect(tester.widget<fm.PolygonLayer>(find.byType(fm.PolygonLayer)).polygons, hasLength(1));
    final circle = tester.widget<fm.CircleLayer>(find.byType(fm.CircleLayer)).circles.single;
    expect(circle.radius, 500);
    expect(circle.useRadiusInMeter, isTrue);
  });

  testWidgets('shapes and tile overlays are stacked by zIndex across kinds', (tester) async {
    final map = await _pumpMap(tester);
    const triangle = [LatLng(48.8, 2.3), LatLng(48.9, 2.3), LatLng(48.9, 2.4)];

    await map.platform.updatePolygons(
      1,
      const MapObjectUpdates(
        added: [
          PlatformPolygon(id: 'low', points: triangle, fillColor: Color(0x55000000)),
          PlatformPolygon(id: 'high', points: triangle, fillColor: Color(0x55000000), zIndex: 3),
        ],
      ),
    );
    await map.platform.updatePolylines(
      1,
      const MapObjectUpdates(
        added: [PlatformPolyline(id: 'line', points: triangle, color: Color(0xFF000000), width: 4, zIndex: 2)],
      ),
    );
    await map.platform.updateTileLayers(
      1,
      const MapObjectUpdates(
        added: [PlatformTileLayer(id: 't', urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png', zIndex: 1)],
      ),
    );
    await tester.pump();

    final layers = tester
        .widgetList(find.byWidgetPredicate((w) => w is fm.PolygonLayer || w is fm.PolylineLayer || w is fm.TileLayer))
        .map(
          (w) => switch (w) {
            fm.PolygonLayer(:final polygons) => 'polygons:${polygons.length}',
            fm.PolylineLayer() => 'polylines',
            _ => 'tiles',
          },
        )
        .toList();
    expect(layers, ['polygons:1', 'tiles', 'polylines', 'polygons:1']);

    final tileState = tester.state(find.byType(fm.TileLayer));
    await map.platform.updatePolylines(
      1,
      const MapObjectUpdates(
        changed: [PlatformPolyline(id: 'line', points: triangle, color: Color(0xFF000000), width: 4, zIndex: 0.5)],
      ),
    );
    await tester.pump();
    expect(tester.state(find.byType(fm.TileLayer)), same(tileState));
    expect(tester.widgetList(find.byType(fm.PolylineLayer)), hasLength(1));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('512 and 1024 tiles cover the extent of a 256 tile one or two levels lower', (tester) async {
    final map = await _pumpMap(tester);
    await map.platform.updateTileLayers(
      1,
      const MapObjectUpdates(
        added: [
          PlatformTileLayer(id: 'a', urlTemplate: 'https://example.invalid/a/{z}/{x}/{y}.png'),
          PlatformTileLayer(id: 'b', urlTemplate: 'https://example.invalid/b/{z}/{x}/{y}.png', tileSize: 512),
          PlatformTileLayer(id: 'c', urlTemplate: 'https://example.invalid/c/{z}/{x}/{y}.png', tileSize: 1024),
        ],
      ),
    );
    await tester.pump();

    final layers = tester.widgetList<fm.TileLayer>(find.byType(fm.TileLayer)).toList();
    expect(layers.map((l) => (l.tileDimension, l.zoomOffset)), [(256, 0.0), (512, -1.0), (1024, -2.0)]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tile layers are drawn and the base map follows the style', (tester) async {
    final map = await _pumpMap(tester);
    expect(find.byType(fm.TileLayer), findsNothing);

    await map.platform.updateTileLayers(
      1,
      const MapObjectUpdates(
        added: [PlatformTileLayer(id: 't', urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png', opacity: 0.5)],
      ),
    );
    await tester.pump();
    expect(find.byType(fm.TileLayer), findsOneWidget);
    expect(find.byType(Opacity), findsOneWidget);

    await map.platform.updateOptions(1, noBaseMapOptions.copyWith(style: PlatformMapStyle.muted));
    await tester.pump();
    expect(find.byType(fm.TileLayer), findsNWidgets(2));
    expect(find.byType(ColorFiltered), findsOneWidget);

    await map.platform.updateTileLayers(
      1,
      const MapObjectUpdates(
        changed: [
          PlatformTileLayer(id: 't', urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png', replacesBaseMap: true),
        ],
      ),
    );
    await tester.pump();
    expect(find.byType(fm.TileLayer), findsOneWidget);
    expect(find.byType(ColorFiltered), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('interaction options map to flutter_map flags', (tester) async {
    final map = await _pumpMap(tester, options: noBaseMapOptions.copyWith(interaction: PlatformInteraction.none));
    final flutterMap = tester.widget<fm.FlutterMap>(find.byType(fm.FlutterMap));
    expect(flutterMap.options.interactionOptions.flags, fm.InteractiveFlag.none);
    expect(flutterMap.options.interactionOptions.keyboardOptions, const fm.KeyboardOptions.disabled());
    final rotation = flutterMap.options.interactionOptions.cursorKeyboardRotationOptions;
    expect(rotation.isKeyTrigger?.call(LogicalKeyboardKey.control), isFalse);

    await map.platform.updateOptions(1, noBaseMapOptions);
    await tester.pump();
    final updated = tester.widget<fm.FlutterMap>(find.byType(fm.FlutterMap));
    expect(fm.InteractiveFlag.hasDrag(updated.options.interactionOptions.flags), isTrue);
    expect(fm.InteractiveFlag.hasRotate(updated.options.interactionOptions.flags), isTrue);
    expect(updated.options.interactionOptions.keyboardOptions.enableArrowKeysPanning, isTrue);
    expect(updated.options.interactionOptions.keyboardOptions.autofocus, isFalse);
    expect(updated.options.interactionOptions.cursorKeyboardRotationOptions.isKeyTrigger, isNull);
  });

  testWidgets('takeSnapshot returns a PNG', (tester) async {
    final map = await _pumpMap(tester);

    final bytes = await tester.runAsync(() => map.platform.takeSnapshot(1));

    expect(bytes, isNotNull);
    expect(bytes!.sublist(1, 4), utf8.encode('PNG'));
  });

  testWidgets('the initial camera is centred on the padded area', (tester) async {
    final map = await _pumpMap(tester, options: noBaseMapOptions.copyWith(padding: const EdgeInsets.only(bottom: 200)));

    final ready = map.of<PlatformMapReadyEvent>().single;
    expect(ready.camera.center.latitude, closeTo(paris.latitude, 1e-6));
    expect(ready.camera.center.longitude, closeTo(paris.longitude, 1e-6));
    expect((await map.platform.getCamera(1)).center.latitude, closeTo(paris.latitude, 1e-6));
    final screen = await map.platform.toScreen(1, paris);
    expect(screen.dy, closeTo(200, 0.01));
  });

  testWidgets('a padding change keeps the camera target', (tester) async {
    final map = await _pumpMap(tester);

    await map.platform.updateOptions(1, noBaseMapOptions.copyWith(padding: const EdgeInsets.only(bottom: 200)));
    await tester.pump();

    final camera = await map.platform.getCamera(1);
    expect(camera.center.latitude, closeTo(paris.latitude, 1e-6));
    expect((await map.platform.toScreen(1, paris)).dy, closeTo(200, 0.01));
    expect(map.of<PlatformCameraIdleEvent>().last.camera.center.latitude, closeTo(paris.latitude, 1e-6));
  });

  testWidgets('fitBounds across the antimeridian keeps the short span', (tester) async {
    final map = await _pumpMap(tester);
    const bounds = PlatformLatLngBounds(southWest: LatLng(-10, 175), northEast: LatLng(10, -175));

    await map.platform.moveCamera(1, const PlatformCameraUpdate.fitBounds(bounds));
    await tester.pump();

    final camera = await map.platform.getCamera(1);
    expect(camera.center.latitude, closeTo(0, 1e-6));
    expect(camera.center.longitude.abs(), closeTo(180, 1e-6));
    expect(camera.zoom, greaterThan(4));
  });

  testWidgets('a move that leaves the camera in place still emits start, move, idle', (tester) async {
    final map = await _pumpMap(tester);
    map.events.clear();

    await map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(zoom: 10));
    await tester.pump();

    expect(map.events.map((e) => e.runtimeType), [
      PlatformCameraMoveStartedEvent,
      PlatformCameraMoveEvent,
      PlatformCameraIdleEvent,
    ]);
  });

  testWidgets('a re-parented view keeps its camera and is ready only once', (tester) async {
    final map = await _pumpMap(tester);
    await map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(center: LatLng(45.764, 4.8357), zoom: 12));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(width: 400, height: 300, child: map.platform.buildView(viewId: 1, options: noBaseMapOptions)),
        ),
      ),
    );
    await tester.pump();

    expect(map.of<PlatformMapReadyEvent>(), hasLength(1));
    final camera = await map.platform.getCamera(1);
    expect(camera.center.latitude, closeTo(45.764, 1e-6));
    expect(camera.zoom, 12);
    expect(map.of<PlatformViewSizeEvent>().last.width, 400);
  });

  testWidgets('marker rotation pivots on the anchor', (tester) async {
    final map = await _pumpMap(tester);
    final marker = PlatformMarker(
      id: 'r',
      position: paris,
      icon: PlatformIcon(key: 'dot', bytes: transparentPng, logicalSize: const Size(20, 20), pixelRatio: 2),
      anchor: const p.Offset(0.5, 1),
      rotation: 45,
    );
    await map.platform.updateMarkers(1, MapObjectUpdates(added: [marker]));
    await tester.pump();

    final transform = tester.widget<Transform>(
      find.descendant(of: find.byType(fm.MarkerLayer), matching: find.byType(Transform)).last,
    );
    expect(transform.alignment, Alignment.bottomCenter);
  });

  testWidgets('markers with the same zIndex keep their insertion order', (tester) async {
    final map = await _pumpMap(tester);
    final ids = [for (var i = 0; i < 100; i++) 'm$i'];
    await map.platform.updateMarkers(1, MapObjectUpdates(added: [for (final id in ids) testMarker(id, paris)]));
    await map.platform.updateMarkers(1, MapObjectUpdates(changed: [testMarker('m50', const LatLng(48.9, 2.4))]));
    await tester.pump();

    expect(drawnMarkerIds(tester), ids);
  });

  testWidgets('events emitted between two subscriptions are not replayed', (tester) async {
    final platform = UnifiedMapsFlutterMap();
    final first = <PlatformMapEvent>[];
    final firstSubscription = platform.events(3).listen(first.add);
    await tester.pumpWidget(MaterialApp(home: platform.buildView(viewId: 3, options: noBaseMapOptions)));
    await tester.pump();
    expect(first.whereType<PlatformMapReadyEvent>(), hasLength(1));
    unawaited(firstSubscription.cancel());

    await platform.moveCamera(3, const PlatformCameraUpdate.newCamera(zoom: 12));
    await tester.pump();
    final second = <PlatformMapEvent>[];
    final secondSubscription = platform.events(3).listen(second.add);
    addTearDown(secondSubscription.cancel);
    await tester.pump();

    expect(second, isEmpty);
  });

  testWidgets('a disposed view ignores calls and stops emitting', (tester) async {
    final map = await _pumpMap(tester);
    await map.platform.dispose(1);
    final countAfterDispose = map.events.length;

    await map.platform.updateMarkers(1, MapObjectUpdates(added: [testMarker('m', paris)]));
    await map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(zoom: 3));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(map.events, hasLength(countAfterDispose));
    expect(await map.platform.takeSnapshot(1), isNull);
    expect(await map.platform.events(1).isEmpty, isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('queries for a disposed view answer from its last camera', (tester) async {
    final map = await _pumpMap(tester);
    await map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(center: LatLng(45.76, 4.84), zoom: 12));
    await tester.pump();
    final region = await map.platform.getVisibleRegion(1);
    final screen = await map.platform.toScreen(1, paris);

    await map.platform.dispose(1);
    await tester.pumpWidget(const SizedBox());

    final camera = await map.platform.getCamera(1);
    expect(camera.zoom, 12);
    expect(camera.center.latitude, closeTo(45.76, 1e-6));
    expect(await map.platform.getVisibleRegion(1), region);
    expect(await map.platform.toScreen(1, paris), screen);
    final back = await map.platform.toLatLng(1, screen);
    expect(back.latitude, closeTo(paris.latitude, 1e-6));
  });

  testWidgets('markers drawn in several world copies do not collide', (tester) async {
    final map = await _pumpMap(
      tester,
      options: noBaseMapOptions.copyWith(initialCamera: const PlatformCamera(center: LatLng(0, 0), zoom: 0)),
    );
    await map.platform.updateMarkers(1, MapObjectUpdates(added: [testMarker('a', const LatLng(0, 0))]));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(drawnMarkerIds(tester).length, greaterThan(1));
    expect(drawnMarkerIds(tester).toSet(), {'a'});

    await map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(zoom: 10));
    await tester.pump();
    expect(drawnMarkerIds(tester), ['a']);
  });

  testWidgets('flat markers do not counter-rotate and untappable markers let taps reach the map', (tester) async {
    final map = await _pumpMap(tester);
    final marker = PlatformMarker(
      id: 'f',
      position: paris,
      icon: PlatformIcon(key: 'dot', bytes: transparentPng, logicalSize: const Size(20, 20), pixelRatio: 2),
      anchor: const p.Offset(0.5, 0.5),
      flat: true,
      tappable: false,
    );
    await map.platform.updateMarkers(1, MapObjectUpdates(added: [marker]));
    await tester.pump();

    expect(tester.widget<fm.MarkerLayer>(find.byType(fm.MarkerLayer)).markers.single.rotate, isFalse);
    await tester.tap(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 500));
    expect(map.of<PlatformMarkerTapEvent>(), isEmpty);
    expect(map.of<PlatformMapTapEvent>(), hasLength(1));
  });

  testWidgets('getCamera answers the initial camera before the view is ready; other queries throw', (tester) async {
    final platform = UnifiedMapsFlutterMap();
    platform.buildView(viewId: 9, options: noBaseMapOptions);

    expect((await platform.getCamera(9)).center, paris);
    await expectLater(platform.getVisibleRegion(9), throwsStateError);
    await expectLater(platform.toScreen(9, paris), throwsStateError);
    await expectLater(platform.getCamera(10), throwsStateError);
  });

  testWidgets('a disposed view that never became ready answers its initial camera', (tester) async {
    final platform = UnifiedMapsFlutterMap();
    platform.buildView(viewId: 9, options: noBaseMapOptions);
    await platform.dispose(9);
    await platform.dispose(11);

    expect((await platform.getCamera(9)).center, paris);
    await expectLater(platform.getCamera(11), throwsStateError);
  });

  testWidgets('the visible region crosses the antimeridian instead of stopping at 180', (tester) async {
    final map = await _pumpMap(
      tester,
      options: noBaseMapOptions.copyWith(initialCamera: const PlatformCamera(center: LatLng(0, 179), zoom: 5)),
    );

    final region = await map.platform.getVisibleRegion(1);
    final halfWidth = 800 * 360 / (256 * 32) / 2;
    expect(region.southWest.longitude, closeTo(179 - halfWidth, 0.05));
    expect(region.northEast.longitude, closeTo(179 + halfWidth - 360, 0.05));

    await map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(zoom: 1));
    await tester.pump();
    final world = await map.platform.getVisibleRegion(1);
    expect((world.southWest.longitude, world.northEast.longitude), (-180.0, 180.0));
  });

  testWidgets('an animated move across the antimeridian takes the short way', (tester) async {
    final map = await _pumpMap(
      tester,
      options: noBaseMapOptions.copyWith(initialCamera: const PlatformCamera(center: LatLng(0, 175), zoom: 5)),
    );

    unawaited(
      map.platform.moveCamera(
        1,
        const PlatformCameraUpdate.newCamera(center: LatLng(0, -175)),
        animation: const Duration(seconds: 1),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect((await map.platform.getCamera(1)).center.longitude.abs(), closeTo(180, 0.5));

    await tester.pumpAndSettle();
    expect((await map.platform.getCamera(1)).center.longitude, closeTo(-175, 1e-6));
  });

  testWidgets('a padding change during an animated move keeps its target', (tester) async {
    final map = await _pumpMap(tester);
    const lyon = LatLng(45.764, 4.8357);
    var done = false;
    unawaited(
      map.platform
          .moveCamera(
            1,
            const PlatformCameraUpdate.newCamera(center: lyon, zoom: 9),
            animation: const Duration(seconds: 1),
          )
          .then((_) => done = true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await map.platform.updateOptions(1, noBaseMapOptions.copyWith(padding: const EdgeInsets.only(bottom: 200)));
    await tester.pump();
    expect(done, isFalse);
    await tester.pumpAndSettle();

    final camera = await map.platform.getCamera(1);
    expect(camera.center.latitude, closeTo(lyon.latitude, 1e-6));
    expect(camera.center.longitude, closeTo(lyon.longitude, 1e-6));
    expect((await map.platform.toScreen(1, lyon)).dy, closeTo(200, 0.01));
  });

  testWidgets('a narrower zoom range moves the camera into it', (tester) async {
    final map = await _pumpMap(tester);
    map.events.clear();

    await map.platform.updateOptions(1, noBaseMapOptions.copyWith(minZoom: 12));
    await tester.pump();
    await tester.pump();

    expect((await map.platform.getCamera(1)).zoom, 12);
    expect(map.of<PlatformCameraIdleEvent>().single.camera.zoom, 12);

    await map.platform.updateOptions(1, noBaseMapOptions.copyWith(maxZoom: 8));
    await tester.pump();
    await tester.pump();
    expect((await map.platform.getCamera(1)).zoom, 8);
  });

  testWidgets('the scroll wheel takes over a running animation', (tester) async {
    final map = await _pumpMap(tester);
    map.events.clear();
    var done = false;
    unawaited(
      map.platform
          .moveCamera(1, const PlatformCameraUpdate.newCamera(zoom: 5), animation: const Duration(seconds: 1))
          .then((_) => done = true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(400, 300)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(done, isTrue);
    final zoomAfterWheel = (await map.platform.getCamera(1)).zoom;

    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    expect((await map.platform.getCamera(1)).zoom, zoomAfterWheel);
    expect(map.of<PlatformCameraMoveStartedEvent>().map((e) => e.byGesture), [false, true]);
    expect(map.of<PlatformCameraIdleEvent>(), hasLength(2));
    expect(map.events.last, isA<PlatformCameraIdleEvent>());
  });

  testWidgets('a drag takes over a running animation', (tester) async {
    final map = await _pumpMap(tester);
    map.events.clear();
    unawaited(
      map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(zoom: 5), animation: const Duration(seconds: 1)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.timedDrag(find.byType(fm.FlutterMap), const Offset(-200, 0), const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));

    expect((await map.platform.getCamera(1)).zoom, greaterThan(5));
    expect(map.of<PlatformCameraMoveStartedEvent>().map((e) => e.byGesture), [false, true]);
    expect(map.of<PlatformCameraIdleEvent>(), hasLength(2));
  });

  testWidgets('a view re-parented mid-animation still ends its movement with idle', (tester) async {
    final map = await _pumpMap(tester);
    map.events.clear();
    unawaited(
      map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(zoom: 5), animation: const Duration(seconds: 1)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(width: 400, height: 300, child: map.platform.buildView(viewId: 1, options: noBaseMapOptions)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(map.of<PlatformCameraMoveStartedEvent>(), hasLength(1));
    expect(map.of<PlatformCameraIdleEvent>(), hasLength(1));
  });

  testWidgets('empty polylines and polygons are skipped', (tester) async {
    final map = await _pumpMap(tester);
    await map.platform.updatePolylines(
      1,
      const MapObjectUpdates(
        added: [
          PlatformPolyline(id: 'empty', points: [], color: Color(0xFF000000), width: 4),
          PlatformPolyline(id: 'line', points: [paris, LatLng(48.9, 2.4)], color: Color(0xFF000000), width: 4),
        ],
      ),
    );
    await map.platform.updatePolygons(
      1,
      const MapObjectUpdates(
        added: [PlatformPolygon(id: 'empty', points: [])],
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.widget<fm.PolylineLayer>(find.byType(fm.PolylineLayer)).polylines, hasLength(1));
  });

  testWidgets('dash patterns repeat whole and keep their lengths, as on Android and Apple', (tester) async {
    final map = await _pumpMap(tester);
    await map.platform.updatePolylines(
      1,
      const MapObjectUpdates(
        added: [
          PlatformPolyline(id: 'one', points: [paris, LatLng(48.9, 2.4)], color: Color(0xFF000000), dashPattern: [10]),
          PlatformPolyline(
            id: 'odd',
            points: [paris, LatLng(48.9, 2.4)],
            color: Color(0xFF000000),
            dashPattern: [10, 6, 4],
          ),
        ],
      ),
    );
    await tester.pump();

    final patterns = tester.widget<fm.PolylineLayer>(find.byType(fm.PolylineLayer)).polylines.map((l) => l.pattern);
    expect(patterns, [
      fm.StrokePattern.dashed(segments: const [10, 10], patternFit: fm.PatternFit.none),
      fm.StrokePattern.dashed(segments: const [10, 6, 4, 10, 6, 4], patternFit: fm.PatternFit.none),
    ]);
  });

  testWidgets('a tile overlay keeps its tiles when its opacity or zIndex changes', (tester) async {
    final map = await _pumpMap(tester);
    const url = 'https://example.invalid/{z}/{x}/{y}.png';
    await map.platform.updateTileLayers(
      1,
      const MapObjectUpdates(
        added: [PlatformTileLayer(id: 't', urlTemplate: url, opacity: 0.5)],
      ),
    );
    await tester.pump();
    final tileState = tester.state(find.byType(fm.TileLayer));

    await map.platform.updateTileLayers(
      1,
      const MapObjectUpdates(
        changed: [PlatformTileLayer(id: 't', urlTemplate: url, zIndex: 3)],
      ),
    );
    await tester.pump();
    expect(tester.state(find.byType(fm.TileLayer)), same(tileState));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);

    await map.platform.updateTileLayers(
      1,
      const MapObjectUpdates(
        changed: [PlatformTileLayer(id: 't', urlTemplate: '$url?v=2', zIndex: 3)],
      ),
    );
    await tester.pump();
    expect(tester.state(find.byType(fm.TileLayer)), isNot(same(tileState)));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tile overlay settings reach the TileLayer and its provider', (tester) async {
    final map = await _pumpMap(tester, platform: UnifiedMapsFlutterMap(userAgentPackageName: 'com.example.app'));
    await map.platform.updateTileLayers(
      1,
      const MapObjectUpdates(
        added: [
          PlatformTileLayer(
            id: 'r',
            urlTemplate: 'https://{s}.example.invalid/{z}/{x}/{y}{r}.png',
            subdomains: ['a', 'b'],
            minZoom: 3,
            maxZoom: 17,
            headers: {'Authorization': 'Bearer x'},
          ),
          PlatformTileLayer(id: 'plain', urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png'),
        ],
      ),
    );
    await tester.pump();

    final layers = tester.widgetList<fm.TileLayer>(find.byType(fm.TileLayer)).toList();
    final retina = layers.first;
    expect(retina.subdomains, ['a', 'b']);
    expect((retina.minZoom, retina.maxZoom, retina.maxNativeZoom), (3.0, double.infinity, 17));
    expect(retina.tileProvider.headers['Authorization'], 'Bearer x');
    expect(retina.tileProvider.headers['User-Agent'], 'flutter_map (com.example.app)');
    expect(tester.view.devicePixelRatio, greaterThanOrEqualTo(2));
    expect(retina.resolvedRetinaMode, fm.RetinaMode.server);
    expect(layers.last.resolvedRetinaMode, fm.RetinaMode.disabled);
    await tester.pumpWidget(const SizedBox());
  });
}
