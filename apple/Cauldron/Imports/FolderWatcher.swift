import Foundation

/// Tells the app when something is added to or removed from a folder, as the share extension
/// leaves a finished recipe for a Cauldron that is already open (#205).
///
/// The folder is watched, rather than the extension posting a Darwin notification, because both
/// sides already share the folder and nothing else has to be agreed: no notification name to keep
/// in step, and no sandbox rule on which names an extension may post. It needs no entitlement.
enum FolderWatcher {
  /// One value each time the folder changes, and one at the start: the folder may have changed
  /// before the watch began, and a look at it costs nothing. Changes that come close together
  /// are one value. The stream ends when the folder can't be opened or goes away, and its watch
  /// ends when it is no longer read.
  ///
  /// The watch is in place by the time this returns, so a change made after the call is never
  /// missed.
  static func changes(in folder: URL) -> AsyncStream<Void> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let descriptor = open(folder.path(percentEncoded: false), O_EVTONLY)
      guard descriptor >= 0 else {
        continuation.finish()
        return
      }
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: descriptor, eventMask: [.write, .extend, .rename, .delete],
        queue: DispatchQueue(label: "computer.srcery.cauldron.folder-watcher"))
      source.setEventHandler {
        // The folder itself moved or went: there is nothing left to watch.
        if !source.data.isDisjoint(with: [.rename, .delete]) {
          continuation.finish()
        } else {
          continuation.yield()
        }
      }
      source.setCancelHandler { close(descriptor) }
      continuation.onTermination = { _ in source.cancel() }
      source.resume()
      continuation.yield()
    }
  }
}
