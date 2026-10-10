import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

/// The data classes every `flutter_unified_map` backend speaks: `flutter_unified_map_android`
/// (Google Maps SDK), `flutter_unified_map_apple` (MapKit) and `flutter_unified_map_flutter_map`
/// implement `UnifiedMapsPlatform` and exchange these `Platform*` objects with the core.
void main() {
  final icon = PlatformIcon(key: 'pin', bytes: Uint8List(0), logicalSize: const Size(24, 24), pixelRatio: 1);
  assert(icon.key == 'pin');
  assert(const LatLng(48.85, 2.35).latitude > 48);
}
