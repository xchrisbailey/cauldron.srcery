import Foundation

/// A folder in the App Group container, where the app and the share extension leave things for
/// each other.
enum AppGroupFolder {
  /// The folder called `name`, made if it isn't there. Nil when the build has no App Group (no
  /// signing team).
  static func named(_ name: String, fileManager: FileManager = .default) -> URL? {
    guard
      let root = fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: AppGroupName.id)
    else { return nil }
    let folder = root.appending(path: name, directoryHint: .isDirectory)
    try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }
}
