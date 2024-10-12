import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets, Size;
import 'package:flutter/painting.dart' as painting show Offset;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_map/flutter_map.dart' show MapCamera;
import 'package:flutter_unified_map_flutter_map/src/base_map_load_monitor.dart';
import 'package:flutter_unified_map_flutter_map/src/camera_math.dart';
import 'package:flutter_unified_map_flutter_map/src/layers/tile_layers.dart';
import 'package:flutter_unified_map_flutter_map/src/marker_store.dart';
import 'package:flutter_unified_map_flutter_map/src/z_order.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

/// Answers camera queries from a frozen camera. The view keeps its entry's last camera current, so the same
/// answers hold while it is mounted, after it is unmounted and after it is disposed.
class CameraSnapshot {
  const CameraSnapshot(this.mapCamera, this.padding);

  final MapCamera mapCamera;
  final EdgeInsets padding;

  PlatformCamera get camera => toPlatformCamera(mapCamera, padding);

  PlatformLatLngBounds get visibleRegion => visibleRegionOf(mapCamera);

  painting.Offset toScreen(LatLng position) => mapCamera.latLngToScreenOffset(position);

  LatLng toLatLng(painting.Offset screenPoint) => mapCamera.screenOffsetToLatLng(screenPoint);
}

abstract class ViewHost {
  /// True once the map emitted [PlatformMapReadyEvent]: the camera and projections are usable.
  bool get isReady;

  Future<void> moveCamera(PlatformCameraUpdate update, {Duration? animation});

  Future<Uint8List?> takeSnapshot();
}

/// Marking a widget dirty from outside its subtree while widgets build is an error, so [action] waits for the end of
/// the frame when called during a build.
void runOutsideBuild(VoidCallback action) {
  final scheduler = SchedulerBinding.instance;
  if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
    scheduler.addPostFrameCallback((_) => action());
  } else {
    action();
  }
}

class ObjectStore<T extends PlatformMapObject> extends ValueNotifier<List<T>> {
  ObjectStore(this._zIndex) : super(const []);

  final double Function(T object) _zIndex;
  final _byId = <String, T>{};

  void apply(MapObjectUpdates<T> updates) {
    if (updates.isEmpty) return;
    for (final id in updates.removedIds) {
      _byId.remove(id);
    }
    for (final object in updates.added) {
      _byId[object.id] = object;
    }
    for (final object in updates.changed) {
      _byId[object.id] = object;
    }
    value = sortedByZ(_byId.values, _zIndex);
  }

  @override
  void dispose() {
    _byId.clear();
    super.dispose();
  }
}

/// flutter_map layer widgets drawn inside the view's `FlutterMap`. The list is set at once, so the view reads the
/// latest one whenever it builds; a list set while widgets are building (from another widget's build) is announced
/// after the frame.
class FlutterMapLayers extends ChangeNotifier {
  List<Widget> _value = const [];
  bool _alive = true;

  List<Widget> get value => _value;

  set value(List<Widget> layers) {
    if (listEquals(layers, _value)) return;
    _value = List.unmodifiable(layers);
    runOutsideBuild(() {
      if (_alive) notifyListeners();
    });
  }

  @override
  void dispose() {
    _alive = false;
    _value = const [];
    super.dispose();
  }
}

/// Per-view registry entry. It exists from the first `buildView` or `events` call until `dispose`, whether or
/// not the widget is currently mounted, so updates pushed before the state exists are simply read on init.
class ViewEntry {
  ViewEntry(
    this.viewId, {
    TileProviderFactory tileProvider = defaultTileProvider,
    String userAgentPackageName = defaultUserAgentPackageName,
  }) {
    _events = StreamController<PlatformMapEvent>.broadcast(onListen: _flushPending);
    loadMonitor = BaseMapLoadMonitor(viewId, emit);
    tiles = TileLayerFactory(
      listener: loadMonitor,
      tileProvider: tileProvider,
      userAgentPackageName: userAgentPackageName,
    );
    options.addListener(_onBaseMapContentChanged);
    tileLayers.addListener(_onBaseMapContentChanged);
  }

  final int viewId;
  final options = ValueNotifier<PlatformMapOptions?>(null);
  final markers = MarkerStore();
  final flutterMapLayers = FlutterMapLayers();
  final polylines = ObjectStore<PlatformPolyline>((p) => p.zIndex);
  final polygons = ObjectStore<PlatformPolygon>((p) => p.zIndex);
  final circles = ObjectStore<PlatformCircle>((c) => c.zIndex);
  final tileLayers = ObjectStore<PlatformTileLayer>((t) => t.zIndex);
  late final BaseMapLoadMonitor loadMonitor;
  late final TileLayerFactory tiles;
  late final Listenable shapesAndTiles = Listenable.merge([tileLayers, polygons, polylines, circles]);

  late final StreamController<PlatformMapEvent> _events;
  final _pending = <PlatformMapEvent>[];
  bool _hadListener = false;
  ViewHost? _host;
  bool _disposed = false;
  bool _released = false;
  bool _readyEmitted = false;
  Size? _reportedSize;

  /// Kept current by the mounted view on every camera change, and kept across a remount, so a re-parented view
  /// resumes where it was.
  MapCamera? lastCamera;

  ViewHost? get readyHost {
    final host = _host;
    return host != null && host.isReady ? host : null;
  }

  CameraSnapshot? get queries {
    final last = lastCamera;
    return last == null ? null : CameraSnapshot(last, options.value?.padding ?? EdgeInsets.zero);
  }

  bool get isReleased => _released;

  Stream<PlatformMapEvent> get events => _events.stream;

  /// Events emitted before the first listener (the ready event can precede the core's subscription) are kept
  /// for it; afterwards the stream behaves as a plain broadcast stream.
  void emit(PlatformMapEvent event) {
    if (_disposed) return;
    if (_hadListener) {
      _events.add(event);
    } else {
      _pending.add(event);
    }
  }

  /// A re-parented view is ready only once.
  void emitReadyOnce(PlatformCamera camera) {
    if (_readyEmitted) return;
    _readyEmitted = true;
    emit(PlatformMapReadyEvent(viewId, camera));
  }

  void reportSize(Size size) {
    if (size == _reportedSize) return;
    _reportedSize = size;
    emit(PlatformViewSizeEvent(viewId, size.width, size.height));
  }

  void attach(ViewHost host) => _host = host;

  void detach(ViewHost host) {
    if (identical(_host, host)) _host = null;
    if (_disposed && _host == null) _releaseNotifiers();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    markers.finishTransitions();
    _pending.clear();
    unawaited(_events.close());
    if (_host == null) _releaseNotifiers();
  }

  void _onBaseMapContentChanged() {
    final style = options.value?.style;
    if (style != null) loadMonitor.contentChanged(style, tileLayers.value);
  }

  void _flushPending() {
    if (_hadListener) return;
    _hadListener = true;
    final pending = List.of(_pending);
    _pending.clear();
    pending.forEach(_events.add);
  }

  void _releaseNotifiers() {
    _released = true;
    options.dispose();
    markers.dispose();
    flutterMapLayers.dispose();
    polylines.dispose();
    polygons.dispose();
    circles.dispose();
    tileLayers.dispose();
  }
}
