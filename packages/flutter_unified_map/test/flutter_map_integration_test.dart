import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_flutter_map/flutter_unified_map_flutter_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show UnifiedMapsPlatform;

import 'support/harness.dart';

const _paris = LatLng(48.8566, 2.3522);
const _lyon = LatLng(45.764, 4.8357);

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _CameraProbe extends StatelessWidget {
  const _CameraProbe(this.seen);

  final List<MapCamera> seen;

  @override
  Widget build(BuildContext context) {
    seen.add(MapCamera.of(context));
    return const SizedBox.shrink();
  }
}

class _FlutterMapProbe extends StatelessWidget {
  const _FlutterMapProbe(this.seen);

  final List<fm.MapCamera> seen;

  @override
  Widget build(BuildContext context) {
    seen.add(fm.MapCamera.of(context));
    return const SizedBox.shrink();
  }
}

void main() {
  setUp(() => UnifiedMapsPlatform.instance = UnifiedMapsFlutterMap());

  testWidgets('UnifiedMap on the real flutter_map backend renders layers and follows the controller', (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    final seen = <MapCamera>[];
    final flutterMapSeen = <fm.MapCamera>[];
    var ready = 0;

    await tester.pumpWidget(
      mapApp(
        controller: controller,
        options: MapOptions(
          initialCenter: _paris,
          initialZoom: 8,
          onMapReady: () => ready++,
          nativeParams: NativeParams(mapType: MapStyle.none),
        ),
        children: [
          const PolylineLayer(
            polylines: [
              Polyline(
                points: [_paris, _lyon],
                color: Color(0xFF1D4ED8),
                strokeWidth: 5,
                borderStrokeWidth: 2,
                borderColor: Color(0xFFFFFFFF),
              ),
            ],
          ),
          const MarkerLayer(
            markers: [
              Marker(point: _paris, iconKey: 'red', alignment: Alignment.topCenter, child: _Dot(Color(0xFFDC2626))),
              Marker(point: LatLng(48.9, 1.9), iconKey: 'red', child: _Dot(Color(0xFFDC2626))),
            ],
          ),
          FlutterMapLayer(child: _FlutterMapProbe(flutterMapSeen)),
          _CameraProbe(seen),
        ],
      ),
    );
    await settle(tester);

    expect(ready, 1);
    final polylines = tester.widget<fm.PolylineLayer>(find.byType(fm.PolylineLayer)).polylines;
    expect(polylines, hasLength(1));
    expect(polylines.single.points, [_paris, _lyon]);
    expect(polylines.single.borderStrokeWidth, 2);

    final markers = tester.widget<fm.MarkerLayer>(find.byType(fm.MarkerLayer)).markers;
    expect(markers, hasLength(2));
    expect(markers.where((m) => m.point == _paris).single.alignment, Alignment.topCenter);
    expect(find.descendant(of: find.byType(fm.MarkerLayer), matching: find.byType(Image)), findsNWidgets(2));
    expect(
      find.descendant(of: find.byType(fm.FlutterMap), matching: find.byType(_FlutterMapProbe)),
      findsOneWidget,
      reason: 'FlutterMapLayer children are drawn inside the FlutterMap',
    );
    expect(flutterMapSeen.last.zoom, closeTo(8, 1e-9));
    expect(seen.last.center.latitude, closeTo(_paris.latitude, 1e-6));
    expect(seen.last.zoom, closeTo(8, 1e-9));

    final moved = controller.move(_lyon, 11);
    await settle(tester);

    expect(moved, isTrue);
    expect(controller.camera.center.latitude, closeTo(_lyon.latitude, 1e-6));
    expect(controller.camera.center.longitude, closeTo(_lyon.longitude, 1e-6));
    expect(controller.camera.zoom, closeTo(11, 1e-9));
    expect(seen.last.center.latitude, closeTo(_lyon.latitude, 1e-6));
    expect(seen.last.zoom, closeTo(11, 1e-9));
    final flutterMapCamera = fm.MapCamera.of(tester.element(find.byType(fm.MarkerLayer)));
    expect(flutterMapCamera.center.latitude, closeTo(_lyon.latitude, 1e-6));
    expect(flutterMapCamera.zoom, closeTo(11, 1e-9));
    expect(flutterMapSeen.last.zoom, closeTo(11, 1e-9));

    controller.rotate(30);
    await settle(tester);

    expect(seen.last.rotation, closeTo(30, 1e-6));
    expect(fm.MapCamera.of(tester.element(find.byType(fm.MarkerLayer))).rotation % 360, closeTo(30, 1e-6));

    await tester.pumpWidget(const SizedBox());
  });
}
