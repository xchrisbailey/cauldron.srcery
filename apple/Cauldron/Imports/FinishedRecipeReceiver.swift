import CauldronImports
import CauldronKit
import Foundation
import OSLog
import SwiftData

/// Puts the recipes the share extension finished into the recipe box (#201).
///
/// Each one goes in through the recipe saver, like any recipe, with the payload's own id. The
/// payload's file is removed only after the save has gone through, so a crash leaves it for the
/// next time; that time the recipe is found by its id and nothing is inserted again.
///
/// A payload that carries a cover link (#203) waits one step longer. The recipe goes in first,
/// without a photo, so it is in the box at once; then the full-size cover is fetched the way an
/// import in the app fetches it (`CoverPhoto`), and only after that is the file removed. A photo
/// that can't be had leaves the recipe without one: it is a nicety and never holds a recipe up.
@MainActor
enum FinishedRecipeReceiver {
  private static let log = Logger(subsystem: "computer.srcery.cauldron", category: "share")

  /// A saved recipe still waiting for its cover photo, and the payload file to remove after.
  struct Cover {
    var entry: FinishedInbox.Entry
    var recipeID: UUID
    var link: String
  }

  /// What a pick-up of finished recipes came to.
  struct Received {
    /// How many recipes were added.
    var added = 0
    /// The covers to fetch (`attach`) before their files are removed.
    var covers: [Cover] = []
    /// The ids of the recipes that were added, for what is done after a save.
    var savedIDs: [UUID] = []
  }

  /// Saves what is waiting in `folder`, oldest first. Returns how many recipes were added, and
  /// the covers still to fetch.
  ///
  /// - Parameters:
  ///   - draftsFolder: the link-or-text inbox. A payload the saver won't take (it can't be
  ///     valid unless the sheet's check and the saver's disagree) is not lost: its link is left
  ///     there to open as a draft, as a failed share would.
  ///   - index: the saved-links index each saved recipe is added to.
  ///   - fileManager: what removes a payload's file.
  @discardableResult
  static func receive(
    from folder: URL?, into context: ModelContext, draftsFolder: URL?,
    index: SavedLinksIndex = .live, fileManager: FileManager = .default
  ) -> Received {
    var received = Received()
    for entry in FinishedInbox.pending(from: folder, fileManager: fileManager) {
      let id = entry.recipe.id
      if let existing = find(id, in: context) {
        // Saved on an earlier pick-up. The photo it was still waiting for, if the file says so
        // and the recipe has none, is fetched now; a recipe banished since stays that way.
        let wantsCover = !existing.isBanished && !existing.coverDeclined && existing.photo == nil
        settle(
          entry, coverLink: wantsCover ? entry.recipe.coverLink : nil, into: &received,
          fileManager: fileManager)
        continue
      }
      let draft = entry.recipe.recipeDraft
      do {
        let saved = try RecipeSaver.save(draft, into: nil, context: context, id: id, index: index)
        // The estimate the sheet couldn't ask for waits in the queue, as an import's does.
        RecipeMacroEstimates.queueAfterSave(of: draft, saved: saved, in: context)
        settle(entry, coverLink: entry.recipe.coverLink, into: &received, fileManager: fileManager)
        received.added += 1
        received.savedIDs.append(saved.id)
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
      }
    }
    return received
  }

  /// A saved recipe's payload is done with when it has no cover to wait for: its file goes.
  /// With one, the file stays until the cover is fetched (`attach`).
  private static func settle(
    _ entry: FinishedInbox.Entry, coverLink: String?, into received: inout Received,
    fileManager: FileManager
  ) {
    if let coverLink {
      received.covers.append(Cover(entry: entry, recipeID: entry.recipe.id, link: coverLink))
    } else {
      FinishedInbox.remove(entry, fileManager: fileManager)
    }
  }

  /// Fetches each cover and puts it on its recipe, then removes the payload's file. A task that
  /// is cancelled (the app went away) stops where it is and leaves the files, so the next
  /// pick-up fetches again. A photo that can't be had, or a recipe that has gone, is final:
  /// the file is removed.
  static func attach(
    _ covers: [Cover], into context: ModelContext, using fetcher: any PageFetcher,
    fileManager: FileManager = .default, now: @Sendable () -> Date = { .now }
  ) async {
    for cover in covers {
      guard let recipe = find(cover.recipeID, in: context), !recipe.isBanished,
        !recipe.coverDeclined, recipe.photo == nil
      else {
        FinishedInbox.remove(cover.entry, fileManager: fileManager)
        continue
      }
      let photo = await CoverPhoto.fetch(cover.link, using: fetcher)
      if Task.isCancelled { return }
      if let photo, !recipe.isBanished, !recipe.coverDeclined, recipe.photo == nil {
        RecipeSaver.savePhoto(.replace(photo), into: recipe, context: context)
        recipe.updatedAt = now()
        do {
          try context.save()
        } catch {
          // The store refused: the file stays for the next time.
          log.error("A cover photo couldn't be saved: \(error.localizedDescription)")
          context.rollback()
          continue
        }
      }
      FinishedInbox.remove(cover.entry, fileManager: fileManager)
    }
  }

  /// The recipe with this id, banished or not: one the cook banished since is not to come back.
  private static func find(_ id: UUID, in context: ModelContext) -> RecipeRecord? {
    var descriptor = FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return (try? context.fetch(descriptor))?.first
  }
}
