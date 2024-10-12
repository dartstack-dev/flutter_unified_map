import MapKit
import QuartzCore

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import Cocoa
#endif

struct MarkerIcon {
  let image: CGImage
  let logicalSize: CGSize
  let pixelRatio: CGFloat
}

final class MarkerAnnotation: NSObject, MKAnnotation {
  @objc dynamic var coordinate: CLLocationCoordinate2D
  var marker: PMarker
  /// On-screen opacity, kept here because the annotation view may not exist (off-screen) or may be reused.
  var alpha: CGFloat = 1
  /// Removed with a transition: still on the map until it has faded out, but no longer part of the published markers.
  var isDisappearing = false

  init(marker: PMarker) {
    self.marker = marker
    coordinate = marker.position.coordinate
  }
}

/// Draws the icon in a sublayer so that rotation can pivot on the anchor without touching the frame MapKit manages.
final class MarkerAnnotationView: MKAnnotationView {
  private let content = CALayer()

  override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
    super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    canShowCallout = false
    displayPriority = .required
    content.contentsGravity = .resize
    #if os(iOS)
      layer.addSublayer(content)
    #else
      wantsLayer = true
      layer?.addSublayer(content)
    #endif
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func configure(annotation: MarkerAnnotation, icon: MarkerIcon?, mapHeading: Double) {
    let marker = annotation.marker
    let size = icon?.logicalSize ?? .zero
    #if os(iOS)
      bounds = CGRect(origin: .zero, size: size)
    #else
      setFrameSize(size)
    #endif
    let anchor = CGPoint(x: marker.anchor.x, y: marker.anchor.y)
    centerOffset = CGPoint(x: (0.5 - anchor.x) * size.width, y: (0.5 - anchor.y) * size.height)
    let priority = MarkerAnnotationView.priority(for: marker.zIndex)
    zPriority = priority
    selectedZPriority = priority
    isEnabled = marker.tappable && !annotation.isDisappearing
    setOpacity(annotation.alpha)

    let yDown = isYDown
    let degrees = marker.flat ? marker.rotation - mapHeading : marker.rotation
    let radians = CGFloat(degrees * .pi / 180)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    content.contents = icon?.image
    content.contentsScale = icon?.pixelRatio ?? 1
    content.setAffineTransform(.identity)
    content.bounds = CGRect(origin: .zero, size: size)
    content.anchorPoint = CGPoint(x: anchor.x, y: yDown ? anchor.y : 1 - anchor.y)
    content.position = CGPoint(
      x: anchor.x * size.width, y: (yDown ? anchor.y : 1 - anchor.y) * size.height)
    content.setAffineTransform(CGAffineTransform(rotationAngle: yDown ? radians : -radians))
    CATransaction.commit()
  }

  func setOpacity(_ alpha: CGFloat) {
    #if os(iOS)
      self.alpha = alpha
    #else
      alphaValue = alpha
    #endif
  }

  private var isYDown: Bool {
    #if os(iOS)
      return true
    #else
      return layer?.contentsAreFlipped() ?? isFlipped
    #endif
  }

  /// MapKit only orders annotation views by zPriority in [0, 1000]; this squeezes any zIndex monotonically into it.
  static func priority(for zIndex: Double) -> MKAnnotationViewZPriority {
    MKAnnotationViewZPriority(rawValue: Float(500 + atan(zIndex / 100) / (.pi / 2) * 499))
  }
}

private struct MarkerFlight {
  let annotation: MarkerAnnotation
  let from: CLLocationCoordinate2D
  let to: CLLocationCoordinate2D
  let fromAlpha: CGFloat
  let toAlpha: CGFloat
  let start: CFTimeInterval
  let duration: CFTimeInterval

  var moves: Bool { from.latitude != to.latitude || from.longitude != to.longitude }
}

/// Markers by id, with `PMarkerTransition` animations driven frame by frame on the annotations themselves: the
/// coordinate (KVO, MapKit moves the view, also while the camera moves) and the opacity (applied to the view when it
/// exists, and by `view(for:in:)` when MapKit creates or reuses one later).
@MainActor
final class AnnotationController {
  /// `configure` sets every property of a view, so one reuse pool serves every icon.
  private static let reuseId = "marker"

  private weak var mapView: MKMapView?
  private var icons: [String: MarkerIcon] = [:]
  private var annotations: [String: MarkerAnnotation] = [:]
  private var disappearing: [String: MarkerAnnotation] = [:]
  private var flights: [ObjectIdentifier: MarkerFlight] = [:]
  private var flatIds = Set<String>()
  private var heading: Double = 0
  private var lastFrame: CFTimeInterval = 0
  private lazy var ticker = FrameTicker { [weak self] now in self?.advance(to: now) }

  init(mapView: MKMapView) {
    self.mapView = mapView
  }

  /// The published markers; disappearing ones are left out.
  var all: [MarkerAnnotation] { Array(annotations.values) }

  func icon(for key: String) -> MarkerIcon? { icons[key] }

  /// Returns the keys whose image could not be decoded; the others are registered.
  func registerIcons(_ newIcons: [PIcon]) -> [String] {
    var keys = Set<String>()
    var failed: [String] = []
    for icon in newIcons {
      guard let image = decodeImage(icon.pngBytes.data) else {
        failed.append(icon.key)
        continue
      }
      icons[icon.key] = MarkerIcon(
        image: image,
        logicalSize: CGSize(width: icon.logicalSize.width, height: icon.logicalSize.height),
        pixelRatio: CGFloat(icon.pixelRatio > 0 ? icon.pixelRatio : 1)
      )
      keys.insert(icon.key)
    }
    for annotation in Array(annotations.values) + Array(disappearing.values)
    where keys.contains(annotation.marker.iconKey) {
      refresh(annotation)
    }
    return failed
  }

  func update(added: [PMarker], changed: [PMarker], removedIds: [String], transition: PMarkerTransition? = nil) {
    guard let mapView else { return }
    let now = max(CACurrentMediaTime(), lastFrame)
    advance(to: now)
    let duration = transition.map { CFTimeInterval(max($0.durationMillis, 0)) / 1000 } ?? 0
    applyRemovals(removedIds, in: mapView, transition: transition, duration: duration, now: now)
    applyUpserts(added + changed, in: mapView, transition: transition, duration: duration, now: now)
    evictUnreferencedIcons()
  }

  private func applyRemovals(
    _ ids: [String], in mapView: MKMapView, transition: PMarkerTransition?, duration: CFTimeInterval,
    now: CFTimeInterval
  ) {
    var removedNow: [MarkerAnnotation] = []
    for id in ids {
      flatIds.remove(id)
      guard let annotation = annotations.removeValue(forKey: id) else { continue }
      if duration > 0 {
        annotation.isDisappearing = true
        disappearing[id] = annotation
        (mapView.view(for: annotation) as? MarkerAnnotationView)?.isEnabled = false
        let target = transition?.disappearTo[id]?.coordinate ?? annotation.coordinate
        fly(annotation, to: target, alpha: 0, start: now, duration: duration)
      } else {
        land(annotation)
        removedNow.append(annotation)
      }
    }
    if !removedNow.isEmpty { mapView.removeAnnotations(removedNow) }
  }

  private func applyUpserts(
    _ markers: [PMarker], in mapView: MKMapView, transition: PMarkerTransition?, duration: CFTimeInterval,
    now: CFTimeInterval
  ) {
    let animated = duration > 0
    var fresh: [MarkerAnnotation] = []
    for marker in markers {
      if marker.flat { flatIds.insert(marker.id) } else { flatIds.remove(marker.id) }
      let target = marker.position.coordinate
      let revived = disappearing[marker.id] != nil
      guard let existing = annotations[marker.id] ?? revive(marker.id) else {
        let annotation = MarkerAnnotation(marker: marker)
        annotations[marker.id] = annotation
        if animated {
          annotation.coordinate = transition?.appearFrom[marker.id]?.coordinate ?? target
          annotation.alpha = 0
          fly(annotation, to: target, alpha: 1, start: now, duration: duration)
        }
        fresh.append(annotation)
        continue
      }
      let previous = existing.marker
      existing.marker = marker
      if !animated {
        land(existing)
        place(existing, at: target, alpha: 1)
      } else if flights[ObjectIdentifier(existing)] != nil || previous.position != marker.position {
        fly(existing, to: target, alpha: 1, start: now, duration: duration)
      }
      if previous != marker || revived { refresh(existing) }
    }
    if !fresh.isEmpty { mapView.addAnnotations(fresh) }
  }

  /// The schema has no unregister call: an icon no published or disappearing marker uses is dropped, by the rule the
  /// Dart side mirrors to know which icons to send again.
  private func evictUnreferencedIcons() {
    var used = Set<String>()
    for annotation in annotations.values { used.insert(annotation.marker.iconKey) }
    for annotation in disappearing.values { used.insert(annotation.marker.iconKey) }
    if used.count < icons.count { icons = icons.filter { used.contains($0.key) } }
  }

  func view(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? {
    guard let annotation = annotation as? MarkerAnnotation else { return nil }
    let view =
      (mapView.dequeueReusableAnnotationView(withIdentifier: Self.reuseId) as? MarkerAnnotationView)
      ?? MarkerAnnotationView(annotation: annotation, reuseIdentifier: Self.reuseId)
    view.annotation = annotation
    view.configure(annotation: annotation, icon: icons[annotation.marker.iconKey], mapHeading: heading)
    return view
  }

  /// Flat markers rotate with the map, so a heading change re-applies their rotation.
  func setHeading(_ newHeading: Double) {
    guard abs(newHeading - heading) > 0.01 else { return }
    heading = newHeading
    for id in flatIds {
      if let annotation = annotations[id] { refresh(annotation) }
    }
    for annotation in disappearing.values where annotation.marker.flat {
      refresh(annotation)
    }
  }

  func removeAll() {
    ticker.stop()
    flights.removeAll()
    mapView?.removeAnnotations(Array(annotations.values) + Array(disappearing.values))
    annotations.removeAll()
    disappearing.removeAll()
    flatIds.removeAll()
    icons.removeAll()
  }

  private func revive(_ id: String) -> MarkerAnnotation? {
    guard let annotation = disappearing.removeValue(forKey: id) else { return nil }
    annotation.isDisappearing = false
    annotations[id] = annotation
    return annotation
  }

  private func fly(
    _ annotation: MarkerAnnotation, to target: CLLocationCoordinate2D, alpha: CGFloat, start: CFTimeInterval,
    duration: CFTimeInterval
  ) {
    flights[ObjectIdentifier(annotation)] = MarkerFlight(
      annotation: annotation, from: annotation.coordinate, to: target, fromAlpha: annotation.alpha, toAlpha: alpha,
      start: start, duration: duration)
    if let mapView, !ticker.isRunning { ticker.start(in: mapView) }
  }

  private func land(_ annotation: MarkerAnnotation) {
    flights.removeValue(forKey: ObjectIdentifier(annotation))
    if flights.isEmpty { ticker.stop() }
  }

  private func place(_ annotation: MarkerAnnotation, at coordinate: CLLocationCoordinate2D, alpha: CGFloat) {
    let current = annotation.coordinate
    if current.latitude != coordinate.latitude || current.longitude != coordinate.longitude {
      annotation.coordinate = coordinate
    }
    if annotation.alpha != alpha {
      annotation.alpha = alpha
      (mapView?.view(for: annotation) as? MarkerAnnotationView)?.setOpacity(alpha)
    }
  }

  private func advance(to now: CFTimeInterval) {
    lastFrame = max(lastFrame, now)
    guard !flights.isEmpty else { return }
    var landed: [MarkerAnnotation] = []
    for (key, flight) in flights {
      let progress = flight.duration > 0 ? min(max((now - flight.start) / flight.duration, 0), 1) : 1
      let eased = EaseInOut.value(at: progress)
      let coordinate = flight.moves && progress < 1 ? Self.interpolate(flight.from, flight.to, eased) : flight.to
      place(
        flight.annotation, at: coordinate, alpha: flight.fromAlpha + (flight.toAlpha - flight.fromAlpha) * eased)
      if progress >= 1 {
        flights.removeValue(forKey: key)
        if flight.annotation.isDisappearing { landed.append(flight.annotation) }
      }
    }
    if !landed.isEmpty {
      for annotation in landed where disappearing[annotation.marker.id] === annotation {
        disappearing.removeValue(forKey: annotation.marker.id)
      }
      mapView?.removeAnnotations(landed)
    }
    if flights.isEmpty { ticker.stop() }
  }

  /// Linear in latitude and in longitude along the shorter way round the antimeridian.
  static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ t: Double)
    -> CLLocationCoordinate2D
  {
    var dLon = b.longitude - a.longitude
    if dLon > 180 { dLon -= 360 } else if dLon < -180 { dLon += 360 }
    return CLLocationCoordinate2D(
      latitude: a.latitude + (b.latitude - a.latitude) * t,
      longitude: CameraMath.normalizedLongitude(a.longitude + dLon * t))
  }

  private func refresh(_ annotation: MarkerAnnotation) {
    guard let view = mapView?.view(for: annotation) as? MarkerAnnotationView else { return }
    view.configure(annotation: annotation, icon: icons[annotation.marker.iconKey], mapHeading: heading)
  }
}
