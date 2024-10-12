import MapKit

/// Every overlay of a view lives in one ordered list on `.aboveRoads`, so polylines, polygons, circles and tile
/// layers share a single zIndex order. Equal zIndex keeps insertion order.
@MainActor
final class OverlayStack {
  private struct Entry {
    let zIndex: Double
    let overlay: MKOverlay
  }

  private weak var mapView: MKMapView?
  private var entries: [Entry] = []
  private var renderers: [ObjectIdentifier: MKOverlayRenderer] = [:]

  init(mapView: MKMapView) {
    self.mapView = mapView
  }

  func insert(_ overlay: MKOverlay, zIndex: Double, renderer: MKOverlayRenderer) {
    renderers[ObjectIdentifier(overlay)] = renderer
    let index = entries.firstIndex { $0.zIndex > zIndex } ?? entries.count
    entries.insert(Entry(zIndex: zIndex, overlay: overlay), at: index)
    mapView?.insertOverlay(overlay, at: index, level: .aboveRoads)
  }

  func remove(_ overlay: MKOverlay) {
    let id = ObjectIdentifier(overlay)
    renderers[id] = nil
    entries.removeAll { ObjectIdentifier($0.overlay) == id }
    mapView?.removeOverlay(overlay)
  }

  /// Bottom to top.
  var ordered: [(overlay: MKOverlay, renderer: MKOverlayRenderer)] {
    entries.compactMap { entry in renderers[ObjectIdentifier(entry.overlay)].map { (entry.overlay, $0) } }
  }

  func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
    renderers[ObjectIdentifier(overlay)]
  }

  func removeAll() {
    mapView?.removeOverlays(entries.map(\.overlay))
    entries.removeAll()
    renderers.removeAll()
  }
}

/// A change of style alone restyles the existing renderer; a change of geometry or zIndex adds the new overlay before
/// removing the old one, so MapKit never draws a frame without the shape.
@MainActor
final class OverlayController {
  private struct Line {
    var source: PPolyline
    let main: MKPolyline
    let mainRenderer: MKPolylineRenderer
    let border: (overlay: MKPolyline, renderer: MKPolylineRenderer)?
  }

  private struct Shape<Overlay: MKOverlay, Renderer: MKOverlayPathRenderer, Source> {
    var source: Source
    let overlay: Overlay
    let renderer: Renderer
  }

  private let stack: OverlayStack
  private var lines: [String: Line] = [:]
  private var polygons: [String: Shape<MKPolygon, MKPolygonRenderer, PPolygon>] = [:]
  private var circles: [String: Shape<MKCircle, MKCircleRenderer, PCircle>] = [:]

  init(stack: OverlayStack) {
    self.stack = stack
  }

  func updatePolylines(added: [PPolyline], changed: [PPolyline], removedIds: [String]) {
    removedIds.forEach(removeLine)
    for polyline in added + changed {
      if var line = lines[polyline.id], Self.sameGeometry(line.source, polyline) {
        line.source = polyline
        lines[polyline.id] = line
        style(line.mainRenderer, polyline, color: polyline.colorArgb, width: polyline.width)
        if let border = line.border {
          style(border.renderer, polyline, color: polyline.borderColorArgb, width: polyline.width + polyline.borderWidth)
        }
        continue
      }
      let previous = lines[polyline.id]
      addLine(polyline)
      if let previous { remove(previous) }
    }
  }

  func updatePolygons(added: [PPolygon], changed: [PPolygon], removedIds: [String]) {
    removedIds.forEach(removePolygon)
    for polygon in added + changed {
      if var shape = polygons[polygon.id], shape.source.points == polygon.points, shape.source.holes == polygon.holes,
        shape.source.zIndex == polygon.zIndex
      {
        shape.source = polygon
        polygons[polygon.id] = shape
        style(shape.renderer, fill: polygon.fillColorArgb, stroke: polygon.strokeColorArgb, width: polygon.strokeWidth)
        continue
      }
      let previous = polygons[polygon.id]
      addPolygon(polygon)
      if let previous { stack.remove(previous.overlay) }
    }
  }

  func updateCircles(added: [PCircle], changed: [PCircle], removedIds: [String]) {
    removedIds.forEach(removeCircle)
    for circle in added + changed {
      if var shape = circles[circle.id], shape.source.center == circle.center,
        shape.source.radiusMeters == circle.radiusMeters, shape.source.zIndex == circle.zIndex
      {
        shape.source = circle
        circles[circle.id] = shape
        style(shape.renderer, fill: circle.fillColorArgb, stroke: circle.strokeColorArgb, width: circle.strokeWidth)
        continue
      }
      let previous = circles[circle.id]
      addCircle(circle)
      if let previous { stack.remove(previous.overlay) }
    }
  }

  func removeAll() {
    lines.keys.forEach(removeLine)
    polygons.keys.forEach(removePolygon)
    circles.keys.forEach(removeCircle)
  }

  private static func sameGeometry(_ a: PPolyline, _ b: PPolyline) -> Bool {
    a.points == b.points && a.geodesic == b.geodesic && a.zIndex == b.zIndex && (a.borderWidth > 0) == (b.borderWidth > 0)
  }

  private func addLine(_ polyline: PPolyline) {
    var border: (MKPolyline, MKPolylineRenderer)?
    if polyline.borderWidth > 0 {
      let overlay = makePolyline(polyline)
      let renderer = MKPolylineRenderer(polyline: overlay)
      style(renderer, polyline, color: polyline.borderColorArgb, width: polyline.width + polyline.borderWidth)
      stack.insert(overlay, zIndex: polyline.zIndex - 0.5, renderer: renderer)
      border = (overlay, renderer)
    }
    let main = makePolyline(polyline)
    let renderer = MKPolylineRenderer(polyline: main)
    style(renderer, polyline, color: polyline.colorArgb, width: polyline.width)
    stack.insert(main, zIndex: polyline.zIndex, renderer: renderer)
    lines[polyline.id] = Line(source: polyline, main: main, mainRenderer: renderer, border: border)
  }

  private func makePolyline(_ polyline: PPolyline) -> MKPolyline {
    var coordinates = polyline.points.map(\.coordinate)
    return polyline.geodesic
      ? MKGeodesicPolyline(coordinates: &coordinates, count: coordinates.count)
      : MKPolyline(coordinates: &coordinates, count: coordinates.count)
  }

  private func style(_ renderer: MKPolylineRenderer, _ polyline: PPolyline, color: Int64, width: Double) {
    renderer.strokeColor = platformColor(argb: color)
    renderer.lineWidth = CGFloat(width)
    renderer.lineCap = polyline.cap.lineCap
    renderer.lineJoin = polyline.join.lineJoin
    if let dashes = polyline.dashPattern, !dashes.isEmpty {
      let even = dashes.count % 2 == 0 ? dashes : dashes + dashes
      renderer.lineDashPattern = even.map { NSNumber(value: $0) }
    } else {
      renderer.lineDashPattern = nil
    }
    renderer.setNeedsDisplay()
  }

  private func style(_ renderer: MKOverlayPathRenderer, fill: Int64, stroke: Int64, width: Double) {
    renderer.fillColor = platformColor(argb: fill)
    renderer.strokeColor = platformColor(argb: stroke)
    renderer.lineWidth = CGFloat(width)
    renderer.setNeedsDisplay()
  }

  private func removeLine(_ id: String) {
    guard let line = lines.removeValue(forKey: id) else { return }
    remove(line)
  }

  private func remove(_ line: Line) {
    stack.remove(line.main)
    if let border = line.border { stack.remove(border.overlay) }
  }

  private func addPolygon(_ polygon: PPolygon) {
    var coordinates = polygon.points.map(\.coordinate)
    let holes = polygon.holes.map { hole -> MKPolygon in
      var points = hole.map(\.coordinate)
      return MKPolygon(coordinates: &points, count: points.count)
    }
    let overlay = MKPolygon(coordinates: &coordinates, count: coordinates.count, interiorPolygons: holes)
    let renderer = MKPolygonRenderer(polygon: overlay)
    style(renderer, fill: polygon.fillColorArgb, stroke: polygon.strokeColorArgb, width: polygon.strokeWidth)
    stack.insert(overlay, zIndex: polygon.zIndex, renderer: renderer)
    polygons[polygon.id] = Shape(source: polygon, overlay: overlay, renderer: renderer)
  }

  private func removePolygon(_ id: String) {
    guard let shape = polygons.removeValue(forKey: id) else { return }
    stack.remove(shape.overlay)
  }

  private func addCircle(_ circle: PCircle) {
    let overlay = MKCircle(center: circle.center.coordinate, radius: circle.radiusMeters)
    let renderer = MKCircleRenderer(circle: overlay)
    style(renderer, fill: circle.fillColorArgb, stroke: circle.strokeColorArgb, width: circle.strokeWidth)
    stack.insert(overlay, zIndex: circle.zIndex, renderer: renderer)
    circles[circle.id] = Shape(source: circle, overlay: overlay, renderer: renderer)
  }

  private func removeCircle(_ id: String) {
    guard let shape = circles.removeValue(forKey: id) else { return }
    stack.remove(shape.overlay)
  }
}
