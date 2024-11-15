import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

const paris = LatLng(48.8566, 2.3522);
const lyon = LatLng(45.7640, 4.8357);

const osmUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const userAgentPackageName = 'dev.alphabyte.flutter_unified_map_example';

enum Brand {
  aurora('Aurora', Color(0xFF0F766E)),
  vela('Vela', Color(0xFF4338CA)),
  ignis('Ignis', Color(0xFFC2410C)),
  noctua('Noctua', Color(0xFF9333EA));

  const Brand(this.label, this.color);

  final String label;
  final Color color;
}

@immutable
class Station {
  const Station({required this.id, required this.point, required this.brand});

  final String id;
  final LatLng point;
  final Brand brand;
}

const _hubs = [
  LatLng(48.86, 2.35),
  LatLng(51.51, -0.13),
  LatLng(52.52, 13.40),
  LatLng(40.42, -3.70),
  LatLng(41.90, 12.50),
  LatLng(45.46, 9.19),
  LatLng(48.14, 11.58),
  LatLng(50.85, 4.35),
  LatLng(52.37, 4.90),
  LatLng(48.21, 16.37),
  LatLng(50.08, 14.44),
  LatLng(52.23, 21.01),
  LatLng(47.50, 19.04),
  LatLng(41.39, 2.17),
  LatLng(45.76, 4.84),
  LatLng(43.30, 5.37),
  LatLng(53.55, 9.99),
  LatLng(50.94, 6.96),
  LatLng(47.38, 8.54),
  LatLng(38.72, -9.14),
  LatLng(55.68, 12.57),
  LatLng(59.33, 18.07),
  LatLng(44.43, 26.10),
  LatLng(37.98, 23.73),
];

/// Deterministic pseudo-random stations: three quarters clustered around large cities, the rest spread over
/// the continent, so every run (and every platform) shows the same map.
List<Station> generateStations({int count = 4000, int seed = 42}) {
  final random = math.Random(seed);
  double gaussian() {
    final u = 1 - random.nextDouble();
    final v = random.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  return List.generate(count, (i) {
    final LatLng point;
    if (random.nextDouble() < 0.75) {
      final hub = _hubs[random.nextInt(_hubs.length)];
      point = LatLng(hub.latitude + gaussian() * 0.6, hub.longitude + gaussian() * 0.9);
    } else {
      point = LatLng(37 + random.nextDouble() * 22, -8 + random.nextDouble() * 33);
    }
    return Station(
      id: 'ST-${(i + 1).toString().padLeft(4, '0')}',
      point: point,
      brand: Brand.values[random.nextInt(Brand.values.length)],
    );
  });
}

const route = [
  paris,
  LatLng(48.6290, 2.4410),
  LatLng(48.4047, 2.7016),
  LatLng(48.1975, 3.2830),
  LatLng(47.7982, 3.5673),
  LatLng(47.4900, 3.9080),
  LatLng(47.0260, 4.8400),
  LatLng(46.7806, 4.8530),
  LatLng(46.3069, 4.8287),
  LatLng(45.9898, 4.7186),
  lyon,
];

const detour = [LatLng(47.4900, 3.9080), LatLng(47.3220, 5.0415), LatLng(47.0260, 4.8400)];

const waypoints = [paris, LatLng(47.7982, 3.5673), LatLng(47.0260, 4.8400), lyon];

const parisZone = [
  LatLng(48.9020, 2.3200),
  LatLng(48.9000, 2.3950),
  LatLng(48.8700, 2.4140),
  LatLng(48.8350, 2.4130),
  LatLng(48.8160, 2.3600),
  LatLng(48.8250, 2.2900),
  LatLng(48.8620, 2.2550),
  LatLng(48.8850, 2.2800),
];

const lyonZone = [
  LatLng(45.7950, 4.8100),
  LatLng(45.7900, 4.8850),
  LatLng(45.7500, 4.9000),
  LatLng(45.7250, 4.8600),
  LatLng(45.7400, 4.8000),
];
