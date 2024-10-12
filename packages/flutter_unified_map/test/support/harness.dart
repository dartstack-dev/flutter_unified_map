import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map/plugin_api.dart' show IconCache;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show UnifiedMapsPlatform;

import 'fake_platform.dart';

FakeUnifiedMapsPlatform installFakePlatform() {
  final fake = FakeUnifiedMapsPlatform();
  UnifiedMapsPlatform.instance = fake;
  return fake;
}

Widget mapApp({MapController? controller, MapOptions options = const MapOptions(), List<Widget> children = const []}) =>
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600), devicePixelRatio: 2),
        child: UnifiedMap(mapController: controller, options: options, children: children),
      ),
    );

/// Lets off-screen rasterisation (real async engine work) and the per-frame flush run: pumps until no icon has been
/// rasterising for [quietRounds] rounds in a row, for at most [timeout] of real time.
Future<void> settle(WidgetTester tester, {int quietRounds = 3, Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  var quiet = 0;
  while (quiet < quietRounds && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 20));
    quiet = IconCache.rendersInFlight == 0 ? quiet + 1 : 0;
  }
}
