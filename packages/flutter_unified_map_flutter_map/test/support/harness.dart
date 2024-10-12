import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map_flutter_map/src/layers/marker_layer.dart' show markerKey;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' as p;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

final transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

const paris = LatLng(48.8566, 2.3522);

const noBaseMapOptions = PlatformMapOptions(
  initialCamera: PlatformCamera(center: paris, zoom: 10),
  style: PlatformMapStyle.none,
);

PlatformMarker testMarker(
  String id,
  LatLng position, {
  double zIndex = 0,
  p.Offset anchor = const p.Offset(0.5, 1),
  Uint8List? png,
}) => PlatformMarker(
  id: id,
  position: position,
  icon: PlatformIcon(key: 'dot', bytes: png ?? transparentPng, logicalSize: const Size(20, 20), pixelRatio: 2),
  anchor: anchor,
  zIndex: zIndex,
);

Finder findMarker(String id) => find.byKey(markerKey(id));

/// The ids of the drawn markers in paint order, once per world copy.
List<String> drawnMarkerIds(WidgetTester tester) => [
  for (final widget in tester.widgetList(find.byWidgetPredicate((w) => w is KeyedSubtree)))
    if (widget.key case ValueKey<(String, String)>(value: ('marker', final id))) id,
];
