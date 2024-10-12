import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

import 'support/fake_platform.dart';
import 'support/harness.dart';

void main() {
  late FakeUnifiedMapsPlatform fake;

  setUp(() => fake = installFakePlatform());

  testWidgets('pushes a changed circle radius to the platform', (tester) async {
    await tester.pumpWidget(
      mapApp(
        children: [
          CircleLayer(
            circles: const [
              CircleMarker(point: LatLng(10, 20), radius: 100, useRadiusInMeter: true, key: ValueKey('acc')),
            ],
          ),
        ],
      ),
    );
    fake.ready();
    await settle(tester);
    expect(fake.circles.values.single.radiusMeters, 100);

    await tester.pumpWidget(
      mapApp(
        children: [
          CircleLayer(
            circles: const [
              CircleMarker(point: LatLng(10, 20), radius: 250, useRadiusInMeter: true, key: ValueKey('acc')),
            ],
          ),
        ],
      ),
    );
    await settle(tester);
    expect(fake.circles.values.single.radiusMeters, 250);
  });
}
