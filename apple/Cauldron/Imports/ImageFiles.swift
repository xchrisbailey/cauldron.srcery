import CauldronImports
import CauldronKit
import Foundation

/// Reads image files the cook chose or dropped, on the Mac. Nothing is copied anywhere: the
/// bytes go into memory and the file is left as it was.
enum ImageFiles {
  /// The bytes of each file that could be read, and why the first that couldn't be wasn't. A file
  /// over the size limit is not read at all. Runs off the main actor.
  static func read(_ urls: [URL]) async -> (images: [Data], problem: PhotoError?) {
    await Task.detached {
      var images: [Data] = []
      var problem: PhotoError?
      for url in urls {
        // A file from the open panel or a drop is outside the sandbox until this is asked.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard url.isFileURL, size > 0 else {
          problem = problem ?? .unreadable
          continue
        }
        guard size <= PhotoProcessing.maxBytes else {
          problem = problem ?? .tooLarge
          continue
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
          problem = problem ?? .unreadable
          continue
        }
        images.append(data)
      }
      return (images, problem)
    }.value
  }
}
