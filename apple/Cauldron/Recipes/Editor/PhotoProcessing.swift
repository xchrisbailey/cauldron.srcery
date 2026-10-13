import CauldronKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo ready to store: JPEG, no larger than `PhotoProcessing.maxPixel` on its long side.
struct ProcessedPhoto: Equatable, Sendable {
  var data: Data
  var width: Int
  var height: Int
}

/// Why a photo couldn't be used. Each has a plain message from the copy module.
enum PhotoError: Error, Equatable, Sendable {
  /// The file isn't an image this device can read.
  case unsupported
  /// It's over the size limit before any processing.
  case tooLarge
  /// It's an image, but too many pixels to work on safely.
  case tooBig
  /// It looks like an image but can't be decoded or re-encoded.
  case unreadable

  var message: CopyString {
    switch self {
    case .unsupported: Copy.photos.unsupported
    case .tooLarge: Copy.photos.tooLarge
    case .tooBig: Copy.photos.tooBig
    case .unreadable: Copy.photos.couldntRead
    }
  }
}

/// Downscales and compresses a photo before it's saved. A pure function of the bytes, so it
/// runs off the main thread and without a view.
enum PhotoProcessing {
  /// The long side, in pixels. Enough for a full-width hero on a large display.
  static let maxPixel = 2048
  static let quality = 0.8
  /// The same 15 MB the web uploads allow.
  static let maxBytes = 15 * 1024 * 1024
  /// Beyond this many pixels (about 100 megapixels) decoding is refused rather than risked.
  static let maxPixels = 100_000_000

  /// `maxPixels` is how many pixels an image may declare before decoding is refused. The
  /// default is generous, for a photo the cook picked; an image from a web page gets less.
  static func process(
    _ data: Data, maxPixel: Int = PhotoProcessing.maxPixel,
    maxPixels: Int = PhotoProcessing.maxPixels
  ) -> Result<ProcessedPhoto, PhotoError> {
    guard data.count <= maxBytes else { return .failure(.tooLarge) }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let type = CGImageSourceGetType(source), UTType(type as String)?.conforms(to: .image) == true,
      CGImageSourceGetCount(source) > 0
    else { return .failure(.unsupported) }

    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
      let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
      pixelWidth > 0, pixelHeight > 0
    else { return .failure(.unreadable) }
    // Read from the header, before anything is decoded: a tiny file can declare a huge image.
    guard pixelWidth * pixelHeight <= maxPixels else { return .failure(.tooBig) }

    // Never enlarges: a small photo is only re-encoded.
    let side = min(maxPixel, max(pixelWidth, pixelHeight))
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: side,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
      let flattened = onWhite(image)
    else { return .failure(.unreadable) }

    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, UTType.jpeg.identifier as CFString, 1, nil)
    else { return .failure(.unreadable) }
    CGImageDestinationAddImage(
      destination, flattened,
      [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return .failure(.unreadable) }
    return .success(
      ProcessedPhoto(data: output as Data, width: flattened.width, height: flattened.height))
  }

  /// JPEG has no transparency, so a transparent PNG would come out black without this.
  private static func onWhite(_ image: CGImage) -> CGImage? {
    guard
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(bounds)
    context.draw(image, in: bounds)
    return context.makeImage()
  }
}
