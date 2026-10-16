import CauldronKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo ready to store: JPEG, no larger than `PhotoProcessing.maxPixel` on its long side.
public struct ProcessedPhoto: Equatable, Sendable {
  public var data: Data
  public var width: Int
  public var height: Int

  public init(data: Data, width: Int, height: Int) {
    self.data = data
    self.width = width
    self.height = height
  }
}

/// Why a photo couldn't be used. Each has a plain message from the copy module.
public enum PhotoError: Error, Equatable, Sendable {
  /// The file isn't an image this device can read.
  case unsupported
  /// It's over the size limit before any processing.
  case tooLarge
  /// It's an image, but too many pixels to work on safely.
  case tooBig
  /// It looks like an image but can't be decoded or re-encoded.
  case unreadable

  public var message: CopyString {
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
public enum PhotoProcessing {
  /// The long side, in pixels. Enough for a full-width hero on a large display.
  public static let maxPixel = 2048
  public static let quality = 0.8
  /// The same 15 MB the web uploads allow.
  public static let maxBytes = 15 * 1024 * 1024
  /// Beyond this many pixels (about 100 megapixels) decoding is refused rather than risked.
  public static let maxPixels = 100_000_000

  /// `maxPixels` is how many pixels an image may declare before decoding is refused. The
  /// default is generous, for a photo the cook picked; an image from a web page gets less.
  public static func process(
    _ data: Data, maxPixel: Int = PhotoProcessing.maxPixel,
    maxPixels: Int = PhotoProcessing.maxPixels
  ) -> Result<ProcessedPhoto, PhotoError> {
    let source: CGImageSource
    let pixelWidth: Int
    let pixelHeight: Int
    switch header(of: data, maxPixels: maxPixels) {
    case .success(let found): (source, pixelWidth, pixelHeight) = found
    case .failure(let error): return .failure(error)
    }

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

  /// Whether `data` is an image this device can read that is within the limits, and its size in
  /// pixels, from its header alone: nothing is decoded.
  public static func inspect(_ data: Data, maxPixels: Int = PhotoProcessing.maxPixels)
    -> Result<(width: Int, height: Int), PhotoError>
  {
    header(of: data, maxPixels: maxPixels).map { (width: $0.1, height: $0.2) }
  }

  private static func header(of data: Data, maxPixels: Int)
    -> Result<(CGImageSource, Int, Int), PhotoError>
  {
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
    return .success((source, pixelWidth, pixelHeight))
  }

  /// The image shrunk to `maxPixel` on its long side and turned upright, for showing small. Nil
  /// when there is nothing to decode.
  public static func thumbnail(of data: Data?, maxPixel: Int) -> CGImage? {
    guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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
