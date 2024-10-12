import CoreGraphics
import Foundation
import MapKit

/// Web Mercator with 256-point tiles, expressed in MapKit map points (`MKMapSize.world` is 2^28 map points wide).
enum CameraMath {
  static let tileSize = 256.0

  static var worldWidth: Double { MKMapSize.world.width }

  static func mapPointsPerPoint(zoom: Double) -> Double {
    worldWidth / (tileSize * pow(2, zoom))
  }

  static func zoom(mapPointsPerPoint: Double) -> Double {
    log2(worldWidth / mapPointsPerPoint / tileSize)
  }

  /// A screen vector (points, y down) as a map-point vector on a map whose top faces [heading] degrees.
  static func mapDelta(dx: Double, dy: Double, heading: Double, mapPointsPerPoint scale: Double) -> (x: Double, y: Double)
  {
    let radians = heading * .pi / 180
    return ((dx * cos(radians) - dy * sin(radians)) * scale, (dx * sin(radians) + dy * cos(radians)) * scale)
  }

  static func wrap(_ point: MKMapPoint) -> MKMapPoint {
    let world = worldWidth
    var x = point.x.truncatingRemainder(dividingBy: world)
    if x < 0 { x += world }
    return MKMapPoint(x: x, y: min(max(point.y, 0), MKMapSize.world.height))
  }

  /// `b.x - a.x` along the shorter way around the antimeridian.
  static func shortestDx(from a: MKMapPoint, to b: MKMapPoint) -> Double {
    let world = worldWidth
    var dx = b.x - a.x
    if dx > world / 2 { dx -= world } else if dx < -world / 2 { dx += world }
    return dx
  }

  static func offset(_ point: MKMapPoint, by delta: (x: Double, y: Double)) -> MKMapPoint {
    wrap(MKMapPoint(x: point.x + delta.x, y: point.y + delta.y))
  }

  static func normalizedLongitude(_ longitude: Double) -> Double {
    var value = (longitude + 180).truncatingRemainder(dividingBy: 360)
    if value < 0 { value += 360 }
    return value - 180
  }

  /// Fits [bounds] into the view minus the map padding and the fit padding, as in FitBoundsSolver.kt: the box is
  /// projected onto the screen axes of a map rotated by [bearing]. Returns the camera target (center of the padded
  /// area) and the zoom.
  static func fitBounds(
    _ bounds: PLatLngBounds,
    fitPadding: PEdgeInsets,
    mapPadding: PEdgeInsets,
    viewSize: CGSize,
    maxZoom: Double?,
    zoomRange: ClosedRange<Double>,
    bearing: Double
  ) -> (center: CLLocationCoordinate2D, zoom: Double) {
    let boxWidth = max(
      Double(viewSize.width) - mapPadding.left - mapPadding.right - fitPadding.left - fitPadding.right, 1)
    let boxHeight = max(
      Double(viewSize.height) - mapPadding.top - mapPadding.bottom - fitPadding.top - fitPadding.bottom, 1)

    let southWest = MKMapPoint(clamped(bounds.southWest.coordinate))
    var northEast = MKMapPoint(clamped(bounds.northEast.coordinate))
    if northEast.x < southWest.x { northEast.x += worldWidth }
    let spanX = northEast.x - southWest.x
    let spanY = max(southWest.y - northEast.y, 0)

    let radians = bearing * .pi / 180
    let absCos = abs(cos(radians))
    let absSin = abs(sin(radians))
    let screenWidth = spanX * absCos + spanY * absSin
    let screenHeight = spanX * absSin + spanY * absCos
    let needed = max(screenWidth / boxWidth, screenHeight / boxHeight)
    var zoom = needed > 0 ? self.zoom(mapPointsPerPoint: needed) : (maxZoom ?? zoomRange.upperBound)
    if let maxZoom { zoom = min(zoom, maxZoom) }
    // The padding shift below is converted to map points at this zoom, so it must already be the zoom the map keeps.
    zoom = min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound)

    let center = MKMapPoint(x: (southWest.x + northEast.x) / 2, y: (southWest.y + northEast.y) / 2)
    let shift = mapDelta(
      dx: (fitPadding.right - fitPadding.left) / 2,
      dy: (fitPadding.bottom - fitPadding.top) / 2,
      heading: bearing,
      mapPointsPerPoint: mapPointsPerPoint(zoom: zoom)
    )
    return (offset(center, by: shift).coordinate, zoom)
  }

  static func clamped(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(
      latitude: min(max(coordinate.latitude, -85.05112878), 85.05112878),
      longitude: coordinate.longitude
    )
  }
}
