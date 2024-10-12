import CoreLocation
import MapKit
import QuartzCore

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif

private enum LoadState {
  case pending
  case loaded
  case failed(PMapErrorCode, String)
}

private struct CameraTarget {
  var center: CLLocationCoordinate2D
  var zoom: Double
  var heading: Double
  var pitch: Double

  var isFinite: Bool {
    center.latitude.isFinite && center.longitude.isFinite && zoom.isFinite && heading.isFinite && pitch.isFinite
  }
}

private struct CameraAnimation {
  let target: CameraTarget
  let end: CFTimeInterval
  let generation: Int
}

/// One MKMapView and its delegate. The camera center reported to Dart and accepted from it is the center of the
/// padded area (Google Maps `setPadding` semantics), wherever MapKit's own camera center is (`cameraAnchor`).
/// Gestures are in MapViewHost+Gestures.swift, snapshots in MapViewHost+Snapshot.swift.
@MainActor
final class MapViewHost: NSObject {
  let viewId: Int64
  let mapView: UnifiedMKMapView
  let events: MapEventSink
  private(set) var options: PMapOptions
  let stack: OverlayStack
  let annotations: AnnotationController
  let overlays: OverlayController
  let tiles: TileOverlayController

  private var blankOverlay: BlankBaseOverlay?
  private var locationManager: CLLocationManager?
  var snapshots: [ObjectIdentifier: SnapshotRequest] = [:]

  private(set) var isReady = false
  private(set) var isDisposed = false
  private var loadState = LoadState.pending
  private var loadTimeoutGeneration = 0
  private var isLoadTimeoutArmed = false
  static let loadTimeout: TimeInterval = 20
  private var lastSize = CGSize.zero
  private var calibration: (size: CGSize, factor: Double)?
  private var zoomRangeLatitude: Double?
  private var lastCamera: PCamera?

  private var isMoving = false
  private var expectsProgrammaticChange = false
  private var programmaticGeneration = 0
  private var changeGeneration = 0
  private var sawWillChange = false
  private var pendingCompletions: [(generation: Int, body: () -> Void)] = []
  private var animation: CameraAnimation?
  private var moveScheduled = false
  private var moveFlushGeneration = 0
  private var lastMoveTime: CFTimeInterval = 0

  #if os(iOS)
    let tapRecognizer = UITapGestureRecognizer()
    let doubleTapRecognizer = UITapGestureRecognizer()
    let longPressRecognizer = UILongPressGestureRecognizer()
  #else
    let clickRecognizer = NSClickGestureRecognizer()
    let doubleClickRecognizer = NSClickGestureRecognizer()
    let pressRecognizer = NSPressGestureRecognizer()
    var eventMonitor: Any?
    var lastUserEventTime: CFTimeInterval = 0
  #endif

  init(viewId: Int64, frame: CGRect, options: PMapOptions, flutterApi: UnifiedMapsFlutterApi) {
    self.viewId = viewId
    self.options = options
    mapView = UnifiedMKMapView(frame: frame)
    #if os(iOS)
      mapView.overrideUserInterfaceStyle = .light
    #else
      mapView.appearance = NSAppearance(named: .aqua)
    #endif
    stack = OverlayStack(mapView: mapView)
    annotations = AnnotationController(mapView: mapView)
    overlays = OverlayController(stack: stack)
    tiles = TileOverlayController(stack: stack)
    events = MapEventSink(api: flutterApi, viewId: viewId)
    super.init()
    mapView.delegate = self
    mapView.onLayout = { [weak self] in self?.handleLayout() }
    mapView.onWindowChange = { [weak self] in self?.handleWindowChange() }
    installGestures()
    apply(options, previous: nil)
  }

  // MARK: Lifecycle

  private func handleLayout() {
    guard !isDisposed else { return }
    let size = mapView.bounds.size
    guard size != lastSize else { return }
    lastSize = size
    guard size.width > 0, size.height > 0 else { return }
    calibration = nil
    if isReady {
      expectProgrammaticChange()
      events.send { api, id in try await api.onViewSize(viewId: id, size: PSize(size)) }
      zoomRangeLatitude = nil
      updateZoomRange()
      return
    }
    applyInitialCamera()
    updateZoomRange()
    applyDoubleTapZoom()
    isReady = true
    let camera = currentCamera()
    events.send { api, id in try await api.onMapReady(viewId: id, camera: camera, size: PSize(size)) }
    switch loadState {
    case .pending: armLoadTimeout()
    case .loaded: events.send { api, id in try await api.onMapLoaded(viewId: id) }
    case .failed(let code, let message):
      events.send { api, id in try await api.onMapError(viewId: id, code: code, message: message) }
    }
  }

  /// MapKit does not load while the view is off-window, so the load timeout only runs while it is on one.
  private func handleWindowChange() {
    if mapView.window == nil {
      cancelLoadTimeout()
    } else {
      armLoadTimeout()
    }
  }

  func dispose() {
    guard !isDisposed else { return }
    isDisposed = true
    events.isEnabled = false
    cancelLoadTimeout()
    completePending()
    for request in snapshots.values { request.cancel() }
    snapshots.removeAll()
    mapView.onLayout = nil
    mapView.onWindowChange = nil
    mapView.delegate = nil
    removeGestures()
    annotations.removeAll()
    overlays.removeAll()
    tiles.removeAll()
    stack.removeAll()
    mapView.showsUserLocation = false
  }

  // MARK: Load state

  /// Events go out only when the state changes; before `onMapReady` the state is kept and sent right after it.
  private func reportLoaded() {
    cancelLoadTimeout()
    if case .loaded = loadState { return }
    loadState = .loaded
    guard isReady, !isDisposed else { return }
    events.send { api, id in try await api.onMapLoaded(viewId: id) }
  }

  private func reportLoadError(_ code: PMapErrorCode, _ message: String) {
    cancelLoadTimeout()
    if case .failed = loadState { return }
    loadState = .failed(code, message)
    guard isReady, !isDisposed else { return }
    events.send { api, id in try await api.onMapError(viewId: id, code: code, message: message) }
  }

  private func armLoadTimeout() {
    guard case .pending = loadState, isReady, !isDisposed, !isLoadTimeoutArmed, mapView.window != nil else { return }
    isLoadTimeoutArmed = true
    loadTimeoutGeneration += 1
    let generation = loadTimeoutGeneration
    runOnMain(after: Self.loadTimeout) { [weak self] in
      guard let self, generation == self.loadTimeoutGeneration else { return }
      self.isLoadTimeoutArmed = false
      self.reportLoadError(
        .loadTimeout,
        "MapKit did not finish loading the map within \(Int(Self.loadTimeout)) s and reported no error. "
          + "Check the network connection.")
    }
  }

  private func cancelLoadTimeout() {
    loadTimeoutGeneration += 1
    isLoadTimeoutArmed = false
  }

  /// With Apple's map content replaced, MapKit may never report a finished load, so a rendered map counts as one.
  private var replacesBaseMap: Bool {
    blankOverlay != nil || stack.ordered.contains { ($0.overlay as? MKTileOverlay)?.canReplaceMapContent == true }
  }

  static func loadFailureMessage(_ error: Error) -> String {
    var chain: [NSError] = []
    var current: NSError? = error as NSError
    while let error = current, chain.count < 4 {
      chain.append(error)
      current = error.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    let codes = chain.map { "\($0.domain) \($0.code)" }.joined(separator: "; ")
    var message = "MapKit failed to load the map: \(chain[0].localizedDescription) (\(codes))."
    if chain.contains(where: { $0.domain == NSURLErrorDomain }) {
      message += " Check the network connection."
    }
    return message
  }

  // MARK: Options

  func update(options newOptions: PMapOptions) {
    apply(newOptions, previous: options)
  }

  /// Only what changed is applied: assigning a new map configuration may make MapKit redraw the base map, and a
  /// sliding panel changes the padding on every frame.
  private func apply(_ new: PMapOptions, previous: PMapOptions?) {
    let paddingChanged = isReady && previous.map { $0.padding != new.padding } == true
    let running = paddingChanged ? runningAnimation : nil
    let keptCamera = paddingChanged && running == nil && !isUserGestureActive() ? currentCamera() : nil
    options = new
    let interaction = new.interaction
    mapView.isScrollEnabled = interaction.scrollEnabled
    mapView.isZoomEnabled = interaction.zoomEnabled
    mapView.isRotateEnabled = interaction.rotateEnabled
    mapView.isPitchEnabled = interaction.tiltEnabled
    if previous?.interaction != interaction { applyDoubleTapZoom() }
    mapView.showsCompass = new.showsCompass
    mapView.showsScale = new.showsScale
    mapView.showsBuildings = new.showsBuildings
    if new.showsUserLocation, previous?.showsUserLocation != true { requestLocationAuthorization() }
    mapView.showsUserLocation = new.showsUserLocation
    if previous?.padding != new.padding {
      #if os(iOS)
        mapView.insetsLayoutMarginsFromSafeArea = false
        mapView.layoutMargins = new.padding.platformInsets
      #else
        mapView.additionalSafeAreaInsets = new.padding.platformInsets
      #endif
    }
    if previous?.style != new.style || previous?.showsPointsOfInterest != new.showsPointsOfInterest
      || previous?.showsTraffic != new.showsTraffic
    {
      applyStyle(new)
    }
    if previous?.backgroundColorArgb != new.backgroundColorArgb { applyBackground(new.backgroundColorArgb) }
    if isReady, let previous, previous.minZoom != new.minZoom || previous.maxZoom != new.maxZoom {
      zoomRangeLatitude = nil
      updateZoomRange()
    }
    if let running {
      retarget(running)
    } else if let keptCamera {
      keepTarget(keptCamera)
    }
  }

  /// Google `setPadding` semantics: the target stays put and moves to the center of the new padded area.
  private func keepTarget(_ camera: PCamera) {
    let target = CameraTarget(
      center: camera.center.coordinate, zoom: camera.zoom, heading: camera.bearing, pitch: camera.tilt)
    guard !isCurrent(target) else { return }
    completePending()
    setCamera(target, duration: 0)
  }

  static func mapType(for style: PMapStyle) -> MKMapType {
    switch style {
    case .standard, .none: return .standard
    case .muted: return .mutedStandard
    case .satellite: return .satellite
    case .hybrid: return .hybrid
    }
  }

  var pointOfInterestFilter: MKPointOfInterestFilter {
    options.showsPointsOfInterest ? .includingAll : .excludingAll
  }

  private func applyStyle(_ options: PMapOptions) {
    if #available(iOS 16.0, macOS 13.0, *) {
      switch options.style {
      case .standard, .none, .muted:
        let configuration = MKStandardMapConfiguration(
          elevationStyle: .flat, emphasisStyle: options.style == .muted ? .muted : .default)
        configuration.pointOfInterestFilter = pointOfInterestFilter
        configuration.showsTraffic = options.showsTraffic
        mapView.preferredConfiguration = configuration
      case .satellite:
        mapView.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
      case .hybrid:
        let configuration = MKHybridMapConfiguration(elevationStyle: .flat)
        configuration.pointOfInterestFilter = pointOfInterestFilter
        configuration.showsTraffic = options.showsTraffic
        mapView.preferredConfiguration = configuration
      }
    } else {
      mapView.mapType = Self.mapType(for: options.style)
      mapView.showsTraffic = options.showsTraffic
      mapView.pointOfInterestFilter = pointOfInterestFilter
    }
    if options.style == .none, blankOverlay == nil {
      let overlay = BlankBaseOverlay()
      let renderer = FillRenderer(overlay: overlay, color: platformColor(argb: options.backgroundColorArgb).cgColor)
      stack.insert(overlay, zIndex: -.infinity, renderer: renderer)
      blankOverlay = overlay
    } else if options.style != .none, let overlay = blankOverlay {
      stack.remove(overlay)
      blankOverlay = nil
    }
  }

  private func applyBackground(_ argb: Int64) {
    let color = platformColor(argb: argb)
    #if os(iOS)
      mapView.backgroundColor = color
    #else
      mapView.layer?.backgroundColor = color.cgColor
    #endif
    if let renderer = blankOverlay.flatMap({ stack.renderer(for: $0) as? FillRenderer }), renderer.color != color.cgColor
    {
      renderer.color = color.cgColor
      renderer.setNeedsDisplay()
    }
  }

  private func requestLocationAuthorization() {
    let manager = locationManager ?? CLLocationManager()
    locationManager = manager
    if manager.authorizationStatus == .notDetermined {
      manager.requestWhenInUseAuthorization()
    }
  }

  /// MapKit's camera altitude is metres along the line of sight; zoom needs map points per screen point. Their ratio
  /// only depends on the view size (field of view), so it is measured on the live map and cached per size.
  private func updateZoomRange() {
    guard let factor = distanceFactor() else { return }
    let latitude = mapView.centerCoordinate.latitude
    if let last = zoomRangeLatitude, abs(last - latitude) < 1 { return }
    zoomRangeLatitude = latitude
    let metersPerMapPoint = MKMetersPerMapPointAtLatitude(latitude)
    let minDistance = factor * CameraMath.mapPointsPerPoint(zoom: options.maxZoom) * metersPerMapPoint
    let maxDistance = factor * CameraMath.mapPointsPerPoint(zoom: options.minZoom) * metersPerMapPoint
    let range =
      options.minZoom > 0
      ? MKMapView.CameraZoomRange(minCenterCoordinateDistance: minDistance, maxCenterCoordinateDistance: maxDistance)
      : MKMapView.CameraZoomRange(minCenterCoordinateDistance: minDistance)
    guard let range else { return }
    let distance = mapView.camera.centerCoordinateDistance
    if distance < range.minCenterCoordinateDistance || distance > range.maxCenterCoordinateDistance {
      expectProgrammaticChange()
    }
    mapView.setCameraZoomRange(range, animated: false)
  }

  // MARK: Geometry helpers

  /// Dart works in top-left logical pixels; AppKit views are y-up unless flipped.
  func topLeft(fromView point: CGPoint) -> CGPoint {
    #if os(iOS)
      return point
    #else
      return mapView.isFlipped ? point : CGPoint(x: point.x, y: mapView.bounds.height - point.y)
    #endif
  }

  private func viewPoint(fromTopLeft point: CGPoint) -> CGPoint {
    topLeft(fromView: point)
  }

  private func coordinate(atTopLeft point: CGPoint) -> CLLocationCoordinate2D? {
    let coordinate = mapView.convert(viewPoint(fromTopLeft: point), toCoordinateFrom: mapView)
    return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
  }

  private var paddedCenter: CGPoint {
    let size = mapView.bounds.size
    let padding = options.padding
    return CGPoint(
      x: padding.left + (Double(size.width) - padding.left - padding.right) / 2,
      y: padding.top + (Double(size.height) - padding.top - padding.bottom) / 2
    )
  }

  /// Measured along the horizontal line through the view center, which stays parallel to the image plane under
  /// pitch and rotation, so the scale there is the scale at the center.
  func measuredMapPointsPerPoint() -> Double? {
    let size = mapView.bounds.size
    guard size.width > 0, size.height > 0 else { return nil }
    let half = size.width / 4
    guard let a = coordinate(atTopLeft: CGPoint(x: size.width / 2 - half, y: size.height / 2)),
      let b = coordinate(atTopLeft: CGPoint(x: size.width / 2 + half, y: size.height / 2))
    else { return nil }
    let pa = MKMapPoint(a)
    let pb = MKMapPoint(b)
    let scale = hypot(CameraMath.shortestDx(from: pa, to: pb), pb.y - pa.y) / Double(2 * half)
    return scale.isFinite && scale > 0 ? scale : nil
  }

  private func distanceFactor() -> Double? {
    let size = mapView.bounds.size
    if let calibration, calibration.size == size { return calibration.factor }
    guard let scale = measuredMapPointsPerPoint() else { return nil }
    let camera = mapView.camera
    let factor =
      camera.centerCoordinateDistance / (scale * MKMetersPerMapPointAtLatitude(camera.centerCoordinate.latitude))
    guard factor.isFinite, factor > 0 else { return nil }
    calibration = (size, factor)
    return factor
  }

  // MARK: Camera

  /// The last measured camera when the map cannot be measured (a zero-size view), so a collapsed map does not report
  /// a jump back to the initial camera.
  func currentCamera() -> PCamera {
    guard let scale = measuredMapPointsPerPoint() else { return lastCamera ?? options.initialCamera }
    let padding = options.padding
    var center = mapView.centerCoordinate
    if padding.left != 0 || padding.top != 0 || padding.right != 0 || padding.bottom != 0,
      let padded = coordinate(atTopLeft: paddedCenter)
    {
      center = padded
    }
    let camera = PCamera(
      center: PLatLng(latitude: center.latitude, longitude: CameraMath.normalizedLongitude(center.longitude)),
      zoom: CameraMath.zoom(mapPointsPerPoint: scale),
      bearing: mapView.camera.heading,
      tilt: Double(mapView.camera.pitch)
    )
    lastCamera = camera
    return camera
  }

  func visibleRegion() -> PLatLngBounds {
    let rect = mapView.visibleMapRect
    let world = MKMapSize.world
    let top = MKMapPoint(x: 0, y: max(rect.minY, 0)).coordinate.latitude
    let bottom = MKMapPoint(x: 0, y: min(rect.maxY, world.height)).coordinate.latitude
    if rect.width >= world.width {
      return PLatLngBounds(
        southWest: PLatLng(latitude: bottom, longitude: -180), northEast: PLatLng(latitude: top, longitude: 180))
    }
    let west = CameraMath.normalizedLongitude(rect.minX / world.width * 360 - 180)
    var east = CameraMath.normalizedLongitude(rect.maxX / world.width * 360 - 180)
    if east == -180 { east = 180 }
    return PLatLngBounds(
      southWest: PLatLng(latitude: bottom, longitude: west), northEast: PLatLng(latitude: top, longitude: east))
  }

  func toScreen(_ position: PLatLng) -> PPoint {
    PPoint(topLeft(fromView: mapView.convert(position.coordinate, toPointTo: mapView)))
  }

  func toLatLng(_ point: PPoint) -> PLatLng {
    PLatLng(mapView.convert(viewPoint(fromTopLeft: point.cgPoint), toCoordinateFrom: mapView))
  }

  private var zoomRange: ClosedRange<Double> {
    min(options.minZoom, options.maxZoom)...options.maxZoom
  }

  private func clampZoom(_ zoom: Double) -> Double {
    min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound)
  }

  /// Where MapKit puts its camera center on screen: the view center, or (iOS) the center of the layout margins that
  /// carry the padding. Measured rather than assumed, so the padded-center math holds either way.
  private var cameraAnchor: CGPoint {
    let size = mapView.bounds.size
    let point = topLeft(fromView: mapView.convert(mapView.centerCoordinate, toPointTo: mapView))
    return point.x.isFinite && point.y.isFinite ? point : CGPoint(x: size.width / 2, y: size.height / 2)
  }

  private func viewCenter(for target: CameraTarget) -> (point: MKMapPoint, scale: Double) {
    let scale = CameraMath.mapPointsPerPoint(zoom: target.zoom)
    let anchor = cameraAnchor
    let padded = paddedCenter
    let delta = CameraMath.mapDelta(
      dx: Double(anchor.x) - padded.x,
      dy: Double(anchor.y) - padded.y,
      heading: target.heading,
      mapPointsPerPoint: scale
    )
    return (CameraMath.offset(MKMapPoint(CameraMath.clamped(target.center)), by: delta), scale)
  }

  /// The padding offset ignores pitch foreshortening: with a tilted camera the padded center is approximate.
  /// `setCamera(_:animated:)` animates with MapKit's own duration, whereas assigning `camera` inside a
  /// UIView/NSAnimationContext animation follows the given one. Returns the programmatic generation of the move, nil when the
  /// camera could not be applied (`completion` is then not called).
  @discardableResult
  private func setCamera(_ target: CameraTarget, duration: Double, completion: (() -> Void)? = nil) -> Int? {
    guard let factor = distanceFactor() else { return nil }
    let (center, scale) = viewCenter(for: target)
    let coordinate = center.coordinate
    let camera = MKMapCamera(
      lookingAtCenter: coordinate,
      fromDistance: factor * scale * MKMetersPerMapPointAtLatitude(coordinate.latitude),
      pitch: CGFloat(target.pitch),
      heading: target.heading
    )
    let generation = expectProgrammaticChange()
    guard duration > 0 else {
      mapView.setCamera(camera, animated: false)
      completion?()
      return generation
    }
    let mapView = self.mapView
    #if os(iOS)
      UIView.animate(
        withDuration: duration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState],
        animations: { mapView.camera = camera },
        completion: { _ in completion?() }
      )
    #else
      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = duration
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
          context.allowsImplicitAnimation = true
          mapView.animator().camera = camera
        },
        completionHandler: { MainActor.assumeIsolated { completion?() } }
      )
    #endif
    return generation
  }

  private func applyInitialCamera() {
    let initial = options.initialCamera
    let target = CameraTarget(
      center: initial.center.coordinate, zoom: clampZoom(initial.zoom), heading: initial.bearing, pitch: initial.tilt)
    guard target.isFinite else { return }
    var flat = target
    flat.heading = 0
    let (center, scale) = viewCenter(for: flat)
    let size = mapView.bounds.size
    let width = Double(size.width) * scale
    let height = Double(size.height) * scale
    expectProgrammaticChange()
    mapView.setVisibleMapRect(
      MKMapRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height), animated: false)
    calibration = nil
    setCamera(target, duration: 0)
  }

  /// Nil when the update cannot be applied, including any non-finite value (MapKit rejects invalid regions).
  private func target(for update: PCameraUpdate) -> CameraTarget? {
    let current = currentCamera()
    let base = CameraTarget(
      center: current.center.coordinate, zoom: current.zoom, heading: current.bearing, pitch: current.tilt)
    var target: CameraTarget?
    if let camera = update.newCamera {
      target = CameraTarget(
        center: camera.center?.coordinate ?? base.center,
        zoom: clampZoom(camera.zoom ?? base.zoom),
        heading: camera.bearing ?? base.heading,
        pitch: camera.tilt ?? base.pitch
      )
    } else if let fit = update.fitBounds {
      let heading = fit.bearing ?? base.heading
      let solution = CameraMath.fitBounds(
        fit.bounds,
        fitPadding: fit.padding,
        mapPadding: options.padding,
        viewSize: mapView.bounds.size,
        maxZoom: fit.maxZoom,
        zoomRange: zoomRange,
        bearing: heading
      )
      target = CameraTarget(center: solution.center, zoom: solution.zoom, heading: heading, pitch: 0)
    } else if let scroll = update.scrollBy {
      let delta = CameraMath.mapDelta(
        dx: scroll.dx, dy: scroll.dy, heading: base.heading,
        mapPointsPerPoint: CameraMath.mapPointsPerPoint(zoom: base.zoom))
      target = base
      target?.center = CameraMath.offset(MKMapPoint(CameraMath.clamped(base.center)), by: delta).coordinate
    } else if let zoomBy = update.zoomBy {
      var zoomed = base
      zoomed.zoom = clampZoom(base.zoom + zoomBy.amount)
      if let focus = zoomBy.focus, let focusCoordinate = coordinate(atTopLeft: focus.cgPoint) {
        let f = MKMapPoint(focusCoordinate)
        let c = MKMapPoint(CameraMath.clamped(base.center))
        let ratio = pow(2, base.zoom - zoomed.zoom)
        let moved = MKMapPoint(x: f.x + CameraMath.shortestDx(from: f, to: c) * ratio, y: f.y + (c.y - f.y) * ratio)
        zoomed.center = CameraMath.wrap(moved).coordinate
      }
      target = zoomed
    }
    guard let target, target.isFinite else { return nil }
    return target
  }

  private func isCurrent(_ target: CameraTarget) -> Bool {
    let current = currentCamera()
    let headingDelta = abs((target.heading - current.bearing).truncatingRemainder(dividingBy: 360))
    return abs(target.center.latitude - current.center.latitude) < 1e-9
      && abs(CameraMath.normalizedLongitude(target.center.longitude) - current.center.longitude) < 1e-9
      && abs(target.zoom - current.zoom) < 1e-6
      && min(headingDelta, 360 - headingDelta) < 1e-6
      && abs(target.pitch - current.tilt) < 1e-6
  }

  /// Completes when the animation ends or is interrupted (by a gesture or a newer move); `regionDidChangeAnimated`
  /// and two timers back up the animation's own completion in case MapKit skips the change.
  func moveCamera(_ update: PCameraUpdate, animationMillis: Int64?, completion: @escaping () -> Void) {
    guard isReady, !isDisposed, let target = target(for: update) else {
      completion()
      return
    }
    guard !isCurrent(target) else {
      if !isMoving {
        let camera = currentCamera()
        events.send { api, id in try await api.onCameraMoveStarted(viewId: id, byGesture: false) }
        events.send { api, id in try await api.onCameraMove(viewId: id, camera: camera) }
        events.send { api, id in try await api.onCameraIdle(viewId: id, camera: camera) }
      }
      completion()
      return
    }
    completePending()
    sawWillChange = false
    let duration = Double(max(animationMillis ?? 0, 0)) / 1000
    guard duration > 0 else {
      setCamera(target, duration: 0)
      completion()
      return
    }
    animate(to: target, duration: duration, completions: [completion])
  }

  private func animate(to target: CameraTarget, duration: Double, completions: [() -> Void]) {
    var applied: Int?
    applied = setCamera(target, duration: duration) { [weak self] in
      if let applied { self?.completePending(upTo: applied) }
    }
    guard let generation = applied else {
      completions.forEach { $0() }
      return
    }
    pendingCompletions += completions.map { (generation, $0) }
    animation = CameraAnimation(target: target, end: CACurrentMediaTime() + duration, generation: generation)
    runOnMain(after: 0.3) { [weak self] in
      guard let self, !self.sawWillChange else { return }
      self.completePending(upTo: generation)
    }
    runOnMain(after: duration + 5) { [weak self] in self?.completePending(upTo: generation) }
  }

  /// The programmatic animation still in flight, if any.
  private var runningAnimation: CameraAnimation? {
    guard let animation, pendingCompletions.contains(where: { $0.generation == animation.generation }) else {
      return nil
    }
    return animation
  }

  /// A padding change during an animated move: Google keeps animating to the target, now centered in the new padded
  /// area, so the move is re-issued for the rest of its duration and keeps its completions.
  private func retarget(_ running: CameraAnimation) {
    let completions = pendingCompletions.map(\.body)
    pendingCompletions.removeAll()
    let remaining = running.end - CACurrentMediaTime()
    guard remaining > 0.02 else {
      setCamera(running.target, duration: 0)
      completions.forEach { $0() }
      return
    }
    animate(to: running.target, duration: remaining, completions: completions)
  }

  private func completePending(upTo generation: Int = .max) {
    let ready = pendingCompletions.filter { $0.generation <= generation }
    guard !ready.isEmpty else { return }
    pendingCompletions.removeAll { $0.generation <= generation }
    ready.forEach { $0.body() }
  }

  @discardableResult
  private func expectProgrammaticChange() -> Int {
    expectsProgrammaticChange = true
    programmaticGeneration += 1
    let generation = programmaticGeneration
    runOnMain(after: 0.5) { [weak self] in
      guard let self, generation == self.programmaticGeneration, !self.isMoving else { return }
      self.expectsProgrammaticChange = false
    }
    return generation
  }

  // MARK: Camera events

  private func beginMoveIfNeeded() {
    guard !isMoving else { return }
    isMoving = true
    changeGeneration = programmaticGeneration
    let byGesture = isUserGestureActive() || !expectsProgrammaticChange
    events.send { api, id in try await api.onCameraMoveStarted(viewId: id, byGesture: byGesture) }
  }

  private var minimumMoveInterval: CFTimeInterval {
    #if os(iOS)
      let fps = mapView.window?.screen.maximumFramesPerSecond ?? 60
    #else
      let fps = mapView.window?.screen?.maximumFramesPerSecond ?? 60
    #endif
    return 1 / Double(max(fps, 1))
  }

  private func scheduleMove() {
    guard !moveScheduled else { return }
    moveScheduled = true
    moveFlushGeneration += 1
    let generation = moveFlushGeneration
    let wait = minimumMoveInterval - (CACurrentMediaTime() - lastMoveTime)
    runOnMain(after: wait) { [weak self] in
      guard let self, generation == self.moveFlushGeneration else { return }
      self.flushMove()
    }
  }

  private func flushMove() {
    guard moveScheduled, !isDisposed else { return }
    moveScheduled = false
    lastMoveTime = CACurrentMediaTime()
    let camera = currentCamera()
    events.send { api, id in try await api.onCameraMove(viewId: id, camera: camera) }
  }
}

// MARK: - MKMapViewDelegate

extension MapViewHost: MKMapViewDelegate {
  func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
    sawWillChange = true
    changeGeneration = programmaticGeneration
    guard isReady, !isDisposed else { return }
    beginMoveIfNeeded()
  }

  func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
    guard !isDisposed else { return }
    annotations.setHeading(mapView.camera.heading)
    guard isReady else { return }
    beginMoveIfNeeded()
    scheduleMove()
  }

  func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
    guard !isDisposed else { return }
    annotations.setHeading(mapView.camera.heading)
    // A move interrupted by a newer setCamera reports its didChange during that call (after the newer move bumped
    // the generation): the newer move's completion and programmatic flag must survive it.
    let ended = changeGeneration
    completePending(upTo: ended)
    if programmaticGeneration == ended { expectsProgrammaticChange = false }
    guard isReady else { return }
    beginMoveIfNeeded()
    if moveScheduled { flushMove() }
    isMoving = false
    calibration = nil
    let camera = currentCamera()
    events.send { api, id in try await api.onCameraIdle(viewId: id, camera: camera) }
    runOnMain(after: 0) { [weak self] in self?.updateZoomRange() }
  }

  func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
    guard !isDisposed else { return }
    reportLoaded()
  }

  func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
    guard !isDisposed else { return }
    reportLoadError(.loadFailed, Self.loadFailureMessage(error))
  }

  func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
    guard !isDisposed, replacesBaseMap else { return }
    reportLoaded()
  }

  func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    annotations.view(for: annotation, in: mapView)
  }

  func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
    guard let annotation = view.annotation as? MarkerAnnotation else { return }
    if isReady, !isDisposed, annotation.marker.tappable, !annotation.isDisappearing {
      let markerId = annotation.marker.id
      events.send { api, id in try await api.onMarkerTap(viewId: id, markerId: markerId) }
    }
    mapView.deselectAnnotation(annotation, animated: false)
  }

  func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
    stack.renderer(for: overlay) ?? MKOverlayRenderer(overlay: overlay)
  }
}
