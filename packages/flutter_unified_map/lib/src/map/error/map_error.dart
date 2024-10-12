import 'package:flutter/foundation.dart';

/// Why the map cannot show its base map.
enum MapErrorCode {
  /// No API key is configured for a platform that needs one (Google Maps on Android).
  apiKeyMissing,

  /// The platform's map services are missing or outdated (Google Play services on Android).
  servicesUnavailable,

  /// The map did not load in time. On Google Maps this is how a rejected API key or a missing network shows up.
  loadTimeout,

  /// The platform reported a load failure; [MapError.message] has its description.
  loadFailed,

  /// `MapOptions.crs` is not Web Mercator (`Epsg3857`), which is the only projection of native maps. The map stays
  /// Web Mercator. Reported by the core on native backends only.
  unsupportedCrs,

  unknown,
}

/// A map error as reported by the platform. [message] is the platform's own description (key name, native
/// error text). [title] and [hint] are English guidance for developers, used by the default [MapErrorView].
@immutable
class MapError {
  final MapErrorCode code;
  final String message;

  const MapError(this.code, this.message);

  String get title => switch (code) {
    MapErrorCode.apiKeyMissing => 'Map not configured: API key missing',
    MapErrorCode.servicesUnavailable => 'Map services unavailable',
    MapErrorCode.loadTimeout => 'The map did not load',
    MapErrorCode.loadFailed => 'The map failed to load',
    MapErrorCode.unsupportedCrs => 'Projection not supported',
    MapErrorCode.unknown => 'Map error',
  };

  String get hint => switch (code) {
    MapErrorCode.apiKeyMissing =>
      'Add <meta-data android:name="com.google.android.geo.API_KEY" android:value="…"/> to the <application> of '
          'android/app/src/main/AndroidManifest.xml.',
    MapErrorCode.servicesUnavailable =>
      'Google Maps needs Google Play services. Install or update them, or use a device or emulator image with '
          'Google APIs.',
    MapErrorCode.loadTimeout =>
      'Check the API key (Maps SDK for Android enabled in Google Cloud, billing account linked, app restriction '
          'matching the package name and SHA-1) and the network connection.',
    MapErrorCode.loadFailed => 'Check the network connection.',
    MapErrorCode.unsupportedCrs =>
      'Native maps (Google Maps, MapKit) only use Web Mercator: use MapOptions.crs = Epsg3857(), or a backend '
          'drawn with flutter_map.',
    MapErrorCode.unknown => '',
  };

  /// Errors that a later successful load clears.
  bool get isLoadError => code == MapErrorCode.loadTimeout || code == MapErrorCode.loadFailed;

  @override
  bool operator ==(Object other) => other is MapError && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'MapError($code, $message)';
}
