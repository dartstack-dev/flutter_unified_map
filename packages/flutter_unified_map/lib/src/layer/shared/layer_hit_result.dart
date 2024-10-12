import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset;
import 'package:latlong2/latlong.dart';

/// What a tap hit in a layer, as flutter_map's `LayerHitResult`: the [hitValues] of the elements under the pointer
/// (topmost first), and where the tap landed. Resolved in Dart by the core.
@immutable
class LayerHitResult<R extends Object> {
  final List<R> hitValues;
  final LatLng coordinate;
  final Offset point;

  const LayerHitResult({required this.hitValues, required this.coordinate, required this.point});
}

/// flutter_map's `LayerHitNotifier`: set when a tap, secondary tap or long press reaches the map (just before
/// `MapOptions.onTap` / `onSecondaryTap` / `onLongPress` run), to the hit elements of the layer or null.
///
/// In flutter_map a `GestureDetector` wrapped around a layer can read it; over a native map the layer is not a
/// hit-testable box, so use `MapOptions.onTap` and read the notifier there (that works on every backend).
typedef LayerHitNotifier<R extends Object> = ValueNotifier<LayerHitResult<R>?>;
