import CauldronKit
import Foundation

/// The rules for telling whether a link is one the cook already has (#204). One place for the
/// app's duplicate check (`DuplicateLinks`) and the share sheet's, so they can't drift.
enum SavedLinks {
  /// The forms of `link` a match is made on: as given (less surrounding space), and without the
  /// parts that don't change the page (`Distill.normalizeURL`). Empty for no link.
  ///
  /// Two links are the same page when their keys share a form. Keeping both forms on each side
  /// means a link typed in by hand with a trailing slash still matches one without.
  static func keys(of link: String?) -> Set<String> {
    guard let link else { return [] }
    let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    return [trimmed, Distill.normalizeURL(trimmed)]
  }

  /// The keys of all of `links`.
  static func keys(of links: [String?]) -> Set<String> {
    links.reduce(into: Set<String>()) { $0.formUnion(keys(of: $1)) }
  }

  /// Whether any of `links` is in `saved`, a set of keys.
  static func contains(_ saved: Set<String>, anyOf links: [String?]) -> Bool {
    !saved.isDisjoint(with: keys(of: links))
  }
}

/// The saved-links index: a small file in the App Group of the keys of every live recipe's
/// source link, which the share sheet reads to tell the cook a recipe is already in the box
/// without opening the store (#204). The app writes it (`rewrite(from:)`); the extension only
/// reads it.
///
/// It is written whole to a temporary file and moved into place, so a reader sees the old index
/// or the new one and never half of one. The folder is a parameter, so a test never touches the
/// real App Group.
struct SavedLinksIndex: Equatable, Sendable {
  /// The folder the file lives in; nil when there is nowhere to keep one (a build without the
  /// App Group, or a test run), where nothing is read or written.
  var folder: URL?

  static let fileName = "SavedLinks.json"
  static let currentVersion = 1

  private struct File: Codable {
    var version: Int
    var links: [String]
  }

  /// The index in the App Group container.
  static var appGroup: SavedLinksIndex {
    SavedLinksIndex(
      folder: FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: AppGroupName.id))
  }

  private var file: URL? { folder?.appending(path: Self.fileName) }

  /// The keys in the index. Empty when there is no file, or it can't be read or is of another
  /// version: the sheet then just doesn't warn.
  func read() -> Set<String> {
    guard let file, let data = try? Data(contentsOf: file),
      let index = try? JSONDecoder().decode(File.self, from: data),
      index.version == Self.currentVersion
    else { return [] }
    return Set(index.links)
  }

  /// Replaces the index with `links`. An index that is already what it should be is not written
  /// again.
  func write(_ links: Set<String>) throws {
    guard let folder, let file else { throw CocoaError(.fileNoSuchFile) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(File(version: Self.currentVersion, links: links.sorted()))
    if (try? Data(contentsOf: file)) == data { return }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try data.write(to: file, options: [.atomic])
  }
}
