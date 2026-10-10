import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/painting.dart' show Color, EdgeInsets, Size;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppKitView, UiKitView;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map_apple/src/conversions.dart';
import 'package:flutter_unified_map_apple/src/flutter_api_handler.dart';
import 'package:flutter_unified_map_apple/src/messages.g.dart';
import 'package:flutter_unified_map_apple/flutter_unified_map_apple.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

class FakeHostApi extends UnifiedMapsHostApi {
  final List<(String, List<Object?>)> calls = [];
  PCamera camera = PCamera(center: PLatLng(latitude: 1, longitude: 2), zoom: 3, bearing: 4, tilt: 5);

  List<Object?> argsOf(String method) => calls.singleWhere((c) => c.$1 == method).$2;
  List<String> get methods => [for (final c in calls) c.$1];

  Object? disposeError;

  @override
  Future<void> dispose(int viewId) async {
    calls.add(('dispose', [viewId]));
    if (disposeError case final error?) throw error;
  }

  @override
  Future<void> updateOptions(int viewId, PMapOptions options) async => calls.add(('updateOptions', [viewId, options]));

  Completer<void>? registerGate;
  Object? registerError;

  @override
  Future<void> registerIcons(int viewId, List<PIcon> icons) async {
    calls.add(('registerIcons', [viewId, icons]));
    await registerGate?.future;
    if (registerError case final error?) throw error;
  }

  @override
  Future<void> updateMarkers(
    int viewId,
    List<PMarker> added,
    List<PMarker> changed,
    List<String> removedIds,
    PMarkerTransition? transition,
  ) async {
    calls.add(('updateMarkers', [viewId, added, changed, removedIds, transition]));
    await updateGate?.future;
    if (updateError case final error?) throw error;
  }

  Object? updateError;

  Completer<void>? updateGate;

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
  pixelRatio: 3,
);

PlatformMarker marker(String id, String iconKey) =>
    PlatformMarker(id: id, position: const LatLng(48.8, 2.3), icon: icon(iconKey), anchor: const Offset(0.5, 1));

const options = PlatformMapOptions(
  initialCamera: PlatformCamera(center: LatLng(48.8566, 2.3522), zoom: 6, bearing: 90, tilt: 30),
  minZoom: 2,
  maxZoom: 18,
  style: PlatformMapStyle.muted,
  backgroundColor: Color(0x80112233),
  interaction: PlatformInteraction(
    flags: PlatformInteraction.all & ~PlatformInteraction.rotate & ~PlatformInteraction.doubleTapZoom,
    tiltEnabled: true,
  ),
  padding: EdgeInsets.fromLTRB(1, 2, 3, 4),
  showsUserLocation: true,
  showsCompass: true,
  showsTraffic: true,
  showsPointsOfInterest: false,
);

PCamera pCamera(double zoom) =>
    PCamera(center: PLatLng(latitude: 48.8, longitude: 2.3), zoom: zoom, bearing: 0, tilt: 0);

Future<void> sendEvent(String method, List<Object?> args) async {
  final message = UnifiedMapsFlutterApi.pigeonChannelCodec.encodeMessage(args);
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    'dev.flutter.pigeon.flutter_unified_map_apple.UnifiedMapsFlutterApi.$method',
    message,
    (_) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHostApi host;
  late UnifiedMapsApple platform;

  setUp(() {
    host = FakeHostApi();
    platform = UnifiedMapsApple(hostApi: host);
  });

  group('conversions', () {
    test('options keep every field, colors as unsigned ARGB', () async {
      await platform.updateOptions(7, options);
      expect(host.argsOf('updateOptions')[0], 7);
      final p = host.argsOf('updateOptions')[1]! as PMapOptions;
      expect(p.initialCamera.center.latitude, 48.8566);
      expect(p.initialCamera.center.longitude, 2.3522);
      expect(p.initialCamera.zoom, 6);
      expect(p.initialCamera.bearing, 90);
      expect(p.initialCamera.tilt, 30);
      expect((p.minZoom, p.maxZoom), (2.0, 18.0));
      expect(p.style, PMapStyle.muted);
      expect(p.backgroundColorArgb, 0x80112233);
      expect(
        p.interaction.flags,
        PlatformInteraction.all & ~PlatformInteraction.rotate & ~PlatformInteraction.doubleTapZoom,
      );
      expect(p.interaction.tiltEnabled, isTrue);
      expect((p.padding.left, p.padding.top, p.padding.right, p.padding.bottom), (1.0, 2.0, 3.0, 4.0));
      expect(p.showsUserLocation, isTrue);
      expect(p.showsCompass, isTrue);
      expect(p.showsBuildings, isFalse);
      expect(p.showsTraffic, isTrue);
      expect(p.showsPointsOfInterest, isFalse);

      await platform.updateOptions(
        1,
        const PlatformMapOptions(initialCamera: PlatformCamera(center: LatLng(0, 0), zoom: 1)),
      );
      expect((host.calls.last.$2[1]! as PMapOptions).backgroundColorArgb, 0xFFE5E3DF);
    });

    test('every map style maps to the Pigeon enum of the same name', () {
      for (final style in PlatformMapStyle.values) {
        expect(toPMapStyle(style).name, style.name);
      }
    });

    test('creation params are the view id and the Pigeon options, through the Pigeon codec', () {
      const codec = UnifiedMapsHostApi.pigeonChannelCodec;
      final decoded = codec.decodeMessage(codec.encodeMessage(<Object?>[42, toPMapOptions(options)]))! as List<Object?>;
      expect(decoded[0], 42);
      expect(decoded[1], toPMapOptions(options));
      expect((decoded[1]! as PMapOptions).interaction.flags & PlatformInteraction.doubleTapZoom, 0);
    });

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
          removedIds: const ['gone'],
        ),
      );
      final line = (host.argsOf('updatePolylines')[1]! as List<PPolyline>).single;
      expect(line.points.map((p) => (p.latitude, p.longitude)), [(0.0, 0.0), (1.0, 1.0)]);
      expect(line.colorArgb, 0xFF0000FF);
      expect(line.width, 5);
      expect(line.borderColorArgb, 0xFFFFFFFF);
      expect(line.borderWidth, 2);
      expect(line.dashPattern, [8, 4]);
      expect(line.cap, PStrokeCap.square);
      expect(line.join, PStrokeJoin.bevel);
      expect(line.zIndex, 2);
      expect(line.geodesic, isTrue);
      expect(host.argsOf('updatePolylines')[3], ['gone']);
    });

    test('polygons keep holes, circles keep radius, tile layers keep template and headers', () async {
      await platform.updatePolygons(
        3,
        MapObjectUpdates(
          changed: [
            const PlatformPolygon(
              id: 'p',
              points: [LatLng(0, 0), LatLng(0, 1), LatLng(1, 1)],
              holes: [
                [LatLng(0.1, 0.1), LatLng(0.1, 0.2), LatLng(0.2, 0.2)],
              ],
              fillColor: Color(0x40FF0000),
              strokeWidth: 3,
              zIndex: 1,
            ),
          ],
        ),
      );
      final polygon = (host.argsOf('updatePolygons')[2]! as List<PPolygon>).single;
      expect(polygon.points.length, 3);
      expect(polygon.holes.single.length, 3);
      expect(polygon.fillColorArgb, 0x40FF0000);
      expect(polygon.strokeColorArgb, 0xFF000000);
      expect(polygon.strokeWidth, 3);
      expect(polygon.zIndex, 1);

      await platform.updateCircles(
        3,
        MapObjectUpdates(
          added: [const PlatformCircle(id: 'c', center: LatLng(2, 3), radiusMeters: 500)],
        ),
      );
      final circle = (host.argsOf('updateCircles')[1]! as List<PCircle>).single;
      expect((circle.center.latitude, circle.center.longitude), (2.0, 3.0));
      expect(circle.radiusMeters, 500);
      expect(circle.fillColorArgb, 0);

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
              maxZoom: 17,
            ),
          ],
        ),
      );
      final tile = (host.argsOf('updateTileLayers')[1]! as List<PTileLayer>).single;
      expect(tile.urlTemplate, 'https://{s}.tile.example/{z}/{x}/{y}{r}.png');
      expect(tile.subdomains, ['a', 'b']);
      expect(tile.headers, {'User-Agent': 'flutter_unified_map'});
      expect(tile.replacesBaseMap, isTrue);
      expect(tile.opacity, 0.5);
      expect(tile.tileSize, 256);
      expect((tile.minZoom, tile.maxZoom), (0.0, 17.0));
    });

    test('camera updates set exactly one variant; animation travels in milliseconds', () async {
      await platform.moveCamera(1, const PlatformCameraUpdate.newCamera(zoom: 12));
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
      await platform.moveCamera(1, const PlatformCameraUpdate.scrollBy(10, -20));
      await platform.moveCamera(1, const PlatformCameraUpdate.zoomBy(1.5, focus: Offset(100, 200)));
      await platform.moveCamera(1, const PlatformCameraUpdate.zoomBy(-1));

      final updates = [for (final call in host.calls) call.$2[1]! as PCameraUpdate];
      final newCamera = updates[0].newCamera!;
      expect((updates[0].fitBounds, updates[0].scrollBy, updates[0].zoomBy), (null, null, null));
      expect((newCamera.center, newCamera.zoom, newCamera.bearing, newCamera.tilt), (null, 12.0, null, null));
      expect(host.calls[0].$2[2], isNull);

      final fit = updates[1].fitBounds!;
      expect(updates[1].newCamera, isNull);
      expect((fit.bounds.southWest.latitude, fit.bounds.northEast.longitude), (1.0, 4.0));
      expect((fit.padding.left, fit.padding.top, fit.padding.right, fit.padding.bottom), (10.0, 0.0, 0.0, 40.0));
      expect((fit.maxZoom, fit.bearing), (15.0, 45.0));
      expect(host.calls[1].$2[2], 350);

      expect((updates[2].scrollBy!.dx, updates[2].scrollBy!.dy), (10.0, -20.0));
      expect(updates[3].zoomBy!.amount, 1.5);
      expect((updates[3].zoomBy!.focus!.x, updates[3].zoomBy!.focus!.y), (100.0, 200.0));
      expect(updates[4].zoomBy!.focus, isNull);
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

  group('icons', () {
    test('registers unseen icons before the markers, once per key', () async {
      await platform.updateMarkers(
        1,
        MapObjectUpdates(added: [marker('a', 'pin'), marker('b', 'pin'), marker('c', 'star')]),
      );
      expect(host.methods, ['registerIcons', 'updateMarkers']);
      final icons = host.argsOf('registerIcons')[1]! as List<PIcon>;
      expect(icons.map((i) => i.key), ['pin', 'star']);
      expect((icons.first.logicalSize.width, icons.first.logicalSize.height), (24.0, 32.0));
      expect(icons.first.pixelRatio, 3);
      expect(icons.first.pngBytes, [137, 80, 78, 71]);
      final added = host.argsOf('updateMarkers')[1]! as List<PMarker>;
      expect(added.map((m) => m.iconKey), ['pin', 'pin', 'star']);
      expect((added.first.anchor.x, added.first.anchor.y), (0.5, 1.0));
      expect(added.first.tappable, isTrue);
      expect(added.first.flat, isFalse);

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
      host.calls.clear();
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      expect(host.methods, isEmpty);
      await platform.updateMarkers(2, MapObjectUpdates(added: [marker('b', 'pin')]));
      expect(host.methods, ['updateMarkers']);
    });

    test('an icon no marker references any more is sent again when it comes back', () async {
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin'), marker('b', 'star')]));
      await platform.updateMarkers(1, MapObjectUpdates(changed: [marker('a', 'star')], removedIds: const ['b']));
      host.calls.clear();
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('c', 'pin')]));
      expect(host.methods, ['registerIcons', 'updateMarkers']);
      expect((host.argsOf('registerIcons')[1]! as List<PIcon>).single.key, 'pin');

      host.calls.clear();
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('d', 'star')]));
      expect(host.methods, ['updateMarkers']);
    });

    test('after a failed marker update the next one sends its icons again', () async {
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      host.updateError = PlatformException(code: 'boom');
      await expectLater(platform.updateMarkers(1, MapObjectUpdates(added: [marker('b', 'pin')])), throwsA(anything));
      host
        ..updateError = null
        ..calls.clear();
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('b', 'pin')]));
      expect(host.methods, ['registerIcons', 'updateMarkers']);
    });

    test('overlapping updates register a new icon once', () async {
      host.registerGate = Completer<void>();
      final first = platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      final second = platform.updateMarkers(1, MapObjectUpdates(added: [marker('b', 'pin')]));
      host.registerGate!.complete();
      await Future.wait([first, second]);
      expect(host.methods.where((m) => m == 'registerIcons'), hasLength(1));
      expect(host.methods.where((m) => m == 'updateMarkers'), hasLength(2));
    });

    test('a failed registration is retried by the next update', () async {
      host.registerError = PlatformException(code: 'boom');
      await expectLater(platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')])), throwsA(anything));
      expect(host.methods, ['registerIcons']);

      host
        ..registerError = null
        ..calls.clear();
      await platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      expect(host.methods, ['registerIcons', 'updateMarkers']);
    });

    test('skips registerIcons when nothing is new', () async {
      await platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['x']));
      expect(host.methods, ['updateMarkers']);
    });
  });

  group('marker order', () {
    test('an update without new icons waits for an earlier one still registering its icons', () async {
      host.registerGate = Completer<void>();
      final first = platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      final second = platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['a']));
      final third = platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      await pumpEventQueue();
      expect(host.methods, ['registerIcons']);

      host.registerGate!.complete();
      await Future.wait([first, second, third]);
      expect(host.methods, ['registerIcons', 'updateMarkers', 'updateMarkers', 'registerIcons', 'updateMarkers']);
      final sends = host.calls.where((c) => c.$1 == 'updateMarkers').map((c) => c.$2).toList();
      expect((sends[0][1]! as List<PMarker>).single.id, 'a');
      expect(sends[1][3], ['a']);
      expect((sends[2][1]! as List<PMarker>).single.id, 'a');
    });

    test('a slow platform reply holds the next update back', () async {
      host.updateGate = Completer<void>();
      final first = platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['x']));
      final second = platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['y']));
      await pumpEventQueue();
      expect(host.calls.map((c) => c.$2[3]), [
        ['x'],
      ]);
      host.updateGate!.complete();
      await Future.wait([first, second]);
      expect(host.calls.map((c) => c.$2[3]), [
        ['x'],
        ['y'],
      ]);
    });

    test('views do not wait for each other', () async {
      host.registerGate = Completer<void>();
      final blocked = platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      await platform.updateMarkers(2, const MapObjectUpdates(removedIds: ['b']));
      expect(host.calls.map((c) => (c.$1, c.$2[0])), [('registerIcons', 1), ('updateMarkers', 2)]);
      host.registerGate!.complete();
      await blocked;
    });

    test('a failed update does not block the next one', () async {
      host.registerError = PlatformException(code: 'boom');
      final failed = platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      final next = platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['b']));
      await expectLater(failed, throwsA(isA<PlatformException>()));
      await next;
      expect(host.methods, ['registerIcons', 'updateMarkers']);
      expect(host.argsOf('updateMarkers')[3], ['b']);
    });

    test('a view disposed while an update registers its icons gets no more marker updates', () async {
      host.registerGate = Completer<void>();
      final first = platform.updateMarkers(1, MapObjectUpdates(added: [marker('a', 'pin')]));
      final queued = platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['a']));
      await pumpEventQueue();
      await platform.dispose(1);
      host.registerGate!.complete();
      await Future.wait([first, queued]);
      expect(host.methods, ['registerIcons', 'dispose']);
    });
  });

  group('marker transition', () {
    test('is sent as milliseconds with appearFrom and disappearTo positions', () async {
      await platform.updateMarkers(
        1,
        MapObjectUpdates(added: [marker('child', 'pin')], removedIds: const ['old']),
        transition: const PlatformMarkerTransition(
          duration: Duration(milliseconds: 500),
          appearFrom: {'child': LatLng(48.1, 11.5)},
          disappearTo: {'old': LatLng(-33.9, 151.2)},
        ),
      );
      final transition = host.argsOf('updateMarkers')[4]! as PMarkerTransition;
      expect(transition.durationMillis, 500);
      expect(transition.appearFrom.keys, ['child']);
      expect((transition.appearFrom['child']!.latitude, transition.appearFrom['child']!.longitude), (48.1, 11.5));
      expect(transition.disappearTo.keys, ['old']);
      expect((transition.disappearTo['old']!.latitude, transition.disappearTo['old']!.longitude), (-33.9, 151.2));
    });

    test('an empty transition still animates (fades), no transition is instant', () async {
      await platform.updateMarkers(
        1,
        const MapObjectUpdates(removedIds: ['a']),
        transition: const PlatformMarkerTransition(duration: Duration(milliseconds: 250)),
      );
      await platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['b']));
      final sends = host.calls.map((c) => c.$2[4] as PMarkerTransition?).toList();
      expect(sends[0]!.durationMillis, 250);
      expect(sends[0]!.appearFrom, isEmpty);
      expect(sends[0]!.disappearTo, isEmpty);
      expect(sends[1], isNull);
    });
  });

  group('platform view', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('iOS builds a UiKitView with the creation params', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final view = platform.buildView(viewId: 5, options: options);
      expect(view, isA<UiKitView>());
      final uiKit = view as UiKitView;
      expect(uiKit.viewType, 'flutter_unified_map_apple/map');
      expect(uiKit.creationParams, [5, toPMapOptions(options)]);
      expect(uiKit.creationParamsCodec, same(UnifiedMapsHostApi.pigeonChannelCodec));
    });

    test('macOS builds an AppKitView with the creation params', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final view = platform.buildView(viewId: 6, options: options);
      expect(view, isA<AppKitView>());
      final appKit = view as AppKitView;
      expect(appKit.viewType, 'flutter_unified_map_apple/map');
      expect(appKit.creationParams, [6, toPMapOptions(options)]);
      expect(appKit.creationParamsCodec, same(UnifiedMapsHostApi.pigeonChannelCodec));
    });
  });

  group('events', () {
    test('handler turns every Pigeon callback into the matching platform event', () {
      final received = <PlatformMapEvent>[];
      final handler = FlutterApiHandler(received.add, (_) => null);
      handler.onMapReady(1, pCamera(6), PSize(width: 400, height: 800));
      handler.onCameraMoveStarted(1, false);
      handler.onCameraMove(1, pCamera(7));
      handler.onCameraIdle(1, pCamera(8));
      handler.onTap(1, PLatLng(latitude: 1, longitude: 2), PPoint(x: 3, y: 4));
      handler.onLongPress(1, PLatLng(latitude: 5, longitude: 6), PPoint(x: 7, y: 8));
      handler.onMarkerTap(1, 'layer/m1');
      handler.onViewSize(1, PSize(width: 300, height: 600));

      expect(received.map((e) => e.runtimeType), [
        PlatformMapReadyEvent,
        PlatformViewSizeEvent,
        PlatformCameraMoveStartedEvent,
        PlatformCameraMoveEvent,
        PlatformCameraIdleEvent,
        PlatformMapTapEvent,
        PlatformMapLongPressEvent,
        PlatformMarkerTapEvent,
        PlatformViewSizeEvent,
      ]);
      expect(received.every((e) => e.viewId == 1), isTrue);
      expect((received[0] as PlatformMapReadyEvent).camera, const PlatformCamera(center: LatLng(48.8, 2.3), zoom: 6));
      expect(
        ((received[1] as PlatformViewSizeEvent).width, (received[1] as PlatformViewSizeEvent).height),
        (400.0, 800.0),
      );
      expect((received[2] as PlatformCameraMoveStartedEvent).byGesture, isFalse);
      expect((received[3] as PlatformCameraMoveEvent).camera.zoom, 7);
      expect((received[4] as PlatformCameraIdleEvent).camera.zoom, 8);
      final tap = received[5] as PlatformMapTapEvent;
      expect((tap.position, tap.screenPoint), (const LatLng(1, 2), const Offset(3, 4)));
      final longPress = received[6] as PlatformMapLongPressEvent;
      expect((longPress.position, longPress.screenPoint), (const LatLng(5, 6), const Offset(7, 8)));
      expect((received[7] as PlatformMarkerTapEvent).markerId, 'layer/m1');
      expect((received[8] as PlatformViewSizeEvent).width, 300);
    });

    test('native events arriving on the Pigeon channels are routed to their view stream', () async {
      final view1 = <PlatformMapEvent>[];
      final view2 = <PlatformMapEvent>[];
      platform.events(1).listen(view1.add);
      platform.events(2).listen(view2.add);

      await sendEvent('onMapReady', [1, pCamera(6), PSize(width: 400, height: 800)]);
      await sendEvent('onCameraMoveStarted', [2, true]);
      await sendEvent('onCameraMove', [2, pCamera(7)]);
      await sendEvent('onCameraIdle', [2, pCamera(7)]);
      await sendEvent('onTap', [1, PLatLng(latitude: 1, longitude: 2), PPoint(x: 3, y: 4)]);
      await sendEvent('onMarkerTap', [1, 'pin-9']);
      await sendEvent('onMarkerTap', [3, 'nobody-listens']);
      await Future<void>.delayed(Duration.zero);

      expect(view1.map((e) => e.runtimeType), [
        PlatformMapReadyEvent,
        PlatformViewSizeEvent,
        PlatformMapTapEvent,
        PlatformMarkerTapEvent,
      ]);
      expect((view1.last as PlatformMarkerTapEvent).markerId, 'pin-9');
      expect(view2.map((e) => e.runtimeType), [
        PlatformCameraMoveStartedEvent,
        PlatformCameraMoveEvent,
        PlatformCameraIdleEvent,
      ]);
      expect((view2.first as PlatformCameraMoveStartedEvent).byGesture, isTrue);
    });

    test('every Pigeon error code maps to the platform error code of the same name', () {
      for (final code in PMapErrorCode.values) {
        expect(fromPMapErrorCode(code).name, code.name);
      }
      expect(PMapErrorCode.values.length, PlatformMapErrorCode.values.length);
    });

    test('load and error callbacks become loaded and error events', () {
      final received = <PlatformMapEvent>[];
      final handler = FlutterApiHandler(received.add, (_) => null);
      handler.onMapError(2, PMapErrorCode.loadTimeout, 'no load within 20 s');
      handler.onMapLoaded(2);
      handler.onMapError(2, PMapErrorCode.loadFailed, 'offline (NSURLErrorDomain -1009)');

      expect(received.map((e) => e.runtimeType), [
        PlatformMapErrorEvent,
        PlatformMapLoadedEvent,
        PlatformMapErrorEvent,
      ]);
      expect(received.every((e) => e.viewId == 2), isTrue);
      final timeout = received[0] as PlatformMapErrorEvent;
      expect((timeout.code, timeout.message), (PlatformMapErrorCode.loadTimeout, 'no load within 20 s'));
      final failure = received[2] as PlatformMapErrorEvent;
      expect((failure.code, failure.message), (PlatformMapErrorCode.loadFailed, 'offline (NSURLErrorDomain -1009)'));
    });

    test('load and error events arriving on the Pigeon channels reach only their view', () async {
      final view1 = <PlatformMapEvent>[];
      final view2 = <PlatformMapEvent>[];
      platform.events(1).listen(view1.add);
      platform.events(2).listen(view2.add);

      await sendEvent('onMapLoaded', [1]);
      await sendEvent('onMapError', [2, PMapErrorCode.loadFailed, 'The operation couldn’t be completed.']);
      await sendEvent('onMapError', [1, PMapErrorCode.loadTimeout, 'timeout']);
      await sendEvent('onMapLoaded', [2]);
      await sendEvent('onMapLoaded', [3]);
      await Future<void>.delayed(Duration.zero);

      expect(view1.map((e) => e.runtimeType), [PlatformMapLoadedEvent, PlatformMapErrorEvent]);
      expect((view1[1] as PlatformMapErrorEvent).code, PlatformMapErrorCode.loadTimeout);
      expect(view2.map((e) => e.runtimeType), [PlatformMapErrorEvent, PlatformMapLoadedEvent]);
      final error = view2[0] as PlatformMapErrorEvent;
      expect((error.code, error.message), (PlatformMapErrorCode.loadFailed, 'The operation couldn’t be completed.'));
    });

    test('dispose closes the stream and drops later events', () async {
      final received = <PlatformMapEvent>[];
      var done = false;
      platform.events(4).listen(received.add, onDone: () => done = true);
      await platform.dispose(4);
      await sendEvent('onMarkerTap', [4, 'late']);
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
      expect(received, isEmpty);
      expect(host.methods, ['dispose']);
    });

    test('a disposed view gets an empty stream', () async {
      platform.events(5);
      await platform.dispose(5);
      var done = false;
      final received = <PlatformMapEvent>[];
      platform.events(5).listen(received.add, onDone: () => done = true);
      await sendEvent('onMarkerTap', [5, 'late']);
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
      expect(received, isEmpty);
    });

    test('dispose closes the stream also when the native dispose fails', () async {
      var done = false;
      platform.events(6).listen((_) {}, onDone: () => done = true);
      host.disposeError = PlatformException(code: 'channel-error');
      await expectLater(platform.dispose(6), throwsA(isA<PlatformException>()));
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
    });
  });
}
