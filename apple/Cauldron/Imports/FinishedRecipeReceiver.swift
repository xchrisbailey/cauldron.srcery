import CauldronImports
import Foundation
import OSLog
import SwiftData

/// Puts the recipes the share extension finished into the recipe box (#201).
///
/// Each one goes in through the recipe saver, like any recipe, with the payload's own id. The
/// payload's file is removed only after the save has gone through, so a crash leaves it for the
/// next time; that time the recipe is found by its id and nothing is inserted again.
@MainActor
enum FinishedRecipeReceiver {
  private static let log = Logger(subsystem: "computer.srcery.cauldron", category: "share")

  /// Saves what is waiting in `folder`, oldest first. Returns how many recipes were added.
  ///
  /// - Parameters:
  ///   - draftsFolder: the link-or-text inbox. A payload the saver won't take (it can't be
  ///     valid unless the sheet's check and the saver's disagree) is not lost: its link is left
  ///     there to open as a draft, as a failed share would.
  ///   - fileManager: what removes a payload's file.
  @discardableResult
  static func receive(
    from folder: URL?, into context: ModelContext, draftsFolder: URL?,
    fileManager: FileManager = .default
  ) -> Int {
    var added = 0
    for entry in FinishedInbox.pending(from: folder, fileManager: fileManager) {
      let id = entry.recipe.id
      if exists(id, in: context) {
        FinishedInbox.remove(entry, fileManager: fileManager)
        continue
      }
      let draft = entry.recipe.recipeDraft
      do {
        let saved = try RecipeSaver.save(draft, into: nil, context: context, id: id)
        // The estimate the sheet couldn't ask for waits in the queue, as an import's does.
        RecipeMacroEstimates.queueAfterSave(of: draft, saved: saved, in: context)
        FinishedInbox.remove(entry, fileManager: fileManager)
        added += 1
      } catch RecipeSaver.Failure.invalid {
        log.error("A finished recipe was not valid; its link was kept for a draft instead.")
        if !draft.sourceURL.isEmpty {
          try? ShareInbox.add(SharedItem(url: draft.sourceURL), in: draftsFolder)
        }
        FinishedInbox.remove(entry, fileManager: fileManager)
      } catch {
        // The store refused. Whatever was inserted is dropped and the payload stays for the
        // next time the app comes forward.
        log.error("A finished recipe couldn't be saved: \(error.localizedDescription)")
        context.rollback()
      }
    }
    return added
  }

  /// Whether a recipe with this id is in the store, banished or not: one the cook banished
  /// since is not to come back.
  private static func exists(_ id: UUID, in context: ModelContext) -> Bool {
    var descriptor = FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return ((try? context.fetchCount(descriptor)) ?? 0) > 0
  }
}
