import 'package:meta/meta.dart';

import 'platform_map_object.dart';

/// Diff between two sets of [PlatformMapObject], keyed by [PlatformMapObject.id].
@immutable
class MapObjectUpdates<T extends PlatformMapObject> {
  final List<T> added;
  final List<T> changed;
  final List<String> removedIds;

  const MapObjectUpdates({this.added = const [], this.changed = const [], this.removedIds = const []});

  factory MapObjectUpdates.from(Map<String, T> previous, Map<String, T> current) {
    final added = <T>[];
    final changed = <T>[];
    for (final entry in current.entries) {
      final before = previous[entry.key];
      if (before == null) {
        added.add(entry.value);
      } else if (before != entry.value) {
        changed.add(entry.value);
      }
    }
    final removedIds = [
      for (final id in previous.keys)
        if (!current.containsKey(id)) id,
    ];
    return MapObjectUpdates(added: added, changed: changed, removedIds: removedIds);
  }

  bool get isEmpty => added.isEmpty && changed.isEmpty && removedIds.isEmpty;
  bool get isNotEmpty => !isEmpty;

  @override
  String toString() => 'MapObjectUpdates(+${added.length} ~${changed.length} -${removedIds.length})';
}
