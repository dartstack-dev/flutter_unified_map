import 'dart:async';

import 'package:flutter/painting.dart' show Color, EdgeInsets, Size;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AndroidView;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map_android/src/messages.g.dart';
import 'package:flutter_unified_map_android/flutter_unified_map_android.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

class FakeHostApi extends UnifiedMapsHostApi {
  final List<(String, List<Object?>)> calls = [];
  PCamera camera = PCamera(center: PLatLng(latitude: 1, longitude: 2), zoom: 3, bearing: 4, tilt: 5);

  /// Called before a marker or icon call is recorded, so a test can hold it back.
  Future<void> Function(String method, int viewId)? delay;
  bool failNextUpdateMarkers = false;
  bool failNextRegisterIcons = false;

  List<Object?> argsOf(String method) => calls.singleWhere((c) => c.$1 == method).$2;
  List<String> get methods => [for (final c in calls) c.$1];

  @override
  Future<void> dispose(int viewId) async => calls.add(('dispose', [viewId]));

  @override
  Future<void> updateOptions(int viewId, PMapOptions options) async => calls.add(('updateOptions', [viewId, options]));

  @override
  Future<void> registerIcons(int viewId, List<PIcon> icons) async {
    await delay?.call('registerIcons', viewId);
    calls.add(('registerIcons', [viewId, icons]));
    if (failNextRegisterIcons) {
      failNextRegisterIcons = false;
      throw PlatformException(code: 'icons');
    }
  }

  @override
  Future<void> updateMarkers(
    int viewId,
    List<PMarker> added,
    List<PMarker> changed,
    List<String> removedIds,
    PMarkerTransition? transition,
  ) async {
    await delay?.call('updateMarkers', viewId);
    calls.add(('updateMarkers', [viewId, added, changed, removedIds, transition]));
    if (failNextUpdateMarkers) {
      failNextUpdateMarkers = false;
      throw PlatformException(code: 'boom');
    }
  }

  @override
  Future<void> updatePolylines(
    int viewId,
    List<PPolyline> added,
    List<PPolyline> changed,
    List<String> removedIds,
  ) async => calls.add(('updatePolylines', [viewId, added, changed, removedIds]));

  @override
  Future<void> updatePolygons(
    int viewId,
    List<PPolygon> added,
    List<PPolygon> changed,
    List<String> removedIds,
  ) async => calls.add(('updatePolygons', [viewId, added, changed, removedIds]));

  @override
  Future<void> updateCircles(int viewId, List<PCircle> added, List<PCircle> changed, List<String> removedIds) async =>
      calls.add(('updateCircles', [viewId, added, changed, removedIds]));

  @override
  Future<void> updateTileLayers(
    int viewId,
    List<PTileLayer> added,
    List<PTileLayer> changed,
    List<String> removedIds,
  ) async => calls.add(('updateTileLayers', [viewId, added, changed, removedIds]));

  @override
  Future<void> moveCamera(int viewId, PCameraUpdate update, int? animationMillis) async =>
      calls.add(('moveCamera', [viewId, update, animationMillis]));

  @override
  Future<PCamera> getCamera(int viewId) async => camera;

  @override
  Future<PLatLngBounds> getVisibleRegion(int viewId) async =>
      PLatLngBounds(southWest: PLatLng(latitude: -1, longitude: -2), northEast: PLatLng(latitude: 1, longitude: 2));

  @override
  Future<PPoint> toScreen(int viewId, PLatLng position) async => PPoint(x: position.latitude, y: position.longitude);

  @override
  Future<PLatLng> toLatLng(int viewId, PPoint screenPoint) async =>
      PLatLng(latitude: screenPoint.x, longitude: screenPoint.y);

  @override
  Future<Uint8List?> takeSnapshot(int viewId) async => Uint8List.fromList([1, 2, 3]);
}

PlatformIcon icon(String key) => PlatformIcon(
  key: key,
  bytes: Uint8List.fromList([137, 80, 78, 71]),
  logicalSize: const Size(24, 32),
  pixelRatio: 2,
);

PlatformMarker marker(String id, String iconKey) =>
    PlatformMarker(id: id, position: const LatLng(48.8, 2.3), icon: icon(iconKey), anchor: const Offset(0.5, 1));

List<String> addedIds(List<Object?> updateMarkersArgs) => [
  for (final m in updateMarkersArgs[1]! as List<PMarker>) m.id,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHostApi host;
  late UnifiedMapsAndroid platform;

  setUp(() {
    host = FakeHostApi();
    platform = UnifiedMapsAndroid(hostApi: host);
  });

  group('options', () {
    test('converts colors, insets, style and interaction', () async {
      await platform.updateOptions(
        7,
        const PlatformMapOptions(
          initialCamera: PlatformCamera(center: LatLng(48.8566, 2.3522), zoom: 6, bearing: 90, tilt: 30),
          minZoom: 2,
          maxZoom: 18,
          style: PlatformMapStyle.hybrid,
          backgroundColor: Color(0x80112233),
          interaction: PlatformInteraction.none,
          padding: EdgeInsets.fromLTRB(1, 2, 3, 4),
          showsUserLocation: true,
          showsCompass: true,
          showsTraffic: true,
        ),
      );
      final options = host.argsOf('updateOptions')[1]! as PMapOptions;
      expect(host.argsOf('updateOptions')[0], 7);
      expect(options.initialCamera.center.latitude, 48.8566);
      expect(options.initialCamera.center.longitude, 2.3522);
      expect(options.initialCamera.zoom, 6);
      expect(options.initialCamera.bearing, 90);
      expect(options.initialCamera.tilt, 30);
      expect(options.minZoom, 2);
      expect(options.maxZoom, 18);
      expect(options.style, PMapStyle.hybrid);
      expect(options.backgroundColorArgb, 0x80112233);
      expect(options.interaction.flags, 0);
      expect(options.interaction.tiltEnabled, isFalse);
      expect(options.padding.left, 1);
      expect(options.padding.top, 2);
      expect(options.padding.right, 3);
      expect(options.padding.bottom, 4);
      expect(options.showsUserLocation, isTrue);
      expect(options.showsCompass, isTrue);
      expect(options.showsBuildings, isFalse);
      expect(options.showsTraffic, isTrue);
      expect(options.showsPointsOfInterest, isTrue);
    });

    test('creation params carry the view id and the options through the Pigeon codec', () {
      final view = platform.buildView(
        viewId: 5,
        options: const PlatformMapOptions(
          initialCamera: PlatformCamera(center: LatLng(48.8, 2.3), zoom: 6, bearing: 90, tilt: 30),
          minZoom: 3,
          style: PlatformMapStyle.muted,
          padding: EdgeInsets.only(bottom: 120),
          showsPointsOfInterest: false,
        ),
      ) as AndroidView;
      expect(view.viewType, UnifiedMapsAndroid.viewType);
      final codec = view.creationParamsCodec!;
      final decoded = codec.decodeMessage(codec.encodeMessage(view.creationParams))! as List<Object?>;
      expect(decoded[0], 5);
      final options = decoded[1]! as PMapOptions;
      expect(options.initialCamera.center.latitude, 48.8);
      expect(options.initialCamera.bearing, 90);
      expect(options.minZoom, 3);
      expect(options.style, PMapStyle.muted);
      expect(options.padding.bottom, 120);
      expect(options.showsPointsOfInterest, isFalse);
    });
  });

  group('markers and icons', () {
    test('registers unseen icons before the markers, once per key and view', () async {
      await platform.updateMarkers(
        1,
        MapObjectUpdates(added: [marker('a', 'pin'), marker('b', 'pin'), marker('c', 'star')]),
      );
      expect(host.methods, ['registerIcons', 'updateMarkers']);
      final icons = host.argsOf('registerIcons')[1]! as List<PIcon>;
      expect(icons.map((i) => i.key), ['pin', 'star']);
      expect(icons.first.logicalSize.width, 24);
      expect(icons.first.logicalSize.height, 32);
      expect(icons.first.pixelRatio, 2);
      expect(icons.first.pngBytes, [137, 80, 78, 71]);
      final added = host.argsOf('updateMarkers')[1]! as List<PMarker>;
      expect(added.map((m) => m.iconKey), ['pin', 'pin', 'star']);
      expect(added.first.anchor.x, 0.5);
      expect(added.first.anchor.y, 1);

      host.calls.clear();
      await platform.updateMarkers(1, MapObjectUpdates(changed: [marker('a', 'pin')], removedIds: const ['b']));
      expect(host.methods, ['updateMarkers']);
      expect(host.argsOf('updateMarkers')[3], ['b']);

      host.calls.clear();
      await platform.updateMarkers(1, MapObjectUpdates(changed: [marker('a', 'flag')]));
      expect(host.methods, ['registerIcons', 'updateMarkers']);
      expect((host.argsOf('registerIcons')[1]! as List<PIcon>).single.key, 'flag');
    });

    test('icon keys are tracked per view and forgotten on dispose', () async {
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      host.calls.clear();
      await platform.updateMarkers(2, MapObjectUpdates(added: [marker('a', 'pin')]));
      expect(host.methods, ['registerIcons', 'updateMarkers']);

      await platform.dispose(1);
      platform.buildView(
        viewId: 1,
        options: const PlatformMapOptions(initialCamera: PlatformCamera(center: LatLng(0, 0), zoom: 1)),
      );
      host.calls.clear();
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      expect(host.methods, ['registerIcons', 'updateMarkers']);
    });

    test('marker updates for a disposed view are ignored', () async {
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      await platform.dispose(1);
      host.calls.clear();
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('b', 'star')]));
      await platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['a']));
      expect(host.calls, isEmpty);
    });

    test('icons whose registration failed are sent again with the next update that uses them', () async {
      host.failNextRegisterIcons = true;
      final failed = platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin'), marker('b', 'star')]));
      final next = platform.updateMarkers(1, MapObjectUpdates(added: [marker('c', 'pin')]));
      await expectLater(failed, throwsA(isA<PlatformException>()));
      await next;
      expect(host.methods, ['registerIcons', 'registerIcons', 'updateMarkers']);
      expect((host.calls[1].$2[1]! as List<PIcon>).map((i) => i.key), ['pin']);
      expect(addedIds(host.calls.last.$2), ['c']);
    });

    test('icons are sent again after a failed updateMarkers', () async {
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      host.failNextUpdateMarkers = true;
      await expectLater(
        platform.updateMarkers(1, MapObjectUpdates(added: [marker('b', 'pin')])),
        throwsA(isA<PlatformException>()),
      );
      host.calls.clear();
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('b', 'pin')]));
      expect(host.methods, ['registerIcons', 'updateMarkers']);
      expect((host.argsOf('registerIcons')[1]! as List<PIcon>).single.key, 'pin');
    });

    test('an icon no marker references any more is sent again when it comes back', () async {
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin'), marker('b', 'pin')]));
      await platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['a']));
      host.calls.clear();
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('c', 'pin')]));
      expect(host.methods, ['updateMarkers']);

      await platform.updateMarkers(1, MapObjectUpdates(changed: [marker('b', 'star'), marker('c', 'star')]));
      host.calls.clear();
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('d', 'pin')]));
      expect(host.methods, ['registerIcons', 'updateMarkers']);
      expect((host.argsOf('registerIcons')[1]! as List<PIcon>).single.key, 'pin');

      await platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['b', 'c', 'd']));
      host.calls.clear();
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('b', 'star')]));
      expect((host.argsOf('registerIcons')[1]! as List<PIcon>).single.key, 'star');
    });

    test('skips registerIcons when nothing is new', () async {
      await platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['x']));
      expect(host.methods, ['updateMarkers']);
      expect(host.argsOf('updateMarkers')[4], isNull);
    });
  });

  group('marker update order', () {
    test('a later update never overtakes an earlier one that waits for its icons', () async {
      final iconsSent = Completer<void>();
      host.delay = (method, _) => method == 'registerIcons' ? iconsSent.future : Future.value();

      final first = platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      final second = platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['a']));
      final third = platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      await pumpEventQueue();
      expect(host.calls, isEmpty);

      iconsSent.complete();
      await Future.wait([first, second, third]);
      expect(host.methods, ['registerIcons', 'updateMarkers', 'updateMarkers', 'registerIcons', 'updateMarkers']);
      expect(addedIds(host.calls[1].$2), ['a']);
      expect(host.calls[2].$2[3], ['a']);
      expect(addedIds(host.calls[4].$2), ['a']);
    });

    test('each update completes only when the native side applied it', () async {
      final gates = <Completer<void>>[];
      host.delay = (method, _) {
        if (method != 'updateMarkers') return Future.value();
        final gate = Completer<void>();
        gates.add(gate);
        return gate.future;
      };
      var firstDone = false;
      var secondDone = false;
      unawaited(platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')])).then((_) => firstDone = true));
      unawaited(
        platform.updateMarkers(1, MapObjectUpdates(added: [marker('b', 'pin')])).then((_) => secondDone = true),
      );
      await pumpEventQueue();
      expect(gates, hasLength(1));

      gates.single.complete();
      await pumpEventQueue();
      expect(firstDone, isTrue);
      expect(secondDone, isFalse);
      expect(gates, hasLength(2));

      gates.last.complete();
      await pumpEventQueue();
      expect(secondDone, isTrue);
      expect(
        [for (final c in host.calls.where((c) => c.$1 == 'updateMarkers')) addedIds(c.$2)],
        [
          ['a'],
          ['b'],
        ],
      );
    });

    test('views are queued independently', () async {
      final view1Icons = Completer<void>();
      host.delay = (method, viewId) => viewId == 1 && method == 'registerIcons' ? view1Icons.future : Future.value();

      final slow = platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      await platform.updateMarkers(2, MapObjectUpdates(added: [marker('b', 'pin')]));
      expect([for (final c in host.calls) (c.$1, c.$2[0])], [('registerIcons', 2), ('updateMarkers', 2)]);

      view1Icons.complete();
      await slow;
      expect(host.calls.where((c) => c.$2[0] == 1).map((c) => c.$1), ['registerIcons', 'updateMarkers']);
    });

    test('a failed update reports its error and the next one still runs', () async {
      host.failNextUpdateMarkers = true;
      final failed = platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      final next = platform.updateMarkers(1, MapObjectUpdates(added: [marker('b', 'pin')]));
      await expectLater(failed, throwsA(isA<PlatformException>()));
      await next;
      expect(host.methods, ['registerIcons', 'updateMarkers', 'registerIcons', 'updateMarkers']);
      expect(addedIds(host.calls.last.$2), ['b']);
    });

    test('updates still queued when the view is disposed are dropped', () async {
      final iconsSent = Completer<void>();
      host.delay = (method, _) => method == 'registerIcons' ? iconsSent.future : Future.value();

      final inFlight = platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      final queued = platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['a']));
      await pumpEventQueue();
      await platform.dispose(1);
      iconsSent.complete();
      await Future.wait([inFlight, queued]);
      expect(host.methods, ['dispose', 'registerIcons', 'updateMarkers']);
    });
  });

  group('marker transitions', () {
    test('converts duration, appearFrom and disappearTo', () async {
      await platform.updateMarkers(
        1,
        MapObjectUpdates(added: [marker('a', 'pin'), marker('b', 'pin')], removedIds: const ['c', 'd']),
        transition: const PlatformMarkerTransition(
          duration: Duration(milliseconds: 500),
          appearFrom: {'a': LatLng(48.1, 11.5)},
          disappearTo: {'c': LatLng(-33.9, 151.2), 'd': LatLng(0.5, -179.9)},
        ),
      );
      final transition = host.argsOf('updateMarkers')[4]! as PMarkerTransition;
      expect(transition.durationMillis, 500);
      expect(transition.appearFrom.keys, ['a']);
      expect(transition.appearFrom['a']!.latitude, 48.1);
      expect(transition.appearFrom['a']!.longitude, 11.5);
      expect(transition.disappearTo.keys, ['c', 'd']);
      expect(transition.disappearTo['c']!.latitude, -33.9);
      expect(transition.disappearTo['c']!.longitude, 151.2);
      expect(transition.disappearTo['d']!.longitude, -179.9);
    });

    test('an empty transition keeps its duration and empty maps', () async {
      await platform.updateMarkers(
        1,
        MapObjectUpdates(changed: [marker('a', 'pin')]),
        transition: const PlatformMarkerTransition(duration: Duration(milliseconds: 250)),
      );
      final transition = host.argsOf('updateMarkers')[4]! as PMarkerTransition;
      expect(transition.durationMillis, 250);
      expect(transition.appearFrom, isEmpty);
      expect(transition.disappearTo, isEmpty);
    });
  });

  group('overlays', () {
    test('polylines carry colors, dash pattern, caps and joins', () async {
      await platform.updatePolylines(
        3,
        MapObjectUpdates(
          added: [
            const PlatformPolyline(
              id: 'l',
              points: [LatLng(0, 0), LatLng(1, 1)],
              color: Color(0xFF0000FF),
              width: 5,
              borderColor: Color(0xFFFFFFFF),
              borderWidth: 2,
              dashPattern: [8, 4],
              cap: PlatformStrokeCap.square,
              join: PlatformStrokeJoin.bevel,
              zIndex: 2,
              geodesic: true,
            ),
          ],
        ),
      );
      final line = (host.argsOf('updatePolylines')[1]! as List<PPolyline>).single;
      expect(line.points.length, 2);
      expect(line.points[1].latitude, 1);
      expect(line.colorArgb, 0xFF0000FF);
      expect(line.width, 5);
      expect(line.borderColorArgb, 0xFFFFFFFF);
      expect(line.borderWidth, 2);
      expect(line.dashPattern, [8, 4]);
      expect(line.cap, PStrokeCap.square);
      expect(line.join, PStrokeJoin.bevel);
      expect(line.zIndex, 2);
      expect(line.geodesic, isTrue);
    });

    test('polygons keep holes, circles keep radius, tile layers keep headers', () async {
      await platform.updatePolygons(
        3,
        MapObjectUpdates(
          added: [
            const PlatformPolygon(
              id: 'p',
              points: [LatLng(0, 0), LatLng(0, 1), LatLng(1, 1)],
              holes: [
                [LatLng(0.1, 0.1), LatLng(0.1, 0.2), LatLng(0.2, 0.2)],
              ],
              fillColor: Color(0x40FF0000),
              strokeWidth: 3,
            ),
          ],
        ),
      );
      final polygon = (host.argsOf('updatePolygons')[1]! as List<PPolygon>).single;
      expect(polygon.points.length, 3);
      expect(polygon.holes.single.length, 3);
      expect(polygon.fillColorArgb, 0x40FF0000);
      expect(polygon.strokeColorArgb, 0xFF000000);
      expect(polygon.strokeWidth, 3);

      await platform.updateCircles(
        3,
        MapObjectUpdates(
          added: [const PlatformCircle(id: 'c', center: LatLng(2, 3), radiusMeters: 500)],
        ),
      );
      final circle = (host.argsOf('updateCircles')[1]! as List<PCircle>).single;
      expect(circle.center.latitude, 2);
      expect(circle.radiusMeters, 500);

      await platform.updateTileLayers(
        3,
        MapObjectUpdates(
          added: [
            const PlatformTileLayer(
              id: 't',
              urlTemplate: 'https://{s}.tile.example/{z}/{x}/{y}{r}.png',
              subdomains: ['a', 'b'],
              headers: {'User-Agent': 'flutter_unified_map'},
              replacesBaseMap: true,
              opacity: 0.5,
            ),
          ],
          removedIds: const ['old'],
        ),
      );
      final tile = (host.argsOf('updateTileLayers')[1]! as List<PTileLayer>).single;
      expect(tile.subdomains, ['a', 'b']);
      expect(tile.headers, {'User-Agent': 'flutter_unified_map'});
      expect(tile.replacesBaseMap, isTrue);
      expect(tile.opacity, 0.5);
      expect(tile.tileSize, 256);
      expect(host.argsOf('updateTileLayers')[3], ['old']);
    });
  });

  group('camera', () {
    test('newCamera sets exactly the newCamera field and keeps nulls', () async {
      await platform.moveCamera(1, const PlatformCameraUpdate.newCamera(zoom: 12));
      final update = host.argsOf('moveCamera')[1]! as PCameraUpdate;
      expect(update.newCamera, isNotNull);
      expect(update.fitBounds, isNull);
      expect(update.scrollBy, isNull);
      expect(update.zoomBy, isNull);
      expect(update.newCamera!.center, isNull);
      expect(update.newCamera!.zoom, 12);
      expect(update.newCamera!.bearing, isNull);
      expect(host.argsOf('moveCamera')[2], isNull);
    });

    test('fitBounds carries bounds, asymmetric padding, maxZoom and bearing, animated in millis', () async {
      await platform.moveCamera(
        1,
        const PlatformCameraUpdate.fitBounds(
          PlatformLatLngBounds(southWest: LatLng(1, 2), northEast: LatLng(3, 4)),
          padding: EdgeInsets.only(left: 10, bottom: 40),
          maxZoom: 15,
          bearing: 45,
        ),
        animation: const Duration(milliseconds: 350),
      );
      final update = host.argsOf('moveCamera')[1]! as PCameraUpdate;
      expect(update.newCamera, isNull);
      final fit = update.fitBounds!;
      expect(fit.bounds.southWest.latitude, 1);
      expect(fit.bounds.northEast.longitude, 4);
      expect(fit.padding.left, 10);
      expect(fit.padding.top, 0);
      expect(fit.padding.right, 0);
      expect(fit.padding.bottom, 40);
      expect(fit.maxZoom, 15);
      expect(fit.bearing, 45);
      expect(host.argsOf('moveCamera')[2], 350);
    });

    test('scrollBy and zoomBy', () async {
      await platform.moveCamera(1, const PlatformCameraUpdate.scrollBy(10, -20));
      await platform.moveCamera(1, const PlatformCameraUpdate.zoomBy(1.5, focus: Offset(100, 200)));
      final scroll = (host.calls[0].$2[1]! as PCameraUpdate).scrollBy!;
      expect(scroll.dx, 10);
      expect(scroll.dy, -20);
      final zoom = (host.calls[1].$2[1]! as PCameraUpdate).zoomBy!;
      expect(zoom.amount, 1.5);
      expect(zoom.focus!.x, 100);
      expect(zoom.focus!.y, 200);
    });

    test('reads camera, region, projections and snapshot back', () async {
      expect(await platform.getCamera(1), const PlatformCamera(center: LatLng(1, 2), zoom: 3, bearing: 4, tilt: 5));
      expect(
        await platform.getVisibleRegion(1),
        const PlatformLatLngBounds(southWest: LatLng(-1, -2), northEast: LatLng(1, 2)),
      );
      expect(await platform.toScreen(1, const LatLng(5, 6)), const Offset(5, 6));
      expect(await platform.toLatLng(1, const Offset(7, 8)), const LatLng(7, 8));
      expect(await platform.takeSnapshot(1), [1, 2, 3]);
    });
  });

  group('events', () {
    test('onMapReady emits ready then size, routed by view id', () async {
      final view1 = <PlatformMapEvent>[];
      final view2 = <PlatformMapEvent>[];
      platform.events(1).listen(view1.add);
      platform.events(2).listen(view2.add);

      platform.flutterApi.onMapReady(
        1,
        PCamera(center: PLatLng(latitude: 48.8, longitude: 2.3), zoom: 6, bearing: 0, tilt: 0),
        PSize(width: 400, height: 800),
      );
      platform.flutterApi.onCameraMoveStarted(2, true);
      platform.flutterApi.onCameraMove(
        2,
        PCamera(center: PLatLng(latitude: 1, longitude: 1), zoom: 7, bearing: 0, tilt: 0),
      );
      platform.flutterApi.onCameraIdle(
        2,
        PCamera(center: PLatLng(latitude: 1, longitude: 1), zoom: 7, bearing: 0, tilt: 0),
      );
      platform.flutterApi.onTap(1, PLatLng(latitude: 1, longitude: 2), PPoint(x: 3, y: 4));
      platform.flutterApi.onLongPress(1, PLatLng(latitude: 5, longitude: 6), PPoint(x: 7, y: 8));
      platform.flutterApi.onMarkerTap(1, 'm1');
      platform.flutterApi.onViewSize(1, PSize(width: 300, height: 600));
      await Future<void>.delayed(Duration.zero);

      expect(view1.map((e) => e.runtimeType), [
        PlatformMapReadyEvent,
        PlatformViewSizeEvent,
        PlatformMapTapEvent,
        PlatformMapLongPressEvent,
        PlatformMarkerTapEvent,
        PlatformViewSizeEvent,
      ]);
      final ready = view1[0] as PlatformMapReadyEvent;
      expect(ready.camera, const PlatformCamera(center: LatLng(48.8, 2.3), zoom: 6));
      final size = view1[1] as PlatformViewSizeEvent;
      expect((size.width, size.height), (400.0, 800.0));
      final tap = view1[2] as PlatformMapTapEvent;
      expect(tap.position, const LatLng(1, 2));
      expect(tap.screenPoint, const Offset(3, 4));
      expect((view1[4] as PlatformMarkerTapEvent).markerId, 'm1');

      expect(view2.map((e) => e.runtimeType), [
        PlatformCameraMoveStartedEvent,
        PlatformCameraMoveEvent,
        PlatformCameraIdleEvent,
      ]);
      expect((view2[0] as PlatformCameraMoveStartedEvent).byGesture, isTrue);
      expect((view2[2] as PlatformCameraIdleEvent).camera.zoom, 7);
    });

    test('events arriving through the Pigeon channel reach the stream', () async {
      final received = <PlatformMapEvent>[];
      platform.events(9).listen(received.add);
      const channel = 'dev.flutter.pigeon.flutter_unified_map_android.UnifiedMapsFlutterApi.onMarkerTap';
      final message = UnifiedMapsFlutterApi.pigeonChannelCodec.encodeMessage(<Object?>[9, 'pin-9']);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel,
        message,
        (_) {},
      );
      expect(received.single, isA<PlatformMarkerTapEvent>().having((e) => e.markerId, 'markerId', 'pin-9'));
    });

    test('onMapLoaded and onMapError are routed by view id with every error code', () async {
      final view1 = <PlatformMapEvent>[];
      final view2 = <PlatformMapEvent>[];
      platform.events(1).listen(view1.add);
      platform.events(2).listen(view2.add);

      for (final code in PMapErrorCode.values) {
        platform.flutterApi.onMapError(1, code, 'message ${code.name}');
      }
      platform.flutterApi.onMapLoaded(1);
      platform.flutterApi.onMapLoaded(2);
      await Future<void>.delayed(Duration.zero);

      expect(view1.whereType<PlatformMapErrorEvent>().map((e) => (e.viewId, e.code, e.message)), [
        (1, PlatformMapErrorCode.apiKeyMissing, 'message apiKeyMissing'),
        (1, PlatformMapErrorCode.servicesUnavailable, 'message servicesUnavailable'),
        (1, PlatformMapErrorCode.loadTimeout, 'message loadTimeout'),
        (1, PlatformMapErrorCode.loadFailed, 'message loadFailed'),
        (1, PlatformMapErrorCode.unknown, 'message unknown'),
      ]);
      expect(view1.last, isA<PlatformMapLoadedEvent>().having((e) => e.viewId, 'viewId', 1));
      expect(view2.single, isA<PlatformMapLoadedEvent>().having((e) => e.viewId, 'viewId', 2));
    });

    test('onMapError and onMapLoaded arriving through the Pigeon channel reach the stream', () async {
      final received = <PlatformMapEvent>[];
      platform.events(7).listen(received.add);
      const prefix = 'dev.flutter.pigeon.flutter_unified_map_android.UnifiedMapsFlutterApi';
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = UnifiedMapsFlutterApi.pigeonChannelCodec;
      await messenger.handlePlatformMessage(
        '$prefix.onMapError',
        codec.encodeMessage(<Object?>[7, PMapErrorCode.apiKeyMissing, 'no key']),
        (_) {},
      );
      await messenger.handlePlatformMessage('$prefix.onMapLoaded', codec.encodeMessage(<Object?>[7]), (_) {});

      expect(received, [
        isA<PlatformMapErrorEvent>()
            .having((e) => e.code, 'code', PlatformMapErrorCode.apiKeyMissing)
            .having((e) => e.message, 'message', 'no key'),
        isA<PlatformMapLoadedEvent>(),
      ]);
    });

    test('dispose closes the stream and nothing is emitted afterwards', () async {
      final received = <PlatformMapEvent>[];
      var done = false;
      platform.events(4).listen(received.add, onDone: () => done = true);
      await platform.dispose(4);
      platform.flutterApi.onMarkerTap(4, 'late');
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
      expect(received, isEmpty);
      expect(host.methods, ['dispose']);
    });

    test('events of a disposed view is an empty stream until the view is built again', () async {
      await platform.dispose(4);
      expect(await platform.events(4).isEmpty, isTrue);

      platform.buildView(
        viewId: 4,
        options: const PlatformMapOptions(initialCamera: PlatformCamera(center: LatLng(0, 0), zoom: 1)),
      );
      final received = <PlatformMapEvent>[];
      platform.events(4).listen(received.add);
      platform.flutterApi.onMarkerTap(4, 'again');
      await Future<void>.delayed(Duration.zero);
      expect(received.single, isA<PlatformMarkerTapEvent>());
    });
  });
}
