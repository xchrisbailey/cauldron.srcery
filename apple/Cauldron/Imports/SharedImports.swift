import CauldronImports
import Foundation
import Observation
import SwiftData
import SwiftUI

/// What the share extension left in the inbox, waiting to be opened as imports one at a time.
/// It also takes the recipes the extension finished (#201) and puts them in the box.
///
/// The app picks the inbox up when it comes forward. A waiting item is opened only when nothing
/// else is in the way: no import sheet and no editor is open (`readyToOpen`), so a draft the cook
/// is working on is never replaced.
@MainActor
@Observable
final class SharedImportQueue {
  /// Items picked up and not opened yet, oldest first.
  private(set) var pending: [SharedImportRoute] = []
  /// An import sheet is open (shared or typed).
  var importOpen = false
  @ObservationIgnored private let folder: URL?
  @ObservationIgnored private let finishedFolder: URL?
  @ObservationIgnored private let enabled: Bool
  /// The editors open now, each by its own token so one that is closed twice counts once.
  private var editors: Set<UUID> = []

  /// - Parameters:
  ///   - folder: the inbox folder; nil is the App Group's, looked up when it is first read.
  ///   - finishedFolder: the folder of finished recipes, the same way.
  ///   - enabled: false under test and in previews, where nothing is picked up so the real
  ///     inbox is never touched.
  init(folder: URL? = nil, finishedFolder: URL? = nil, enabled: Bool) {
    self.folder = folder
    self.finishedFolder = finishedFolder
    self.enabled = enabled
  }

  /// How many are waiting their turn.
  var waiting: Int { pending.count }

  /// Something is waiting and nothing is in its way.
  var readyToOpen: Bool { !pending.isEmpty && !importOpen && editors.isEmpty }

  /// Takes what is in the inbox. Called at launch and whenever the app comes forward.
  ///
  /// Finished recipes go first, into `context`: a recipe that can't be saved as it is falls back
  /// to a link for a draft, which the second step then finds. Without a context only drafts are
  /// taken. Returns how many recipes were added.
  @discardableResult
  func pickUp(in context: ModelContext? = nil) -> Int {
    guard enabled else { return 0 }
    var added = 0
    if let context {
      added = FinishedRecipeReceiver.receive(
        from: finishedFolder ?? FinishedInbox.folder(), into: context,
        draftsFolder: folder ?? ShareInbox.folder())
    }
    pending.append(
      contentsOf: ShareInbox.takeAll(from: folder ?? ShareInbox.folder()).compactMap(
        SharedImportRoute.init))
    return added
  }

  /// The next item to open, removed from the queue; nil unless `readyToOpen`.
  func next() -> SharedImportRoute? {
    guard readyToOpen else { return nil }
    return pending.removeFirst()
  }

  func editorOpened(_ token: UUID) { editors.insert(token) }

  func editorClosed(_ token: UUID) { editors.remove(token) }
}

private struct SharedImportsPickUp: ViewModifier {
  let queue: SharedImportQueue
  let ai: RecipeAIService?
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.modelContext) private var context

  func body(content: Content) -> some View {
    content
      .environment(queue)
      // Runs at launch and each time the app comes forward.
      .task(id: scenePhase) {
        guard scenePhase == .active else { return }
        // Recipes that synced in while the app was away count for the share sheet's duplicate
        // check too.
        SavedLinksIndex.live.rewrite(from: context)
        // An estimate a finished recipe is waiting for runs at once, if the AI can be reached.
        if queue.pickUp(in: context) > 0, let ai {
          await AIQueueRunner.drain(in: context, using: ai.estimator)
        }
      }
  }
}

extension View {
  /// Gives the view the queue of shared items and picks the inbox up whenever the app comes
  /// forward. Recipes the share sheet finished are saved into the view's context; `ai` runs
  /// the macro estimates they are waiting for.
  func sharedImports(_ queue: SharedImportQueue, ai: RecipeAIService? = nil) -> some View {
    modifier(SharedImportsPickUp(queue: queue, ai: ai))
  }
}
