import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map_flutter_map/flutter_unified_map_flutter_map.dart';
import 'package:flutter_unified_map_flutter_map/src/base_map_load_monitor.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

const _paris = LatLng(48.8566, 2.3522);

const _options = PlatformMapOptions(initialCamera: PlatformCamera(center: _paris, zoom: 10));

/// Serves every tile from memory, failing all of them while [failing] is set.
class _TileServer {
  _TileServer(this.image, {this.failing = false});

  final ui.Image image;
  bool failing;
  int requests = 0;
}

class _FakeTileProvider extends fm.TileProvider {
  _FakeTileProvider(this.server);

  final _TileServer server;
  bool disposed = false;
  bool usedAfterDispose = false;

  @override
  ImageProvider getImage(fm.TileCoordinates coordinates, fm.TileLayer options) {
    if (disposed) usedAfterDispose = true;
    server.requests++;
    return _FakeTileImage(server.failing ? null : server.image, getTileUrl(coordinates, options));
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _FakeTileImage extends ImageProvider<_FakeTileImage> {
  _FakeTileImage(this.image, this.url);

  final ui.Image? image;
  final String url;

  @override
  Future<_FakeTileImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_FakeTileImage key, ImageDecoderCallback decode) {
    final image = this.image;
    return OneFrameImageStreamCompleter(
      image == null
          ? Future.error(_HttpStatusException(503, 'Service Unavailable', uri: Uri.parse(url)))
          : Future.value(ImageInfo(image: image.clone())),
    );
  }
}

class _HttpStatusException implements Exception {
  const _HttpStatusException(this.statusCode, this.reason, {required this.uri});

  final int statusCode;
  final String reason;
  final Uri uri;

  @override
  String toString() => 'HTTP $statusCode $reason for $uri';
}

Future<_TileServer> _server(WidgetTester tester, {bool failing = false}) async {
  final image = await tester.runAsync(() => createTestImage(width: 1, height: 1));
  return _TileServer(image!, failing: failing);
}

class _Harness {
  _Harness(this.platform);

  final UnifiedMapsFlutterMap platform;
  final events = <PlatformMapEvent>[];

  List<PlatformMapEvent> get loadEvents =>
      events.where((e) => e is PlatformMapLoadedEvent || e is PlatformMapErrorEvent).toList();
}

Future<_Harness> _pumpMap(
  WidgetTester tester, {
  PlatformMapOptions options = _options,
  TileProviderFactory? tileProvider,
  Future<void> Function(UnifiedMapsFlutterMap platform)? beforeBuild,
}) async {
  final platform = tileProvider == null ? UnifiedMapsFlutterMap() : UnifiedMapsFlutterMap(tileProvider: tileProvider);
  final harness = _Harness(platform);
  final subscription = platform.events(1).listen(harness.events.add);
  addTearDown(subscription.cancel);
  await beforeBuild?.call(platform);
  await tester.pumpWidget(MaterialApp(home: platform.buildView(viewId: 1, options: options)));
  await _settleTiles(tester);
  return harness;
}

Future<void> _settleTiles(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('style none without tile layers is loaded right after ready', (tester) async {
    final map = await _pumpMap(tester, options: _options.copyWith(style: PlatformMapStyle.none));

    expect(map.events.first, isA<PlatformMapReadyEvent>());
    expect(map.loadEvents, [isA<PlatformMapLoadedEvent>().having((e) => e.viewId, 'viewId', 1)]);
    expect(map.events.indexOf(map.loadEvents.single), greaterThan(0));
  });

  testWidgets('the first base map tile emits loaded once', (tester) async {
    final server = await _server(tester);
    final map = await _pumpMap(tester, tileProvider: (_) => _FakeTileProvider(server));

    expect(server.requests, greaterThan(1));
    expect(map.events.first, isA<PlatformMapReadyEvent>());
    expect(map.loadEvents, [isA<PlatformMapLoadedEvent>()]);

    await map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(center: LatLng(45.76, 4.83), zoom: 12));
    await _settleTiles(tester);
    expect(map.loadEvents, hasLength(1));
    await _unmount(tester);
  });

  testWidgets('failing base map tiles emit a single loadFailed naming the host and the exception', (tester) async {
    final server = await _server(tester, failing: true);
    final map = await _pumpMap(tester, tileProvider: (_) => _FakeTileProvider(server));
    await map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(center: LatLng(45.76, 4.83), zoom: 12));
    await _settleTiles(tester);

    expect(server.requests, greaterThan(1));
    expect(map.events.first, isA<PlatformMapReadyEvent>());
    final error = map.loadEvents.single as PlatformMapErrorEvent;
    expect(error.viewId, 1);
    expect(error.code, PlatformMapErrorCode.loadFailed);
    expect(error.message, contains('tile.openstreetmap.org'));
    expect(error.message, contains('HTTP 503 Service Unavailable'));
    await _unmount(tester);
  });

  testWidgets('a tile loading after a failure emits loaded again, and a later failure is reported once', (
    tester,
  ) async {
    final server = await _server(tester, failing: true);
    final map = await _pumpMap(tester, tileProvider: (_) => _FakeTileProvider(server));
    expect(map.loadEvents, [isA<PlatformMapErrorEvent>()]);

    server.failing = false;
    await map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(center: LatLng(45.76, 4.83), zoom: 12));
    await _settleTiles(tester);
    expect(map.loadEvents, [isA<PlatformMapErrorEvent>(), isA<PlatformMapLoadedEvent>()]);

    server.failing = true;
    await map.platform.moveCamera(1, const PlatformCameraUpdate.newCamera(center: LatLng(43.3, 5.37), zoom: 13));
    await _settleTiles(tester);
    expect(map.loadEvents, [
      isA<PlatformMapErrorEvent>(),
      isA<PlatformMapLoadedEvent>(),
    ], reason: 'a base tile loaded moments ago, so these failures are not a load error');
    await _unmount(tester);
  });

  testWidgets('a replacing tile layer is the base map; the hidden built-in style is not loaded', (tester) async {
    final base = await _server(tester, failing: true);
    final replacement = await _server(tester);
    final map = await _pumpMap(
      tester,
      tileProvider: (layer) => _FakeTileProvider(layer == null ? base : replacement),
      beforeBuild: (platform) => platform.updateTileLayers(
        1,
        const MapObjectUpdates(
          added: [
            PlatformTileLayer(id: 't', urlTemplate: 'https://tiles.example.com/{z}/{x}/{y}.png', replacesBaseMap: true),
          ],
        ),
      ),
    );

    expect(base.requests, 0);
    expect(replacement.requests, greaterThan(0));
    expect(map.loadEvents, [isA<PlatformMapLoadedEvent>()]);
    await _unmount(tester);
  });

  testWidgets('failing tiles of a replacing layer name its host', (tester) async {
    final server = await _server(tester, failing: true);
    final map = await _pumpMap(
      tester,
      options: _options.copyWith(style: PlatformMapStyle.none),
      tileProvider: (_) => _FakeTileProvider(server),
    );
    expect(map.loadEvents, [isA<PlatformMapLoadedEvent>()]);

    await map.platform.updateTileLayers(
      1,
      const MapObjectUpdates(
        added: [
          PlatformTileLayer(id: 't', urlTemplate: 'https://tiles.example.com/{z}/{x}/{y}.png', replacesBaseMap: true),
        ],
      ),
    );
    await _settleTiles(tester);

    expect(map.loadEvents, [isA<PlatformMapLoadedEvent>(), isA<PlatformMapErrorEvent>()]);
    expect((map.loadEvents.last as PlatformMapErrorEvent).message, contains('tiles.example.com'));
    await _unmount(tester);
  });

  testWidgets('the base map comes back with a new tile provider once a replacing layer is removed', (tester) async {
    final server = await _server(tester);
    final providers = <_FakeTileProvider>[];
    final map = await _pumpMap(
      tester,
      tileProvider: (_) {
        final provider = _FakeTileProvider(server);
        providers.add(provider);
        return provider;
      },
    );
    const replacing = PlatformTileLayer(
      id: 't',
      urlTemplate: 'https://tiles.example.com/{z}/{x}/{y}.png',
      replacesBaseMap: true,
    );

    await map.platform.updateTileLayers(1, const MapObjectUpdates(added: [replacing]));
    await _settleTiles(tester);
    await map.platform.updateTileLayers(1, const MapObjectUpdates(removedIds: ['t']));
    await _settleTiles(tester);

    final base = tester.widget<fm.TileLayer>(find.byType(fm.TileLayer)).tileProvider as _FakeTileProvider;
    expect(base.disposed, isFalse);
    expect(providers.where((p) => p.usedAfterDispose), isEmpty);
    expect(providers.first.disposed, isTrue);
    await _unmount(tester);
  });

  group('BaseMapLoadMonitor', () {
    late DateTime now;
    late List<PlatformMapEvent> events;
    late BaseMapLoadMonitor monitor;

    setUp(() {
      now = DateTime(2026);
      events = [];
      monitor = BaseMapLoadMonitor(1, events.add, clock: () => now)
        ..contentChanged(PlatformMapStyle.standard, const [])
        ..ready();
    });

    test('a failure long enough after the last load is reported', () {
      monitor.tileLoaded(null);
      now = now.add(const Duration(seconds: 5));
      monitor.tileFailed(null, 'tile.openstreetmap.org', 'HTTP 503');
      expect(events, [isA<PlatformMapLoadedEvent>()]);

      now = now.add(BaseMapLoadMonitor.recentLoadWindow);
      monitor.tileFailed(null, 'tile.openstreetmap.org', 'HTTP 503');
      expect(events, [isA<PlatformMapLoadedEvent>(), isA<PlatformMapErrorEvent>()]);
    });

    test('a load of the previous style does not hide the failures of the new one', () {
      monitor.tileLoaded(null);
      monitor.contentChanged(PlatformMapStyle.satellite, const []);
      now = now.add(const Duration(seconds: 1));
      monitor.tileFailed(null, 'server.arcgisonline.com', 'HTTP 503');
      expect(events.last, isA<PlatformMapErrorEvent>());
    });

    test('the message keeps the host of a URL, not its path or query', () {
      monitor.tileFailed(
        null,
        'api.mapbox.com',
        'HTTP request failed, statusCode: 401, https://api.mapbox.com/v4/a/1/2/3.png?access_token=secret',
      );
      final message = (events.single as PlatformMapErrorEvent).message;
      expect(message, contains('statusCode: 401, api.mapbox.com'));
      expect(message, isNot(contains('secret')));
      expect(message, isNot(contains('/v4/')));
    });
  });
}
