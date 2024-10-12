import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

@MainActor
final class MapViewRegistry {
  private var hosts: [Int64: MapViewHost] = [:]

  func host(_ viewId: Int64) -> MapViewHost? { hosts[viewId] }

  func add(_ host: MapViewHost) {
    hosts[host.viewId]?.dispose()
    hosts[host.viewId] = host
  }

  @discardableResult
  func remove(_ viewId: Int64) -> MapViewHost? { hosts.removeValue(forKey: viewId) }

  func release(_ host: MapViewHost) {
    guard hosts[host.viewId] === host else { return }
    hosts.removeValue(forKey: host.viewId)
    host.dispose()
  }
}

/// Pigeon handlers run on the platform thread, which is the main thread on iOS and macOS.
final class HostApiImpl: UnifiedMapsHostApi {
  private let registry: MapViewRegistry

  init(registry: MapViewRegistry) {
    self.registry = registry
  }

  private func withHost(_ viewId: Int64, _ body: @MainActor (MapViewHost) -> Void) {
    MainActor.assumeIsolated {
      if let host = registry.host(viewId) { body(host) }
    }
  }

  private func unknownView(_ viewId: Int64) -> PigeonError {
    PigeonError(code: "unknown-view", message: "No map view with id \(viewId)", details: nil)
  }

  func dispose(viewId: Int64) throws {
    MainActor.assumeIsolated { registry.remove(viewId)?.dispose() }
  }

  func updateOptions(viewId: Int64, options: PMapOptions) throws {
    withHost(viewId) { $0.update(options: options) }
  }

  /// The valid icons are registered even when others fail; the Dart side then sends every failed key again.
  func registerIcons(viewId: Int64, icons: [PIcon]) throws {
    let failed = MainActor.assumeIsolated { registry.host(viewId)?.annotations.registerIcons(icons) ?? [] }
    guard failed.isEmpty else {
      throw PigeonError(
        code: "icon-decode-failed", message: "Could not decode the PNG of the icons \(failed)", details: failed)
    }
  }

  func updateMarkers(
    viewId: Int64, added: [PMarker], changed: [PMarker], removedIds: [String], transition: PMarkerTransition?
  ) throws {
    withHost(viewId) {
      $0.annotations.update(added: added, changed: changed, removedIds: removedIds, transition: transition)
    }
  }

  func updatePolylines(viewId: Int64, added: [PPolyline], changed: [PPolyline], removedIds: [String]) throws {
    withHost(viewId) { $0.overlays.updatePolylines(added: added, changed: changed, removedIds: removedIds) }
  }

  func updatePolygons(viewId: Int64, added: [PPolygon], changed: [PPolygon], removedIds: [String]) throws {
    withHost(viewId) { $0.overlays.updatePolygons(added: added, changed: changed, removedIds: removedIds) }
  }

  func updateCircles(viewId: Int64, added: [PCircle], changed: [PCircle], removedIds: [String]) throws {
    withHost(viewId) { $0.overlays.updateCircles(added: added, changed: changed, removedIds: removedIds) }
  }

  func updateTileLayers(viewId: Int64, added: [PTileLayer], changed: [PTileLayer], removedIds: [String]) throws {
    withHost(viewId) { $0.tiles.update(added: added, changed: changed, removedIds: removedIds) }
  }

  // Contract stubs (see AGENTS.md): accepted and ignored until the Apple unit implements them.
  func updateGroundOverlays(viewId: Int64, added: [PGroundOverlay], changed: [PGroundOverlay], removedIds: [String])
    throws
  {}

  func resetTileLayer(viewId: Int64, tileLayerId: String) throws {}

  func unregisterIcons(viewId: Int64, keys: [String]) throws {}

  func stopCamera(viewId: Int64) throws {}

  /// Main-actor isolated so the generated `Task { @MainActor in ... }` runs it without hopping to the global executor:
  /// a nonisolated async witness would leave the main actor first, and instant moves sent back to back (the core does
  /// not await them) could then reach MapKit out of order.
  @MainActor
  func moveCamera(viewId: Int64, update: PCameraUpdate, animationMillis: Int64?) async throws {
    guard let host = registry.host(viewId) else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      host.moveCamera(update, animationMillis: animationMillis) { continuation.resume() }
    }
  }

  func getCamera(viewId: Int64) throws -> PCamera {
    let camera = MainActor.assumeIsolated { registry.host(viewId)?.currentCamera() }
    guard let camera else { throw unknownView(viewId) }
    return camera
  }

  func getVisibleRegion(viewId: Int64) throws -> PLatLngBounds {
    let region = MainActor.assumeIsolated { registry.host(viewId)?.visibleRegion() }
    guard let region else { throw unknownView(viewId) }
    return region
  }

  func toScreen(viewId: Int64, position: PLatLng) throws -> PPoint {
    let point = MainActor.assumeIsolated { registry.host(viewId)?.toScreen(position) }
    guard let point else { throw unknownView(viewId) }
    return point
  }

  func toLatLng(viewId: Int64, screenPoint: PPoint) throws -> PLatLng {
    let position = MainActor.assumeIsolated { registry.host(viewId)?.toLatLng(screenPoint) }
    guard let position else { throw unknownView(viewId) }
    return position
  }

  @MainActor
  func takeSnapshot(viewId: Int64) async throws -> FlutterStandardTypedData? {
    guard let host = registry.host(viewId) else { return nil }
    return await withCheckedContinuation { (continuation: CheckedContinuation<FlutterStandardTypedData?, Never>) in
      host.takeSnapshot { continuation.resume(returning: $0) }
    }
  }
}
