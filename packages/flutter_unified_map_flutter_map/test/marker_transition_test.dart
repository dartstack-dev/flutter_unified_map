import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map_flutter_map/flutter_unified_map_flutter_map.dart';
import 'package:flutter_unified_map_flutter_map/src/layers/marker_layer.dart' show MarkerOpacity, RenderMarkerOpacity;
import 'package:flutter_unified_map_flutter_map/src/marker_store.dart' show lerpLatLng;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' as p;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

import 'support/harness.dart';

const _north = LatLng(48.9566, 2.3522);
const _east = LatLng(48.8566, 2.5522);
const _duration = Duration(milliseconds: 400);
const _half = Duration(milliseconds: 200);

PlatformMarker _marker(String id, LatLng position, {Uint8List? png}) =>
    testMarker(id, position, anchor: const p.Offset(0.5, 0.5), png: png);

PlatformMarkerTransition _transition({
  Map<String, LatLng> appearFrom = const {},
  Map<String, LatLng> disappearTo = const {},
}) => PlatformMarkerTransition(duration: _duration, appearFrom: appearFrom, disappearTo: disappearTo);

late UnifiedMapsFlutterMap _platform;

Future<(UnifiedMapsFlutterMap, List<PlatformMapEvent>)> _pumpMap(WidgetTester tester) async {
  final platform = _platform = UnifiedMapsFlutterMap();
  final events = <PlatformMapEvent>[];
  final subscription = platform.events(1).listen(events.add);
  addTearDown(subscription.cancel);
  await tester.pumpWidget(MaterialApp(home: platform.buildView(viewId: 1, options: noBaseMapOptions)));
  await tester.pump();
  return (platform, events);
}

/// Read from the screen: the marker's drawn centre (its anchor) and the widgets wrapping its icon.
Future<({LatLng position, double opacity, bool ignoresTaps})> _state(WidgetTester tester, String id) async {
  final marker = findMarker(id);
  final center = tester.getCenter(marker) - tester.getTopLeft(find.byType(fm.FlutterMap));
  final opacity = tester.widget<MarkerOpacity>(find.descendant(of: marker, matching: find.byType(MarkerOpacity)));
  final ignore = tester.widget<IgnorePointer>(find.descendant(of: marker, matching: find.byType(IgnorePointer)).first);
  return (
    position: await _platform.toLatLng(1, p.Offset(center.dx, center.dy)),
    opacity: opacity.opacity,
    ignoresTaps: ignore.ignoring,
  );
}

Matcher _near(LatLng expected) => isA<LatLng>()
    .having((l) => l.latitude, 'latitude', closeTo(expected.latitude, 1e-6))
    .having((l) => l.longitude, 'longitude', closeTo(expected.longitude, 1e-6));

/// A fraction [t] of the way from [a] to [b] in a straight line on the screen, which is the Web Mercator plane.
Future<LatLng> _between(LatLng a, LatLng b, double t) async {
  final from = await _platform.toScreen(1, a);
  final to = await _platform.toScreen(1, b);
  return _platform.toLatLng(1, p.Offset(from.dx + (to.dx - from.dx) * t, from.dy + (to.dy - from.dy) * t));
}

Future<Uint8List> _redSquarePng(WidgetTester tester) async => (await tester.runAsync(() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 40, 40), Paint()..color = const Color(0xFFFF0000));
  final image = await recorder.endRecording().toImage(40, 40);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}))!;

Future<Color> _pixelAt(WidgetTester tester, UnifiedMapsFlutterMap platform, Uint8List snapshot, LatLng at) async {
  final screen = await platform.toScreen(1, at);
  return (await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(snapshot);
    final image = (await codec.getNextFrame()).image;
    final ratio = image.width * tester.view.devicePixelRatio / tester.view.physicalSize.width;
    final data = (await image.toByteData())!;
    final offset = ((screen.dy * ratio).round() * image.width + (screen.dx * ratio).round()) * 4;
    image.dispose();
    codec.dispose();
    return Color.fromARGB(255, data.getUint8(offset), data.getUint8(offset + 1), data.getUint8(offset + 2));
  }))!;
}

void main() {
  test('positions move straight on the Mercator plane, the shorter way across the antimeridian', () {
    final mid = lerpLatLng(const LatLng(0, 170), const LatLng(10, -170), 0.75);
    expect(mid.latitude, closeTo(7.516714568, 1e-9));
    expect(mid.longitude, closeTo(-175, 1e-9));
    expect(lerpLatLng(const LatLng(0, -170), const LatLng(0, 170), 0.25).longitude, closeTo(-175, 1e-9));
    expect(lerpLatLng(paris, _north, 1), _north);
  });

  testWidgets('an added marker slides from appearFrom while fading in, with ease-in-out', (tester) async {
    final (platform, _) = await _pumpMap(tester);

    await platform.updateMarkers(
      1,
      MapObjectUpdates(added: [_marker('a', _north)]),
      transition: _transition(appearFrom: {'a': paris}),
    );
    await tester.pump();
    expect((await _state(tester, 'a')).position, _near(paris));
    expect((await _state(tester, 'a')).opacity, 0);

    await tester.pump(const Duration(milliseconds: 100));
    final quarter = Curves.easeInOut.transform(0.25);
    expect((await _state(tester, 'a')).position, _near(await _between(paris, _north, quarter)));
    expect((await _state(tester, 'a')).opacity, closeTo(quarter, 1e-9));

    await tester.pump(const Duration(milliseconds: 100));
    expect((await _state(tester, 'a')).position, _near(await _between(paris, _north, 0.5)));
    expect((await _state(tester, 'a')).opacity, closeTo(0.5, 1e-9));

    await tester.pump(_half);
    expect((await _state(tester, 'a')).position, _near(_north));
    expect((await _state(tester, 'a')).opacity, 1);

    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
    expect((await _state(tester, 'a')).position, _near(_north));
  });

  testWidgets('an added marker without appearFrom fades in at its position', (tester) async {
    final (platform, _) = await _pumpMap(tester);

    await platform.updateMarkers(1, MapObjectUpdates(added: [_marker('a', _east)]), transition: _transition());
    await tester.pump();
    await tester.pump(_half);

    expect((await _state(tester, 'a')).position, _near(_east));
    expect((await _state(tester, 'a')).opacity, closeTo(0.5, 1e-9));
  });

  testWidgets('a changed position glides; an unchanged marker stays put', (tester) async {
    final (platform, _) = await _pumpMap(tester);
    await platform.updateMarkers(1, MapObjectUpdates(added: [_marker('a', paris), _marker('b', _east)]));
    await tester.pump();

    await platform.updateMarkers(
      1,
      MapObjectUpdates(changed: [_marker('a', _north), _marker('b', _east)]),
      transition: _transition(),
    );
    await tester.pump();
    await tester.pump(_half);

    expect((await _state(tester, 'a')).position, _near(await _between(paris, _north, 0.5)));
    expect((await _state(tester, 'a')).opacity, 1);
    expect((await _state(tester, 'b')).position, _near(_east));
  });

  testWidgets('a removed marker slides to disappearTo while fading out, ignores taps, then is removed', (tester) async {
    final (platform, events) = await _pumpMap(tester);
    await platform.updateMarkers(1, MapObjectUpdates(added: [_marker('a', paris)]));
    await tester.pump();

    await platform.updateMarkers(
      1,
      const MapObjectUpdates(removedIds: ['a']),
      transition: _transition(disappearTo: {'a': _north}),
    );
    await tester.pump();
    await tester.pump(_half);

    final mid = (await _state(tester, 'a'));
    expect(mid.position, _near(await _between(paris, _north, 0.5)));
    expect(mid.opacity, closeTo(0.5, 1e-9));
    expect(mid.ignoresTaps, isTrue);
    await tester.tap(find.byType(Image), warnIfMissed: false);
    expect(events.whereType<PlatformMarkerTapEvent>(), isEmpty);

    await tester.pump(_duration);
    expect(findMarker('a'), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(events.whereType<PlatformMarkerTapEvent>(), isEmpty);
  });

  testWidgets('a removed marker without disappearTo fades out where it is', (tester) async {
    final (platform, _) = await _pumpMap(tester);
    await platform.updateMarkers(1, MapObjectUpdates(added: [_marker('a', _east)]));
    await tester.pump();

    await platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['a']), transition: _transition());
    await tester.pump();
    await tester.pump(_half);

    expect((await _state(tester, 'a')).position, _near(_east));
    expect((await _state(tester, 'a')).opacity, closeTo(0.5, 1e-9));
  });

  testWidgets('a disappearing marker added again is revived from where it is', (tester) async {
    final (platform, _) = await _pumpMap(tester);
    await platform.updateMarkers(1, MapObjectUpdates(added: [_marker('a', paris)]));
    await tester.pump();
    await platform.updateMarkers(
      1,
      const MapObjectUpdates(removedIds: ['a']),
      transition: _transition(disappearTo: {'a': _north}),
    );
    await tester.pump();
    await tester.pump(_half);
    final mid = await _between(paris, _north, 0.5);

    await platform.updateMarkers(1, MapObjectUpdates(added: [_marker('a', paris)]), transition: _transition());
    await tester.pump();
    expect((await _state(tester, 'a')).position, _near(mid));
    expect((await _state(tester, 'a')).opacity, closeTo(0.5, 1e-9));
    expect((await _state(tester, 'a')).ignoresTaps, isFalse);

    await tester.pump(_half);
    expect((await _state(tester, 'a')).position, _near(await _between(mid, paris, 0.5)));
    expect((await _state(tester, 'a')).opacity, closeTo(0.75, 1e-9));

    await tester.pump(_duration);
    expect((await _state(tester, 'a')).position, _near(paris));
    expect((await _state(tester, 'a')).opacity, 1);
    expect(drawnMarkerIds(tester), hasLength(1));
  });

  testWidgets('a marker in flight continues from its on-screen state; the others keep their own timeline', (
    tester,
  ) async {
    final (platform, _) = await _pumpMap(tester);
    await platform.updateMarkers(1, MapObjectUpdates(added: [_marker('a', paris), _marker('b', paris)]));
    await tester.pump();
    await platform.updateMarkers(
      1,
      MapObjectUpdates(changed: [_marker('a', _north), _marker('b', _north)]),
      transition: _transition(),
    );
    await tester.pump();
    await tester.pump(_half);
    final mid = await _between(paris, _north, 0.5);

    await platform.updateMarkers(1, MapObjectUpdates(changed: [_marker('a', _east)]), transition: _transition());
    await tester.pump();
    expect((await _state(tester, 'a')).position, _near(mid));
    expect((await _state(tester, 'b')).position, _near(mid));

    await tester.pump(const Duration(milliseconds: 100));
    expect((await _state(tester, 'a')).position, _near(await _between(mid, _east, Curves.easeInOut.transform(0.25))));
    expect(
      (await _state(tester, 'b')).position,
      _near(await _between(paris, _north, Curves.easeInOut.transform(0.75))),
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect((await _state(tester, 'a')).position, _near(await _between(mid, _east, 0.5)));
    expect((await _state(tester, 'b')).position, _near(_north));

    await tester.pump(_half);
    expect((await _state(tester, 'a')).position, _near(_east));
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a view re-parented mid-transition finishes it on its new state', (tester) async {
    final (platform, events) = await _pumpMap(tester);
    await platform.updateMarkers(1, MapObjectUpdates(added: [_marker('old', paris)]));
    await tester.pump();
    await platform.updateMarkers(
      1,
      MapObjectUpdates(added: [_marker('new', _north)], removedIds: ['old']),
      transition: _transition(appearFrom: {'new': paris}, disappearTo: {'old': _north}),
    );
    await tester.pump();
    await tester.pump(_half);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(width: 400, height: 300, child: platform.buildView(viewId: 1, options: noBaseMapOptions)),
        ),
      ),
    );
    await tester.pump();
    expect((await _state(tester, 'new')).opacity, closeTo(0.5, 1e-9));
    expect((await _state(tester, 'old')).opacity, closeTo(0.5, 1e-9));
    expect((await _state(tester, 'old')).ignoresTaps, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    expect((await _state(tester, 'new')).opacity, closeTo(Curves.easeInOut.transform(0.75), 1e-9));

    await tester.pump(const Duration(milliseconds: 100));
    expect(drawnMarkerIds(tester), ['new']);
    expect((await _state(tester, 'new')).position, _near(_north));
    expect((await _state(tester, 'new')).opacity, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
    expect(events.whereType<PlatformMapReadyEvent>(), hasLength(1));
  });

  testWidgets('an unmounted view ends its transitions', (tester) async {
    final (platform, _) = await _pumpMap(tester);
    await platform.updateMarkers(1, MapObjectUpdates(added: [_marker('old', paris)]));
    await tester.pump();
    await platform.updateMarkers(
      1,
      MapObjectUpdates(added: [_marker('new', _north)], removedIds: ['old']),
      transition: _transition(appearFrom: {'new': paris}),
    );
    await tester.pump();
    await tester.pump(_half);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(MaterialApp(home: platform.buildView(viewId: 1, options: noBaseMapOptions)));
    await tester.pump();

    expect(drawnMarkerIds(tester), ['new']);
    expect((await _state(tester, 'new')).position, _near(_north));
    expect((await _state(tester, 'new')).opacity, 1);
  });

  testWidgets('an update without transition is instant and leaves other markers in flight', (tester) async {
    final (platform, _) = await _pumpMap(tester);
    await platform.updateMarkers(1, MapObjectUpdates(added: [_marker('a', paris), _marker('b', paris)]));
    await tester.pump();
    await platform.updateMarkers(
      1,
      MapObjectUpdates(changed: [_marker('a', _north), _marker('b', _north)]),
      transition: _transition(),
    );
    await tester.pump();
    await tester.pump(_half);

    await platform.updateMarkers(1, MapObjectUpdates(changed: [_marker('a', _east)]));
    await tester.pump();

    expect((await _state(tester, 'a')).position, _near(_east));
    expect((await _state(tester, 'b')).position, _near(await _between(paris, _north, 0.5)));
  });

  testWidgets('updates sent without awaiting apply in call order', (tester) async {
    final (platform, _) = await _pumpMap(tester);

    unawaited(platform.updateMarkers(1, MapObjectUpdates(added: [_marker('a', paris), _marker('b', paris)])));
    unawaited(platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['a']), transition: _transition()));
    unawaited(platform.updateMarkers(1, MapObjectUpdates(added: [_marker('a', _east)])));
    unawaited(platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['b'])));
    await tester.pump();

    expect(drawnMarkerIds(tester), ['a']);
    expect((await _state(tester, 'a')).position, _near(_east));
    expect((await _state(tester, 'a')).opacity, 1);

    await tester.pump(_duration);
    expect(drawnMarkerIds(tester), ['a']);
  });

  testWidgets('a transition sent before the view exists is applied instantly', (tester) async {
    final platform = UnifiedMapsFlutterMap();
    await platform.updateMarkers(
      1,
      MapObjectUpdates(added: [_marker('a', _north)]),
      transition: _transition(appearFrom: {'a': paris}),
    );
    await tester.pumpWidget(MaterialApp(home: platform.buildView(viewId: 1, options: noBaseMapOptions)));
    await tester.pump();

    expect((await _state(tester, 'a')).position, _near(_north));
    expect((await _state(tester, 'a')).opacity, 1);
  });

  testWidgets('dispose ends every transition', (tester) async {
    final (platform, _) = await _pumpMap(tester);
    await platform.updateMarkers(1, MapObjectUpdates(added: [_marker('a', paris)]));
    await tester.pump();
    await platform.updateMarkers(
      1,
      MapObjectUpdates(added: [_marker('b', _north)], removedIds: ['a']),
      transition: _transition(appearFrom: {'b': paris}, disappearTo: {'a': _north}),
    );
    await tester.pump();
    await tester.pump(_half);

    await platform.dispose(1);
    await tester.pump();

    expect(drawnMarkerIds(tester), ['b']);
    expect((await _state(tester, 'b')).position, _near(_north));
    expect((await _state(tester, 'b')).opacity, 1);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('snapshots leave disappearing markers out without changing the screen', (tester) async {
    final (platform, _) = await _pumpMap(tester);
    final red = await _redSquarePng(tester);
    await tester.runAsync(() => precacheImage(MemoryImage(red, scale: 2), tester.element(find.byType(fm.FlutterMap))));
    await platform.updateMarkers(
      1,
      MapObjectUpdates(
        added: [
          _marker('a', paris, png: red),
          _marker('b', _east, png: red),
        ],
      ),
    );
    await tester.pump();

    final before = (await tester.runAsync(() => platform.takeSnapshot(1)))!;
    expect((await _pixelAt(tester, platform, before, paris)).r, 1);
    expect((await _pixelAt(tester, platform, before, paris)).g, 0);

    await platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['a']), transition: _transition());
    await tester.pump();
    await tester.pump(_half);
    final layer = tester
        .renderObject<RenderMarkerOpacity>(find.descendant(of: findMarker('a'), matching: find.byType(MarkerOpacity)))
        .compositedLayer!;
    final alpha = layer.alpha;
    expect(alpha, inInclusiveRange(126, 129));

    final during = (await tester.runAsync(() => platform.takeSnapshot(1)))!;
    final background = await _pixelAt(tester, platform, during, paris);
    expect(background.r, closeTo(background.g, 0.01));
    final kept = await _pixelAt(tester, platform, during, _east);
    expect((kept.r, kept.g), (1, 0));

    expect(layer.alpha, alpha);
    expect(drawnMarkerIds(tester), ['a', 'b']);
    expect((await _state(tester, 'a')).opacity, closeTo(0.5, 1e-9));
  });

  testWidgets('an update without transition puts a touched marker in flight at its target at once', (tester) async {
    final (platform, _) = await _pumpMap(tester);
    await platform.updateMarkers(
      1,
      MapObjectUpdates(added: [_marker('a', _north)]),
      transition: _transition(appearFrom: {'a': paris}),
    );
    await tester.pump();
    await tester.pump(_half);
    expect((await _state(tester, 'a')).opacity, closeTo(0.5, 1e-9));

    final red = await _redSquarePng(tester);
    await platform.updateMarkers(1, MapObjectUpdates(changed: [_marker('a', _north, png: red)]));
    await tester.pump();

    expect((await _state(tester, 'a')).position, _near(_north));
    expect((await _state(tester, 'a')).opacity, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('only markers that fade or are left out of snapshots get their own layer', (tester) async {
    final (platform, _) = await _pumpMap(tester);
    await platform.updateMarkers(1, MapObjectUpdates(added: [_marker('a', paris), _marker('b', _east)]));
    await tester.pump();
    RenderMarkerOpacity render(String id) =>
        tester.renderObject(find.descendant(of: findMarker(id), matching: find.byType(MarkerOpacity)));
    expect(render('a').isRepaintBoundary, isFalse);

    await platform.updateMarkers(1, const MapObjectUpdates(removedIds: ['a']), transition: _transition());
    await tester.pump();
    expect(render('a').isRepaintBoundary, isTrue);
    expect(render('a').compositedLayer, isNotNull);
    expect(render('b').isRepaintBoundary, isFalse);
  });
}
