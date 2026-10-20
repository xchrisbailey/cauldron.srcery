import CauldronImports
import CauldronKit
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
  /// Saved recipes still waiting for their cover photo (`fetchCovers`).
  @ObservationIgnored private var covers: [FinishedRecipeReceiver.Cover] = []
  /// The recipes whose covers are being fetched now, so a second pick-up doesn't fetch them again.
  @ObservationIgnored private var fetching: Set<UUID> = []
  /// A photo edit whose durable cover cancellation has not succeeded yet.
  @ObservationIgnored private var changedPhotos: Set<UUID> = []
  /// An import sheet is open (shared or typed).
  var importOpen = false
  @ObservationIgnored private let folder: URL?
  @ObservationIgnored private let finishedFolder: URL?
  @ObservationIgnored private let enabled: Bool
  /// The editors open now, each by its own token so one that is closed twice counts once.
  private var editors: Set<UUID> = []
  private(set) var retainedPending: [UUID] = []
  private var deferred: Set<UUID> = []
  private var opening: UUID?
  let retainedStore: RetainedSharedDraftStore

  /// - Parameters:
  ///   - folder: the inbox folder; nil is the App Group's, looked up when it is first read.
  ///   - finishedFolder: the folder of finished recipes, the same way.
  ///   - enabled: false under test and in previews, where nothing is picked up so the real
  ///     inbox is never touched.
  init(folder: URL? = nil, finishedFolder: URL? = nil, retainedFolder: URL? = nil, enabled: Bool) {
    self.folder = folder
    self.finishedFolder = finishedFolder
    self.enabled = enabled
    retainedStore = RetainedSharedDraftStore(
      folder: retainedFolder
        ?? (folder == nil
          ? (enabled ? RetainedSharedDraftStore.live().folder : nil)
          : folder?.appending(path: "RetainedSharedDrafts")))
  }

  /// How many are waiting their turn.
  var waiting: Int { pending.count + retainedPending.count }

  /// Something is waiting and nothing is in its way.
  var readyToOpen: Bool { waiting > 0 && !importOpen && editors.isEmpty }

  /// Takes what is in the inbox. Called at launch and whenever the app comes forward.
  ///
  /// Finished recipes go first, into `context`: a recipe that can't be saved as it is falls back
  /// to a link for a draft, which the second step then finds. Without a context only drafts are
  /// taken. Returns how many recipes were added.
  ///
  /// - Parameter includingDrafts: false takes the finished recipes and leaves the links and text
  ///   for the next time the app comes forward (`receiveWhileOpen`).
  @discardableResult
  func pickUp(in context: ModelContext? = nil, includingDrafts: Bool = true) -> Int {
    guard enabled else { return 0 }
    var added = 0
    if let context {
      // The folder is the truth about what waits for a photo, so each pick-up replaces the list.
      let received = FinishedRecipeReceiver.receive(
        from: finishedFolder ?? FinishedInbox.folder(), into: context,
        draftsFolder: folder ?? ShareInbox.folder())
      added = received.added
      covers = received.covers
    }
    guard includingDrafts else { return added }
    deferred = []
    refreshRetained(in: context)
    pending.append(
      contentsOf: ShareInbox.takeAll(from: folder ?? ShareInbox.folder()).compactMap(
        SharedImportRoute.init))
    return added
  }

  private func refreshRetained(in context: ModelContext?) {
    let saved: [RecipeRecord]
    if let context {
      guard let records = try? context.fetch(FetchDescriptor<RecipeRecord>()) else { return }
      saved = records
    } else {
      saved = []
    }
    let savedIDs = Set(saved.map(\.id))
    for var item in retainedStore.all() where item.status == .editing {
      if savedIDs.contains(item.id) {
        item.status = .saved
        try? retainedStore.write(item)
        retainedPending.removeAll { $0 == item.id }
      } else if !deferred.contains(item.id), opening != item.id,
        !retainedPending.contains(item.id)
      {
        retainedPending.append(item.id)
      }
    }
  }

  /// Explicit requests jump ahead without changing the order of unrelated waiting drafts.
  func request(_ id: UUID, in context: ModelContext? = nil) {
    guard enabled, opening != id, let item = retainedStore.read(id),
      item.status == .editing
    else { return }
    if let context {
      let savedID = id
      guard
        let saved = try? context.fetch(
          FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == savedID }))
      else { return }
      if !saved.isEmpty {
        var terminal = item
        terminal.status = .saved
        try? retainedStore.write(terminal)
        retainedPending.removeAll { $0 == id }
        return
      }
    }
    deferred.remove(id)
    retainedPending.removeAll { $0 == id }
    retainedPending.insert(id, at: 0)
  }

  func nextSession() -> SharedDraftSession? {
    guard readyToOpen else { return nil }
    while !retainedPending.isEmpty {
      let id = retainedPending.removeFirst()
      if let session = try? SharedDraftSession(id: id, store: retainedStore) {
        opening = id
        importOpen = true
        return session
      }
    }
    return nil
  }

  func closedSession(_ id: UUID) {
    deferred.insert(id)
    if opening == id { opening = nil }
    importOpen = false
  }

  /// Fetches the cover photos of the recipes `pickUp` added, and removes their files. It takes
  /// as long as the pages take, so it is run apart from the pick-up, which does not wait.
  func fetchCovers(into context: ModelContext, using fetcher: any PageFetcher) async {
    let waiting = covers.filter { !fetching.contains($0.recipeID) }
    covers = []
    let ids = Set(waiting.map(\.recipeID))
    fetching.formUnion(ids)
    defer { fetching.subtract(ids) }
    await FinishedRecipeReceiver.attach(waiting, into: context, using: fetcher)
    await fetchRetainedCovers(into: context, using: fetcher)
  }

  private func fetchRetainedCovers(into context: ModelContext, using fetcher: any PageFetcher) async
  {
    for item in retainedStore.all()
    where item.status == .saved && !fetching.contains(item.id)
      && !changedPhotos.contains(item.id)
    {
      guard let link = item.parsed?.coverLink else { continue }
      let id = item.id
      guard
        let saved = try? context.fetch(
          FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })
        ).first
      else { continue }
      if saved.isBanished || saved.photo != nil || item.photoRemoved || item.photo != nil {
        finishRetainedCover(id)
        continue
      }
      fetching.insert(id)
      let photo = await CoverPhoto.fetch(link, using: fetcher)
      fetching.remove(id)
      guard !Task.isCancelled else { return }
      // A photo changed or removed while the fetch ran must not be replaced by its result.
      guard !changedPhotos.contains(id), let current = retainedStore.read(id),
        current.status == .saved,
        current.parsed?.coverLink == link,
        !current.photoRemoved, current.photo == nil
      else { continue }
      if let photo, !saved.isBanished, saved.photo == nil {
        RecipeSaver.savePhoto(.replace(photo), into: saved, context: context)
        saved.updatedAt = .now
        do { try context.save() } catch { context.rollback(); continue }
      }
      finishRetainedCover(id)
    }
  }

  private func finishRetainedCover(_ id: UUID) {
    guard var item = retainedStore.read(id), item.status == .saved else { return }
    item.parsed?.coverLink = nil
    try? retainedStore.write(item)
  }

  /// A successful explicit photo edit takes precedence over a pending imported cover.
  func photoChanged(_ id: UUID) throws {
    guard var item = retainedStore.read(id), item.status != .discarded,
      item.parsed?.coverLink != nil
    else { changedPhotos.remove(id); return }
    changedPhotos.insert(id)
    item.parsed?.coverLink = nil
    try retainedStore.write(item)
    changedPhotos.remove(id)
  }

  /// What follows a pick-up that added `added` recipes: the estimates they wait for run at once
  /// if the AI can be reached, then their full-size covers are fetched.
  func settle(
    added: Int, in context: ModelContext, ai: RecipeAIService?, fetcher: any PageFetcher
  ) async {
    if added > 0, let ai {
      await AIQueueRunner.drain(in: context, using: ai.estimator)
    }
    await fetchCovers(into: context, using: fetcher)
  }

  /// Takes finished recipes as the share extension leaves them, for as long as the task runs.
  /// This is how a recipe saved from the Mac's share popover reaches an app that is already open
  /// and in front, which no scene change would tell. Only finished recipes are taken: a link or
  /// text for a draft waits for the app to come forward, so no sheet opens by itself.
  ///
  /// - Parameter then: runs after each look at the folder, with how many recipes it added. What
  ///   it does (an estimate, a cover photo) doesn't hold up the next look.
  func receiveWhileOpen(
    in context: ModelContext, then: @escaping @MainActor @Sendable (Int) async -> Void
  ) async {
    guard enabled, let folder = finishedFolder ?? FinishedInbox.folder() else { return }
    var running: [Task<Void, Never>] = []
    for await _ in FolderWatcher.changes(in: folder) {
      let added = pickUp(in: context, includingDrafts: false)
      running.append(Task { await then(added) })
    }
    // Cancelled: what is still going stops with the watch.
    if Task.isCancelled { running.forEach { $0.cancel() } }
    for task in running { await task.value }
  }

  /// The next item to open, removed from the queue; nil unless `readyToOpen`.
  func next() -> SharedImportRoute? {
    guard readyToOpen, !pending.isEmpty else { return nil }
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
  @Environment(\.pageFetcher) private var fetcher

  func body(content: Content) -> some View {
    content
      .environment(queue)
      #if os(macOS)
        // The share popover leaves a recipe while the window is open, and no scene change says
        // so: watch the folder it leaves it in.
        .task {
          await queue.receiveWhileOpen(in: context) { [queue, context, ai, fetcher] added in
            await queue.settle(added: added, in: context, ai: ai, fetcher: fetcher)
          }
        }
      #endif
      // Runs at launch and each time the app comes forward.
      .task(id: scenePhase) {
        guard scenePhase == .active else { return }
        // Recipes that synced in while the app was away count for the share sheet's duplicate
        // check too.
        SavedLinksIndex.live.rewrite(from: context)
        // What a finished recipe is waiting for: its estimate and its full-size cover.
        let added = queue.pickUp(in: context)
        await queue.settle(added: added, in: context, ai: ai, fetcher: fetcher)
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
