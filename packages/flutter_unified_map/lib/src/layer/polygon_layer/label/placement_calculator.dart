// Ported from flutter_map 8.3.2 (polygon label placement calculators), BSD-3-Clause, Copyright (c) 2018 the
// flutter_map authors.
import 'package:collection/collection.dart';
import 'package:dart_polylabel2/dart_polylabel2.dart' as dart_polylabel2;
import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';

import '../polygon.dart';

/// Where a polygon's label goes. Same API as flutter_map's.
@immutable
abstract interface class PolygonLabelPlacementCalculator {
  /// Mean of the points.
  @literal
  const factory PolygonLabelPlacementCalculator.simpleCentroid() = SimpleCentroidCalculator._;

  /// Mean of the points, unwrapped across the antimeridian.
  @literal
  const factory PolygonLabelPlacementCalculator.simpleMultiWorldCentroid() = SimpleMultiWorldCentroidCalculator._;

  /// Area centroid (the default).
  @literal
  const factory PolygonLabelPlacementCalculator.centroid() = CentroidCalculator._;

  /// Pole of inaccessibility (the point inside the polygon farthest from its edges), to [precision] degrees.
  const factory PolygonLabelPlacementCalculator.polylabel({double precision}) = PolylabelCalculator._;

  LatLng call(Polygon polygon);
}

class CentroidCalculator implements PolygonLabelPlacementCalculator {
  @literal
  const CentroidCalculator._();

  @override
  LatLng call(Polygon polygon) {
    final points = polygon.points;
    if (points.isEmpty) throw ArgumentError('Polygon must contain at least one point');
    if (points.length == 1) return points[0];
    double signedArea = 0;
    double centroidX = 0;
    double centroidY = 0;
    for (var i = 0; i < points.length - 1; i++) {
      final x0 = points[i].longitude;
      final y0 = points[i].latitude;
      final x1 = points[i + 1].longitude;
      final y1 = points[i + 1].latitude;
      final a = x0 * y1 - x1 * y0;
      signedArea += a;
      centroidX += (x0 + x1) * a;
      centroidY += (y0 + y1) * a;
    }
    final x0 = points.last.longitude;
    final y0 = points.last.latitude;
    final x1 = points.first.longitude;
    final y1 = points.first.latitude;
    final a = x0 * y1 - x1 * y0;
    signedArea += a;
    centroidX += (x0 + x1) * a;
    centroidY += (y0 + y1) * a;
    signedArea *= 0.5;
    centroidX /= 6 * signedArea;
    centroidY /= 6 * signedArea;
    if (signedArea == 0) {
      double sumX = 0;
      double sumY = 0;
      for (final point in points) {
        sumX += point.longitude;
        sumY += point.latitude;
      }
      return LatLng(sumY / points.length, sumX / points.length);
    }
    return LatLng(centroidY, centroidX);
  }
}

class SimpleCentroidCalculator implements PolygonLabelPlacementCalculator {
  @literal
  const SimpleCentroidCalculator._();

  @override
  LatLng call(Polygon polygon) =>
      LatLng(polygon.points.map((e) => e.latitude).average, polygon.points.map((e) => e.longitude).average);
}

class SimpleMultiWorldCentroidCalculator implements PolygonLabelPlacementCalculator {
  @literal
  const SimpleMultiWorldCentroidCalculator._();

  @override
  LatLng call(Polygon polygon) {
    if (polygon.points.isEmpty) throw ArgumentError('Polygon must contain at least one point');
    const halfWorld = 180;
    var count = 0;
    double sum = 0;
    late double lastLng;
    for (final point in polygon.points) {
      var lng = point.longitude;
      count++;
      if (count > 1) {
        if (lng - lastLng > halfWorld) {
          lng -= 2 * halfWorld;
        } else if (lng - lastLng < -halfWorld) {
          lng += 2 * halfWorld;
        }
      }
      lastLng = lng;
      sum += lastLng;
    }
    return LatLng(polygon.points.map((e) => e.latitude).average, sum / count);
  }
}

class PolylabelCalculator implements PolygonLabelPlacementCalculator {
  const PolylabelCalculator._({this.precision = 0.0001});

  final double precision;

  @override
  LatLng call(Polygon polygon) {
    final (point: (:x, :y), distance: _) = dart_polylabel2.polylabel([
      List<dart_polylabel2.Point>.generate(
        polygon.points.length,
        (i) => (x: polygon.points[i].latitude, y: polygon.points[i].longitude),
        growable: false,
      ),
    ], precision: precision);
    return LatLng(x, y);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PolylabelCalculator && precision == other.precision);

  @override
  int get hashCode => precision.hashCode;
}
