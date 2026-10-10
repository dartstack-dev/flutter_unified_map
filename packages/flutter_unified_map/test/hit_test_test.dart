import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/src/layer/shared/hit_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' show PlatformCamera;

import 'support/harness.dart';

void main() {
  final camera = MapCamera(
    crs: const Epsg3857(),
    rotation: 0,
    center: LatLng(0, 0),
    zoom: 10,
    nonRotatedSize: Size(800, 600),
  );
  LatLng at(double x, double y) => camera.screenOffsetToLatLng(Offset(x, y));

  group('polylines', () {
    final line = Polyline<String>(points: [at(100, 100), at(300, 100)], strokeWidth: 8, hitValue: 'line');

    test('hit within the minimum hitbox of a thin line, as flutter_map', () {
      expect(hitPolylines(camera, [line], const Offset(200, 100), 10), [line]);
      expect(hitPolylines(camera, [line], const Offset(200, 109.9), 10), [line]);
      expect(hitPolylines(camera, [line], const Offset(200, 110.1), 10), isEmpty);
      expect(hitPolylines(camera, [line], const Offset(309, 100), 10), [line], reason: 'near the end cap');
      expect(hitPolylines(camera, [line], const Offset(311, 100), 10), isEmpty);
    });

    test('hit within half the stroke and border of a wide line', () {
      final wide = Polyline<String>(points: line.points, strokeWidth: 16, borderStrokeWidth: 8, hitValue: 'wide');
      expect(hitPolylines(camera, [wide], const Offset(200, 111.9), 10), [wide]);
      expect(hitPolylines(camera, [wide], const Offset(200, 112.1), 10), isEmpty);
    });

    test('a line across the antimeridian is hit where the map draws it', () {
      final east = MapCamera(
        crs: const Epsg3857(),
        rotation: 0,
        center: LatLng(0, 179.9),
        zoom: 10,
        nonRotatedSize: Size(800, 600),
      );
      final crossing = Polyline<String>(points: const [LatLng(0, 179.8), LatLng(0, -179.9)], hitValue: 'x');
      final onScreen = east.latLngToScreenOffset(const LatLng(0, 179.95));
      expect(hitPolylines(east, [crossing], onScreen, 10), [crossing]);
    });

    test('top-most first', () {
      final other = Polyline<String>(points: [at(200, 0), at(200, 200)], hitValue: 'other');
      expect(hitPolylines(camera, [line, other], const Offset(200, 100), 10), [other, line]);
    });
  });

  group('polygons', () {
    final square = Polygon<String>(
      points: [at(100, 100), at(300, 100), at(300, 300), at(100, 300)],
      holePointsList: [
        [at(150, 150), at(250, 150), at(250, 250), at(150, 250)],
      ],
      hitValue: 'square',
    );

    test('inside the outer ring and outside the holes', () {
      expect(hitPolygons(camera, [square], const Offset(120, 120)), [square]);
      expect(hitPolygons(camera, [square], const Offset(200, 200)), isEmpty);
      expect(hitPolygons(camera, [square], const Offset(350, 200)), isEmpty);
    });
  });

  group('circles', () {
    test('pixel and meter radii', () {
      final pixels = CircleMarker<String>(point: at(400, 300), radius: 20, hitValue: 'px');
      final meters = CircleMarker<String>(
        point: at(400, 300),
        radius: 50 * camera.metersPerPixel(at(400, 300).latitude),
        useRadiusInMeter: true,
        hitValue: 'm',
      );
      expect(hitCircles(camera, [pixels, meters], const Offset(415, 300)), [meters, pixels]);
      expect(hitCircles(camera, [pixels, meters], const Offset(440, 300)), [meters]);
      expect(hitCircles(camera, [pixels, meters], const Offset(460, 300)), isEmpty);
    });
  });

  testWidgets('map taps update the layers hit notifiers', (tester) async {
    final fake = installFakePlatform();
    final polylineHits = LayerHitNotifier<String>(null);
    final polygonHits = LayerHitNotifier<String>(null);
    final circleHits = LayerHitNotifier<String>(null);
    await tester.pumpWidget(
      mapApp(
        children: [
          PolygonLayer(
            hitNotifier: polygonHits,
            polygons: [
              Polygon(points: [at(100, 100), at(300, 100), at(300, 300), at(100, 300)], hitValue: 'area'),
            ],
          ),
          PolylineLayer(
            hitNotifier: polylineHits,
            polylines: [
              Polyline(points: [at(100, 200), at(700, 200)], strokeWidth: 4, hitValue: 'road'),
            ],
          ),
          CircleLayer(
            hitNotifier: circleHits,
            circles: [CircleMarker(point: at(600, 400), radius: 15, hitValue: 'dot')],
          ),
        ],
      ),
    );
    fake.ready(camera: const PlatformCamera(center: LatLng(0, 0), zoom: 10));
    await tester.pump();

    fake.tap(at(200, 205), const Offset(200, 205));
    expect(polylineHits.value!.hitValues, ['road']);
    expect(polylineHits.value!.point, const Offset(200, 205));
    expect(polygonHits.value!.hitValues, ['area']);
    expect(circleHits.value, isNull);

    fake.tap(at(605, 405), const Offset(605, 405));
    expect(circleHits.value!.hitValues, ['dot']);
    expect(polylineHits.value, isNull);
    expect(polygonHits.value, isNull);
  });
}
