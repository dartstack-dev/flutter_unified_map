import 'package:flutter/widgets.dart';

import '../shared/map_layer_state.dart';
import 'marker.dart';
import 'marker_publisher.dart';

/// flutter_map's `MarkerLayer`. Each marker becomes a native marker showing its rasterised child (on the flutter_map
/// backend, the same bitmap in flutter_map's marker layer).
class MarkerLayer extends StatefulWidget {
  final List<Marker> markers;

  /// Default alignment of markers that do not set their own.
  final Alignment alignment;

  /// Default for markers that do not set [Marker.rotate]: true keeps them upright.
  final bool rotate;

  const MarkerLayer({super.key, required this.markers, this.alignment = Alignment.center, this.rotate = false});

  @override
  State<MarkerLayer> createState() => _MarkerLayerState();
}

class _MarkerLayerState extends MapLayerState<MarkerLayer> {
  late final _publisher = MarkerPublisher(layerId);
  var _synced = const <Marker>[];

  @override
  bool updateShouldSync(MarkerLayer oldWidget) =>
      !sameItems(_synced, widget.markers) ||
      oldWidget.alignment != widget.alignment ||
      oldWidget.rotate != widget.rotate;

  @override
  void sync() {
    _synced = List.of(widget.markers);
    final byId = <String, Marker>{};
    final specs = <MarkerSpec>[];
    for (var i = 0; i < widget.markers.length; i++) {
      final marker = widget.markers[i];
      final id = objectId(marker.key, i);
      assert(!byId.containsKey(id), 'MarkerLayer: two markers have the same key ${marker.key}');
      byId[id] = marker;
      specs.add(
        MarkerSpec(
          id: id,
          position: marker.point,
          iconKey: marker.effectiveIconKey,
          child: marker.child,
          size: Size(marker.width, marker.height),
          alignment: marker.alignment ?? widget.alignment,
          rotate: marker.rotate ?? widget.rotate,
          tappable: marker.onTap != null,
          nativeParams: marker.nativeParams,
        ),
      );
    }
    _publisher.publish(host, specs, onTap: (id) => byId[id]?.onTap?.call());
  }

  @override
  void dispose() {
    _publisher.dispose();
    super.dispose();
  }
}
