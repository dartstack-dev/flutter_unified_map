import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    as platform
    show Offset;

import 'support/fake_platform.dart';
import 'support/harness.dart';
import 'support/test_layer.dart';

void main() {
  late FakeUnifiedMapsPlatform fake;

  setUp(() => fake = installFakePlatform());

  testWidgets('builds the platform view with converted options', (tester) async {
    await tester.pumpWidget(
      mapApp(
        options: const MapOptions(
          initialCenter: LatLng(48.85, 2.35),
          initialZoom: 6,
          initialRotation: 15,
          minZoom: 3,
          maxZoom: 18,
          backgroundColor: Color(0xFF123456),
          interactionOptions: InteractionOptions(flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom),
          nativeParams: NativeParams(
            mapType: MapStyle.satellite,
            showsUserLocation: true,
            showsCompass: true,
            showsPointsOfInterest: false,
          ),
        ),
      ),
    );
    final options = fake.builtViews[fake.lastViewId]!;
    expect(options.initialCamera, const PlatformCamera(center: LatLng(48.85, 2.35), zoom: 6, bearing: 345));
    expect(options.minZoom, 3);
    expect(options.maxZoom, 18);
    expect(options.style, PlatformMapStyle.satellite);
    expect(options.showsUserLocation, isTrue);
    expect(options.showsCompass, isTrue);
    expect(options.showsPointsOfInterest, isFalse);
    expect(options.backgroundColor, const Color(0xFF123456));
    expect(options.interaction, const PlatformInteraction(flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom));
    expect(find.byKey(const ValueKey('fake-map')), findsOneWidget);
  });

  testWidgets('every map gets its own view id and disposes it', (tester) async {
    await tester.pumpWidget(mapApp());
    final first = fake.lastViewId;
    await tester.pumpWidget(mapApp(options: const MapOptions(initialZoom: 4)));
    expect(fake.builtViews.length, 1, reason: 'same element keeps its view');
    await tester.pumpWidget(const SizedBox());
    expect(fake.disposed, [first]);
    await tester.pumpWidget(mapApp());
    expect(fake.lastViewId, isNot(first));
  });

  testWidgets('pushes markers only after ready, with anchor, flat and icon', (tester) async {
    await tester.pumpWidget(
      mapApp(
        children: [
          MarkerLayer(
            alignment: Alignment.topCenter,
            markers: const [
              Marker(
                key: ValueKey('a'),
                point: LatLng(1, 2),
                child: ColoredBox(color: Color(0xFFFF0000)),
              ),
              Marker(
                point: LatLng(3, 4),
                width: 20,
                height: 10,
                alignment: Alignment.centerLeft,
                rotate: true,
                child: ColoredBox(color: Color(0xFF00FF00)),
              ),
            ],
          ),
        ],
      ),
    );
    await settle(tester);
    expect(fake.markerUpdates, isEmpty);

    var readyCalled = false;
    await tester.pumpWidget(
      mapApp(
        options: MapOptions(onMapReady: () => readyCalled = true),
        children: [
          MarkerLayer(
            alignment: Alignment.topCenter,
            markers: const [
              Marker(
                key: ValueKey('a'),
                point: LatLng(1, 2),
                child: ColoredBox(color: Color(0xFFFF0000)),
              ),
              Marker(
                point: LatLng(3, 4),
                width: 20,
                height: 10,
                alignment: Alignment.centerLeft,
                rotate: true,
                child: ColoredBox(color: Color(0xFF00FF00)),
              ),
            ],
          ),
        ],
      ),
    );
    fake.ready();
    expect(readyCalled, isTrue);
    await settle(tester);

    expect(fake.markers, hasLength(2));
    final keyed = fake.markers.values.firstWhere((m) => m.id.endsWith('/k:a'));
    final indexed = fake.markers.values.firstWhere((m) => m.id.endsWith('/1'));
    expect(keyed.position, const LatLng(1, 2));
    expect(keyed.anchor, const platform.Offset(0.5, 1.0));
    expect(keyed.flat, isTrue);
    expect(keyed.icon.logicalSize, const Size(30, 30));
    expect(keyed.icon.pixelRatio, 2);
    expect(keyed.icon.bytes, isNotEmpty);
    expect(indexed.anchor, const platform.Offset(1.0, 0.5));
    expect(indexed.flat, isFalse);
    expect(indexed.icon.logicalSize, const Size(20, 10));
    expect(indexed.icon.key, isNot(keyed.icon.key));
    expect(keyed.id.split('/').first, indexed.id.split('/').first);
  });

  testWidgets('diffs markers: changed and removed, shared icons rasterised once', (tester) async {
    Widget build(List<Marker> markers) => mapApp(children: [MarkerLayer(markers: markers)]);
    const child = ColoredBox(color: Color(0xFF0000FF));
    await tester.pumpWidget(
      build(const [
        Marker(key: ValueKey(1), point: LatLng(0, 0), child: child),
        Marker(key: ValueKey(2), point: LatLng(1, 1), child: child),
        Marker(key: ValueKey(3), point: LatLng(2, 2), child: child),
      ]),
    );
    fake.ready();
    await settle(tester);
    expect(fake.markers, hasLength(3));
    expect(fake.markers.values.map((m) => m.icon.key).toSet(), hasLength(1));
    final updatesBefore = fake.markerUpdates.length;

    await tester.pumpWidget(
      build(const [
        Marker(key: ValueKey(1), point: LatLng(0, 0), child: child),
        Marker(key: ValueKey(2), point: LatLng(5, 5), child: child),
      ]),
    );
    await settle(tester);
    expect(fake.markerUpdates.length, updatesBefore + 1);
    final update = fake.markerUpdates.last;
    expect(update.added, isEmpty);
    expect(update.changed.single.position, const LatLng(5, 5));
    expect(update.removedIds.single, endsWith('/kint:3'));
  });

  testWidgets('a marker whose new icon is still rendering stays as it was until the icon is ready', (tester) async {
    Widget build(Color color, LatLng point) => mapApp(
      children: [
        MarkerLayer(
          markers: [
            Marker(
              key: const ValueKey('m'),
              point: point,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(build(const Color(0xFFFF0000), const LatLng(0, 0)));
    fake.ready();
    await settle(tester);
    final first = fake.markers.values.single;

    await tester.pumpWidget(build(const Color(0xFF00FF00), const LatLng(1, 1)));
    await tester.pump();
    expect(fake.markers.values.single, first, reason: 'previous generation untouched until the new icon is ready');
    final updatesBefore = fake.markerUpdates.length;
    await settle(tester);

    expect(fake.markerUpdates.expand((u) => u.removedIds), isEmpty);
    expect(fake.markerUpdates.length, updatesBefore + 1, reason: 'icon and position change together');
    final last = fake.markers.values.single;
    expect(last.icon.key, isNot(first.icon.key));
    expect(last.position, const LatLng(1, 1));
  });

  testWidgets('marker taps reach Marker.onTap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      mapApp(
        children: [
          MarkerLayer(
            markers: [
              Marker(
                key: const ValueKey('t'),
                point: const LatLng(0, 0),
                onTap: () => tapped++,
                child: const SizedBox(),
              ),
            ],
          ),
        ],
      ),
    );
    fake.ready();
    await settle(tester);
    fake.tapMarker(fake.markers.keys.single);
    expect(tapped, 1);
  });

  testWidgets('converts polylines, polygons, circles and tile layers', (tester) async {
    await tester.pumpWidget(
      mapApp(
        children: const [
          TileLayer(
            urlTemplate: 'https://tile/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example',
            tileDisplay: TileDisplay.instantaneous(opacity: 0.5),
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: [LatLng(0, 0), LatLng(1, 1)],
                strokeWidth: 4,
                color: Color(0xFF0000FF),
                borderStrokeWidth: 2,
                borderColor: Color(0xFFFFFFFF),
                pattern: StrokePattern.dotted(),
                strokeCap: StrokeCap.butt,
                strokeJoin: StrokeJoin.bevel,
              ),
            ],
          ),
          PolygonLayer(
            polygons: [
              Polygon(
                points: [LatLng(0, 0), LatLng(0, 1), LatLng(1, 1)],
                holePointsList: [
                  [LatLng(0.1, 0.5), LatLng(0.2, 0.6), LatLng(0.3, 0.7)],
                ],
                borderStrokeWidth: 3,
              ),
            ],
          ),
          CircleLayer(
            circles: [
              CircleMarker(key: ValueKey('m'), point: LatLng(0, 0), radius: 100, useRadiusInMeter: true),
              CircleMarker(point: LatLng(0, 0), radius: 10),
            ],
          ),
        ],
      ),
    );
    fake.ready(camera: const PlatformCamera(center: LatLng(0, 0), zoom: 10));
    await tester.pump();

    final tiles = fake.tileLayers.values.single;
    expect(tiles.urlTemplate, 'https://tile/{z}/{x}/{y}.png');
    expect(tiles.headers['User-Agent'], 'flutter_unified_map (com.example)');
    expect(tiles.opacity, 0.5);
    expect(tiles.subdomains, ['a', 'b', 'c']);

    final line = fake.polylines.values.single;
    expect(line.width, 4);
    expect(line.borderWidth, 2);
    expect(line.dashPattern, [4, 6]);
    expect(line.cap, PlatformStrokeCap.butt);
    expect(line.join, PlatformStrokeJoin.bevel);
    expect(line.zIndex, greaterThan(tiles.zIndex));

    final polygon = fake.polygons.values.single;
    expect(polygon.fillColor, const Color(0x00000000));
    expect(polygon.holes, hasLength(1));
    expect(polygon.strokeWidth, 3);

    final meters = fake.circles.values.firstWhere((c) => c.id.endsWith('/k:m'));
    final pixels = fake.circles.values.firstWhere((c) => c.id.endsWith('/1'));
    expect(meters.radiusMeters, 100);
    final mpp10 = MapCamera(
      crs: const Epsg3857(),
      rotation: 0,
      center: LatLng(0, 0),
      zoom: 10,
      nonRotatedSize: Size(800, 600),
    ).metersPerPixel(0);
    expect(pixels.radiusMeters, closeTo(10 * mpp10, 1e-6));

    fake.moveTo(const PlatformCamera(center: LatLng(0, 0), zoom: 11));
    await tester.pump();
    expect(fake.circles.values.firstWhere((c) => c.id.endsWith('/1')).radiusMeters, closeTo(5 * mpp10, 1e-6));
    expect(fake.circles.values.firstWhere((c) => c.id.endsWith('/k:m')).radiusMeters, 100);
  });

  testWidgets('maps platform events to MapEvents and callbacks', (tester) async {
    final controller = MapController();
    final callbacks = <MapEvent>[];
    final positions = <(MapCamera, bool)>[];
    final taps = <(TapPosition, LatLng)>[];
    await tester.pumpWidget(
      mapApp(
        controller: controller,
        options: MapOptions(
          onMapEvent: callbacks.add,
          onPositionChanged: (camera, gesture) => positions.add((camera, gesture)),
          onTap: (position, point) => taps.add((position, point)),
        ),
      ),
    );
    final streamed = <MapEvent>[];
    final subscription = controller.mapEventStream.listen(streamed.add);
    fake.ready(camera: const PlatformCamera(center: LatLng(10, 10), zoom: 5));
    await tester.pump();
    expect(controller.camera.center, const LatLng(10, 10));
    expect(controller.camera.nonRotatedSize, const Size(800, 600));

    fake.moveTo(const PlatformCamera(center: LatLng(11, 10), zoom: 5));
    await tester.pump();
    expect(callbacks.map((e) => e.runtimeType), [MapEventMoveStart, MapEventMove, MapEventMoveEnd]);
    expect(callbacks.map((e) => e.source), everyElement(MapEventSource.onDrag));
    final move = callbacks[1] as MapEventMove;
    expect(move.oldCamera.center, const LatLng(10, 10));
    expect(move.camera.center, const LatLng(11, 10));
    expect(positions.single.$2, isTrue);
    expect(positions.single.$1.center, const LatLng(11, 10));
    expect(streamed.map((e) => e.runtimeType), [MapEventMoveStart, MapEventMove, MapEventMoveEnd]);

    callbacks.clear();
    positions.clear();
    controller.move(const LatLng(12, 10), 6, id: 'mine');
    fake.moveTo(const PlatformCamera(center: LatLng(12, 10), zoom: 6), byGesture: false);
    await tester.pump();
    expect(callbacks.map((e) => e.source), everyElement(MapEventSource.mapController), reason: 'as flutter_map');
    expect((callbacks[1] as MapEventMove).id, 'mine');
    expect(positions.single.$2, isFalse);

    callbacks.clear();
    fake.moveTo(const PlatformCamera(center: LatLng(12, 10), zoom: 6, bearing: 30));
    await tester.pump();
    expect(callbacks[1], isA<MapEventRotate>());
    expect(controller.camera.rotation, -30, reason: 'a compass bearing of 30° turns the content 30° counter-clockwise');

    callbacks.clear();
    fake.tap(const LatLng(1, 1), const Offset(10, 20));
    expect(callbacks.single, isA<MapEventTap>());
    expect(taps.single.$1.relative, const Offset(10, 20));
    expect(taps.single.$1.global, const Offset(10, 20));
    expect(taps.single.$2, const LatLng(1, 1));

    unawaited(subscription.cancel());
  });

  testWidgets('platform bearing is a compass heading: bearing 90 puts north on the left', (tester) async {
    final controller = MapController();
    await tester.pumpWidget(mapApp(controller: controller));
    fake.ready(camera: const PlatformCamera(center: LatLng(45, 5), zoom: 10, bearing: 90));
    await tester.pump();
    final north = controller.camera.latLngToScreenOffset(const LatLng(45.1, 5));
    expect(north.dx, lessThan(400 - 1));
    expect(north.dy, closeTo(300, 1e-6));
    final east = controller.camera.latLngToScreenOffset(const LatLng(45, 5.1));
    expect(east.dy, lessThan(300 - 1), reason: 'the camera faces east');
    controller.dispose();
  });

  testWidgets('onMapReady and initialCameraFit run once even if ready is reported again', (tester) async {
    var readyCount = 0;
    await tester.pumpWidget(
      mapApp(
        options: MapOptions(
          onMapReady: () => readyCount++,
          initialCameraFit: CameraFit.bounds(bounds: LatLngBounds(const LatLng(40, -5), const LatLng(50, 8))),
        ),
      ),
    );
    fake.ready();
    fake.ready(camera: const PlatformCamera(center: LatLng(3, 3), zoom: 4));
    await tester.pump();
    expect(readyCount, 1);
    expect(fake.cameraMoves, hasLength(1));
  });

  testWidgets('removing minZoom and maxZoom clears them on the camera', (tester) async {
    MapCamera? seen;
    Widget build(MapOptions options) => mapApp(
      options: options,
      children: [
        Builder(
          builder: (context) {
            seen = MapCamera.of(context);
            return const SizedBox();
          },
        ),
      ],
    );
    await tester.pumpWidget(build(const MapOptions(minZoom: 4, maxZoom: 12)));
    fake.ready();
    await tester.pump();
    expect((seen!.minZoom, seen!.maxZoom), (4.0, 12.0));
    await tester.pumpWidget(build(const MapOptions()));
    expect((seen!.minZoom, seen!.maxZoom), (null, null));
    expect((fake.optionUpdates.last.minZoom, fake.optionUpdates.last.maxZoom), (0.0, 22.0));
  });

  testWidgets('MapCamera.of follows the camera and the layout size', (tester) async {
    MapCamera? seen;
    await tester.pumpWidget(
      mapApp(
        children: [
          Builder(
            builder: (context) {
              seen = MapCamera.of(context);
              return const SizedBox();
            },
          ),
        ],
      ),
    );
    expect(seen!.nonRotatedSize, const Size(800, 600));
    fake.ready(camera: const PlatformCamera(center: LatLng(3, 4), zoom: 7));
    await tester.pump();
    expect(seen!.center, const LatLng(3, 4));
    expect(seen!.zoom, 7);
  });

  testWidgets('option changes reach updateOptions once ready', (tester) async {
    await tester.pumpWidget(mapApp());
    fake.ready();
    await tester.pumpWidget(
      mapApp(
        options: const MapOptions(nativeParams: NativeParams(mapType: MapStyle.none)),
      ),
    );
    expect(fake.optionUpdates.single.style, PlatformMapStyle.none);
    await tester.pumpWidget(
      mapApp(
        options: const MapOptions(initialZoom: 3, nativeParams: NativeParams(mapType: MapStyle.none)),
      ),
    );
    expect(fake.optionUpdates, hasLength(1), reason: 'initial camera changes are not options updates');
  });

  testWidgets('applies initialCameraFit on ready', (tester) async {
    await tester.pumpWidget(
      mapApp(
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds(const LatLng(40, -5), const LatLng(50, 8)),
            padding: const EdgeInsets.all(20),
          ),
        ),
      ),
    );
    expect(fake.cameraMoves, isEmpty);
    fake.ready();
    final update = fake.cameraMoves.single.update as PlatformCameraUpdateFitBounds;
    expect(update.bounds.southWest, const LatLng(40, -5));
    expect(update.padding, const EdgeInsets.all(20));
  });

  testWidgets('layers removed from the tree are removed from the platform', (tester) async {
    await tester.pumpWidget(
      mapApp(
        children: const [
          PolylineLayer(
            polylines: [
              Polyline(points: [LatLng(0, 0), LatLng(1, 1)]),
            ],
          ),
        ],
      ),
    );
    fake.ready();
    await tester.pump();
    expect(fake.polylines, hasLength(1));
    await tester.pumpWidget(mapApp());
    await tester.pump();
    expect(fake.polylines, isEmpty);
  });

  testWidgets('non-layer children are drawn above the map', (tester) async {
    await tester.pumpWidget(mapApp(children: const [Positioned(right: 0, bottom: 0, child: Text('overlay'))]));
    expect(find.text('overlay'), findsOneWidget);
  });

  testWidgets('a marker without onTap is not tappable, so taps on it reach the map', (tester) async {
    await tester.pumpWidget(
      mapApp(
        children: [
          MarkerLayer(
            markers: [
              const Marker(
                key: ValueKey('plain'),
                point: LatLng(0, 0),
                child: ColoredBox(color: Color(0xFFFF0000)),
              ),
              Marker(
                key: const ValueKey('button'),
                point: const LatLng(1, 1),
                onTap: () {},
                child: const ColoredBox(color: Color(0xFFFF0000)),
              ),
            ],
          ),
        ],
      ),
    );
    fake.ready();
    await settle(tester);
    expect(fake.markers.values.singleWhere((m) => m.id.endsWith('/k:plain')).tappable, isFalse);
    expect(fake.markers.values.singleWhere((m) => m.id.endsWith('/k:button')).tappable, isTrue);
  });

  testWidgets('markers with equal keys share an id, different keys never do', (tester) async {
    final a = Object();
    final b = Object();
    final c = _Thing();
    final d = _Thing();
    Widget build(List<Key> keys) => mapApp(
      children: [
        MarkerLayer(
          markers: [
            for (final (i, key) in keys.indexed)
              Marker(
                key: key,
                point: LatLng(i.toDouble(), 0),
                child: const ColoredBox(color: Color(0xFF00FF00)),
              ),
          ],
        ),
      ],
    );
    final keys = [const ValueKey(1), const ValueKey('1'), ObjectKey(a), ObjectKey(b), ValueKey(c), ValueKey(d)];
    await tester.pumpWidget(build([...keys, UniqueKey()]));
    fake.ready();
    await settle(tester);
    expect(fake.markers, hasLength(7), reason: 'one id per distinct key');
    final ids = Map.of(fake.markers);

    await tester.pumpWidget(build([for (final key in keys) key is ValueKey<_Thing> ? ValueKey(key.value) : key]));
    await settle(tester);
    expect(fake.markers.keys.toSet(), ids.keys.toSet().difference({ids.keys.last}), reason: 'ids follow key equality');
  });

  testWidgets('icons are rasterised again when the theme changes', (tester) async {
    Widget build(Brightness brightness) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600), devicePixelRatio: 2),
        child: UnifiedMap(
          children: [
            MarkerLayer(
              markers: [Marker(key: const ValueKey('m'), point: const LatLng(0, 0), child: const Icon(Icons.place))],
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(build(Brightness.light));
    fake.ready();
    await settle(tester);
    final light = fake.markers.values.single.icon;

    await tester.pumpWidget(build(Brightness.dark));
    await settle(tester);
    final dark = fake.markers.values.single.icon;
    expect(dark.key, isNot(light.key));
    expect(dark.bytes, isNot(light.bytes), reason: 'the icon color follows the dark theme');
  });

  testWidgets('a failed shape update is reported, re-sent and recorded only once applied', (tester) async {
    Widget build(List<LatLng> points) => mapApp(
      children: [
        PolylineLayer(polylines: [Polyline(points: points)]),
      ],
    );
    await tester.pumpWidget(build(const [LatLng(0, 0), LatLng(1, 1)]));
    var attempts = 0;
    fake.shapeUpdateGate = () async {
      if (++attempts == 1) throw StateError('view not found');
    };
    fake.ready();
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isStateError);
    expect(attempts, 2);
    expect(fake.polylines, hasLength(1), reason: 'retried after the failure');
    expect(fake.polylineUpdates.single.added, hasLength(1));

    await tester.pumpWidget(build(const [LatLng(0, 0), LatLng(2, 2)]));
    await tester.pump();
    expect(fake.polylineUpdates.last.changed, hasLength(1), reason: 'diffed against what was applied');
  });

  testWidgets('idleCamera and liveCamera listeners see the map ready on the first notification', (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    final key = GlobalKey<TestLayerState>();
    await tester.pumpWidget(
      mapApp(
        controller: controller,
        children: [TestLayer(key: key)],
      ),
    );
    final host = key.currentState!.host;
    final seen = <(String, bool, bool)>[];
    void listen(String name, ValueListenable<Object?> camera) => camera.addListener(() {
      if (seen.any((s) => s.$1 == name)) return;
      seen.add((name, host.isReady, controller.move(const LatLng(5, 5), 3)));
    });
    listen('idle', host.idleCamera);
    listen('live', host.liveCamera);
    fake.ready();
    expect(seen, unorderedEquals([('idle', true, true), ('live', true, true)]), reason: 'they can drive the camera');
  });

  testWidgets('a late idle does not take the id of the next programmatic move', (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    final events = <MapEvent>[];
    await tester.pumpWidget(
      mapApp(
        controller: controller,
        options: MapOptions(onMapEvent: events.add),
      ),
    );
    fake.ready();
    final viewId = fake.lastViewId;
    unawaited(controller.animateTo(dest: const LatLng(1, 1), customId: 'a'));
    fake.emit(PlatformCameraMoveStartedEvent(viewId, byGesture: false));
    fake.emit(PlatformCameraMoveEvent(viewId, const PlatformCamera(center: LatLng(1, 1), zoom: 2)));
    controller.move(const LatLng(2, 2), 2, id: 'b');
    fake.emit(PlatformCameraIdleEvent(viewId, const PlatformCamera(center: LatLng(1, 1), zoom: 2)));
    fake.emit(PlatformCameraMoveStartedEvent(viewId, byGesture: false));
    fake.emit(PlatformCameraMoveEvent(viewId, const PlatformCamera(center: LatLng(2, 2), zoom: 2)));
    fake.emit(PlatformCameraIdleEvent(viewId, const PlatformCamera(center: LatLng(2, 2), zoom: 2)));
    expect(events.whereType<MapEventMove>().map((e) => e.id), ['a', 'b']);
    expect(events.map((e) => e.source), everyElement(MapEventSource.mapController));
  });

  testWidgets('a movement interrupted by another one ends before the next starts', (tester) async {
    final events = <MapEvent>[];
    await tester.pumpWidget(mapApp(options: MapOptions(onMapEvent: events.add)));
    fake.ready();
    final viewId = fake.lastViewId;
    fake.emit(PlatformCameraMoveStartedEvent(viewId, byGesture: false));
    fake.emit(PlatformCameraMoveEvent(viewId, const PlatformCamera(center: LatLng(1, 1), zoom: 2)));
    fake.moveTo(const PlatformCamera(center: LatLng(3, 3), zoom: 2));
    expect(events.map((e) => (e.runtimeType, e.source)), [
      (MapEventMoveStart, MapEventSource.mapController),
      (MapEventMove, MapEventSource.mapController),
      (MapEventMoveEnd, MapEventSource.mapController),
      (MapEventMoveStart, MapEventSource.onDrag),
      (MapEventMove, MapEventSource.onDrag),
      (MapEventMoveEnd, MapEventSource.onDrag),
    ]);
  });

  testWidgets('platform failures of fire-and-forget calls are reported, not thrown', (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(mapApp(controller: controller));
    fake.ready();
    await tester.pump();

    fake.moveCameraError = StateError('view torn down');
    expect(controller.move(const LatLng(1, 1), 4), isTrue);
    await tester.pump();
    expect(tester.takeException(), isStateError);
    fake.moveCameraError = null;

    fake.optionsError = StateError('rejected');
    await tester.pumpWidget(
      mapApp(
        controller: controller,
        options: const MapOptions(nativeParams: NativeParams(mapType: MapStyle.none)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isStateError);
    fake.optionsError = null;
    await tester.pumpWidget(
      mapApp(
        controller: controller,
        options: const MapOptions(initialZoom: 4, nativeParams: NativeParams(mapType: MapStyle.none)),
      ),
    );
    expect(fake.optionUpdates.single.style, PlatformMapStyle.none, reason: 'the failed options go out again');

    fake.snapshotError = StateError('no surface');
    expect(await controller.takeSnapshot(), isNull);
    expect(tester.takeException(), isStateError);
  });

  testWidgets('takeSnapshot is null before ready and the bytes once ready', (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(mapApp(controller: controller));
    expect(await controller.takeSnapshot(), isNull);
    fake.ready();
    expect(await controller.takeSnapshot(), hasLength(4));
  });

  testWidgets('long presses reach onLongPress and the hit notifiers', (tester) async {
    final presses = <LatLng>[];
    final hits = LayerHitNotifier<String>(null);
    final events = <MapEvent>[];
    await tester.pumpWidget(
      mapApp(
        options: MapOptions(onLongPress: (_, point) => presses.add(point), onMapEvent: events.add),
        children: [
          CircleLayer(
            hitNotifier: hits,
            circles: const [CircleMarker(point: LatLng(0, 0), radius: 20, hitValue: 'c')],
          ),
        ],
      ),
    );
    fake.ready(camera: const PlatformCamera(center: LatLng(0, 0), zoom: 10));
    await tester.pump();
    fake.longPress(const LatLng(0, 0), const Offset(405, 300));
    expect(presses, [const LatLng(0, 0)]);
    expect(hits.value!.hitValues, ['c']);
    expect(events.single, isA<MapEventLongPress>());
  });

  testWidgets('a resize after the first layout emits MapEventNonRotatedSizeChange', (tester) async {
    final events = <MapEvent>[];
    Widget app(double width) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 300,
          child: UnifiedMap(
            options: MapOptions(onMapEvent: events.add),
            children: const [],
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(400));
    await tester.pump();
    expect(events, isEmpty, reason: 'the first size is not a change');
    await tester.pumpWidget(app(500));
    await tester.pump();
    final change = events.single as MapEventNonRotatedSizeChange;
    expect(change.source, MapEventSource.nonRotatedSizeChange);
    expect(
      (change.oldCamera.nonRotatedSize, change.camera.nonRotatedSize),
      (const Size(400, 300), const Size(500, 300)),
    );
  });

  testWidgets('swapping controllers moves the events to the new one and detaches the old one', (tester) async {
    final first = MapController();
    final second = MapController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(mapApp());
    fake.ready();
    expect(() => first.camera, throwsStateError);

    await tester.pumpWidget(mapApp(controller: first));
    final firstEvents = <MapEvent>[];
    final secondEvents = <MapEvent>[];
    first.mapEventStream.listen(firstEvents.add);
    second.mapEventStream.listen(secondEvents.add);
    expect(first.move(const LatLng(1, 1), 3), isTrue);

    await tester.pumpWidget(mapApp(controller: second));
    expect(() => first.camera, throwsStateError, reason: 'detached');
    fake.moveTo(const PlatformCamera(center: LatLng(4, 4), zoom: 3));
    await tester.pump();
    expect(firstEvents, isEmpty);
    expect(secondEvents.whereType<MapEventMove>(), hasLength(1));
    expect(second.camera.center, const LatLng(4, 4));
  });

  testWidgets('TileLayer fetches up to maxNativeZoom and hides above maxZoom', (tester) async {
    await tester.pumpWidget(
      mapApp(
        children: const [
          TileLayer(urlTemplate: 'https://tile/{z}/{x}/{y}.png', maxNativeZoom: 17, maxZoom: 12, tileDimension: 512),
        ],
      ),
    );
    fake.ready(camera: const PlatformCamera(center: LatLng(0, 0), zoom: 10));
    await tester.pump();
    final tiles = fake.tileLayers.values.single;
    expect((tiles.maxZoom, tiles.tileSize), (17.0, 512));

    fake.moveTo(const PlatformCamera(center: LatLng(0, 0), zoom: 13));
    await tester.pump();
    expect(fake.tileLayers, isEmpty);
    fake.moveTo(const PlatformCamera(center: LatLng(0, 0), zoom: 11));
    await tester.pump();
    expect(fake.tileLayers, hasLength(1));
  });
}

class _Thing {}
