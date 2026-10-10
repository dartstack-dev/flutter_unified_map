import 'package:flutter/foundation.dart';
import 'package:flutter_unified_map_apple/flutter_unified_map_apple.dart';

/// The endorsed iOS and macOS implementation of `flutter_unified_map`: Apple MapKit (`MKMapView`)
/// in a platform view. The Flutter plugin registrant calls `UnifiedMapsApple`'s `registerWith` at
/// startup, so an app only adds its map and geolocation usage keys to `Info.plist` and uses
/// `UnifiedMap` from `flutter_unified_map`. Run the repository's top-level `example/` app on the
/// iOS simulator or macOS to see the map.
void main() => debugPrint('$UnifiedMapsApple is the endorsed Apple backend');
