import Foundation

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif

/// Creation params are `[viewId, PMapOptions]`, sent with the Pigeon codec by `UnifiedMapsApple.buildView`.
final class MapViewFactory: NSObject, FlutterPlatformViewFactory {
  private let registry: MapViewRegistry
  private let flutterApi: UnifiedMapsFlutterApi

  init(registry: MapViewRegistry, flutterApi: UnifiedMapsFlutterApi) {
    self.registry = registry
    self.flutterApi = flutterApi
  }

  #if os(iOS)
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
      MainActor.assumeIsolated {
        let (view, release) = makeView(frame: frame, arguments: args)
        return MapPlatformView(view: view, onRelease: release)
      }
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
      MessagesPigeonCodec.shared
    }
  #else
    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
      MainActor.assumeIsolated {
        let (view, release) = makeView(frame: .zero, arguments: args)
        return MapContainerView(content: view, onRelease: release)
      }
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
      MessagesPigeonCodec.shared
    }
  #endif

  @MainActor
  private func makeView(frame: CGRect, arguments: Any?) -> (view: PlatformView, release: @MainActor () -> Void) {
    guard let args = arguments as? [Any?], args.count == 2, let viewId = args[0] as? Int64,
      let options = args[1] as? PMapOptions
    else { return (PlatformView(frame: frame), {}) }
    let host = MapViewHost(viewId: viewId, frame: frame, options: options, flutterApi: flutterApi)
    registry.add(host)
    let registry = self.registry
    return (host.mapView, { [weak host] in if let host { registry.release(host) } })
  }
}

/// The engine releases its platform views without a Dart `dispose` on hot restart, and creates then releases one for a
/// map unmounted before its view existed: releasing the host when the engine lets go of the view keeps the registry
/// from holding dead maps. Only the engine retains this object.
#if os(iOS)
  final class MapPlatformView: NSObject, FlutterPlatformView {
    private let mapView: UIView
    private let onRelease: @MainActor () -> Void

    init(view: UIView, onRelease: @escaping @MainActor () -> Void) {
      mapView = view
      self.onRelease = onRelease
    }

    deinit {
      let release = onRelease
      DispatchQueue.main.async { MainActor.assumeIsolated { release() } }
    }

    func view() -> UIView { mapView }
  }
#else
  final class MapContainerView: NSView {
    private let releaser: Releaser

    init(content: NSView, onRelease: @escaping @MainActor () -> Void) {
      releaser = Releaser(onRelease)
      super.init(frame: content.frame)
      content.frame = bounds
      content.autoresizingMask = [.width, .height]
      addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not supported")
    }
  }

  /// Runs the release when the container goes away; kept outside the main-actor NSView so its deinit can hand the
  /// release to the main queue.
  private final class Releaser {
    private let body: @MainActor () -> Void

    init(_ body: @escaping @MainActor () -> Void) {
      self.body = body
    }

    deinit {
      let release = body
      DispatchQueue.main.async { MainActor.assumeIsolated { release() } }
    }
  }
#endif
