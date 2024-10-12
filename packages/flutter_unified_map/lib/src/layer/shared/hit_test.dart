import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import '../../map/camera/camera_math.dart';
import '../../map/camera/map_camera.dart';
import '../circle_layer/circle_marker.dart';
import '../polygon_layer/polygon.dart';
import '../polyline_layer/polyline.dart';
import 'layer_hit_result.dart';
import 'map_layer_state.dart';

/// Registers [hits] as the hit tester of [layer] when it has a [notifier]: on every map tap and long press the
/// notifier gets the hit values under the finger, or null when nothing was hit.
void registerHitTester<R extends Object>(
  MapLayerState layer,
  LayerHitNotifier<R>? notifier,
  List<R?> Function(MapCamera camera, Offset point) hits,
) {
  layer.host.registry.setHitTester(
    layer.layerId,
    notifier == null
        ? null
        : (camera, position, point) {
            final values = hits(camera, point);
            notifier.value = values.isEmpty
                ? null
                : LayerHitResult<R>(hitValues: values.whereType<R>().toList(), coordinate: position, point: point);
          },
  );
}

/// Polylines under [point], top-most first: the tap is within half the stroke and border width of a segment, or
/// within [minimumHitbox] of it for thin lines (as flutter_map).
List<Polyline<R>> hitPolylines<R extends Object>(
  MapCamera camera,
  List<Polyline<R>> polylines,
  Offset point,
  double minimumHitbox,
) {
  final hits = <Polyline<R>>[];
  for (final polyline in polylines.reversed) {
    if (polyline.points.isEmpty) continue;
    final tolerance = math.max(polyline.strokeWidth / 2 + polyline.borderStrokeWidth / 2, minimumHitbox);
    final screen = [for (final p in polyline.points) _onScreen(camera, p)];
    if (screen.length == 1) {
      if ((screen.first - point).distance <= tolerance) hits.add(polyline);
      continue;
    }
    for (var i = 0; i < screen.length - 1; i++) {
      if (_distanceToSegment(point, screen[i], screen[i + 1]) <= tolerance) {
        hits.add(polyline);
        break;
      }
    }
  }
  return hits;
}

/// Polygons containing [point] (outside their holes), top-most first.
List<Polygon<R>> hitPolygons<R extends Object>(MapCamera camera, List<Polygon<R>> polygons, Offset point) {
  final hits = <Polygon<R>>[];
  for (final polygon in polygons.reversed) {
    if (polygon.points.length < 3) continue;
    if (!_contains(camera, polygon.points, point)) continue;
    final holes = polygon.holePointsList ?? const [];
    if (holes.any((hole) => hole.length >= 3 && _contains(camera, hole, point))) continue;
    hits.add(polygon);
  }
  return hits;
}

/// Circles whose on-screen disc contains [point], top-most first.
List<CircleMarker<R>> hitCircles<R extends Object>(MapCamera camera, List<CircleMarker<R>> circles, Offset point) {
  final hits = <CircleMarker<R>>[];
  for (final circle in circles.reversed) {
    final radius = circle.useRadiusInMeter
        ? circle.radius / camera.metersPerPixel(circle.point.latitude)
        : circle.radius;
    if ((_onScreen(camera, circle.point) - point).distance <= radius + circle.borderStrokeWidth / 2) {
      hits.add(circle);
    }
  }
  return hits;
}

/// Screen position of the copy of [latLng] nearest the view center: native maps repeat the world horizontally, so a
/// shape across the antimeridian is drawn there.
Offset _onScreen(MapCamera camera, LatLng latLng) {
  final worldWidth = camera.getWorldWidthAtZoom();
  var delta = camera.projectAtZoom(latLng) - camera.projectAtZoom(camera.center);
  final shift = (delta.dx / worldWidth).roundToDouble();
  if (shift != 0) delta = delta.translate(-shift * worldWidth, 0);
  return rotateOffset(delta, camera.rotationRad) + camera.nonRotatedSize.center(Offset.zero);
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (p - a).distance;
  final ap = p - a;
  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

bool _contains(MapCamera camera, List<LatLng> ring, Offset point) {
  final screen = [for (final p in ring) _onScreen(camera, p)];
  var inside = false;
  for (var i = 0, j = screen.length - 1; i < screen.length; j = i++) {
    final a = screen[i];
    final b = screen[j];
    if ((a.dy > point.dy) != (b.dy > point.dy) && point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}
