import 'package:flutter/widgets.dart';

import '../shared/map_layer_state.dart';

/// A raw flutter_map layer: [child] is drawn inside the map's `FlutterMap`, above the map's own objects, on the
/// platforms that draw the map with flutter_map (web, Windows, Linux). On Android, iOS and macOS it draws nothing.
///
/// [child] sees flutter_map's `MapCamera.of` / `MapController.of`, so any flutter_map layer widget works there.
/// Requires `flutter_map` as a dependency of the app.
class FlutterMapLayer extends StatefulWidget {
  final Widget child;

  const FlutterMapLayer({super.key, required this.child});

  @override
  State<FlutterMapLayer> createState() => _FlutterMapLayerState();
}

class _FlutterMapLayerState extends MapLayerState<FlutterMapLayer> {
  @override
  void sync() => setFlutterMapLayers([widget.child]);
}
