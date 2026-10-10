import 'package:flutter/foundation.dart';
import 'package:flutter_unified_map_android/flutter_unified_map_android.dart';

/// The endorsed Android implementation of `flutter_unified_map`: the Google Maps SDK drawn in
/// a platform view. The Flutter plugin registrant calls `UnifiedMapsAndroid`'s `registerWith` at
/// startup, so an app only adds its API key to `AndroidManifest.xml` and uses `UnifiedMap` from
/// `flutter_unified_map`. Run the repository's top-level `example/` app on an Android device to
/// see the map.
void main() => debugPrint('$UnifiedMapsAndroid is the endorsed Android backend');
