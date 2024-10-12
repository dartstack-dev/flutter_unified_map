import 'dart:typed_data';

import 'package:flutter/painting.dart' show Size;
import 'package:meta/meta.dart';

/// A rasterised marker image.
///
/// [bytes] is a PNG rendered at [pixelRatio]; the platform draws it at [logicalSize] logical pixels.
/// Equality is by [key] only, so diffs never compare bytes: the core guarantees one key per distinct image.
@immutable
class PlatformIcon {
  final String key;
  final Uint8List bytes;
  final Size logicalSize;
  final double pixelRatio;

  const PlatformIcon({required this.key, required this.bytes, required this.logicalSize, required this.pixelRatio});

  @override
  bool operator ==(Object other) => other is PlatformIcon && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'PlatformIcon($key, $logicalSize @${pixelRatio}x, ${bytes.length} bytes)';
}
