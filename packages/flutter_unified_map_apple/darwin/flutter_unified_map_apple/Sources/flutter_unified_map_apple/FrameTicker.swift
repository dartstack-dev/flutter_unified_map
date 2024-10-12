import QuartzCore

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import Cocoa
#endif

/// Calls `onFrame` on every display refresh while running, with the time the frame will be presented (the display
/// link's target timestamp, so positions match MapKit's own camera animation). Runs in the common run loop modes so it
/// keeps ticking while a map gesture tracks events.
@MainActor
final class FrameTicker {
  private let onFrame: @MainActor (CFTimeInterval) -> Void
  #if os(iOS)
    private var link: CADisplayLink?
  #else
    private var link: AnyObject?
    private var timer: Timer?
  #endif

  init(onFrame: @escaping @MainActor (CFTimeInterval) -> Void) {
    self.onFrame = onFrame
  }

  var isRunning: Bool {
    #if os(macOS)
      return link != nil || timer != nil
    #else
      return link != nil
    #endif
  }

  func start(in view: PlatformView) {
    guard !isRunning else { return }
    let target = FrameTickerTarget { [weak self] time in
      guard let self else { return false }
      self.onFrame(time)
      return true
    }
    #if os(iOS)
      let link = CADisplayLink(target: target, selector: #selector(FrameTickerTarget.step))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
      link.add(to: .main, forMode: .common)
      self.link = link
    #else
      if #available(macOS 14.0, *) {
        let link = view.displayLink(target: target, selector: #selector(FrameTickerTarget.step))
        link.add(to: .main, forMode: .common)
        self.link = link
      } else {
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
          MainActor.assumeIsolated { target.fire(timer) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
      }
    #endif
  }

  func stop() {
    #if os(iOS)
      link?.invalidate()
    #else
      if #available(macOS 14.0, *) { (link as? CADisplayLink)?.invalidate() }
      timer?.invalidate()
      timer = nil
    #endif
    link = nil
  }
}

/// CADisplayLink retains its target, so the ticker hands it this proxy instead of itself. The run loop keeps the link
/// or timer alive, so the proxy invalidates it once the ticker is gone, even if nobody called `stop()`.
@MainActor
private final class FrameTickerTarget: NSObject {
  private let body: @MainActor (CFTimeInterval) -> Bool

  init(_ body: @escaping @MainActor (CFTimeInterval) -> Bool) {
    self.body = body
  }

  @objc func step(_ link: AnyObject) {
    #if os(iOS)
      guard let link = link as? CADisplayLink else { return }
    #else
      guard #available(macOS 14.0, *), let link = link as? CADisplayLink else { return }
    #endif
    if !body(link.targetTimestamp) { link.invalidate() }
  }

  func fire(_ timer: Timer) {
    if !body(CACurrentMediaTime()) { timer.invalidate() }
  }
}

/// CSS / Core Animation `ease-in-out`, the curve every backend uses for marker transitions.
enum EaseInOut {
  private static let p1 = (x: 0.42, y: 0.0)
  private static let p2 = (x: 0.58, y: 1.0)

  static func value(at t: Double) -> Double {
    guard t > 0 else { return 0 }
    guard t < 1 else { return 1 }
    var s = t
    for _ in 0..<8 {
      let x = bezier(s, p1.x, p2.x) - t
      let dx = derivative(s, p1.x, p2.x)
      if abs(x) < 1e-6 || abs(dx) < 1e-6 { break }
      s = min(max(s - x / dx, 0), 1)
    }
    return bezier(s, p1.y, p2.y)
  }

  private static func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
    let u = 1 - s
    return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
  }

  private static func derivative(_ s: Double, _ a: Double, _ b: Double) -> Double {
    let u = 1 - s
    return 3 * u * u * a + 6 * u * s * (b - a) + 3 * s * s * (1 - b)
  }
}
