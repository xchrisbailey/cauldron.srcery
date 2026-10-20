import CauldronImports
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

  init(id: UUID, store: RetainedSharedDraftStore) throws {
    guard let retained = store.read(id), retained.status == .editing, retained.recipeDraft != nil
    else { throw Failure.unavailable }
    self.id = id
    self.store = store
    self.retained = retained
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
    do {
      let recipe = try RecipeSaver.save(draft, into: nil, context: context, id: id, index: index)
      finish()
      return recipe
    } catch {
      context.rollback()
      throw error
    }
  }

  private func finish() {
    retained.status = .saved
    // The saved record is also durable terminal knowledge if this write fails.
    try? store.write(retained)
  }
}
