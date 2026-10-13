import CauldronKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Vision

/// Why a page couldn't be read.
enum PageReadError: Error, Equatable, Sendable {
  /// The bytes aren't an image this device can decode.
  case unreadable
  /// Recognition itself failed.
  case failed
  /// The work was cancelled, such as by Stop or by closing the sheet. Not a failure to show.
  case cancelled
}

/// Reads the text off a photographed page. Everything here is on the device: an image never
/// leaves it, and only the text goes on to the model, as pasted text does. The live one is
/// `VisionTextReader`; tests use a fake.
protocol RecipeTextReader: Sendable {
  /// The text on one page, as lines in reading order, or an empty string when there is none.
  /// `image` is the bytes of an image in any format ImageIO reads.
  func read(_ image: Data) async throws(PageReadError) -> String
}

/// Vision's text recognition, at the accurate level with language correction, and the text put
/// in reading order (`ReadingOrder`). The Swift API (`RecognizeTextRequest`) is the current one
/// for iOS 27 and macOS 27: the older `VNRecognizeTextRequest` is its Objective-C twin.
struct VisionTextReader: RecipeTextReader {
  /// A photo is shrunk to this on its long side before it is read. A page photographed on a
  /// phone is 12 to 48 megapixels; recognition gets nothing from more than this (an A4 page at
  /// 350 dpi), and the decode would hold hundreds of megabytes.
  static let longSide = 4096

  init() {}

  @concurrent
  func read(_ image: Data) async throws(PageReadError) -> String {
    guard let page = Self.page(from: image, longSide: Self.longSide) else { throw .unreadable }
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = true
    let observations: [RecognizedTextObservation]
    do {
      observations = try await request.perform(on: page)
    } catch is CancellationError {
      throw .cancelled
    } catch {
      throw .failed
    }
    if Task.isCancelled { throw .cancelled }
    return ReadingOrder.text(Self.fragments(from: observations))
  }

  /// Vision's boxes start at the bottom-left corner; reading order's start at the top-left.
  static func fragments(from observations: [RecognizedTextObservation]) -> [TextFragment] {
    observations.map { observation in
      let box = observation.boundingBox.cgRect
      return TextFragment(
        text: observation.transcript,
        box: TextBox(
          x: Double(box.minX), y: Double(1 - box.maxY), width: Double(box.width),
          height: Double(box.height)))
    }
  }

  /// The image upright (its orientation applied) and no larger than `longSide`.
  static func page(from data: Data, longSide: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0
    else { return nil }
    // Never enlarges.
    let side = min(longSide, max(width, height))
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: side,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }
}

extension EnvironmentValues {
  /// What reads text off a photographed page for Distill: Vision unless a preview or a test says
  /// otherwise.
  @Entry var recipeTextReader: any RecipeTextReader = VisionTextReader()
}
