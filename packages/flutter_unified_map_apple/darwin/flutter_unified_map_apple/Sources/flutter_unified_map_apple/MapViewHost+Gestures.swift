import MapKit
import QuartzCore

#if os(iOS)
  import UIKit

  typealias PlatformGestureRecognizer = UIGestureRecognizer
#elseif os(macOS)
  import Cocoa

  typealias PlatformGestureRecognizer = NSGestureRecognizer
#endif

/// Taps, long presses and the user-gesture flag of camera moves.
extension MapViewHost {
  var ownRecognizers: [PlatformGestureRecognizer] {
    #if os(iOS)
      [tapRecognizer, doubleTapRecognizer, longPressRecognizer]
    #else
      [clickRecognizer, doubleClickRecognizer, pressRecognizer]
    #endif
  }

  /// MapKit's own recognizers, which it installs on the map view and on subviews a few levels down. Annotation views
  /// carry none, so their subtrees are skipped.
  var mapKitRecognizers: [PlatformGestureRecognizer] {
    let own = Set(ownRecognizers.map(ObjectIdentifier.init))
    var found: [PlatformGestureRecognizer] = []
    var views: [PlatformView] = [mapView]
    for _ in 0..<3 {
      for view in views {
        #if os(iOS)
          let recognizers = view.gestureRecognizers ?? []
        #else
          let recognizers = view.gestureRecognizers
        #endif
        found += recognizers.filter { !own.contains(ObjectIdentifier($0)) }
      }
      views = views.flatMap(\.subviews).filter { !($0 is MKAnnotationView) }
    }
    return found
  }

  func installGestures() {
    #if os(iOS)
      doubleTapRecognizer.numberOfTapsRequired = 2
      doubleTapRecognizer.delaysTouchesEnded = false
      tapRecognizer.addTarget(self, action: #selector(handleTap(_:)))
      tapRecognizer.require(toFail: doubleTapRecognizer)
      longPressRecognizer.addTarget(self, action: #selector(handleLongPress(_:)))
      for recognizer in ownRecognizers {
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        mapView.addGestureRecognizer(recognizer)
      }
    #else
      doubleClickRecognizer.numberOfClicksRequired = 2
      clickRecognizer.target = self
      clickRecognizer.action = #selector(handleClick(_:))
      pressRecognizer.target = self
      pressRecognizer.action = #selector(handlePress(_:))
      pressRecognizer.minimumPressDuration = 0.5
      for recognizer in ownRecognizers {
        recognizer.delaysPrimaryMouseButtonEvents = false
        recognizer.delegate = self
        mapView.addGestureRecognizer(recognizer)
      }
      // MapKit handles trackpad scrolls, pinches and rotations as events, not recognizers: they mark user gestures.
      eventMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.scrollWheel, .magnify, .rotate, .leftMouseDragged, .otherMouseDragged]
      ) { [weak self] event in
        MainActor.assumeIsolated { self?.noteUserEvent(event) }
        return event
      }
    #endif
  }

  func removeGestures() {
    for recognizer in ownRecognizers {
      mapView.removeGestureRecognizer(recognizer)
    }
    #if os(macOS)
      if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
      eventMonitor = nil
    #endif
  }

  #if os(macOS)
    private func noteUserEvent(_ event: NSEvent) {
      guard event.window != nil, event.window === mapView.window else { return }
      if mapView.bounds.contains(mapView.convert(event.locationInWindow, from: nil)) {
        lastUserEventTime = CACurrentMediaTime()
      }
    }
  #endif

  /// Whether a camera change comes from the user rather than from `setCamera`, a resize or a zoom-range clamp.
  func isUserGestureActive() -> Bool {
    #if os(macOS)
      if CACurrentMediaTime() - lastUserEventTime < 0.15 { return true }
    #endif
    for recognizer in mapKitRecognizers {
      switch recognizer.state {
      case .began, .changed:
        return true
      case .ended:
        #if os(iOS)
          if let tap = recognizer as? UITapGestureRecognizer, tap.numberOfTapsRequired >= 2 { return true }
        #else
          if let click = recognizer as? NSClickGestureRecognizer, click.numberOfClicksRequired >= 2 { return true }
        #endif
      default:
        break
      }
    }
    return false
  }

  /// MapKit has no switch for double-tap zoom alone, so its own double-tap recognizers are toggled (iOS only). The
  /// single-tap recognizer waits for the double tap only while a double tap can zoom: a disabled recognizer counts
  /// as failed, so taps are reported at once otherwise.
  func applyDoubleTapZoom() {
    #if os(iOS)
      let enabled = options.interaction.zoomEnabled && options.interaction.doubleTapZoomEnabled
      for case let tap as UITapGestureRecognizer in mapKitRecognizers
      where tap.numberOfTapsRequired == 2 && tap.numberOfTouchesRequired == 1 {
        tap.isEnabled = enabled
      }
      doubleTapRecognizer.isEnabled = enabled
    #else
      doubleClickRecognizer.isEnabled = options.interaction.zoomEnabled
    #endif
  }

  private func emitTap(atView point: CGPoint, longPress: Bool) {
    guard isReady, !isDisposed else { return }
    let screen = PPoint(topLeft(fromView: point))
    let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
    guard CLLocationCoordinate2DIsValid(coordinate) else { return }
    let position = PLatLng(coordinate)
    if longPress {
      events.send { api, id in try await api.onLongPress(viewId: id, position: position, screenPoint: screen) }
    } else {
      events.send { api, id in try await api.onTap(viewId: id, position: position, screenPoint: screen) }
    }
  }

  #if os(iOS)
    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended else { return }
      emitTap(atView: recognizer.location(in: mapView), longPress: false)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
      guard recognizer.state == .began else { return }
      emitTap(atView: recognizer.location(in: mapView), longPress: true)
    }
  #else
    @objc private func handleClick(_ recognizer: NSClickGestureRecognizer) {
      guard recognizer.state == .ended else { return }
      emitTap(atView: recognizer.location(in: mapView), longPress: false)
    }

    @objc private func handlePress(_ recognizer: NSPressGestureRecognizer) {
      guard recognizer.state == .began else { return }
      emitTap(atView: recognizer.location(in: mapView), longPress: true)
    }

    fileprivate func hitView(_ event: NSEvent) -> NSView? {
      guard let superview = mapView.superview else { return nil }
      return mapView.hitTest(superview.convert(event.locationInWindow, from: nil))
    }
  #endif

  /// A non-tappable or disappearing marker lets the tap through to the map, as a non-clickable Google Maps marker
  /// does, so the core can still hit-test the shapes beneath it.
  fileprivate func isOnTappableMarker(_ view: PlatformView?) -> Bool {
    var current = view
    while let candidate = current, candidate !== mapView {
      if let annotationView = candidate as? MKAnnotationView {
        guard let annotation = annotationView.annotation as? MarkerAnnotation else { return true }
        return annotation.marker.tappable && !annotation.isDisappearing
      }
      current = candidate.superview
    }
    return false
  }
}

#if os(iOS)
  extension MapViewHost: UIGestureRecognizerDelegate {
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      !isOnTappableMarker(touch.view)
    }
  }
#else
  extension MapViewHost: NSGestureRecognizerDelegate {
    func gestureRecognizer(
      _ gestureRecognizer: NSGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
      true
    }

    func gestureRecognizer(
      _ gestureRecognizer: NSGestureRecognizer,
      shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
      gestureRecognizer === clickRecognizer && otherGestureRecognizer === doubleClickRecognizer
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent)
      -> Bool
    {
      !isOnTappableMarker(hitView(event))
    }
  }
#endif
