import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Straight-alpha RGBA pixels of a decoded image.
class RgbaImage {
  const RgbaImage(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;

  ui.Rect get bounds => ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

  /// Counts pixels inside [region] (physical pixels, clipped to the image) for which [test] holds.
  int count(bool Function(int r, int g, int b, int a) test, {ui.Rect? region}) {
    final area = (region ?? bounds).intersect(bounds);
    if (area.isEmpty) return 0;
    var n = 0;
    for (var y = area.top.floor(); y < area.bottom.ceil(); y++) {
      for (var x = area.left.floor(); x < area.right.ceil(); x++) {
        final i = (y * width + x) * 4;
        if (test(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])) n++;
      }
    }
    return n;
  }
}

Future<RgbaImage> decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    return RgbaImage(image.width, image.height, data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  } finally {
    image.dispose();
    codec.dispose();
  }
}

/// Opaque-enough pixels whose every channel is within [tolerance] of [color]'s.
int countPixelsNear(RgbaImage image, ui.Color color, {int tolerance = 40, ui.Rect? region}) {
  final argb = color.toARGB32();
  final r0 = (argb >> 16) & 0xFF;
  final g0 = (argb >> 8) & 0xFF;
  final b0 = argb & 0xFF;
  return image.count(
    (r, g, b, a) =>
        a >= 200 && (r - r0).abs() <= tolerance && (g - g0).abs() <= tolerance && (b - b0).abs() <= tolerance,
    region: region,
  );
}

/// Pixels whose hue (degrees) lies in [minHue, maxHue] with at least [minSaturation] and [minValue] (0..1).
/// A semi-transparent fill blended over a neutral base map keeps its hue, so this finds it whatever the
/// background lightness.
int countPixelsWithHue(
  RgbaImage image, {
  required double minHue,
  required double maxHue,
  double minSaturation = 0.25,
  double minValue = 0.4,
  ui.Rect? region,
}) => image.count((r, g, b, a) {
  if (a < 200) return false;
  final hsv = _hsv(r, g, b);
  return hsv.s >= minSaturation && hsv.v >= minValue && hsv.h >= minHue && hsv.h <= maxHue;
}, region: region);

({double h, double s, double v}) _hsv(int r, int g, int b) {
  final maxC = math.max(r, math.max(g, b));
  final minC = math.min(r, math.min(g, b));
  final delta = (maxC - minC).toDouble();
  final v = maxC / 255;
  final s = maxC == 0 ? 0.0 : delta / maxC;
  if (delta == 0) return (h: 0, s: s, v: v);
  double h;
  if (maxC == r) {
    h = 60 * (((g - b) / delta) % 6);
  } else if (maxC == g) {
    h = 60 * ((b - r) / delta + 2);
  } else {
    h = 60 * ((r - g) / delta + 4);
  }
  return (h: h < 0 ? h + 360 : h, s: s, v: v);
}
