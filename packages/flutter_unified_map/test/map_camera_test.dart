import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show Distance;
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map/src/map/camera/camera_math.dart';

void main() {
  group('MapCamera', () {
    final camera = MapCamera(
      crs: const Epsg3857(),
      rotation: 0,
      center: LatLng(48.8566, 2.3522),
      zoom: 12,
      nonRotatedSize: Size(800, 600),
    );

    test('projects the center to the middle of the view', () {
      final p = camera.latLngToScreenOffset(camera.center);
      expect(p.dx, closeTo(400, 1e-9));
      expect(p.dy, closeTo(300, 1e-9));
    });

    test('screen and geographic coordinates round-trip, rotated or not', () {
      for (final rotation in [0.0, 30.0, -120.0]) {
        final rotated = camera.copyWith(rotation: rotation);
        for (final offset in const [Offset(0, 0), Offset(800, 600), Offset(123.4, 567.8)]) {
          final back = rotated.latLngToScreenOffset(rotated.screenOffsetToLatLng(offset));
          expect(back.dx, closeTo(offset.dx, 1e-6));
          expect(back.dy, closeTo(offset.dy, 1e-6));
        }
      }
    });

    test('project and unproject are inverse at any zoom', () {
      const point = LatLng(-33.86, 151.21);
      for (final zoom in [0.0, 5.5, 18.0]) {
        final back = camera.unprojectAtZoom(camera.projectAtZoom(point, zoom), zoom);
        expect(back.latitude, closeTo(point.latitude, 1e-9));
        expect(back.longitude, closeTo(point.longitude, 1e-9));
      }
      expect(camera.projectAtZoom(const LatLng(0, 0), 0), const Offset(128, 128));
    });

    test('north is up and east is right without rotation', () {
      final north = camera.latLngToScreenOffset(const LatLng(48.9, 2.3522));
      final east = camera.latLngToScreenOffset(const LatLng(48.8566, 2.4));
      expect(north.dy, lessThan(300));
      expect(east.dx, greaterThan(400));
      final rotated = camera.copyWith(rotation: 90).latLngToScreenOffset(const LatLng(48.9, 2.3522));
      expect(rotated.dx, greaterThan(400), reason: 'rotating the map 90° clockwise puts north on the right');
    });

    test('visibleBounds covers the view and grows with rotation', () {
      final bounds = camera.visibleBounds;
      expect(bounds.contains(camera.center), isTrue);
      expect(bounds.contains(camera.screenOffsetToLatLng(const Offset(1, 1))), isTrue);
      expect(bounds.contains(camera.screenOffsetToLatLng(const Offset(799, 599))), isTrue);
      final width = 800 * camera.metersPerPixel();
      expect(const Distance().distance(bounds.southWest, bounds.southEast), closeTo(width, width * 0.01));
      final rotated = camera.copyWith(rotation: 45).visibleBounds;
      expect(rotated.containsBounds(LatLngBounds(bounds.center, bounds.center)), isTrue);
      expect(rotated.north - rotated.south, greaterThan(bounds.north - bounds.south));
      expect(camera.copyWith(rotation: 90).size, const Size(600, 800));
    });

    test('visibleBounds stops at the antimeridian, as flutter_map', () {
      final east = MapCamera(
        crs: const Epsg3857(),
        rotation: 0,
        center: LatLng(0, 179),
        zoom: 5,
        nonRotatedSize: Size(800, 600),
      );
      expect(east.visibleBounds.east, 180);
      expect(east.visibleBounds.west, lessThan(179));
      final world = MapCamera(
        crs: const Epsg3857(),
        rotation: 0,
        center: LatLng(0, 0),
        zoom: 0,
        nonRotatedSize: Size(1000, 600),
      );
      expect((world.visibleBounds.west, world.visibleBounds.east), (-180.0, 180.0));
    });

    test('metersPerPixel halves per zoom level', () {
      expect(camera.copyWith(zoom: 13).metersPerPixel(), closeTo(camera.metersPerPixel() / 2, 1e-9));
      expect(camera.copyWith(zoom: 0).metersPerPixel(0), closeTo(2 * math.pi * 6378137 / 256, 0.01));
    });

    test('clampZoom honours min and max', () {
      final limited = camera.copyWith(minZoom: 3, maxZoom: 15);
      expect(limited.clampZoom(1), 3);
      expect(limited.clampZoom(20), 15);
      expect(camera.clampZoom(25), 25);
    });
  });

  group('LatLngBounds', () {
    test('is built from points and corners in any order', () {
      final bounds = LatLngBounds(const LatLng(10, 20), const LatLng(-5, -3));
      expect((bounds.north, bounds.south, bounds.east, bounds.west), (10.0, -5.0, 20.0, -3.0));
      expect(bounds, LatLngBounds.fromPoints(const [LatLng(-5, 20), LatLng(10, -3), LatLng(0, 0)]));
    });

    test('contains, overlaps and extends', () {
      final bounds = LatLngBounds(const LatLng(0, 0), const LatLng(10, 10));
      expect(bounds.contains(const LatLng(5, 5)), isTrue);
      expect(bounds.contains(const LatLng(11, 5)), isFalse);
      expect(bounds.isOverlapping(LatLngBounds(const LatLng(9, 9), const LatLng(20, 20))), isTrue);
      expect(bounds.isOverlapping(LatLngBounds(const LatLng(11, 11), const LatLng(20, 20))), isFalse);
      expect(bounds.containsBounds(LatLngBounds(const LatLng(1, 1), const LatLng(2, 2))), isTrue);
      bounds.extend(const LatLng(-1, 12));
      expect((bounds.south, bounds.east), (-1.0, 12.0));
      bounds.extendBounds(LatLngBounds(const LatLng(20, -20), const LatLng(21, -19)));
      expect((bounds.north, bounds.west), (21.0, -20.0));
    });

    test('centers', () {
      final bounds = LatLngBounds(const LatLng(0, 0), const LatLng(10, 20));
      expect(bounds.simpleCenter, const LatLng(5, 10));
      expect(bounds.center.latitude, closeTo(5, 0.2));
      expect(bounds.center.longitude, closeTo(10, 0.2));
    });
  });

  group('solveCameraFit', () {
    const points = [LatLng(45, 4), LatLng(45.0004, 4.0004)];
    const middlePoint = LatLng(45.0002, 4.0002);

    test('keeps the map maxZoom when the fit allows more, and centers the padded area for that zoom', () {
      final camera = MapCamera(
        crs: const Epsg3857(),
        center: LatLng(45, 4),
        zoom: 10,
        rotation: 30,
        maxZoom: 16,
        nonRotatedSize: Size(400, 800),
      );
      final fit = CameraFit.coordinates(coordinates: points, maxZoom: 18, padding: const EdgeInsets.only(bottom: 300));
      final solved = solveCameraFit(camera, fit);
      expect(solved.zoom, 16);
      final fitted = camera.copyWith(center: solved.center, zoom: solved.zoom);
      final middle = fitted.latLngToScreenOffset(middlePoint);
      expect(middle.dy, closeTo((800 - 300) / 2, 1), reason: 'centered in the area above the padding');
    });

    test('padding larger than the view fits the whole view, centered', () {
      final camera = MapCamera(
        crs: const Epsg3857(),
        center: LatLng(45, 4),
        zoom: 10,
        rotation: 10,
        nonRotatedSize: Size(400, 300),
      );
      final fit = CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.only(bottom: 320));
      final solved = solveCameraFit(camera, fit);
      final fitted = camera.copyWith(center: solved.center, zoom: solved.zoom);
      final middle = fitted.latLngToScreenOffset(middlePoint);
      expect(middle.dx, closeTo(200, 1));
      expect(middle.dy, closeTo(150, 1));
    });

    test('rotation stays continuous through north', () {
      expect(rotationFromBearing(30), 330);
      expect(rotationFromBearing(30, near: 0), -30);
      expect(rotationFromBearing(1, near: 359), 359);
      expect(rotationFromBearing(359, near: 359), 361);
      expect(rotationFromBearing(0, near: 720.5), 720);
    });
  });
}
