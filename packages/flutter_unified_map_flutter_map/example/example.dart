import 'package:flutter/foundation.dart';
import 'package:flutter_unified_map_flutter_map/flutter_unified_map_flutter_map.dart';

/// The endorsed implementation of `flutter_unified_map` for web, Windows and Linux (and the one
/// widget tests run against): the real `flutter_map` drawing OpenStreetMap-style tiles. Apps use
/// `UnifiedMap` from `flutter_unified_map` and never this package directly. Run the repository's
/// top-level `example/` app on Chrome to see the map.
void main() => debugPrint('$UnifiedMapsFlutterMap is the endorsed web and desktop backend');
