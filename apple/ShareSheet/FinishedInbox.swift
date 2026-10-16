import CauldronImports
import Foundation

/// Where the share extension leaves a recipe it read and the cook kept, for the app to put in
/// the recipe box (#201). One JSON file per recipe, named for its id, in a folder of its own in
/// the App Group container.
///
/// The folder is not the link-or-text inbox's (`ShareInbox`): that one removes any file it can't
/// read as a `SharedItem`, which would throw a finished recipe away. And unlike that inbox,
/// nothing here is removed until the app has saved what it holds (`remove`).
enum FinishedInbox {
  /// A payload waiting, and the file it came from.
  struct Entry {
    var recipe: FinishedRecipe
    var file: URL
  }

  /// The folder. Nil when the build has no App Group (no signing team).
  static func folder(fileManager: FileManager = .default) -> URL? {
    guard
      let root = fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: ShareInbox.appGroupID)
    else { return nil }
    let folder = root.appending(path: "FinishedRecipes", directoryHint: .isDirectory)
    try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  /// Leaves `recipe` for the app. Throws when there is no folder or it can't be written. The
  /// file is written whole or not at all, so the app never reads half of one.
  static func add(_ recipe: FinishedRecipe, in folder: URL? = folder()) throws {
    guard let folder else { throw CocoaError(.fileNoSuchFile) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(recipe)
    try data.write(to: file(for: recipe.id, in: folder), options: [.atomic])
  }

  /// Every waiting payload, oldest first. Nothing is removed, except a file that can't be read
  /// or is of another version: it could never be saved, and would only be tried again for ever.
  static func pending(from folder: URL? = folder(), fileManager: FileManager = .default)
    -> [Entry]
  {
    guard let folder,
      let files = try? fileManager.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
    else { return [] }
    var entries: [Entry] = []
    for file in files where file.pathExtension == "json" {
      if let data = try? Data(contentsOf: file),
        let recipe = try? JSONDecoder().decode(FinishedRecipe.self, from: data),
        recipe.version == FinishedRecipe.currentVersion
      {
        entries.append(Entry(recipe: recipe, file: file))
      } else {
        try? fileManager.removeItem(at: file)
      }
    }
    return entries.sorted { $0.recipe.sharedAt < $1.recipe.sharedAt }
  }

  /// Removes a payload once the recipe it holds is saved.
  static func remove(_ entry: Entry, fileManager: FileManager = .default) {
    try? fileManager.removeItem(at: entry.file)
  }

  private static func file(for id: UUID, in folder: URL) -> URL {
    folder.appending(path: "\(id.uuidString).json")
  }
}
