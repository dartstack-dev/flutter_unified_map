import MapKit

final class UrlTileOverlay: MKTileOverlay {
  /// Tiles are cached on disk and in memory across views and launches; URLSession.shared's default cache is small,
  /// and tile servers such as OpenStreetMap's ask clients to cache.
  static let session: URLSession = {
    let configuration = URLSessionConfiguration.default
    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("flutter_unified_map_tiles", isDirectory: true)
    configuration.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 200 << 20, directory: directory)
    return URLSession(configuration: configuration)
  }()

  private let template: String
  private let subdomains: [String]
  private let headers: [String: String]

  init(layer: PTileLayer) {
    template = layer.urlTemplate
    subdomains = layer.subdomains
    headers = layer.headers
    super.init(urlTemplate: nil)
    let size = max(layer.tileSize, 1)
    tileSize = CGSize(width: CGFloat(size), height: CGFloat(size))
    // MapKit compares these with the tile's own z, which for a 512/1024 tile is one/two levels below the map zoom
    // (AGENTS.md); minZoom/maxZoom are map zooms, as on Android and flutter_map.
    let levels = Self.levels(tileSize: size)
    minimumZ = max(Int(layer.minZoom.rounded(.down)) - levels, 0)
    maximumZ = max(Int(layer.maxZoom.rounded(.up)) - levels, minimumZ)
    canReplaceMapContent = layer.replacesBaseMap
  }

  static func levels(tileSize: Int64) -> Int {
    guard tileSize > 256, tileSize.nonzeroBitCount == 1 else { return 0 }
    return tileSize.trailingZeroBitCount - 8
  }

  override func url(forTilePath path: MKTileOverlayPath) -> URL {
    let subdomain = subdomains.isEmpty ? "" : subdomains[abs(path.x + path.y) % subdomains.count]
    let retina = path.contentScaleFactor >= 2 ? "@2x" : ""
    let url =
      template
      .replacingOccurrences(of: "{z}", with: String(path.z))
      .replacingOccurrences(of: "{x}", with: String(path.x))
      .replacingOccurrences(of: "{y}", with: String(path.y))
      .replacingOccurrences(of: "{s}", with: subdomain)
      .replacingOccurrences(of: "{r}", with: retina)
    return URL(string: url) ?? URL(fileURLWithPath: "/dev/null")
  }

  override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
    var request = URLRequest(url: url(forTilePath: path))
    for (name, value) in headers {
      request.setValue(value, forHTTPHeaderField: name)
    }
    Self.session.dataTask(with: request) { data, response, error in
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        result(nil, error ?? URLError(.badServerResponse))
        return
      }
      result(data, error)
    }.resume()
  }
}

/// Covers the whole world above Apple's base map for `PMapStyle.none`; its renderer fills with the background color
/// so MapKit never has to load a tile.
final class BlankBaseOverlay: MKTileOverlay {
  init() {
    super.init(urlTemplate: nil)
    canReplaceMapContent = true
  }
}

/// MapKit draws on its own threads while the color is set on the main thread.
final class FillRenderer: MKOverlayRenderer {
  private let lock = NSLock()
  private var storedColor: CGColor

  init(overlay: MKOverlay, color: CGColor) {
    storedColor = color
    super.init(overlay: overlay)
  }

  var color: CGColor {
    get {
      lock.lock()
      defer { lock.unlock() }
      return storedColor
    }
    set {
      lock.lock()
      storedColor = newValue
      lock.unlock()
    }
  }

  override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
    context.setFillColor(color)
    context.fill(rect(for: mapRect))
  }
}

@MainActor
final class TileOverlayController {
  private struct Entry {
    var layer: PTileLayer
    let overlay: UrlTileOverlay
    let renderer: MKTileOverlayRenderer
  }

  private let stack: OverlayStack
  private var entries: [String: Entry] = [:]

  init(stack: OverlayStack) {
    self.stack = stack
  }

  /// A change of opacity alone keeps the overlay and its rendered tiles; any other change rebuilds it.
  func update(added: [PTileLayer], changed: [PTileLayer], removedIds: [String]) {
    removedIds.forEach(remove)
    for layer in added + changed {
      if var entry = entries[layer.id], Self.differsInOpacityOnly(entry.layer, layer) {
        entry.layer = layer
        entries[layer.id] = entry
        entry.renderer.alpha = CGFloat(layer.opacity)
        entry.renderer.setNeedsDisplay()
        continue
      }
      let overlay = UrlTileOverlay(layer: layer)
      let renderer = MKTileOverlayRenderer(tileOverlay: overlay)
      renderer.alpha = CGFloat(layer.opacity)
      let previous = entries[layer.id]
      stack.insert(overlay, zIndex: layer.zIndex, renderer: renderer)
      entries[layer.id] = Entry(layer: layer, overlay: overlay, renderer: renderer)
      if let previous { stack.remove(previous.overlay) }
    }
  }

  static func differsInOpacityOnly(_ old: PTileLayer, _ new: PTileLayer) -> Bool {
    var same = new
    same.opacity = old.opacity
    return same == old
  }

  func removeAll() {
    entries.keys.forEach(remove)
  }

  private func remove(_ id: String) {
    guard let entry = entries.removeValue(forKey: id) else { return }
    stack.remove(entry.overlay)
  }
}
