import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/plugin_api.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show
        PlatformCamera,
        PlatformCameraIdleEvent,
        PlatformCameraMoveEvent,
        PlatformCameraMoveStartedEvent,
        PlatformMarkerTransition;

import 'support/fake_platform.dart';
import 'support/harness.dart';
import 'support/test_layer.dart';

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);
const _blue = Color(0xFF0000FF);
const _p0 = LatLng(0, 0);
const _p1 = LatLng(1, 1);
const _p2 = LatLng(2, 2);

void main() {
  late FakeUnifiedMapsPlatform fake;

  setUp(() => fake = installFakePlatform());

  Future<TestLayerState> mountLayer(WidgetTester tester, {List<Widget> extra = const []}) async {
    final key = GlobalKey<TestLayerState>();
    await tester.pumpWidget(
      mapApp(
        children: [
          TestLayer(key: key),
          ...extra,
        ],
      ),
    );
    fake.ready();
    await settle(tester);
    return key.currentState!;
  }

  Set<String> idsOnMap() => fake.markers.keys.toSet();

  test('integerZoom tolerates platforms that report 4.9999999 for zoom 5', () {
    expect(integerZoom(4.9999999), 5);
    expect(integerZoom(5), 5);
    expect(integerZoom(5.7), 5);
    expect(integerZoom(4.99), 4);
    expect(integerZoom(-0.0000001), 0);
  });

  testWidgets('a layer written against plugin_api publishes markers, receives taps and draws polylines', (
    tester,
  ) async {
    final layer = await mountLayer(tester);
    expect(layer.host.isReady, isTrue);
    expect(layer.host.pixelRatio, 2);

    layer.show({'a': (_p0, _red), 'b': (_p1, _red)});
    await settle(tester);
    expect(idsOnMap(), {layer.idOf('a'), layer.idOf('b')});
    expect(layer.idOf('a'), startsWith('${layer.layerId}/'));
    expect(fake.markers.values.map((m) => m.icon.key).toSet(), hasLength(1), reason: 'one icon per iconKey');
    expect(layer.publisher.published.map((s) => s.id), [layer.idOf('a'), layer.idOf('b')]);

    fake.tapMarker(layer.idOf('b'));
    expect(layer.taps, [layer.idOf('b')]);

    layer.setPolylines(const [
      Polyline(points: [_p0, _p1], strokeWidth: 3),
    ]);
    await tester.pump();
    expect(fake.polylines.keys, ['${layer.layerId}/0']);

    await tester.pumpWidget(mapApp());
    await tester.pump();
    expect(fake.markers, isEmpty, reason: 'disposing the layer removes its objects');
    expect(fake.polylines, isEmpty);
  });

  testWidgets('a generation is published only once all its icons are ready; a newer one supersedes it', (tester) async {
    final layer = await mountLayer(tester);
    layer.show({'a': (_p0, _red)});
    await settle(tester);
    final before = Map.of(fake.markers);
    final updatesBefore = fake.markerUpdates.length;

    layer.show({'a': (_p1, _red), 'b': (_p1, _green)});
    await tester.pump();
    await tester.pump();
    expect(layer.publisher.hasPending, isTrue);
    expect(fake.markers, before, reason: 'previous generation untouched while the green icon renders');
    expect(fake.markerUpdates.length, updatesBefore);

    layer.show({'c': (_p2, _blue)});
    await tester.pump();
    await settle(tester);
    expect(layer.publisher.hasPending, isFalse);
    expect(idsOnMap(), {layer.idOf('c')});
    expect(fake.markerUpdates.length, updatesBefore + 1, reason: 'one atomic update from a to c');
    final update = fake.markerUpdates.last;
    expect(update.added.map((m) => m.id), [layer.idOf('c')]);
    expect(update.removedIds, [layer.idOf('a')]);
    expect(
      fake.markerUpdates.expand((u) => [...u.added, ...u.changed]).map((m) => m.id),
      isNot(contains(layer.idOf('b'))),
      reason: 'the superseded generation never reaches the platform',
    );
  });

  testWidgets('transition hints are merged into one PlatformMarkerTransition for the ids the push touches', (
    tester,
  ) async {
    final second = GlobalKey<TestLayerState>();
    final layer = await mountLayer(tester, extra: [TestLayer(key: second)]);
    final other = second.currentState!;
    layer.show({'parent': (_p0, _red), 'stay': (_p2, _red)});
    other.show({'x': (_p0, _blue)});
    await settle(tester);

    layer.show(
      {'child1': (_p1, _red), 'child2': (_p2, _red), 'stay': (_p2, _red)},
      transition: MarkerTransition(
        duration: const Duration(milliseconds: 300),
        appearFrom: {layer.idOf('child1'): _p0, layer.idOf('stay'): _p0, layer.idOf('unknown'): _p0},
        disappearTo: {layer.idOf('parent'): _p1, layer.idOf('stay'): _p1},
      ),
    );
    other.show({'x': (_p0, _blue)}, transition: const MarkerTransition(duration: Duration(seconds: 2)));
    await tester.pump();
    expect(
      fake.markerTransitions.last,
      PlatformMarkerTransition(
        duration: const Duration(milliseconds: 300),
        appearFrom: {layer.idOf('child1'): _p0},
        disappearTo: {layer.idOf('parent'): _p1},
      ),
      reason: 'the other layer is unchanged in this push, so its longer duration does not count',
    );

    layer.show(
      {'child1': (_p0, _red), 'stay': (_p2, _red)},
      transition: MarkerTransition(
        duration: const Duration(milliseconds: 300),
        disappearTo: {layer.idOf('child2'): _p0},
      ),
    );
    other.show({'x': (_p1, _blue)}, transition: const MarkerTransition(duration: Duration(milliseconds: 500)));
    await tester.pump();
    final merged = fake.markerTransitions.last!;
    expect(merged.duration, const Duration(milliseconds: 500), reason: 'duration is the longest of the touched layers');
    expect(merged.appearFrom, isEmpty);
    expect(merged.disappearTo, {layer.idOf('child2'): _p0});
    expect(fake.markerUpdates.last.changed.map((m) => m.id), unorderedEquals([layer.idOf('child1'), other.idOf('x')]));

    layer.show({'child1': (_p1, _red), 'stay': (_p2, _red)});
    await tester.pump();
    expect(fake.markerTransitions.last, isNull, reason: 'hints are used once');
  });

  testWidgets('transitions set before one push are merged', (tester) async {
    final layer = await mountLayer(tester);
    layer.show({'a': (_p0, _red)});
    await settle(tester);

    layer.show({
      'a': (_p0, _red),
      'b': (_p1, _red),
    }, transition: MarkerTransition(duration: const Duration(milliseconds: 200), appearFrom: {layer.idOf('b'): _p0}));
    layer.show(
      {'b': (_p1, _red), 'c': (_p2, _red)},
      transition: MarkerTransition(
        duration: const Duration(milliseconds: 100),
        appearFrom: {layer.idOf('c'): _p1},
        disappearTo: {layer.idOf('a'): _p1},
      ),
    );
    await tester.pump();
    expect(fake.markerUpdates.last.added.map((m) => m.id), unorderedEquals([layer.idOf('b'), layer.idOf('c')]));
    expect(
      fake.markerTransitions.last,
      PlatformMarkerTransition(
        duration: const Duration(milliseconds: 200),
        appearFrom: {layer.idOf('b'): _p0, layer.idOf('c'): _p1},
        disappearTo: {layer.idOf('a'): _p1},
      ),
    );
  });

  testWidgets('markers of layers without a transition go out first, in an update without transition', (tester) async {
    const pin = ColoredBox(color: _blue);
    final plain = ValueNotifier<List<Marker>>(const [Marker(key: ValueKey('me'), point: _p0, child: pin)]);
    addTearDown(plain.dispose);
    final layer = await mountLayer(
      tester,
      extra: [
        ValueListenableBuilder(
          valueListenable: plain,
          builder: (context, markers, _) => MarkerLayer(markers: markers),
        ),
      ],
    );
    layer.show({'a': (_p0, _red)});
    await settle(tester);
    final plainIds = fake.markers.keys.where((id) => !id.startsWith('${layer.layerId}/')).toSet();
    expect(plainIds, hasLength(1));
    final updatesBefore = fake.markerUpdates.length;

    plain.value = const [
      Marker(key: ValueKey('me'), point: _p1, child: pin),
      Marker(key: ValueKey('sel'), point: _p2, child: pin),
    ];
    layer.show({
      'b': (_p1, _red),
    }, transition: MarkerTransition(duration: const Duration(milliseconds: 300), appearFrom: {layer.idOf('b'): _p0}));
    await tester.pump();
    await tester.pump();

    final updates = fake.markerUpdates.skip(updatesBefore).toList();
    final transitions = fake.markerTransitions.skip(updatesBefore).toList();
    expect(updates, hasLength(2));
    expect(transitions.first, isNull);
    expect(updates.first.changed.map((m) => m.id), plainIds);
    expect(updates.first.added.map((m) => m.id).single, isNot(startsWith('${layer.layerId}/')));
    expect(updates.first.removedIds, isEmpty);
    expect(updates.last.added.map((m) => m.id), [layer.idOf('b')]);
    expect(updates.last.removedIds, [layer.idOf('a')]);
    expect(updates.last.changed, isEmpty);
    expect(
      transitions.last,
      PlatformMarkerTransition(duration: const Duration(milliseconds: 300), appearFrom: {layer.idOf('b'): _p0}),
    );
    expect(fake.maxMarkerUpdatesInFlight, 1);
  });

  testWidgets('a marker update the platform failed is sent again, with its transition', (tester) async {
    final layer = await mountLayer(tester);
    layer.show({'a': (_p0, _red)});
    await settle(tester);
    var attempts = 0;
    fake.markerUpdateGate = () async {
      attempts++;
      if (attempts == 1) throw StateError('icon registration failed');
    };

    final transition = MarkerTransition(
      duration: const Duration(milliseconds: 200),
      appearFrom: {layer.idOf('b'): _p0},
    );
    layer.show({'a': (_p0, _red), 'b': (_p1, _red)}, transition: transition);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(attempts, 2, reason: 'retried once right away');
    expect(tester.takeException(), isStateError, reason: 'the failure is reported');
    expect(idsOnMap(), {layer.idOf('a'), layer.idOf('b')});
    expect(fake.markerUpdates.last.added.map((m) => m.id), [layer.idOf('b')]);
    expect(
      fake.markerTransitions.last,
      PlatformMarkerTransition(duration: const Duration(milliseconds: 200), appearFrom: {layer.idOf('b'): _p0}),
    );

    attempts = 0;
    fake.markerUpdateGate = () async {
      attempts++;
      throw StateError('still failing');
    };
    layer.show({'a': (_p0, _red), 'b': (_p1, _red), 'c': (_p2, _red)});
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(attempts, 2, reason: 'a platform that keeps failing is not called every frame');
    expect(tester.takeException(), isStateError, reason: 'reported once for the series of failures');

    fake.markerUpdateGate = null;
    layer.show({'a': (_p1, _red), 'b': (_p1, _red), 'c': (_p2, _red)});
    await tester.pump();
    await tester.pump();
    expect(idsOnMap(), {layer.idOf('a'), layer.idOf('b'), layer.idOf('c')});
    expect(fake.markers[layer.idOf('a')]!.position, _p1);
  });

  testWidgets('polylines published with a generation wait for it and for its markers to be applied', (tester) async {
    final layer = await mountLayer(tester);
    layer.show({'a': (_p0, _red)});
    await settle(tester);
    final gates = <Completer<void>>[];
    fake.markerUpdateGate = () {
      final gate = Completer<void>();
      gates.add(gate);
      return gate.future;
    };
    const leg = Polyline(points: [_p0, _p1]);

    layer.show({'a': (_p1, _red)});
    await tester.pump();
    expect(gates, hasLength(1));
    layer.show({'a': (_p1, _red), 'b': (_p2, _red)}, polylines: const [leg]);
    await tester.pump();
    await tester.pump();
    expect(fake.polylines, isEmpty, reason: 'held while the previous marker update is in flight');

    gates.single.complete();
    await tester.pump();
    await tester.pump();
    expect(gates, hasLength(2), reason: 'markers of that generation sent in the next flush');
    expect(fake.polylines, isEmpty, reason: 'the polylines wait until those markers are applied');
    gates.last.complete();
    await tester.pump();
    await tester.pump();
    expect(idsOnMap(), {layer.idOf('a'), layer.idOf('b')});
    expect(fake.polylines.keys, ['${layer.layerId}/0']);

    fake.markerUpdateGate = null;
    layer.show({'a': (_p1, _red), 'c': (_p0, _green)}, polylines: const []);
    await tester.pump();
    await tester.pump();
    expect(fake.polylines.keys, ['${layer.layerId}/0'], reason: 'the generation waits for its green icon');
    await settle(tester);
    expect(fake.polylines, isEmpty);
    expect(idsOnMap(), {layer.idOf('a'), layer.idOf('c')});
  });

  testWidgets('a layer mounted again goes back on top without z-indexes growing', (tester) async {
    final base = GlobalKey<TestLayerState>();
    final toggled = GlobalKey<TestLayerState>();
    Widget app({required bool withToggled}) => mapApp(
      children: [
        TestLayer(key: base),
        if (withToggled) TestLayer(key: toggled),
      ],
    );
    await tester.pumpWidget(app(withToggled: true));
    fake.ready();
    await settle(tester);
    final registry = base.currentState!.host.registry;
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(app(withToggled: false));
      await tester.pumpWidget(app(withToggled: true));
    }
    expect(registry.zIndexOf(base.currentState!.layerId), 0);
    expect(registry.zIndexOf(toggled.currentState!.layerId), 1);
  });

  testWidgets('marker pushes reach the platform one at a time, coalescing what changed meanwhile', (tester) async {
    final layer = await mountLayer(tester);
    layer.show({'a': (_p0, _red)});
    await settle(tester);
    final updatesBefore = fake.markerUpdates.length;
    final gates = <Completer<void>>[];
    fake.markerUpdateGate = () {
      final gate = Completer<void>();
      gates.add(gate);
      return gate.future;
    };

    layer.show({'a': (_p1, _red)});
    await tester.pump();
    expect(gates, hasLength(1));
    layer.show({'a': (_p1, _red), 'x': (_p2, _red)});
    await tester.pump();
    layer.show({'a': (_p2, _red), 'b': (_p0, _red)});
    await tester.pump();
    await tester.pump();
    expect(fake.markerUpdatesInFlight, 1);
    expect(gates, hasLength(1), reason: 'no second update while the first is in flight');

    gates.first.complete();
    await tester.pump();
    await tester.pump();
    expect(gates, hasLength(2));
    gates.last.complete();
    await tester.pump();

    expect(fake.maxMarkerUpdatesInFlight, 1);
    final updates = fake.markerUpdates.skip(updatesBefore).toList();
    expect(updates, hasLength(2));
    expect(updates.first.changed.single.position, _p1);
    expect(updates.last.changed.single.position, _p2);
    expect(updates.last.added.map((m) => m.id), [layer.idOf('b')]);
    expect(updates.expand((u) => u.added).map((m) => m.id), isNot(contains(layer.idOf('x'))));
    expect(idsOnMap(), {layer.idOf('a'), layer.idOf('b')});
  });

  testWidgets('flutter_map layers are forwarded only when the platform draws with flutter_map', (tester) async {
    const first = SizedBox(key: ValueKey('first'));
    const second = SizedBox(key: ValueKey('second'));
    final layer = await mountLayer(tester, extra: const [FlutterMapLayer(child: first)]);
    expect(layer.host.supportsFlutterMapLayers, isFalse);
    layer.setFlutterMapLayers(const [second]);
    await tester.pump();
    expect(fake.flutterMapLayerCalls, isEmpty);
    await tester.pumpWidget(const SizedBox());

    fake = installFakePlatform()..flutterMapLayersSupported = true;
    final supported = await mountLayer(tester, extra: const [FlutterMapLayer(child: first)]);
    expect(supported.host.supportsFlutterMapLayers, isTrue);
    expect(_unwrapped(fake.flutterMapLayerCalls.last), [first]);

    supported.setFlutterMapLayers(const [second]);
    await tester.pump();
    expect(_unwrapped(fake.flutterMapLayerCalls.last), [
      second,
      first,
    ], reason: 'in layer order: the test layer comes first');
    final keys = fake.flutterMapLayerCalls.last.map((w) => w.key).toList();
    expect(keys.toSet().length, 2, reason: 'every layer widget is keyed by its layer, so state follows its layer');

    await tester.pumpWidget(mapApp(children: [TestLayer(key: GlobalKey())]));
    await tester.pump();
    expect(fake.flutterMapLayerCalls.last, isEmpty);
  });

  testWidgets('liveCamera follows every move event, idleCamera only settled moves', (tester) async {
    final layer = await mountLayer(tester);
    expect(layer.host.liveCamera.value.zoom, 2);
    expect(layer.host.liveCamera.value.nonRotatedSize, const Size(800, 600));
    final idleBefore = layer.idleCameras.length;

    final viewId = fake.lastViewId;
    fake.emit(PlatformCameraMoveStartedEvent(viewId, byGesture: true));
    fake.emit(PlatformCameraMoveEvent(viewId, const PlatformCamera(center: LatLng(10, 10), zoom: 4.5)));
    fake.emit(PlatformCameraMoveEvent(viewId, const PlatformCamera(center: LatLng(10, 10), zoom: 5.2)));
    expect(layer.liveCameras.map((c) => c.zoom), containsAllInOrder([4.5, 5.2]));
    expect(layer.host.liveCamera.value.zoom, 5.2);
    expect(layer.idleCameras.length, idleBefore, reason: 'not settled yet');

    fake.emit(PlatformCameraIdleEvent(viewId, const PlatformCamera(center: LatLng(10, 10), zoom: 5.2)));
    expect(layer.idleCameras.length, idleBefore + 1);
    expect(layer.idleCameras.last!.zoom, 5.2);
  });

  testWidgets('liveCamera follows resizes and new zoom bounds', (tester) async {
    final key = GlobalKey<TestLayerState>();
    Widget app(double width, {double? maxZoom}) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 300,
          child: UnifiedMap(
            options: MapOptions(maxZoom: maxZoom),
            children: [TestLayer(key: key)],
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(400));
    fake.ready();
    await tester.pump();
    final host = key.currentState!.host;
    expect(host.liveCamera.value.nonRotatedSize, const Size(400, 300));
    expect(host.liveCamera.value.zoom, 2, reason: 'the camera reported with ready');

    await tester.pumpWidget(app(500));
    expect(key.currentState!.liveCameras.last.nonRotatedSize, const Size(500, 300));

    await tester.pumpWidget(app(500, maxZoom: 10));
    expect(host.liveCamera.value.maxZoom, 10);
    expect(host.liveCamera.value.nonRotatedSize, const Size(500, 300));
  });

  testWidgets('layers stack in the order of UnifiedMap.children, even when inserted later', (tester) async {
    const route = PolylineLayer(
      key: ValueKey('route'),
      polylines: [
        Polyline(points: [_p0, _p1]),
      ],
    );
    const tiles = TileLayer(key: ValueKey('tiles'), urlTemplate: 'https://tile/{z}/{x}/{y}.png');
    const area = PolygonLayer(
      key: ValueKey('area'),
      polygons: [
        Polygon(points: [_p0, _p1, _p2]),
      ],
    );
    await tester.pumpWidget(mapApp(children: const [route]));
    fake.ready();
    await tester.pump();
    final routeZ = fake.polylines.values.single.zIndex;

    await tester.pumpWidget(mapApp(children: const [tiles, route, area]));
    await tester.pump();
    final tileZ = fake.tileLayers.values.single.zIndex;
    final polylineZ = fake.polylines.values.single.zIndex;
    final polygonZ = fake.polygons.values.single.zIndex;
    expect(tileZ, lessThan(polylineZ), reason: 'the base tiles stay below the route');
    expect(polylineZ, lessThan(polygonZ));
    expect(fake.polylineUpdates.length, routeZ == polylineZ ? 1 : 2, reason: 'the route is re-sent only if it moved');

    await tester.pumpWidget(mapApp(children: const [area, route]));
    await tester.pump();
    expect(fake.polygons.values.single.zIndex, lessThan(fake.polylines.values.single.zIndex), reason: 'reordered');
  });

  testWidgets('a layer changed in place is synced again, an unchanged one is not', (tester) async {
    final markers = <Marker>[
      const Marker(
        key: ValueKey('a'),
        point: _p0,
        child: ColoredBox(color: _red),
      ),
    ];
    final layer = MarkerLayer(markers: markers);
    await tester.pumpWidget(mapApp(children: [layer]));
    fake.ready();
    await settle(tester);
    final updates = fake.markerUpdates.length;

    await tester.pumpWidget(mapApp(children: [MarkerLayer(markers: markers)]));
    await settle(tester);
    expect(fake.markerUpdates.length, updates);

    markers.add(
      const Marker(
        key: ValueKey('b'),
        point: _p1,
        child: ColoredBox(color: _red),
      ),
    );
    await tester.pumpWidget(mapApp(children: [MarkerLayer(markers: markers)]));
    await settle(tester);
    expect(fake.markers, hasLength(2));
  });

  testWidgets('an icon that fails to rasterise is reported and left out, the others are published', (tester) async {
    final layer = await mountLayer(tester);
    MarkerSpec spec(String key, Size size) => MarkerSpec(
      id: layer.idOf(key),
      position: _p0,
      iconKey: key,
      child: const ColoredBox(color: _red),
      size: size,
    );
    layer.publisher.publish(layer.host, [spec('ok', const Size(10, 10)), spec('broken', Size.zero)]);
    await settle(tester);
    expect(tester.takeException(), isNotNull);
    expect(idsOnMap(), {layer.idOf('ok')});

    layer.publisher.publish(layer.host, [spec('ok', const Size(10, 10)), spec('broken', Size.zero)]);
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'not tried again while it keeps failing');

    layer.publisher.publish(layer.host, [spec('ok', const Size(10, 10))]);
    await settle(tester);
    layer.publisher.publish(layer.host, [spec('ok', const Size(10, 10)), spec('broken', Size.zero)]);
    await settle(tester);
    expect(tester.takeException(), isNotNull, reason: 'tried again after a generation without it');
  });

  testWidgets('warns once when markers get a new child widget on every rebuild', (tester) async {
    final printed = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    Widget app(int round) => mapApp(
      children: [
        MarkerLayer(
          markers: [
            for (var i = 0; i < 3; i++)
              Marker(
                key: ValueKey(i),
                point: _p0,
                child: ColoredBox(color: Color(0xFF000000 + round)),
              ),
          ],
        ),
      ],
    );
    try {
      await tester.pumpWidget(app(0));
      fake.ready();
      for (var round = 1; round < 6; round++) {
        await tester.pumpWidget(app(round));
      }
      await settle(tester);
    } finally {
      debugPrint = previous;
    }
    expect(printed.where((m) => m.contains('iconKey')), hasLength(1));
  });
}

List<Widget> _unwrapped(List<Widget> layers) => [for (final layer in layers) (layer as KeyedSubtree).child];
