import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_unified_map_flutter_map/src/camera_math.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

int interactiveFlags(PlatformInteraction interaction) => interaction.flags;

/// One instance, so that rebuilt options compare equal and flutter_map does not reset its gestures.
final _noCursorRotation = CursorKeyboardRotationOptions.disabled();

/// flutter_map's keyboard panning and ctrl-drag rotation are not covered by the interactive flags, and its default
/// keyboard options take the focus when the map appears, which native maps never do.
InteractionOptions interactionOptions(PlatformInteraction interaction) => InteractionOptions(
  flags: interactiveFlags(interaction),
  keyboardOptions: interaction.has(PlatformInteraction.drag)
      ? const KeyboardOptions(autofocus: false)
      : const KeyboardOptions.disabled(),
  cursorKeyboardRotationOptions: interaction.has(PlatformInteraction.rotate)
      ? const CursorKeyboardRotationOptions()
      : _noCursorRotation,
);

MapOptions buildMapOptions(
  PlatformMapOptions options, {
  required TapCallback onTap,
  required LongPressCallback onLongPress,
  required MapEventCallback onMapEvent,
  required VoidCallback onMapReady,
}) {
  final initial = options.initialCamera;
  final rotation = rotationFromBearing(initial.bearing);
  return MapOptions(
    initialCenter: initialViewCenter(initial.center, initial.zoom, rotation, options.padding),
    initialZoom: initial.zoom,
    initialRotation: rotation,
    minZoom: options.minZoom,
    maxZoom: options.maxZoom,
    backgroundColor: options.backgroundColor,
    interactionOptions: interactionOptions(options.interaction),
    onTap: onTap,
    onLongPress: onLongPress,
    onMapEvent: onMapEvent,
    onMapReady: onMapReady,
  );
}
