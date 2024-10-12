import 'dart:typed_data';

import 'package:flutter/foundation.dart' show Factory, visibleForTesting;
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer;
import 'package:flutter/services.dart' show BinaryMessenger;
import 'package:flutter/widgets.dart' show AndroidView, TextDirection, Widget;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

import 'src/conversions.dart';
import 'src/map_event_relay.dart';
import 'src/messages.g.dart';

export 'src/messages.g.dart' show UnifiedMapsFlutterApi, UnifiedMapsHostApi;

/// Android implementation of [UnifiedMapsPlatform] on the Google Maps SDK for Android.
class UnifiedMapsAndroid extends UnifiedMapsPlatform {
  /// Talks to the native side through [binaryMessenger] (the default one when null); tests pass a fake [hostApi].
  UnifiedMapsAndroid({@visibleForTesting UnifiedMapsHostApi? hostApi, BinaryMessenger? binaryMessenger})
    : _hostApi = hostApi ?? UnifiedMapsHostApi(binaryMessenger: binaryMessenger),
      _binaryMessenger = binaryMessenger;

  /// The platform view type registered by the Kotlin plugin.
  static const String viewType = 'flutter_unified_map_android/map';

  /// Makes this the [UnifiedMapsPlatform]; called by the generated plugin registrant.
  static void registerWith() {
    UnifiedMapsPlatform.instance = UnifiedMapsAndroid();
  }

  final UnifiedMapsHostApi _hostApi;
  final BinaryMessenger? _binaryMessenger;
  bool _listening = false;

  // registerWith runs from the plugin registrant before main(), when the default messenger does not exist yet.
  void _listen() {
    if (_listening) return;
    _listening = true;
    UnifiedMapsFlutterApi.setUp(_relay, binaryMessenger: _binaryMessenger);
  }

  final MapEventRelay _relay = MapEventRelay();

  /// Receives the native events; tests call it directly.
  @visibleForTesting
  UnifiedMapsFlutterApi get flutterApi => _relay;

  final Map<int, _IconBook> _icons = {};
  final Map<int, _MarkerQueue> _markerQueues = {};
  final Set<int> _disposed = {};

  @override
  Widget buildView({
    required int viewId,
    required PlatformMapOptions options,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  }) {
    _listen();
    _disposed.remove(viewId);
    return AndroidView(
      viewType: viewType,
      creationParams: <Object?>[viewId, toPMapOptions(options)],
      creationParamsCodec: UnifiedMapsHostApi.pigeonChannelCodec,
      gestureRecognizers: gestureRecognizers,
      layoutDirection: TextDirection.ltr,
    );
  }

  @override
  Future<void> dispose(int viewId) async {
    _disposed.add(viewId);
    _icons.remove(viewId);
    _markerQueues.remove(viewId)?.close();
    _relay.close(viewId);
    await _hostApi.dispose(viewId);
  }

  @override
  Future<void> updateOptions(int viewId, PlatformMapOptions options) =>
      _hostApi.updateOptions(viewId, toPMapOptions(options));

  @override
  Future<void> updateMarkers(
    int viewId,
    MapObjectUpdates<PlatformMarker> updates, {
    PlatformMarkerTransition? transition,
  }) {
    if (_disposed.contains(viewId)) return Future.value();
    final book = _icons.putIfAbsent(viewId, _IconBook.new);
    final added = updates.added.map(toPMarker).toList(growable: false);
    final changed = updates.changed.map(toPMarker).toList(growable: false);
    final pTransition = transition == null ? null : toPMarkerTransition(transition);
    return _markerQueues.putIfAbsent(viewId, _MarkerQueue.new).enqueue(() async {
      // Applied in the queue so that, when an earlier update failed, this one sends its icons again.
      final icons = book.apply(updates);
      try {
        if (icons.isNotEmpty) await _hostApi.registerIcons(viewId, icons.map(toPIcon).toList(growable: false));
        await _hostApi.updateMarkers(viewId, added, changed, updates.removedIds, pTransition);
      } catch (_) {
        book.reset();
        rethrow;
      }
    });
  }

  @override
  Future<void> updatePolylines(int viewId, MapObjectUpdates<PlatformPolyline> updates) => _hostApi.updatePolylines(
    viewId,
    updates.added.map(toPPolyline).toList(growable: false),
    updates.changed.map(toPPolyline).toList(growable: false),
    updates.removedIds,
  );

  @override
  Future<void> updatePolygons(int viewId, MapObjectUpdates<PlatformPolygon> updates) => _hostApi.updatePolygons(
    viewId,
    updates.added.map(toPPolygon).toList(growable: false),
    updates.changed.map(toPPolygon).toList(growable: false),
    updates.removedIds,
  );

  @override
  Future<void> updateCircles(int viewId, MapObjectUpdates<PlatformCircle> updates) => _hostApi.updateCircles(
    viewId,
    updates.added.map(toPCircle).toList(growable: false),
    updates.changed.map(toPCircle).toList(growable: false),
    updates.removedIds,
  );

  @override
  Future<void> updateTileLayers(int viewId, MapObjectUpdates<PlatformTileLayer> updates) => _hostApi.updateTileLayers(
    viewId,
    updates.added.map(toPTileLayer).toList(growable: false),
    updates.changed.map(toPTileLayer).toList(growable: false),
    updates.removedIds,
  );

  @override
  Future<void> updateGroundOverlays(int viewId, MapObjectUpdates<PlatformGroundOverlay> updates) async {
    final images = {for (final overlay in [...updates.added, ...updates.changed]) overlay.image.key: overlay.image};
    if (images.isNotEmpty) await _hostApi.registerIcons(viewId, images.values.map(toPIcon).toList(growable: false));
    await _hostApi.updateGroundOverlays(
      viewId,
      updates.added.map(toPGroundOverlay).toList(growable: false),
      updates.changed.map(toPGroundOverlay).toList(growable: false),
      updates.removedIds,
    );
  }

  @override
  Future<void> resetTileLayer(int viewId, String tileLayerId) => _hostApi.resetTileLayer(viewId, tileLayerId);

  @override
  void setTileLoader(int viewId, PlatformTileLoader loader) => _relay.setTileLoader(viewId, loader);

  @override
  Future<void> moveCamera(int viewId, PlatformCameraUpdate update, {Duration? animation}) =>
      _hostApi.moveCamera(viewId, toPCameraUpdate(update), animation?.inMilliseconds);

  @override
  Future<void> stopCamera(int viewId) => _hostApi.stopCamera(viewId);

  @override
  Future<PlatformCamera> getCamera(int viewId) async => fromPCamera(await _hostApi.getCamera(viewId));

  @override
  Future<PlatformLatLngBounds> getVisibleRegion(int viewId) async =>
      fromPBounds(await _hostApi.getVisibleRegion(viewId));

  @override
  Future<Offset> toScreen(int viewId, LatLng position) async =>
      fromPPoint(await _hostApi.toScreen(viewId, toPLatLng(position)));

  @override
  Future<LatLng> toLatLng(int viewId, Offset screenPoint) async =>
      fromPLatLng(await _hostApi.toLatLng(viewId, toPPoint(screenPoint)));

  @override
  Future<Uint8List?> takeSnapshot(int viewId) => _hostApi.takeSnapshot(viewId);

  @override
  Stream<PlatformMapEvent> events(int viewId) {
    _listen();
    return _disposed.contains(viewId) ? const Stream<PlatformMapEvent>.empty() : _relay.events(viewId);
  }
}

/// flutter_unified_map_apple has its own queue for the same reason; the platform interface is where both belong.
///
/// Runs a view's marker updates one after the other: each sends `registerIcons` then `updateMarkers`, and an update
/// that starts after an earlier one awaited its icons would otherwise reach the native side first.
class _MarkerQueue {
  Future<void> _tail = Future.value();
  bool _closed = false;

  Future<void> enqueue(Future<void> Function() send) {
    final result = _tail.then((_) => _closed ? null : send());
    _tail = result.catchError((Object _) {});
    return result;
  }

  void close() => _closed = true;
}

/// Which icon keys a view's native side holds. The native side drops icons that no marker references any more
/// (the schema has no unregister call), by the same rule, so a key that comes back is sent again.
class _IconBook {
  final Set<String> _sent = {};
  final Map<String, String> _keyByMarker = {};

  /// Records [updates] and returns the icons the native side does not hold yet.
  List<PlatformIcon> apply(MapObjectUpdates<PlatformMarker> updates) {
    final toSend = <String, PlatformIcon>{};
    for (final marker in [...updates.changed, ...updates.added]) {
      if (!_sent.contains(marker.icon.key)) toSend[marker.icon.key] = marker.icon;
    }
    _sent.addAll(toSend.keys);
    updates.removedIds.forEach(_keyByMarker.remove);
    for (final marker in [...updates.changed, ...updates.added]) {
      _keyByMarker[marker.id] = marker.icon.key;
    }
    _sent.retainAll(_keyByMarker.values.toSet());
    return toSend.values.toList(growable: false);
  }

  /// After a failed update the native side may have dropped icons this book still counts as sent.
  void reset() => _sent.clear();
}
