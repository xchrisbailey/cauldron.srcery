import CauldronImports
import CauldronKit
import Foundation
import SwiftData

/// The editor's durable shared-draft lifecycle. The saved recipe uses the handoff identity,
/// so a crash between the database save and the terminal write cannot insert a second recipe.
@MainActor
final class SharedDraftSession: Identifiable {
  enum Failure: Error { case unavailable }
  let id: UUID
  let store: RetainedSharedDraftStore
  private(set) var retained: RetainedSharedDraft
  var draft: RecipeDraft { retained.recipeDraft ?? RecipeDraft() }
  var isParsed: Bool { retained.recipeDraft != nil }

  init(id: UUID, store: RetainedSharedDraftStore) throws {
    guard let retained = store.read(id), retained.status == .editing
    else { throw Failure.unavailable }
    self.id = id
    self.store = store
    self.retained = retained
  }

  /// Raw sources stay retained through failures. Promotion precedes the ready/editor state.
  func retry(using model: ImportModel) {
    guard retained.status == .editing, !isParsed else { return }
    model.beforeReview = { [self] review in
      guard retained.status == .editing else { return Copy.sharedDrafts.couldntKeep }
      do {
        var next = retained
        next.update(review.draft, coverLink: review.coverLink)
        try store.write(next)
        retained = next
        return nil
      } catch {
        return Copy.sharedRetry.couldntKeepResult
      }
    }
    guard let route = SharedImportRoute(retained.item) else {
      model.reportRecoveryFailure(Copy.sharedRetry.unreadable)
      return
    }
    model.start(sharing: route)
  }

  func checkpoint(_ draft: RecipeDraft) throws {
    guard retained.status == .editing else { return }
    var next = retained
    next.update(draft)
    try store.write(next)
    retained = next
  }

  func discard() throws {
    var next = retained
    next.status = .discarded
    try store.write(next)
    retained = next
  }

  func save(_ draft: RecipeDraft, in context: ModelContext, index: SavedLinksIndex = .live) throws
    -> RecipeRecord
  {
    let id = id
    let found = try context.fetch(
      FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })
    ).first
    if let found {
      finish()
      return found
    }
    guard retained.status == .editing else { throw Failure.unavailable }
    try checkpoint(draft)
    let recipe = try RecipeSaver.save(draft, into: nil, context: context, id: id, index: index)
    finish()
    return recipe
  }

  private func finish() {
    retained.status = .saved
    // The saved record is also durable terminal knowledge if this write fails.
    try? store.write(retained)
  }
}
