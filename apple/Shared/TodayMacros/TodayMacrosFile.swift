import Foundation

/// The snapshot as a file: one JSON file in the App Group container, replaced atomically so the
/// widget never reads half of one. The folder is a parameter so tests write to a folder of their
/// own and never the real container. Shared by the app and the widget extension.
enum TodayMacrosFile {
  static let fileName = "TodayMacros.json"

  /// The App Group container. Nil when the build has no App Group (no signing team).
  static func liveFolder(fileManager: FileManager = .default) -> URL? {
    fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppGroupName.id)
  }

  /// Replaces the file with `snapshot`. Throws when there is no folder or it can't be written.
  static func write(_ snapshot: TodayMacrosSnapshot, to folder: URL?) throws {
    guard let folder else { throw CocoaError(.fileNoSuchFile) }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(snapshot).write(
      to: folder.appending(path: fileName, directoryHint: .notDirectory), options: [.atomic])
  }

  /// The snapshot the app left, or nil when there is none or it can't be read.
  static func read(from folder: URL?) -> TodayMacrosSnapshot? {
    guard let folder,
      let data = try? Data(
        contentsOf: folder.appending(path: fileName, directoryHint: .notDirectory))
    else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(TodayMacrosSnapshot.self, from: data)
  }
}
