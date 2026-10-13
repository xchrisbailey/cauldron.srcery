import CauldronKit
import Foundation

/// Fetches an import's cover photo (`Photos.fromUrl` and `coverPhoto` in the reference). A photo
/// that can't be had leaves the draft without one: nothing here throws, and nothing here may
/// fail an import.
enum CoverPhoto {
  /// The same 15 MB a photo the cook picks may be.
  static let maxBytes = PhotoProcessing.maxBytes
  /// The reference gave the photo this long, after which the draft goes without one.
  static let timeout = Duration.seconds(20)

  static func fetch(
    _ link: String, using fetcher: any PageFetcher, timeout: Duration = CoverPhoto.timeout
  ) async -> ProcessedPhoto? {
    guard Distill.isAcceptedLink(link) else { return nil }
    return await withTaskGroup(of: ProcessedPhoto?.self) { group in
      group.addTask { await load(link, using: fetcher) }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }

  private static func load(_ link: String, using fetcher: any PageFetcher) async
    -> ProcessedPhoto?
  {
    do {
      let page = try await fetcher.fetch(
        FetchRequest(url: link, maxBytes: maxBytes, accept: "image/*"))
      guard page.bytes.count <= maxBytes, !page.bytes.isEmpty, isImageType(page.contentType)
      else { return nil }
      // The decode checks the bytes are an image this device can read, downscales and
      // re-encodes.
      switch PhotoProcessing.process(page.bytes) {
      case .success(let photo): return photo
      case .failure: return nil
      }
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
