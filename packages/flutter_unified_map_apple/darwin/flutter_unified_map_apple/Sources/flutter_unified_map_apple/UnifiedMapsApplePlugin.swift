#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif

public class UnifiedMapsApplePlugin: NSObject, FlutterPlugin {
  static let viewType = "flutter_unified_map_apple/map"

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let registry = MainActor.assumeIsolated { MapViewRegistry() }
    let flutterApi = UnifiedMapsFlutterApi(binaryMessenger: messenger)
    UnifiedMapsHostApiSetup.setUp(binaryMessenger: messenger, api: HostApiImpl(registry: registry))
    registrar.register(MapViewFactory(registry: registry, flutterApi: flutterApi), withId: viewType)
  }
}
