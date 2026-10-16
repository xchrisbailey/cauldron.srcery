import Foundation

/// Something shared to Cauldron from another app: a link, some text, or both.
struct SharedItem: Codable, Sendable, Equatable, Identifiable {
  var id = UUID()
  var url: String?
  var text: String?
  var sharedAt = Date.now
}

/// Where the share extension leaves what it was given, for the app to pick up. One small JSON
/// file per item in the App Group container, so the extension and the app never write the same
/// file. Shared by the app and its extensions.
enum ShareInbox {
  static let appGroupID = AppGroupName.id
  /// Text beyond this is cut: far more than any recipe, and the import caps it again.
  static let textMax = 50_000

  /// The inbox folder. Nil when the build has no App Group (no signing team).
  static func folder(fileManager: FileManager = .default) -> URL? {
    guard
      let root = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    else { return nil }
    let folder = root.appending(path: "ShareInbox", directoryHint: .isDirectory)
    try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  /// Leaves `item` for the app. Throws when there is no inbox or it can't be written.
  static func add(_ item: SharedItem, in folder: URL? = folder()) throws {
    guard let folder else { throw CocoaError(.fileNoSuchFile) }
    var item = item
    item.text = item.text.map { String($0.prefix(textMax)) }
    let data = try JSONEncoder().encode(item)
    try data.write(
      to: folder.appending(path: "\(item.id.uuidString).json"), options: [.atomic])
  }

  /// Every waiting item, oldest first, removed from the inbox as it is read. A file that
  /// can't be read is removed too, so it can't block the inbox for ever.
  static func takeAll(from folder: URL? = folder(), fileManager: FileManager = .default)
    -> [SharedItem]
  {
    guard let folder,
      let files = try? fileManager.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
    else { return [] }
    var items: [SharedItem] = []
    for file in files where file.pathExtension == "json" {
      if let data = try? Data(contentsOf: file),
        let item = try? JSONDecoder().decode(SharedItem.self, from: data)
      {
        items.append(item)
      }
      try? fileManager.removeItem(at: file)
    }
    return items.sorted { $0.sharedAt < $1.sharedAt }
  }
}
