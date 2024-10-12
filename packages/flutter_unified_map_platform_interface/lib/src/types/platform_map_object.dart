import 'package:meta/meta.dart';

/// Anything the core pushes to a platform view by id: markers, polylines, polygons, circles, tile layers.
///
/// Equality drives [MapObjectUpdates]: two objects with the same [id] and equal fields are not re-sent.
@immutable
abstract class PlatformMapObject {
  const PlatformMapObject();

  String get id;
}
