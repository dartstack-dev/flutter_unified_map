import MapKit

struct SnapshotMarker {
  let coordinate: CLLocationCoordinate2D
  let marker: PMarker
  let icon: MarkerIcon
  let alpha: CGFloat
}

struct SnapshotPath {
  let rings: [[CLLocationCoordinate2D]]
  let closed: Bool
  let fill: CGColor?
  let stroke: CGColor?
  let lineWidth: CGFloat
  let lineCap: CGLineCap
  let lineJoin: CGLineJoin
  let dash: [CGFloat]
  let alpha: CGFloat
}

final class SnapshotTiles {
  let overlay: MKTileOverlay
  let alpha: CGFloat
  let tiles: [(path: MKTileOverlayPath, rect: MKMapRect)]
  private let lock = NSLock()
  private var images: [Int: CGImage] = [:]

  init(overlay: MKTileOverlay, alpha: CGFloat, tiles: [(path: MKTileOverlayPath, rect: MKMapRect)]) {
    self.overlay = overlay
    self.alpha = alpha
    self.tiles = tiles
  }

  func store(_ image: CGImage, at index: Int) {
    lock.lock()
    images[index] = image
    lock.unlock()
  }

  func image(at index: Int) -> CGImage? {
    lock.lock()
    defer { lock.unlock() }
    return images[index]
  }
}

enum SnapshotLayer {
  case path(SnapshotPath)
  case tiles(SnapshotTiles)
}

/// What the live map shows, captured on the main thread so the snapshot can be composed once MapKit and the tile
/// servers answer. `background` replaces Apple's base map when the style is `none` or a tile layer replaces it.
/// Immutable once captured (tile images go through `SnapshotTiles`' lock), so it is composed off the main thread.
struct SnapshotScene: @unchecked Sendable {
  let background: CGColor?
  let layers: [SnapshotLayer]
  let markers: [SnapshotMarker]

  static let maxTilesPerLayer = 256
  static let circleSegments = 96

  /// Same z as MapKit would pick for the layer: Web Mercator zoom shifted by the tile size, capped at `maximumZ`.
  static func tiles(
    for overlay: MKTileOverlay, visible: MKMapRect, zoom: Double, contentScale: CGFloat
  ) -> [(path: MKTileOverlayPath, rect: MKMapRect)] {
    let tileSize = max(Double(overlay.tileSize.width), 1)
    var z = min(Int((zoom - log2(tileSize / CameraMath.tileSize)).rounded()), overlay.maximumZ)
    while z >= max(overlay.minimumZ, 0) {
      let count = 1 << min(z, 30)
      let span = CameraMath.worldWidth / Double(count)
      let firstX = Int((visible.minX / span).rounded(.down))
      let lastX = Int(((visible.maxX - 1e-9) / span).rounded(.down))
      let firstY = max(Int((visible.minY / span).rounded(.down)), 0)
      let lastY = min(Int(((visible.maxY - 1e-9) / span).rounded(.down)), count - 1)
      let total = (lastX - firstX + 1) * (lastY - firstY + 1)
      if total <= maxTilesPerLayer {
        guard total > 0 else { return [] }
        var tiles: [(MKTileOverlayPath, MKMapRect)] = []
        for y in firstY...lastY {
          for x in firstX...lastX {
            let wrapped = ((x % count) + count) % count
            tiles.append(
              (
                MKTileOverlayPath(x: wrapped, y: y, z: z, contentScaleFactor: contentScale),
                MKMapRect(x: Double(x) * span, y: Double(y) * span, width: span, height: span)
              ))
          }
        }
        return tiles
      }
      z -= 1
    }
    return []
  }

  static func circle(center: CLLocationCoordinate2D, radiusMeters: Double) -> [CLLocationCoordinate2D] {
    let centerPoint = MKMapPoint(center)
    let radius = radiusMeters / MKMetersPerMapPointAtLatitude(center.latitude)
    return (0..<circleSegments).map { index in
      let angle = Double(index) / Double(circleSegments) * 2 * .pi
      return MKMapPoint(x: centerPoint.x + radius * cos(angle), y: centerPoint.y + radius * sin(angle)).coordinate
    }
  }

  /// Fetches every tile, giving up on the stragglers after [timeout] so a dead tile server cannot hang the call.
  func loadTiles(timeout: TimeInterval, completion: @escaping () -> Void) {
    let group = DispatchGroup()
    for case .tiles(let layer) in layers {
      for (index, tile) in layer.tiles.enumerated() {
        group.enter()
        layer.overlay.loadTile(at: tile.path) { data, _ in
          if let data, let image = decodeImage(data) { layer.store(image, at: index) }
          group.leave()
        }
      }
    }
    let finish = Once(completion)
    group.notify(queue: .main) { finish.run() }
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish.run() }
  }
}

/// Waits for the MapKit snapshot and the tiles; only touched on the main thread.
final class SnapshotJoin: @unchecked Sendable {
  var snapshot: MKMapSnapshotter.Snapshot?
  private var remaining: Int
  private let body: (MKMapSnapshotter.Snapshot?) -> Void

  init(parts: Int, _ body: @escaping (MKMapSnapshotter.Snapshot?) -> Void) {
    remaining = parts
    self.body = body
  }

  func arrive() {
    remaining -= 1
    if remaining == 0 { body(snapshot) }
  }
}

final class Once {
  private var body: (() -> Void)?

  init(_ body: @escaping () -> Void) {
    self.body = body
  }

  func run() {
    let current = body
    body = nil
    current?()
  }
}

/// What the composer draws on: the base map image (nil when the scene has its own background) and the projection of
/// coordinates to top-left points. Immutable, used off the main thread (MapKit's snapshot projects from any thread).
struct SnapshotCanvas: @unchecked Sendable {
  let base: CGImage?
  let size: CGSize
  let pixelWidth: Int
  let pixelHeight: Int
  let pitched: Bool
  let point: (CLLocationCoordinate2D) -> CGPoint

  init(
    base: CGImage?, size: CGSize, pixelWidth: Int, pixelHeight: Int, pitched: Bool,
    point: @escaping (CLLocationCoordinate2D) -> CGPoint
  ) {
    self.base = base
    self.size = size
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.pitched = pitched
    self.point = point
  }

  /// MapKit's projection, perspective included. Reads the image, so it is built on the main thread.
  init?(snapshot: MKMapSnapshotter.Snapshot, pitched: Bool) {
    guard let base = snapshot.image.platformCGImage, snapshot.image.size.width > 0 else { return nil }
    let size = snapshot.image.size
    self.init(base: base, size: size, pixelWidth: base.width, pixelHeight: base.height, pitched: pitched) {
      let p = snapshot.point(for: $0)
      #if os(iOS)
        return p
      #else
        return CGPoint(x: p.x, y: size.height - p.y)
      #endif
    }
  }
}

/// Web Mercator around the view center, rotated by the heading; exact for an untilted camera.
struct SnapshotProjection {
  let center: MKMapPoint
  let mapPointsPerPoint: Double
  let heading: Double
  let size: CGSize

  func point(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
    let p = MKMapPoint(coordinate)
    let dx = CameraMath.shortestDx(from: center, to: p)
    let dy = p.y - center.y
    let radians = heading * .pi / 180
    return CGPoint(
      x: Double(size.width) / 2 + (dx * cos(radians) + dy * sin(radians)) / mapPointsPerPoint,
      y: Double(size.height) / 2 + (dy * cos(radians) - dx * sin(radians)) / mapPointsPerPoint
    )
  }
}

enum SnapshotComposer {
  /// Each tile is drawn through an affine map of three corners; under pitch the projection is perspective, so the
  /// tile is cut into cells that are each close to affine.
  static let pitchedTileCells = 4

  /// Draws in top-left points. Images go through `draw(_:corners:)`, which maps the image's own corners, so they
  /// come out upright whatever the flip of the context.
  static func compose(_ canvas: SnapshotCanvas, scene: SnapshotScene, heading: Double) -> Data? {
    guard canvas.pixelWidth > 0, canvas.pixelHeight > 0, canvas.size.width > 0 else { return nil }
    let size = canvas.size
    let scale = CGFloat(canvas.pixelWidth) / size.width
    guard
      let context = CGContext(
        data: nil,
        width: canvas.pixelWidth,
        height: canvas.pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.translateBy(x: 0, y: CGFloat(canvas.pixelHeight))
    context.scaleBy(x: scale, y: -scale)
    let point = canvas.point

    if let background = scene.background {
      context.setFillColor(background)
      context.fill(CGRect(origin: .zero, size: size))
    } else if let base = canvas.base {
      draw(
        base, in: context,
        corners: (CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height)))
    }

    let cells = canvas.pitched ? pitchedTileCells : 1
    for layer in scene.layers {
      switch layer {
      case .tiles(let tiles):
        context.saveGState()
        context.setAlpha(tiles.alpha)
        for (index, tile) in tiles.tiles.enumerated() {
          guard let image = tiles.image(at: index) else { continue }
          drawTile(image, covering: tile.rect, cells: cells, in: context, point: point)
        }
        context.restoreGState()
      case .path(let path):
        let cgPath = CGMutablePath()
        for ring in path.rings where ring.count > 1 {
          cgPath.addLines(between: ring.map(point))
          if path.closed { cgPath.closeSubpath() }
        }
        context.saveGState()
        context.setAlpha(path.alpha)
        if let fill = path.fill, path.closed {
          context.addPath(cgPath)
          context.setFillColor(fill)
          context.fillPath(using: .evenOdd)
        }
        if let stroke = path.stroke, path.lineWidth > 0 {
          context.addPath(cgPath)
          context.setStrokeColor(stroke)
          context.setLineWidth(path.lineWidth)
          context.setLineCap(path.lineCap)
          context.setLineJoin(path.lineJoin)
          if !path.dash.isEmpty { context.setLineDash(phase: 0, lengths: path.dash) }
          context.strokePath()
        }
        context.restoreGState()
      }
    }

    for item in scene.markers.sorted(by: { $0.marker.zIndex < $1.marker.zIndex }) {
      let anchor = point(item.coordinate)
      let width = item.icon.logicalSize.width
      let height = item.icon.logicalSize.height
      let degrees = item.marker.flat ? item.marker.rotation - heading : item.marker.rotation
      let radians = CGFloat(degrees * .pi / 180)
      let ax = CGFloat(item.marker.anchor.x)
      let ay = CGFloat(item.marker.anchor.y)
      func corner(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(
          x: anchor.x + x * cos(radians) - y * sin(radians),
          y: anchor.y + x * sin(radians) + y * cos(radians))
      }
      context.saveGState()
      context.setAlpha(item.alpha)
      draw(
        item.icon.image, in: context,
        corners: (
          corner(-ax * width, -ay * height),
          corner((1 - ax) * width, -ay * height),
          corner(-ax * width, (1 - ay) * height)
        ))
      context.restoreGState()
    }
    return context.makeImage().flatMap(encodePNG)
  }

  private static func drawTile(
    _ image: CGImage, covering rect: MKMapRect, cells: Int, in context: CGContext,
    point: (CLLocationCoordinate2D) -> CGPoint
  ) {
    func project(_ x: Double, _ y: Double) -> CGPoint { point(MKMapPoint(x: x, y: y).coordinate) }
    let cellWidth = rect.width / Double(cells)
    let cellHeight = rect.height / Double(cells)
    let pixelWidth = Double(image.width) / Double(cells)
    let pixelHeight = Double(image.height) / Double(cells)
    for row in 0..<cells {
      for column in 0..<cells {
        let piece =
          cells == 1
          ? image
          : image.cropping(
            to: CGRect(
              x: Double(column) * pixelWidth, y: Double(row) * pixelHeight, width: pixelWidth, height: pixelHeight
            ).integral)
        guard let piece else { continue }
        let x = rect.minX + Double(column) * cellWidth
        let y = rect.minY + Double(row) * cellHeight
        draw(
          piece, in: context,
          corners: (project(x, y), project(x + cellWidth, y), project(x, y + cellHeight)))
      }
    }
  }

  /// Maps the image's top-left, top-right and bottom-left corners onto the given points.
  private static func draw(
    _ image: CGImage, in context: CGContext, corners: (topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint)
  ) {
    let transform = CGAffineTransform(
      a: corners.topRight.x - corners.topLeft.x,
      b: corners.topRight.y - corners.topLeft.y,
      c: corners.topLeft.x - corners.bottomLeft.x,
      d: corners.topLeft.y - corners.bottomLeft.y,
      tx: corners.bottomLeft.x,
      ty: corners.bottomLeft.y
    )
    context.saveGState()
    context.concatenate(transform)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    context.restoreGState()
  }
}
