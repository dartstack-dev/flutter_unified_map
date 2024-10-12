import 'package:flutter/widgets.dart';
import 'package:flutter_unified_map/plugin_api.dart';

/// A layer written only against `plugin_api.dart`, as an extension package would write it.
class TestLayer extends StatefulWidget {
  const TestLayer({super.key});

  @override
  State<TestLayer> createState() => TestLayerState();
}

class TestLayerState extends MapLayerState<TestLayer> {
  late final publisher = MarkerPublisher(layerId);
  final liveCameras = <MapCamera>[];
  final idleCameras = <MapCamera?>[];
  final taps = <String>[];

  String idOf(String key) => objectId(ValueKey(key), 0);

  /// Publishes one 10×10 square per entry, colored as given (the color is the icon key).
  void show(Map<String, (LatLng, Color)> pins, {MarkerTransition? transition, List<Polyline>? polylines}) =>
      publisher.publish(
        host,
        [
          for (final MapEntry(key: key, value: (point, color)) in pins.entries)
            MarkerSpec(
              id: idOf(key),
              position: point,
              iconKey: color,
              child: ColoredBox(color: color),
              size: const Size(10, 10),
            ),
        ],
        onTap: taps.add,
        transition: transition,
        polylines: polylines,
      );

  @override
  void attachHost(MapLayerHost host) {
    host.liveCamera.addListener(_onLive);
    host.idleCamera.addListener(_onIdle);
  }

  @override
  void detachHost(MapLayerHost host) {
    host.liveCamera.removeListener(_onLive);
    host.idleCamera.removeListener(_onIdle);
  }

  void _onLive() => liveCameras.add(host.liveCamera.value);

  void _onIdle() => idleCameras.add(host.idleCamera.value);

  @override
  void sync() {}

  @override
  void dispose() {
    publisher.dispose();
    super.dispose();
  }
}
