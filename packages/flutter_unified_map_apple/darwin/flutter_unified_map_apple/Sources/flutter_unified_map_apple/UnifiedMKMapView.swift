import MapKit

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif

final class UnifiedMKMapView: MKMapView {
  var onLayout: (() -> Void)?
  var onWindowChange: (() -> Void)?

  #if os(iOS)
    override func layoutSubviews() {
      super.layoutSubviews()
      onLayout?()
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      onWindowChange?()
    }
  #else
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      onWindowChange?()
    }

    override func setFrameSize(_ newSize: NSSize) {
      super.setFrameSize(newSize)
      needsLayout = true
    }

    override func layout() {
      super.layout()
      onLayout?()
    }
  #endif
}

@MainActor
final class MapEventSink {
  private let api: UnifiedMapsFlutterApi
  private let viewId: Int64
  var isEnabled = true

  init(api: UnifiedMapsFlutterApi, viewId: Int64) {
    self.api = api
    self.viewId = viewId
  }

  /// Tasks enqueued on the main actor run in order, so events reach Dart in the order they were sent.
  func send(_ call: @escaping @MainActor (UnifiedMapsFlutterApi, Int64) async throws -> Void) {
    guard isEnabled else { return }
    let api = self.api
    let viewId = self.viewId
    Task { @MainActor in try? await call(api, viewId) }
  }
}

@MainActor
func runOnMain(after seconds: Double, _ body: @escaping @MainActor () -> Void) {
  DispatchQueue.main.asyncAfter(deadline: .now() + max(seconds, 0)) {
    MainActor.assumeIsolated { body() }
  }
}
