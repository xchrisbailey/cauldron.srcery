import CauldronImports
import CauldronKit
import Foundation
import Observation

/// The share sheet's logic: it reads what was shared with the same import model as the Distill
/// sheet, shows a summary of the recipe it found, and on Save leaves the finished recipe for
/// the app (`FinishedInbox`). The views only show it. The extension never opens the store.
///
/// Every way out is safe. Anything that goes wrong (a page that can't be read, a recipe that
/// can't be left for the app) offers the old path, `sendToCauldron()`, which leaves the link or
/// text for the app to open as a draft.
@MainActor
@Observable
final class ShareSheetModel {
  /// What the cook is shown of a recipe the import read.
  struct Review: Equatable {
    var draft: RecipeDraft
    var title: String
    /// Where it came from, as a site name; nil for text with no link.
    var source: String?
    var ingredients: Int
    var steps: Int
    /// The draft can be saved as it is.
    var canSave: Bool
    /// A small picture of the recipe's cover, when the page had one that could be fetched.
    var thumbnail: ProcessedPhoto?
    /// Where the full-size cover is, which the app fetches when it adds the recipe.
    var coverLink: String?
    /// The macros per serving, when there are any to show: the page's, or the estimate.
    var macros: Macros?
    /// The macros are an estimate.
    var macrosEstimated: Bool
    /// No macros yet: the estimate could not be asked for, so the app asks once the recipe is
    /// saved. Never a guess.
    var macrosPending: Bool
    /// A recipe from the same link is already in the box (#204). Saving still works.
    var duplicate = false
  }

  /// Something to tell the cook, in plain words, and whether `sendToCauldron()` is still open.
  struct Notice: Equatable {
    var message: CopyString
    var canSend: Bool
  }

  enum Phase: Equatable {
    case reading
    case ready(Review)
    /// The finished recipe is left for the app.
    case saved
    /// The link or text is left for the app to open as a draft.
    case sent
    case failed(Notice)
  }

  /// How the sheet closes.
  enum Closing: Equatable {
    /// Finished; the share goes through.
    case done
    /// The cook backed out.
    case cancelled
  }

  private let item: SharedItem
  private let importer: ImportModel
  private let finishedFolder: URL?
  private let inboxFolder: URL?
  private let id: UUID
  private let now: @Sendable () -> Date
  private let closeDelay: Duration
  private let close: @MainActor (Closing) -> Void
  /// Where the sheet ended, once it has: the import's own phase stands until then.
  private var outcome: Phase?
  private var started = false
  @ObservationIgnored private var closing: Task<Void, Never>?

  /// - Parameters:
  ///   - item: what was shared.
  ///   - importer: the import to run it with.
  ///   - finishedFolder: where a finished recipe is left.
  ///   - inboxFolder: where the link or text is left.
  ///   - id: the saved recipe's id.
  ///   - closeDelay: how long the confirmation stays before the sheet closes itself.
  ///   - close: ends the share. It is called only once everything is written.
  init(
    item: SharedItem, importer: ImportModel, finishedFolder: URL?, inboxFolder: URL?,
    id: UUID = UUID(), now: @escaping @Sendable () -> Date = { .now },
    closeDelay: Duration = .milliseconds(1400), close: @escaping @MainActor (Closing) -> Void
  ) {
    self.item = item
    self.importer = importer
    self.finishedFolder = finishedFolder
    self.inboxFolder = inboxFolder
    self.id = id
    self.now = now
    self.closeDelay = closeDelay
    self.close = close
  }

  /// The sheet as the extension runs it: the cook's chosen AI from the App Group's settings, the
  /// network for pages, and the App Group's folders.
  static func live(
    item: SharedItem, close: @escaping @MainActor (Closing) -> Void
  ) -> ShareSheetModel {
    let ai = RecipeAIService.live(suiteName: AppGroup.id)
    let importer = ImportModel(
      fetcher: URLSessionPageFetcher(), extractor: ai.extractor,
      estimator: macroEstimator(for: ai),
      options: DistillOptions(macroTimeout: macroTimeout),
      findDuplicate: duplicateLookup(savedLinks: { SavedLinksIndex.appGroup.read() }),
      cover: .sheetThumbnail)
    return ShareSheetModel(
      item: item, importer: importer, finishedFolder: FinishedInbox.folder(),
      inboxFolder: ShareInbox.folder(), close: close)
  }

  /// How long the sheet waits for the macro estimate before leaving it for the app. The app's
  /// own import waits 30 seconds; the sheet is a quick "keep this one" moment.
  static let macroTimeout = Duration.seconds(10)

  /// Who the sheet asks for the macro estimate, if anybody. The chosen cloud provider alone, and
  /// only when it has a key: with none, asking could only fail. Whether it can be reached is
  /// found by asking, within `macroTimeout`, and the import does not ask at all after the
  /// on-device model had to read the recipe (the cloud provider had just failed to answer).
  /// An estimate that isn't had is marked pending and the app asks later; the on-device model
  /// never estimates, so a guess never reaches a recipe.
  static func macroEstimator(for ai: RecipeAIService) -> (any RecipeAI)? {
    ai.hasKey ? ai.estimator : nil
  }

  /// Where the sheet is.
  var phase: Phase {
    if let outcome { return outcome }
    switch importer.phase {
    case .editing, .working:
      return .reading
    case .ready(let review):
      return .ready(
        Self.summary(
          of: review.draft, thumbnail: review.thumbnail, coverLink: review.coverLink,
          duplicate: review.duplicate != nil))
    case .failed(let notice):
      return .failed(Notice(message: notice.message, canSend: true))
    }
  }

  /// Starts reading what was shared. Once only.
  func start() {
    guard !started else { return }
    started = true
    guard let route = SharedImportRoute(item) else {
      outcome = .failed(Notice(message: Copy.importNative.nothingToSend, canSend: false))
      return
    }
    importer.start(sharing: route)
  }

  /// Waits for the read to end; for tests.
  func finished() async {
    await importer.finished()
  }

  /// Leaves the recipe for the app, then closes after a moment. The sheet closes only after
  /// the file is written; if it can't be written, the old path is offered instead.
  func save() {
    guard outcome == nil, case .ready(let review) = phase, review.canSave else { return }
    let recipe = FinishedRecipe(
      draft: review.draft, id: id, sharedAt: now(), coverLink: review.coverLink)
    do {
      try FinishedInbox.add(recipe, in: finishedFolder)
    } catch {
      outcome = .failed(Notice(message: Copy.importNative.couldntSave, canSend: true))
      return
    }
    outcome = .saved
    closeSoon()
  }

  /// Leaves the link or text for the app to open as a draft (today's path), then closes after a
  /// moment. Edit in Cauldron is this, and so is the way out of every failure.
  func sendToCauldron() {
    guard outcome != .saved, outcome != .sent else { return }
    do {
      try ShareInbox.add(item, in: inboxFolder)
    } catch {
      outcome = .failed(Notice(message: Copy.importNative.couldntSend, canSend: false))
      return
    }
    importer.discard()
    outcome = .sent
    closeSoon()
  }

  /// The cook backed out. Nothing is kept.
  func cancel() {
    closing?.cancel()
    importer.discard()
    close(.cancelled)
  }

  private func closeSoon() {
    closing = Task { [close, closeDelay] in
      try? await Task.sleep(for: closeDelay)
      guard !Task.isCancelled else { return }
      close(.done)
    }
  }

  /// Waits for the sheet to close itself; for tests.
  func closed() async {
    await closing?.value
  }

  static func summary(
    of draft: RecipeDraft, thumbnail: ProcessedPhoto? = nil, coverLink: String? = nil,
    duplicate: Bool = false
  ) -> Review {
    let typed = draft.typedMacros
    let macros = typed == Macros() ? nil : typed
    return Review(
      draft: draft, title: draft.trimmed(draft.title), source: source(of: draft.sourceURL),
      ingredients: draft.ingredients.filter { !$0.isHeading && !$0.isBlank }.count,
      steps: draft.steps.filter { !$0.isBlank }.count, canSave: draft.validate().isEmpty,
      thumbnail: thumbnail, coverLink: coverLink, macros: macros,
      macrosEstimated: macros != nil && macros == draft.estimatedMacros,
      macrosPending: macros == nil && draft.estimateOnSave, duplicate: duplicate)

  }

  /// The import's check for a recipe already in the box, from the saved-links index: `savedLinks`
  /// gives the index's keys, and any of the import's links among them is a duplicate. The index
  /// holds links, not recipes, so the duplicate it names has no id or title; the sheet only asks
  /// whether there is one. The rules are the app's (`SavedLinks`).
  static func duplicateLookup(
    savedLinks: @escaping @MainActor () -> Set<String>
  ) -> @MainActor ([String?]) -> ImportReview.Duplicate? {
    { links in
      SavedLinks.contains(savedLinks(), anyOf: links)
        ? ImportReview.Duplicate(id: UUID(), title: "") : nil
    }
  }

  /// The site a link is on: its host, less a leading "www.".
  static func source(of link: String) -> String? {
    guard let host = URL(string: link)?.host(), !host.isEmpty else { return nil }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }
}
