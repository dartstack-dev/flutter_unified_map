#if os(iOS)
  import Flutter
  import UIKit

  typealias PlatformView = UIView
  typealias PlatformImage = UIImage
  typealias PlatformColor = UIColor
  typealias PlatformEdgeInsets = UIEdgeInsets
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS

  typealias PlatformView = NSView
  typealias PlatformImage = NSImage
  typealias PlatformColor = NSColor
  typealias PlatformEdgeInsets = NSEdgeInsets
#endif

extension PlatformImage {
  var platformCGImage: CGImage? {
    #if os(iOS)
      return cgImage
    #else
      var rect = CGRect(origin: .zero, size: size)
      return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    #endif
  }

  var platformScale: CGFloat {
    #if os(iOS)
      return scale
    #else
      guard let image = platformCGImage, size.width > 0 else { return 1 }
      return CGFloat(image.width) / size.width
    #endif
  }
}
