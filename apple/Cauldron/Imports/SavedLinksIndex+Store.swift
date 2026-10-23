import CauldronKit
import OSLog
import SwiftData

extension SavedLinksIndex {
  private static let log = Logger(subsystem: "computer.srcery.cauldron", category: "share")

  /// The index the running app keeps: the App Group's, except under test, where it has no
  /// folder so a test run never touches the real one.
  static var live: SavedLinksIndex { live(mode: CauldronStore.launchMode) }

  static func live(mode: CauldronStore.Mode) -> SavedLinksIndex {
    mode == .synced || mode == .local ? .appGroup : SavedLinksIndex(folder: nil)
  }

  /// Writes the index from the recipes in `context`: the links of every recipe that isn't
  /// banished. Called wherever a recipe is saved, edited, banished or restored, and at launch,
  /// so it always stands for the store. Returns whether the index is now written.
  ///
  /// A failure is logged and the app carries on: the sheet then warns by an older index, and
  /// the next rewrite puts it right. Nothing is written when the store can't be read, so a
  /// failed read never empties the index.
  @discardableResult
  func rewrite(from context: ModelContext) -> Bool {
    guard folder != nil else { return false }
    do {
      let recipes = try context.fetch(FetchDescriptor<RecipeRecord>())
      let keys = recipes.filter { !$0.isBanished }.reduce(into: Set<String>()) {
        $0.formUnion(SavedLinks.keys(of: $1.sourceURL))
      }
      try write(keys)
      return true
    } catch {
      Self.log.error("Couldn't write the saved links: \(error.localizedDescription)")
      return false
    }
  }
}
