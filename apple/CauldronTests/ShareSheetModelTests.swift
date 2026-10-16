import CauldronKit
import Foundation
import Testing

@testable import Cauldron
@testable import CauldronImports

/// The share sheet's logic with a scripted page and model: from what was shared to the ready
/// summary, and what Save, Edit in Cauldron and every way out leave behind. Folders are
/// temporary; nothing touches the network or the real inbox.
@MainActor
@Suite("Share sheet")
struct ShareSheetModelTests {
  private let finished: URL
  private let drafts: URL

  init() throws {
    finished = try Self.folder("finished")
    drafts = try Self.folder("drafts")
  }

  private static func folder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "ShareSheetModelTests-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func tidy() {
    try? FileManager.default.removeItem(at: finished)
    try? FileManager.default.removeItem(at: drafts)
  }

  private func files(in folder: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: folder.path()))?.sorted() ?? []
  }

  private final class Closings {
    var all: [ShareSheetModel.Closing] = []
    /// What was in the folders each time the sheet closed.
    var filesAtClose: [(finished: Int, drafts: Int)] = []
  }

  private func sheet(
    _ item: SharedItem, fetcher: ScriptedFetcher = ScriptedFetcher(),
    extractor: (any RecipeExtracting)? = nil, finished: URL? = nil, drafts: URL? = nil,
    id: UUID = UUID(), keyMissing: Bool = false, closings: Closings = Closings()
  ) -> ShareSheetModel {
    let finishedFolder = finished ?? self.finished
    let draftsFolder = drafts ?? self.drafts
    return ShareSheetModel(
      item: item,
      importer: ImportModel(fetcher: fetcher, extractor: extractor, options: ImportFixtures.quick),
      finishedFolder: finishedFolder, inboxFolder: draftsFolder, id: id,
      now: { Date(timeIntervalSince1970: 1_800_000_000) }, closeDelay: .milliseconds(1),
      keyMissing: { keyMissing }
    ) { closing in
      closings.all.append(closing)
      closings.filesAtClose.append(
        (
          (try? FileManager.default.contentsOfDirectory(atPath: finishedFolder.path()).count) ?? 0,
          (try? FileManager.default.contentsOfDirectory(atPath: draftsFolder.path()).count) ?? 0
        ))
    }
  }

  private let tacos = SharedItem(url: ImportFixtures.tacosLink)

  private func ready(_ sheet: ShareSheetModel) throws -> ShareSheetModel.Review {
    guard case .ready(let review) = sheet.phase else {
      throw Failure("not ready: \(sheet.phase)")
    }
    return review
  }

  private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }

  private var tacosFetcher: ScriptedFetcher {
    ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)])
  }

  // MARK: Reading

  @Test func aSharedPageReadsFromReadingToAReadySummary() async throws {
    defer { tidy() }
    let sheet = sheet(tacos, fetcher: tacosFetcher)
    #expect(sheet.phase == .reading)
    sheet.start()
    #expect(sheet.phase == .reading)
    await sheet.finished()

    let review = try ready(sheet)
    #expect(review.title == "Smoky black bean tacos")
    #expect(review.source == "cook.example")
    #expect(review.ingredients == 3)
    #expect(review.steps == 2)
    #expect(review.canSave)
    #expect(review.draft.sourceURL == ImportFixtures.tacosLink)
  }

  @Test func anInstagramCaptionIsReadAsTextWithThePostAsItsSource() async throws {
    defer { tidy() }
    let post = "https://www.instagram.com/reel/Cabc123/"
    let fetcher = ScriptedFetcher()
    let sheet = sheet(
      SharedItem(url: post, text: "Garlic pasta: boil spaghetti. Fry garlic. Toss."),
      fetcher: fetcher,
      extractor: ScriptedExtractor(recipe: readRecipe(title: "Garlic pasta")))
    sheet.start()
    await sheet.finished()

    let review = try ready(sheet)
    #expect(fetcher.requests.isEmpty)
    #expect(review.title == "Garlic pasta")
    #expect(review.source == "instagram.com")
    #expect(review.ingredients == 2 && review.steps == 2)
  }

  @Test func startingTwiceReadsOnce() async throws {
    defer { tidy() }
    let fetcher = tacosFetcher
    let sheet = sheet(tacos, fetcher: fetcher)
    sheet.start()
    sheet.start()
    await sheet.finished()
    #expect(fetcher.requests.count == 1)
  }

  @Test func theSiteIsTheLinksHostWithoutWww() {
    #expect(ShareSheetModel.source(of: "https://www.seriouseats.com/a/b") == "seriouseats.com")
    #expect(ShareSheetModel.source(of: "https://cook.example/x") == "cook.example")
    #expect(ShareSheetModel.source(of: "") == nil)
  }

  // MARK: Save

  @Test func saveLeavesTheFinishedRecipeAndClosesOnlyAfterIt() async throws {
    defer { tidy() }
    let id = UUID()
    let closings = Closings()
    let sheet = sheet(tacos, fetcher: tacosFetcher, id: id, closings: closings)
    sheet.start()
    await sheet.finished()
    sheet.save()

    #expect(sheet.phase == .saved)
    let waiting = FinishedInbox.pending(from: finished)
    #expect(waiting.map(\.recipe.id) == [id])
    #expect(waiting.first?.recipe.sharedAt == Date(timeIntervalSince1970: 1_800_000_000))
    let recipe = try #require(waiting.first?.recipe).recipeDraft
    #expect(recipe.title == "Smoky black bean tacos")
    #expect(recipe.ingredients.compactMap(\.parsed).count == 3)
    // Nothing was left as a draft to open.
    #expect(files(in: drafts).isEmpty)

    #expect(closings.all.isEmpty)
    await sheet.closed()
    #expect(closings.all == [.done])
    // The payload was on disk when the sheet closed.
    #expect(closings.filesAtClose.first?.finished == 1)
  }

  @Test func savingTwiceLeavesOneRecipe() async throws {
    defer { tidy() }
    let sheet = sheet(tacos, fetcher: tacosFetcher)
    sheet.start()
    await sheet.finished()
    sheet.save()
    sheet.save()
    #expect(files(in: finished).count == 1)
  }

  @Test func aDraftThatFailsTheEditorsChecksIsNotOfferedForSaving() {
    var draft = RecipeDraft()
    draft.title = "  "
    draft.setIngredientText(draft.ingredients[0].id, "1 egg")
    #expect(!ShareSheetModel.summary(of: draft).canSave)
    draft.title = "Fried egg"
    #expect(ShareSheetModel.summary(of: draft).canSave)
    #expect(ShareSheetModel.summary(of: draft).ingredients == 1)
    #expect(ShareSheetModel.summary(of: draft).steps == 0)
  }

  @Test func aRecipeThatCantBeLeftOffersTheOldPath() async throws {
    defer { tidy() }
    let missing = FileManager.default.temporaryDirectory.appending(path: "no-\(UUID())/x/y")
    // A file where the folder should be, so nothing can be written under it.
    try Data().write(
      to: missing.deletingLastPathComponent().deletingLastPathComponent(), options: [])
    defer {
      try? FileManager.default.removeItem(
        at: missing.deletingLastPathComponent().deletingLastPathComponent())
    }
    let closings = Closings()
    let sheet = sheet(tacos, fetcher: tacosFetcher, finished: missing, closings: closings)
    sheet.start()
    await sheet.finished()
    sheet.save()

    #expect(sheet.phase == .failed(.init(message: Copy.importNative.couldntSave, canSend: true)))
    #expect(closings.all.isEmpty)
    sheet.sendToCauldron()
    #expect(sheet.phase == .sent)
    #expect(ShareInbox.takeAll(from: drafts).map(\.url) == [ImportFixtures.tacosLink])
  }

  // MARK: Edit in Cauldron, failures and Cancel

  @Test func editInCauldronLeavesTheLinkForADraftAndNoRecipe() async throws {
    defer { tidy() }
    let closings = Closings()
    let sheet = sheet(tacos, fetcher: tacosFetcher, closings: closings)
    sheet.start()
    await sheet.finished()
    sheet.sendToCauldron()

    #expect(sheet.phase == .sent)
    #expect(files(in: finished).isEmpty)
    await sheet.closed()
    #expect(closings.all == [.done])
    #expect(closings.filesAtClose.first?.drafts == 1)
    #expect(ShareInbox.takeAll(from: drafts).map(\.url) == [ImportFixtures.tacosLink])
  }

  @Test func aPageThatCantBeReadOffersToSendItInstead() async throws {
    defer { tidy() }
    let item = SharedItem(url: "https://down.example/a")
    let sheet = sheet(
      item, fetcher: ScriptedFetcher(["https://down.example/a": .fail(.status(404))]))
    sheet.start()
    await sheet.finished()

    guard case .failed(let notice) = sheet.phase else {
      Issue.record("should fail: \(sheet.phase)")
      return
    }
    #expect(notice.canSend)
    #expect(!notice.message.text.isEmpty)
    sheet.sendToCauldron()
    #expect(sheet.phase == .sent)
    #expect(ShareInbox.takeAll(from: drafts).map(\.url) == ["https://down.example/a"])
  }

  @Test func withNoKeyAndNoModelAPageThatNeedsOneOffersToSendItInstead() async throws {
    defer { tidy() }
    // A page with no recipe markup, which only a model could read.
    let item = SharedItem(url: ImportFixtures.soupLink)
    let sheet = sheet(
      item,
      fetcher: ScriptedFetcher([
        ImportFixtures.soupLink: .html("<article><p>A long story about my week.</p></article>")
      ]),
      extractor: ScriptedExtractor(failing: .missingKey))
    sheet.start()
    await sheet.finished()

    guard case .failed(let notice) = sheet.phase else {
      Issue.record("should fail: \(sheet.phase)")
      return
    }
    #expect(notice.canSend)
    sheet.sendToCauldron()
    #expect(ShareInbox.takeAll(from: drafts).map(\.url) == [ImportFixtures.soupLink])
  }

  @Test func whenNothingCanBeLeftForTheAppTheSheetSaysSoAndOffersNoMoreSending() async throws {
    defer { tidy() }
    let sheet = ShareSheetModel(
      item: tacos,
      importer: ImportModel(
        fetcher: ScriptedFetcher(["https://down.example/a": .fail(.status(404))]), extractor: nil,
        options: ImportFixtures.quick),
      finishedFolder: nil, inboxFolder: nil, closeDelay: .milliseconds(1), close: { _ in })
    sheet.sendToCauldron()
    #expect(sheet.phase == .failed(.init(message: Copy.importNative.couldntSend, canSend: false)))
  }

  @Test func cancelClosesWithNothingLeftBehind() async throws {
    defer { tidy() }
    let closings = Closings()
    let fetcher = ScriptedFetcher([ImportFixtures.tacosLink: .hold])
    let sheet = sheet(tacos, fetcher: fetcher, closings: closings)
    sheet.start()
    #expect(sheet.phase == .reading)
    sheet.cancel()
    #expect(closings.all == [.cancelled])
    #expect(files(in: finished).isEmpty && files(in: drafts).isEmpty)
  }

  // MARK: The summary (#202)

  private let post = "https://www.instagram.com/reel/Cabc123/"

  /// A caption a model read, with two lines it wasn't sure of.
  private func caption(rough: Bool = false) -> (SharedItem, ScriptedExtractor) {
    let recipe = ExtractedRecipe(
      title: "Hot honey halloumi", servings: 2, prepMinutes: 5, cookMinutes: 15, tags: [],
      ingredients: [
        ExtractedLine(line: "225 g halloumi, sliced", section: nil, unsure: false),
        ExtractedLine(line: "a big drizzle of hot honey", section: nil, unsure: true),
        ExtractedLine(line: "pickled onions (link in bio)", section: nil, unsure: true),
      ],
      steps: [ExtractedStep(text: "Fry the halloumi.", section: nil, unsure: false)])
    return (
      SharedItem(url: post, text: "Hot honey halloumi: fry it, drizzle it."),
      ScriptedExtractor(recipe: recipe, rough: rough)
    )
  }

  @Test func theSummaryCountsTheLinesToCheckAndTheNumbers() async throws {
    defer { tidy() }
    let (item, extractor) = caption()
    let sheet = sheet(item, extractor: extractor)
    sheet.start()
    await sheet.finished()

    let review = try ready(sheet)
    #expect(review.ingredients == 3)
    #expect(review.linesToCheck == 2)
    #expect(review.steps == 1)
    #expect(review.servings == 2)
    // No total given: prep plus cook.
    #expect(review.minutes == 20)
    #expect(!review.rough)
    #expect(review.editLabel == Copy.importNative.fixInCauldron)
  }

  @Test func aCleanRecipeHasNoLinesToCheckAndOffersEdit() async throws {
    defer { tidy() }
    let sheet = sheet(tacos, fetcher: tacosFetcher)
    sheet.start()
    await sheet.finished()

    let review = try ready(sheet)
    #expect(review.linesToCheck == 0)
    #expect(review.editLabel == Copy.importNative.editInCauldron)
    // Prep 15 and cook 20 on the page.
    #expect(review.minutes == 35)
    #expect(review.servings == 4)
  }

  @Test func theFixButtonLeavesTheCaptionAndTheLinkForADraftAndNoRecipe() async throws {
    defer { tidy() }
    let (item, extractor) = caption()
    let sheet = sheet(item, extractor: extractor)
    sheet.start()
    await sheet.finished()
    sheet.sendToCauldron()

    #expect(sheet.phase == .sent)
    #expect(files(in: finished).isEmpty)
    let kept = ShareInbox.takeAll(from: drafts)
    #expect(kept.map(\.url) == [post])
    #expect(kept.map(\.text) == ["Hot honey halloumi: fry it, drizzle it."])
  }

  @Test func theOnDeviceFallbackIsMarkedRoughAndStaysRoughWhenSaved() async throws {
    defer { tidy() }
    let (item, extractor) = caption(rough: true)
    let sheet = sheet(item, extractor: extractor)
    sheet.start()
    await sheet.finished()

    let review = try ready(sheet)
    #expect(review.rough)
    sheet.save()
    let saved = try #require(FinishedInbox.pending(from: finished).first?.recipe).recipeDraft
    #expect(saved.imported?.rough == true)
  }

  @Test func aPageOnlyAModelCouldReadWithNoKeyGetsTheNoKeyNotice() async throws {
    defer { tidy() }
    let item = SharedItem(url: ImportFixtures.soupLink)
    let sheet = sheet(
      item,
      fetcher: ScriptedFetcher([
        ImportFixtures.soupLink: .html("<article><p>A long story about my week.</p></article>")
      ]),
      extractor: ScriptedExtractor(failing: .missingKey), keyMissing: true)
    sheet.start()
    await sheet.finished()

    #expect(
      sheet.phase
        == .failed(.init(message: Copy.importNative.noAIKey, canSend: true, kind: .noKey)))
    sheet.sendToCauldron()
    #expect(sheet.phase == .sent)
    #expect(ShareInbox.takeAll(from: drafts).map(\.url) == [ImportFixtures.soupLink])
  }

  @Test func anUnreadablePageIsNotBlamedOnAMissingKey() async throws {
    defer { tidy() }
    let sheet = sheet(
      SharedItem(url: "https://down.example/a"),
      fetcher: ScriptedFetcher(["https://down.example/a": .fail(.status(404))]), keyMissing: true)
    sheet.start()
    await sheet.finished()

    guard case .failed(let notice) = sheet.phase else {
      Issue.record("should fail: \(sheet.phase)")
      return
    }
    #expect(notice.kind == .unreadable)
    #expect(notice.message != Copy.importNative.noAIKey)
    #expect(notice.canSend)
  }

  @Test func aRecipeFromThePageNeedsNoKey() async throws {
    defer { tidy() }
    let sheet = sheet(tacos, fetcher: tacosFetcher, keyMissing: true)
    sheet.start()
    await sheet.finished()
    _ = try ready(sheet)
  }

  @Test func cancelWhileReadingStopsTheReadAndLeavesNothing() async throws {
    defer { tidy() }
    let closings = Closings()
    let sheet = sheet(
      tacos, fetcher: ScriptedFetcher([ImportFixtures.tacosLink: .hold]), closings: closings)
    sheet.start()
    #expect(sheet.phase == .reading)
    sheet.cancel()
    await sheet.finished()
    // Still reading as far as the view goes, but closed, and nothing was written.
    #expect(closings.all == [.cancelled])
    #expect(files(in: finished).isEmpty && files(in: drafts).isEmpty)
  }

  @Test func nothingSharedIsAFailureWithNothingToSend() {
    defer { tidy() }
    let sheet = sheet(SharedItem())
    sheet.start()
    #expect(sheet.phase == .failed(.init(message: Copy.importNative.nothingToSend, canSend: false)))
  }
}
