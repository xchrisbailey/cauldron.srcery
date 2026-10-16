import CauldronKit
import CoreGraphics
import Foundation
import Observation

/// What the cook gets to review after Distill: the draft, and the recipe already in the box
/// from the same link, if there is one.
public struct ImportReview: Equatable {
  public struct Duplicate: Equatable {
    public var id: UUID
    public var title: String

    public init(id: UUID, title: String) {
      self.id = id
      self.title = title
    }
  }

  public var draft: RecipeDraft
  public var duplicate: Duplicate?
  /// The link to the page's cover photo, when it had one a link could fetch. The share sheet
  /// leaves it for the app, which fetches the full-size photo itself.
  public var coverLink: String?
  /// A small picture of the cover, for a screen that only shows it (`CoverMode.thumbnail`).
  public var thumbnail: ProcessedPhoto?

  public init(
    draft: RecipeDraft, duplicate: Duplicate?, coverLink: String? = nil,
    thumbnail: ProcessedPhoto? = nil
  ) {
    self.draft = draft
    self.duplicate = duplicate
    self.coverLink = coverLink
    self.thumbnail = thumbnail
  }
}

/// Why a distill failed, in the plain words of the copy module, and what to offer next.
public struct ImportFailureNotice: Equatable {
  public var code: ImportFailureCode
  public var message: CopyString
  /// The failure was of a link, which the cook can paste the text of instead (`Failed` in the
  /// reference offers it when the job had a link).
  public var canPaste: Bool
  /// The failure may pass, so trying again is worth offering.
  public var canRetry: Bool
  /// The failure was of photos, which the cook can change and read again.
  public var canChangePhotos = false
}

/// A page the cook captured, held in memory until it is read. Never written to disk.
public struct ScannedPage: Identifiable, Equatable {
  public let id = UUID()
  /// The image as captured, in any format ImageIO reads.
  public let data: Data
  /// A small picture of it for the page strip.
  public let thumbnail: CGImage?

  public static func == (left: ScannedPage, right: ScannedPage) -> Bool { left.id == right.id }
}

/// The Distill sheet's logic: what was typed, running the pipeline, and where it ended. The
/// views only show it. Nothing is stored; the cook saves from the editor.
@MainActor
@Observable
public final class ImportModel: Identifiable {
  public enum Phase: Equatable {
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
    /// Photographed pages, read on the device and then distilled as pasted text is.
    case pages([ScannedPage], keepFirstPage: Bool)
  }

  /// Where a run in progress is, when it is reading pages.
  public struct ReadingProgress: Equatable {
    public var page: Int
    public var of: Int
  }

  /// What an import does with the page's cover photo.
  public enum CoverMode: Equatable, Sendable {
    /// Fetch the photo and put it in the draft, ready to save (the app's import).
    case photo
    /// Fetch only a small picture to show, in `ImportReview.thumbnail`, within `timeout`, and
    /// leave the draft without a photo (the share sheet, which cannot afford the full one).
    case thumbnail(maxPixel: Int, timeout: Duration)

    /// The share sheet's: 320 pixels is enough for a small picture at three times the scale.
    public static let sheetThumbnail = CoverMode.thumbnail(maxPixel: 320, timeout: .seconds(8))
  }

  /// A recipe has at most this many pages.
  public static let pageLimit = 10

  public var link = "" {
    didSet {
      guard link != oldValue else { return }
      linkError = nil
      // A new link means the cook has moved on: text pasted from here on isn't from the old one.
      if !trimmed(link).isEmpty { pastingFor = nil }
    }
  }
  public var text = ""
  public private(set) var linkError: CopyString?
  public private(set) var phase = Phase.editing
  /// The cook stopped the last run; the form says so.
  public private(set) var stopped = false
  /// The link whose page couldn't be read, while its text is being pasted instead.
  public private(set) var pastingFor: String?
  /// The pages photographed or chosen so far, in the order they were captured.
  public private(set) var pages: [ScannedPage] = []
  /// Offer the first page's picture as the recipe photo once the draft is made. Off unless the
  /// cook turns it on: a cookbook page is rarely the picture anyone wants.
  public var keepFirstPage = false
  /// Why the last page added, or the scanner, didn't work; the photo section says so.
  public private(set) var photoMessage: CopyString?
  /// Which page is being read, while one is.
  public private(set) var reading: ReadingProgress?
  /// The paste box is the way on: pages couldn't be read, or the cook gave up on them.
  public private(set) var prefersPaste = false

  @ObservationIgnored private let fetcher: any PageFetcher
  @ObservationIgnored private let extractor: (any RecipeExtracting)?
  /// Asked for the macro estimate during the import, as the reference did. Nil where there is
  /// no AI service: the estimate is then left for after the recipe is saved.
  @ObservationIgnored private let estimator: (any RecipeAI)?
  @ObservationIgnored private let reader: any RecipeTextReader
  @ObservationIgnored private let maxPixels: Int
  @ObservationIgnored private let options: DistillOptions
  @ObservationIgnored private let findDuplicate: @MainActor ([String?]) -> ImportReview.Duplicate?
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private let cover: CoverMode
  @ObservationIgnored private var lastRequest: Request?
  /// The text read off the pages in the last run, to fix by hand if it can't be distilled.
  @ObservationIgnored private var lastReadText: String?
  @ObservationIgnored private var photoFailure: PhotoFailure?
  @ObservationIgnored private var task: Task<Void, Never>?
  /// Counts runs, so the end of one that was stopped is ignored.
  @ObservationIgnored private var generation = 0

  public init(
    fetcher: any PageFetcher, extractor: (any RecipeExtracting)?,
    estimator: (any RecipeAI)? = nil,
    reader: any RecipeTextReader = VisionTextReader(),
    maxPixels: Int = PhotoProcessing.maxPixels,
    options: DistillOptions = DistillOptions(),
    findDuplicate: @escaping @MainActor ([String?]) -> ImportReview.Duplicate? = { _ in nil },
    cover: CoverMode = .photo, now: @escaping @Sendable () -> Date = { .now }
  ) {
    self.cover = cover
    self.fetcher = fetcher
    self.extractor = extractor
    self.estimator = estimator
    self.reader = reader
    self.maxPixels = maxPixels
    self.options = options
    self.findDuplicate = findDuplicate
    self.now = now
  }

  // MARK: The form

  /// A link takes the place of text, as in the reference: the paste box is off while one is
  /// typed.
  public var pasteIsOff: Bool { !trimmed(link).isEmpty }

  /// Pages take the place of a link and of pasted text while there are any: what was typed is
  /// kept, and comes back when the pages are taken away.
  public var pagesAreOn: Bool { !pages.isEmpty }

  public var canStart: Bool {
    phase == .editing && (pagesAreOn || !trimmed(link).isEmpty || !trimmed(text).isEmpty)
  }

  /// Runs the pages, or the link, or the pasted text when there is no link.
  public func start() {
    guard phase == .editing else { return }
    if pagesAreOn {
      run(.pages(pages, keepFirstPage: keepFirstPage))
      return
    }
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

  /// Starts on something shared to Cauldron, as if the cook had typed or pasted it and pressed
  /// Distill: a link takes the link path with all its checks, and a caption is pasted text with
  /// the post kept as its source. Only on a clean form.
  public func start(sharing route: SharedImportRoute) {
    guard phase == .editing, link.isEmpty, text.isEmpty, !pagesAreOn else { return }
    switch route {
    case .link(let address):
      link = address
    case .caption(let caption, let post):
      text = caption
      pastingFor = post
    case .text(let pasted):
      text = pasted
    }
    start()
  }

  /// Gives up on the run in progress and goes back to the form with what was typed.
  public func stop() {
    guard phase == .working else { return }
    generation += 1
    task?.cancel()
    task = nil
    reading = nil
    stopped = true
    phase = .editing
  }

  /// After a link couldn't be read: the form again, on the paste box, with the link kept as the
  /// source of what is pasted.
  public func pasteInstead() {
    guard case .failed(let notice) = phase, notice.canPaste else { return }
    switch lastRequest {
    case .link(let address)?:
      link = ""
      pastingFor = address
    case .pages?:
      // What was read off the pages comes along to be fixed, if it fits.
      if let read = lastReadText, trimmed(text).isEmpty, read.count <= Distill.textMax {
        text = read
      }
      pages = []
      keepFirstPage = false
      prefersPaste = true
    default:
      return
    }
    stopped = false
    phase = .editing
  }

  /// After photos couldn't be read: the form again with the pages as they were, to change.
  public func changePhotos() {
    guard case .failed(let notice) = phase, notice.canChangePhotos else { return }
    stopped = false
    phase = .editing
  }

  /// Runs the last request again.
  public func retry() {
    guard case .failed(let notice) = phase, notice.canRetry, let lastRequest else { return }
    run(lastRequest)
  }

  /// Back to a clean form. Pasted text that couldn't be read is kept so it can be fixed.
  public func another() {
    let keepsText: Bool
    if case .text? = lastRequest, case .failed = phase {
      keepsText = true
    } else {
      keepsText = false
    }
    link = ""
    pastingFor = nil
    if !keepsText { text = "" }
    pages = []
    keepFirstPage = false
    photoMessage = nil
    prefersPaste = false
    stopped = false
    phase = .editing
  }

  /// The sheet closed: stops whatever is running and keeps nothing.
  public func discard() {
    generation += 1
    task?.cancel()
    task = nil
    pages = []
  }

  // MARK: The pages

  /// Adds pages from the images' bytes, up to the limit. An image that can't be used is left out
  /// with the reason in `photoMessage`; the rest are kept.
  public func addPages(_ images: [Data]) async {
    guard phase == .editing else { return }
    photoMessage = nil
    var refusal: CopyString?
    var overflow = false
    let limit = maxPixels
    for image in images {
      guard pages.count < Self.pageLimit else {
        overflow = true
        break
      }
      // Off the main actor: the check reads the header, the thumbnail decodes (shrunk).
      let made = await Task.detached { () -> Result<CGImage?, PhotoError> in
        switch PhotoProcessing.inspect(image, maxPixels: limit) {
        case .failure(let error): return .failure(error)
        case .success: return .success(PhotoProcessing.thumbnail(of: image, maxPixel: 240))
        }
      }.value
      guard phase == .editing else { return }
      switch made {
      case .success(let thumbnail):
        pages.append(ScannedPage(data: image, thumbnail: thumbnail))
      case .failure(let error):
        refusal = refusal ?? error.message
      }
    }
    photoMessage = refusal ?? (overflow ? Copy.importNative.pageLimit(Self.pageLimit) : nil)
  }

  public func removePage(_ id: UUID) {
    guard phase == .editing else { return }
    pages.removeAll { $0.id == id }
    if pages.isEmpty { keepFirstPage = false }
    photoMessage = nil
  }

  /// The photo section couldn't capture: the scanner is missing, refused, or stopped.
  public func reportPhotoProblem(_ message: CopyString?) {
    photoMessage = message
  }

  /// Waits for the run in progress to end; for tests.
  public func finished() async {
    await task?.value
  }

  // MARK: Running

  private func run(_ request: Request) {
    lastRequest = request
    lastReadText = nil
    reading = nil
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
    var keptPhoto: ProcessedPhoto?
    do throws(DistillError) {
      switch request {
      case .link(let address):
        distilled = try await Distill.url(
          address, fetcher: fetcher, extractor: extractor, options: options)
      case .text(let pasted, _):
        distilled = try await Distill.text(pasted, extractor: extractor, options: options)
      case .pages(let scanned, let keepFirst):
        let read = try await readPages(scanned, run: run)
        lastReadText = read
        distilled = try await Distill.text(read, extractor: extractor, options: options)
        if keepFirst, let first = scanned.first?.data {
          keptPhoto = await Task.detached {
            if case .success(let photo) = PhotoProcessing.process(first) { photo } else { nil }
          }.value
        }
      }
    } catch {
      guard run == generation else { return }
      reading = nil
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
    // never fails the import. The macro estimate is asked for beside it, for the cook to check.
    var photo = keptPhoto
    var thumbnail: ProcessedPhoto?
    var coverLink: String?
    async let estimate = estimateMacros(for: distilled)
    if case .link = request, let image = distilled.imageUrl {
      switch cover {
      case .photo:
        photo = await CoverPhoto.fetch(image, using: fetcher)
      case .thumbnail(let maxPixel, let timeout):
        if Distill.isAcceptedLink(image) { coverLink = image }
        thumbnail = await CoverPhoto.fetch(
          image, using: fetcher, timeout: timeout,
          decode: CoverPhoto.thumbnailDecode(maxPixel: maxPixel))
      }
    }
    let outcome = await estimate
    guard run == generation, !Task.isCancelled else { return }

    var keptLink: String?
    var fetchedAt: Date?
    switch request {
    case .link: fetchedAt = now()
    case .text(_, let link): keptLink = link
    case .pages: break
    }
    var draft = RecipeDraft(
      importing: distilled, photo: photo, link: keptLink, fetchedAt: fetchedAt)
    // An estimate goes into the fields, flagged to check. One that couldn't be had (no key, out
    // of reach, too slow) is queued by Save instead; it is never guessed (decision 10).
    if let outcome { draft.apply(outcome) }
    let links: [String?]
    switch request {
    case .link(let address): links = [address, distilled.draft.sourceUrl]
    case .text(_, let link): links = [link]
    case .pages: links = [nil]
    }
    reading = nil
    phase = .ready(
      ImportReview(
        draft: draft, duplicate: findDuplicate(links), coverLink: coverLink,
        thumbnail: thumbnail))
  }

  /// Asks for the macros of a recipe whose source published none, within the import's limit
  /// (`withMacros` in the reference). Nil when there is nothing to ask or nobody to ask, and
  /// when the on-device model read the recipe: it is only used when the chosen cloud provider
  /// couldn't be reached, so asking that provider now would only wait out the limit. The
  /// estimate is then left for after the recipe is saved.
  private func estimateMacros(for distilled: Distilled) async -> RecipeMacroEstimates.DraftOutcome?
  {
    guard let input = distilled.macroEstimate, let estimator, !distilled.rough else { return nil }
    return await RecipeMacroEstimates.divine(input, using: estimator, within: options.macroTimeout)
  }

  /// What went wrong reading pages that isn't a failure of distilling the text.
  private enum PhotoFailure {
    case noText
    case unreadable
  }

  /// Reads the pages one at a time, in the order they were captured, and joins what they say.
  private func readPages(_ scanned: [ScannedPage], run: Int) async throws(DistillError) -> String {
    photoFailure = nil
    var texts: [String] = []
    for (index, page) in scanned.enumerated() {
      guard run == generation, !Task.isCancelled else { throw .cancelled }
      reading = ReadingProgress(page: index + 1, of: scanned.count)
      do {
        texts.append(try await reader.read(page.data))
      } catch {
        switch error {
        case .cancelled: throw .cancelled
        case .unreadable, .failed:
          photoFailure = .unreadable
          throw .failed(.couldntRead)
        }
      }
    }
    guard run == generation, !Task.isCancelled else { throw .cancelled }
    reading = nil
    let joined = ReadingOrder.join(pages: texts)
    if joined.isEmpty {
      photoFailure = .noText
      throw .failed(.noRecipe)
    }
    return joined
  }

  private func notice(for code: ImportFailureCode, request: Request) -> ImportFailureNotice {
    var isText = false
    var isLink = false
    var isPages = false
    switch request {
    case .link: isLink = true
    case .text: isText = true
    case .pages: isPages = true
    }
    if isPages {
      let message: CopyString
      switch (photoFailure, code) {
      case (.noText?, _): message = Copy.importNative.noText
      case (.unreadable?, _): message = Copy.importNative.couldntReadPhotos
      case (nil, .noRecipe): message = Copy.importNative.noRecipeInPhotos
      case (nil, .tooLarge): message = Copy.importNative.tooMuchText
      case (nil, _): message = Copy.imports.failure(code)
      }
      let transient = photoFailure == nil && (code == .timeout || code == .unavailable)
      return ImportFailureNotice(
        code: code, message: message, canPaste: true, canRetry: transient,
        canChangePhotos: !transient)
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
