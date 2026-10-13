import CauldronKit
import Foundation
import Observation

/// What the cook gets to review after Distill: the draft, and the recipe already in the box
/// from the same link, if there is one.
struct ImportReview: Equatable {
  struct Duplicate: Equatable {
    var id: UUID
    var title: String
  }

  var draft: RecipeDraft
  var duplicate: Duplicate?
}

/// Why a distill failed, in the plain words of the copy module, and what to offer next.
struct ImportFailureNotice: Equatable {
  var code: ImportFailureCode
  var message: CopyString
  /// The failure was of a link, which the cook can paste the text of instead (`Failed` in the
  /// reference offers it when the job had a link).
  var canPaste: Bool
  /// The failure may pass, so trying again is worth offering.
  var canRetry: Bool
}

/// The Distill sheet's logic: what was typed, running the pipeline, and where it ended. The
/// views only show it. Nothing is stored; the cook saves from the editor.
@MainActor
@Observable
final class ImportModel: Identifiable {
  enum Phase: Equatable {
    /// The form: a link or pasted text.
    case editing
    case working
    case failed(ImportFailureNotice)
    /// A draft to review.
    case ready(ImportReview)
  }

  /// What a run was started with.
  private enum Request: Equatable {
    case link(String)
    /// `link` is kept as the source of text pasted after that link couldn't be read.
    case text(String, link: String?)
  }

  var link = "" {
    didSet {
      guard link != oldValue else { return }
      linkError = nil
      // A new link means the cook has moved on: text pasted from here on isn't from the old one.
      if !trimmed(link).isEmpty { pastingFor = nil }
    }
  }
  var text = ""
  private(set) var linkError: CopyString?
  private(set) var phase = Phase.editing
  /// The cook stopped the last run; the form says so.
  private(set) var stopped = false
  /// The link whose page couldn't be read, while its text is being pasted instead.
  private(set) var pastingFor: String?

  @ObservationIgnored private let fetcher: any PageFetcher
  @ObservationIgnored private let extractor: (any RecipeExtracting)?
  @ObservationIgnored private let options: DistillOptions
  @ObservationIgnored private let findDuplicate: @MainActor ([String?]) -> ImportReview.Duplicate?
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private var lastRequest: Request?
  @ObservationIgnored private var task: Task<Void, Never>?
  /// Counts runs, so the end of one that was stopped is ignored.
  @ObservationIgnored private var generation = 0

  init(
    fetcher: any PageFetcher, extractor: (any RecipeExtracting)?,
    options: DistillOptions = DistillOptions(),
    findDuplicate: @escaping @MainActor ([String?]) -> ImportReview.Duplicate? = { _ in nil },
    now: @escaping @Sendable () -> Date = { .now }
  ) {
    self.fetcher = fetcher
    self.extractor = extractor
    self.options = options
    self.findDuplicate = findDuplicate
    self.now = now
  }

  // MARK: The form

  /// A link takes the place of text, as in the reference: the paste box is off while one is
  /// typed.
  var pasteIsOff: Bool { !trimmed(link).isEmpty }

  var canStart: Bool {
    phase == .editing && (!trimmed(link).isEmpty || !trimmed(text).isEmpty)
  }

  /// Runs the link, or the pasted text when there is no link.
  func start() {
    guard phase == .editing else { return }
    let address = trimmed(link)
    if !address.isEmpty {
      guard Distill.isAcceptedLink(address) else {
        linkError = Copy.validation.link
        return
      }
      run(.link(address))
    } else if !trimmed(text).isEmpty {
      run(.text(trimmed(text), link: pastingFor))
    }
  }

  /// Gives up on the run in progress and goes back to the form with what was typed.
  func stop() {
    guard phase == .working else { return }
    generation += 1
    task?.cancel()
    task = nil
    stopped = true
    phase = .editing
  }

  /// After a link couldn't be read: the form again, on the paste box, with the link kept as the
  /// source of what is pasted.
  func pasteInstead() {
    guard case .failed(let notice) = phase, notice.canPaste,
      case .link(let address)? = lastRequest
    else { return }
    link = ""
    pastingFor = address
    stopped = false
    phase = .editing
  }

  /// Runs the last request again.
  func retry() {
    guard case .failed(let notice) = phase, notice.canRetry, let lastRequest else { return }
    run(lastRequest)
  }

  /// Back to a clean form. Pasted text that couldn't be read is kept so it can be fixed.
  func another() {
    let keepsText: Bool
    if case .text? = lastRequest, case .failed = phase {
      keepsText = true
    } else {
      keepsText = false
    }
    link = ""
    pastingFor = nil
    if !keepsText { text = "" }
    stopped = false
    phase = .editing
  }

  /// The sheet closed: stops whatever is running and keeps nothing.
  func discard() {
    generation += 1
    task?.cancel()
    task = nil
  }

  /// Waits for the run in progress to end; for tests.
  func finished() async {
    await task?.value
  }

  // MARK: Running

  private func run(_ request: Request) {
    lastRequest = request
    stopped = false
    phase = .working
    generation += 1
    let run = generation
    task = Task { [weak self] in
      guard let self else { return }
      await self.perform(request, run: run)
    }
  }

  private func perform(_ request: Request, run: Int) async {
    let distilled: Distilled
    do throws(DistillError) {
      switch request {
      case .link(let address):
        distilled = try await Distill.url(
          address, fetcher: fetcher, extractor: extractor, options: options)
      case .text(let pasted, _):
        distilled = try await Distill.text(pasted, extractor: extractor, options: options)
      }
    } catch {
      guard run == generation else { return }
      switch error {
      case .cancelled:
        stopped = true
        phase = .editing
      case .failed(let code, _):
        phase = .failed(notice(for: code, request: request))
      }
      return
    }

    // The cover photo is only a nicety: it takes as long as it takes (up to its limit) and
    // never fails the import.
    var photo: ProcessedPhoto?
    if case .link = request, let image = distilled.imageUrl {
      photo = await CoverPhoto.fetch(image, using: fetcher)
    }
    guard run == generation, !Task.isCancelled else { return }

    var keptLink: String?
    var fetchedAt: Date?
    switch request {
    case .link: fetchedAt = now()
    case .text(_, let link): keptLink = link
    }
    let draft = RecipeDraft(
      importing: distilled, photo: photo, link: keptLink, fetchedAt: fetchedAt)
    let links: [String?]
    switch request {
    case .link(let address): links = [address, distilled.draft.sourceUrl]
    case .text(_, let link): links = [link]
    }
    phase = .ready(ImportReview(draft: draft, duplicate: findDuplicate(links)))
  }

  private func notice(for code: ImportFailureCode, request: Request) -> ImportFailureNotice {
    var isText = false
    var isLink = false
    switch request {
    case .link: isLink = true
    case .text: isText = true
    }
    // The reference words "no recipe" differently for a paste than for a page.
    let message =
      code == .noRecipe && isText ? Copy.imports.noRecipeInText : Copy.imports.failure(code)
    return ImportFailureNotice(
      code: code, message: message, canPaste: isLink,
      canRetry: code == .timeout || code == .unavailable)
  }

  private func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
