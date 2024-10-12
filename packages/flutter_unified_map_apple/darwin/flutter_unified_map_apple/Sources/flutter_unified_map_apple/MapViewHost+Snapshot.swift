import MapKit

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif

/// `takeSnapshot`: what the live map shows is captured on the main thread (`SnapshotScene`), the base map comes from
/// MKMapSnapshotter, the tiles from their servers, and the image is composed and encoded off the main thread.
extension MapViewHost {
  func takeSnapshot(completion: @escaping (FlutterStandardTypedData?) -> Void) {
    let size = mapView.bounds.size
    guard isReady, !isDisposed, size.width > 0, size.height > 0 else {
      completion(nil)
      return
    }
    let scene = snapshotScene()
    let heading = mapView.camera.heading
    let pitched = mapView.camera.pitch > 0.5
    let scale = screenScale
    let projection = measuredMapPointsPerPoint().map {
      SnapshotProjection(center: MKMapPoint(mapView.centerCoordinate), mapPointsPerPoint: $0, heading: heading, size: size)
    }
    // When the app's own layers replace the base map, Apple's snapshot service is not needed: it would only cost a
    // network round trip, and fail offline, exactly when an app relies on its own tiles. Under pitch its perspective
    // projection is still needed.
    let ownCanvas: SnapshotCanvas? =
      scene.background == nil
      ? nil
      : projection.map { projection in
        SnapshotCanvas(
          base: nil, size: size, pixelWidth: Int((size.width * scale).rounded()),
          pixelHeight: Int((size.height * scale).rounded()), pitched: pitched, point: projection.point)
      }

    let snapshotter = ownCanvas != nil && !pitched ? nil : MKMapSnapshotter(options: snapshotOptions(size: size))
    let request = SnapshotRequest(snapshotter: snapshotter, completion: completion)
    let token = ObjectIdentifier(request)
    snapshots[token] = request

    let compose: (SnapshotCanvas?) -> Void = { [weak self] canvas in
      guard let canvas else {
        self?.snapshots.removeValue(forKey: token)
        request.finish(nil)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let png = SnapshotComposer.compose(canvas, scene: scene, heading: heading)
        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            self?.snapshots.removeValue(forKey: token)
            request.finish(png.map { FlutterStandardTypedData(bytes: $0) })
          }
        }
      }
    }
    guard let snapshotter else {
      scene.loadTiles(timeout: 10) { compose(ownCanvas) }
      return
    }
    let join = SnapshotJoin(parts: 2) { snapshot in
      compose(snapshot.flatMap { SnapshotCanvas(snapshot: $0, pitched: pitched) } ?? ownCanvas)
    }
    snapshotter.start(with: .main) { result, _ in
      MainActor.assumeIsolated {
        join.snapshot = result
        join.arrive()
      }
    }
    scene.loadTiles(timeout: 10) { join.arrive() }
  }

  /// From the options rather than the map view: before iOS 17 / macOS 14 the snapshot takes a map type and a point of
  /// interest filter, which `applyStyle` only sets on the map view before iOS 16 / macOS 13.
  private func snapshotOptions(size: CGSize) -> MKMapSnapshotter.Options {
    let snapshotOptions = MKMapSnapshotter.Options()
    snapshotOptions.camera = mapView.camera
    snapshotOptions.size = size
    snapshotOptions.showsBuildings = mapView.showsBuildings
    snapshotOptions.pointOfInterestFilter = pointOfInterestFilter
    if #available(iOS 17.0, macOS 14.0, *) {
      snapshotOptions.preferredConfiguration = mapView.preferredConfiguration
    } else {
      snapshotOptions.mapType = Self.mapType(for: options.style)
    }
    #if os(iOS)
      snapshotOptions.traitCollection = mapView.traitCollection
    #else
      snapshotOptions.appearance = mapView.effectiveAppearance
    #endif
    return snapshotOptions
  }

  private var screenScale: CGFloat {
    #if os(iOS)
      return mapView.window?.screen.scale ?? UIScreen.main.scale
    #else
      return mapView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    #endif
  }

  private func snapshotScene() -> SnapshotScene {
    var background: CGColor?
    var layers: [SnapshotLayer] = []
    let visible = mapView.visibleMapRect
    let zoom = currentCamera().zoom
    for (overlay, renderer) in stack.ordered {
      if overlay is BlankBaseOverlay, let fill = renderer as? FillRenderer {
        background = fill.color
      } else if let tileOverlay = overlay as? UrlTileOverlay {
        if tileOverlay.canReplaceMapContent {
          background = background ?? platformColor(argb: options.backgroundColorArgb).cgColor
        }
        let tiles = SnapshotScene.tiles(for: tileOverlay, visible: visible, zoom: zoom, contentScale: screenScale)
        layers.append(.tiles(SnapshotTiles(overlay: tileOverlay, alpha: renderer.alpha, tiles: tiles)))
      } else if let path = snapshotPath(overlay, renderer) {
        layers.append(.path(path))
      }
    }
    let markers: [SnapshotMarker] = annotations.all.compactMap { annotation in
      guard let icon = annotations.icon(for: annotation.marker.iconKey) else { return nil }
      return SnapshotMarker(
        coordinate: annotation.coordinate, marker: annotation.marker, icon: icon, alpha: annotation.alpha)
    }
    return SnapshotScene(background: background, layers: layers, markers: markers)
  }

  private func snapshotPath(_ overlay: MKOverlay, _ renderer: MKOverlayRenderer) -> SnapshotPath? {
    guard let renderer = renderer as? MKOverlayPathRenderer else { return nil }
    let rings: [[CLLocationCoordinate2D]]
    let closed: Bool
    if let polyline = overlay as? MKPolyline {
      rings = [coordinates(of: polyline)]
      closed = false
    } else if let polygon = overlay as? MKPolygon {
      rings = [coordinates(of: polygon)] + (polygon.interiorPolygons ?? []).map(coordinates(of:))
      closed = true
    } else if let circle = overlay as? MKCircle {
      rings = [SnapshotScene.circle(center: circle.coordinate, radiusMeters: circle.radius)]
      closed = true
    } else {
      return nil
    }
    return SnapshotPath(
      rings: rings,
      closed: closed,
      fill: renderer.fillColor?.cgColor,
      stroke: renderer.strokeColor?.cgColor,
      lineWidth: renderer.lineWidth,
      lineCap: renderer.lineCap,
      lineJoin: renderer.lineJoin,
      dash: (renderer.lineDashPattern ?? []).map { CGFloat($0.doubleValue) },
      alpha: renderer.alpha
    )
  }

  private func coordinates(of shape: MKMultiPoint) -> [CLLocationCoordinate2D] {
    let points = shape.points()
    return (0..<shape.pointCount).map { points[$0].coordinate }
  }
}

/// Owns the snapshotter until it answers (the host may be released first) and answers Dart exactly once, with nil
/// when the view is disposed mid-snapshot.
@MainActor
final class SnapshotRequest {
  private var snapshotter: MKMapSnapshotter?
  private var completion: ((FlutterStandardTypedData?) -> Void)?

  init(snapshotter: MKMapSnapshotter?, completion: @escaping (FlutterStandardTypedData?) -> Void) {
    self.snapshotter = snapshotter
    self.completion = completion
  }

  func finish(_ data: FlutterStandardTypedData?) {
    snapshotter = nil
    let body = completion
    completion = nil
    body?(data)
  }

  func cancel() {
    snapshotter?.cancel()
    finish(nil)
  }
}
