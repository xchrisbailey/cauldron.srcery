import CauldronKit
import Foundation

/// Fetches an import's cover photo (`Photos.fromUrl` and `coverPhoto` in the reference). A photo
/// that can't be had leaves the draft without one: nothing here throws, and nothing here may
/// fail an import or hold it up.
enum CoverPhoto {
  /// The same 15 MB a photo the cook picks may be.
  static let maxBytes = PhotoProcessing.maxBytes
  /// A photo from a page may declare this many pixels (24 megapixels) and no more. A page can
  /// serve a file under 100 KB that declares 100 million pixels, which decodes to 400 MB; the
  /// 100 megapixels the picker allows is for photos the cook chose.
  static let maxPixels = 24_000_000
  /// The reference gave the photo this long, after which the draft goes without one.
  static let timeout = Duration.seconds(20)

  /// Turns the bytes into a photo, or nothing. A test swaps in a slow one.
  typealias Decode = @Sendable (Data) -> ProcessedPhoto?

  static let decode: Decode = { bytes in
    switch PhotoProcessing.process(bytes, maxPixels: maxPixels) {
    case .success(let photo): return photo
    case .failure: return nil
    }
  }

  /// The photo, or nil if it can't be had within `timeout`. The limit bounds the whole step as
  /// the import sees it: fetch and decode. A decode that is still running when it passes (it
  /// has no point to be cancelled at) is left to finish on its own and its result is dropped.
  static func fetch(
    _ link: String, using fetcher: any PageFetcher, timeout: Duration = CoverPhoto.timeout,
    decode: @escaping Decode = CoverPhoto.decode
  ) async -> ProcessedPhoto? {
    guard Distill.isAcceptedLink(link) else { return nil }
    // The first thing put in the stream is the answer: the work's, the clock's, or nil because
    // the import was cancelled.
    let (answers, answer) = AsyncStream<ProcessedPhoto?>.makeStream(
      bufferingPolicy: .bufferingOldest(1))
    let work = Task.detached {
      answer.yield(await load(link, using: fetcher, decode: decode))
    }
    let clock = Task.detached {
      try? await Task.sleep(for: timeout)
      answer.yield(nil)
    }
    let photo = await withTaskCancellationHandler {
      var iterator = answers.makeAsyncIterator()
      return await iterator.next() ?? nil
    } onCancel: {
      answer.yield(nil)
    }
    work.cancel()
    clock.cancel()
    return photo
  }

  private static func load(
    _ link: String, using fetcher: any PageFetcher, decode: Decode
  ) async -> ProcessedPhoto? {
    do {
      let page = try await fetcher.fetch(
        FetchRequest(url: link, maxBytes: maxBytes, accept: "image/*"))
      guard page.bytes.count <= maxBytes, !page.bytes.isEmpty, isImageType(page.contentType)
      else { return nil }
      // The decode checks the bytes are an image this device can read, within the pixel limit,
      // downscales and re-encodes.
      return decode(page.bytes)
    } catch {
      return nil
    }
  }

  /// A page of HTML or JSON is an error page, not a photo. A server that doesn't say, or says
  /// "binary", is given the benefit of the doubt, as the decode is the real check.
  static func isImageType(_ contentType: String?) -> Bool {
    guard
      let type = contentType?.split(separator: ";").first?
        .trimmingCharacters(in: .whitespaces).lowercased(), !type.isEmpty
    else { return true }
    return type.hasPrefix("image/") || type == "application/octet-stream"
      || type == "binary/octet-stream"
  }
}
