import CoreLocation
import Foundation
import ImageIO
import MapKit

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif

// Contract stub: the previous boolean switches derived from the flutter_map flags; the Apple unit replaces them with
// one native switch per flag.
extension PInteraction {
  private static let drag: Int64 = 1
  private static let pinchMove: Int64 = 1 << 2
  private static let pinchZoom: Int64 = 1 << 3
  private static let doubleTapZoom: Int64 = 1 << 4
  private static let scrollWheelZoom: Int64 = 1 << 6
  private static let rotate: Int64 = 1 << 7

  var scrollEnabled: Bool { flags & (Self.drag | Self.pinchMove) != 0 }
  var zoomEnabled: Bool { flags & (Self.pinchZoom | Self.scrollWheelZoom) != 0 }
  var rotateEnabled: Bool { flags & Self.rotate != 0 }
  var doubleTapZoomEnabled: Bool { flags & Self.doubleTapZoom != 0 }
}

extension PMapOptions {
  var showsScale: Bool { apple?.showsScale ?? false }
}

extension PLatLng {
  init(_ coordinate: CLLocationCoordinate2D) {
    self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
  }

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}

extension PPoint {
  init(_ point: CGPoint) {
    self.init(x: Double(point.x), y: Double(point.y))
  }

  var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

extension PSize {
  init(_ size: CGSize) {
    self.init(width: Double(size.width), height: Double(size.height))
  }
}

extension PEdgeInsets {
  var platformInsets: PlatformEdgeInsets {
    PlatformEdgeInsets(top: CGFloat(top), left: CGFloat(left), bottom: CGFloat(bottom), right: CGFloat(right))
  }
}

func platformColor(argb: Int64) -> PlatformColor {
  let value = UInt32(truncatingIfNeeded: argb)
  let alpha = CGFloat((value >> 24) & 0xFF) / 255
  let red = CGFloat((value >> 16) & 0xFF) / 255
  let green = CGFloat((value >> 8) & 0xFF) / 255
  let blue = CGFloat(value & 0xFF) / 255
  #if os(iOS)
    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
  #else
    return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
  #endif
}

extension PStrokeCap {
  var lineCap: CGLineCap {
    switch self {
    case .butt: return .butt
    case .round: return .round
    case .square: return .square
    }
  }
}

extension PStrokeJoin {
  var lineJoin: CGLineJoin {
    switch self {
    case .miter: return .miter
    case .round: return .round
    case .bevel: return .bevel
    }
  }
}

/// Any format ImageIO reads (tiles are often JPEG). Decoded now rather than when Core Animation first draws the image,
/// which would be on the main thread in the frame where many new markers appear.
func decodeImage(_ data: Data) -> CGImage? {
  guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
  return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
}

func encodePNG(_ image: CGImage) -> Data? {
  let data = NSMutableData()
  guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil)
  else { return nil }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { return nil }
  return data as Data
}
