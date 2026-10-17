import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron
@testable import CauldronImports

/// Distilling from photographed pages: the flow with a scripted reader and model. Nothing here
/// runs Vision, the camera or the network.
@MainActor
@Suite("Distill from a photo")
struct ImportPhotoTests {
  private func model(
    _ reader: ScriptedReader, extractor: (any RecipeExtracting)? = nil,
    maxPixels: Int = PhotoProcessing.maxPixels
  ) -> ImportModel {
    ImportModel(
      fetcher: ScriptedFetcher(), extractor: extractor, reader: reader, maxPixels: maxPixels,
      options: ImportFixtures.quick)
  }

  /// Distinct pictures, so the order they were read in can be told from what the reader saw.
  private func pictures(_ count: Int) -> [Data] {
    (0..<count).map { ImportFixtures.imageData(40 + $0, 30) }
  }

  private func distill(_ flow: ImportModel, pages: [Data]) async {
    await flow.addPages(pages)
    flow.start()
    await flow.finished()
  }

  private func review(_ flow: ImportModel) throws -> ImportReview {
    guard case .ready(let review) = flow.phase else {
      throw Failure("not ready: \(flow.phase)")
    }
    return review
  }

  private func notice(_ flow: ImportModel) throws -> ImportFailureNotice {
    guard case .failed(let notice) = flow.phase else { throw Failure("not failed: \(flow.phase)") }
    return notice
  }

  private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }

  // MARK: Reading

  @Test func aPageThatReadsClearlyNeedsNoModelAndIsAPasteWithNoSource() async throws {
    let extractor = ScriptedExtractor(recipe: readRecipe(title: "From the model"))
    let reader = ScriptedReader(pages: ImportFixtures.soupPage)
    let flow = model(reader, extractor: extractor)
    await distill(flow, pages: pictures(1))

    let ready = try review(flow)
    #expect(ready.draft.title == "Tomato soup")
    #expect(extractor.inputs.isEmpty, "the text was laid out clearly: no model was asked")
    #expect(ready.draft.imported?.platform == .text)
    #expect(ready.draft.imported?.fetchedAt == nil)
    #expect(ready.draft.imported?.rough == false)
    #expect(ready.draft.sourceURL.isEmpty)
    #expect(ready.draft.servings == "4")
    #expect(ready.draft.ingredients.map(\.text).filter { !$0.isEmpty }.count >= 2)
    #expect(ready.draft.steps.count == 2)
    #expect(ready.draft.photo == .keep, "a cookbook page isn't the recipe's picture unless asked")
  }

  @Test func twoPagesAreReadInTheOrderTheyWereCapturedAndJoined() async throws {
    let extractor = ScriptedExtractor(recipe: readRecipe(title: "From the model"))
    let reader = ScriptedReader(pages: ImportFixtures.soupPageOne, ImportFixtures.soupPageTwo)
    let pages = pictures(2)
    let flow = model(reader, extractor: extractor)
    await distill(flow, pages: pages)

    #expect(reader.images == pages)
    let ready = try review(flow)
    #expect(ready.draft.title == "Tomato soup")
    #expect(ready.draft.steps.count == 2, "the method on the second page is in the draft")
    #expect(ready.draft.ingredients.map(\.text).contains { $0.contains("onions") })
    #expect(extractor.inputs.isEmpty)
  }

  @Test func theTextGoesToTheModelJoinedWithABlankLineWhenThePagesDontReadClearly() async throws {
    let extractor = ScriptedExtractor(recipe: readRecipe(title: "Grandma's soup"))
    let reader = ScriptedReader(pages: "some soup my gran makes", "boil the onions and carrots")
    let flow = model(reader, extractor: extractor)
    await distill(flow, pages: pictures(2))

    let ready = try review(flow)
    #expect(ready.draft.title == "Grandma's soup")
    let asked = try #require(extractor.inputs.first)
    #expect(asked.text == "some soup my gran makes\n\nboil the onions and carrots")
    #expect(extractor.inputs.count == 1)
  }

  @Test func theModelsRoughReadingIsFlaggedAsInAPaste() async throws {
    let extractor = ScriptedExtractor(recipe: readRecipe(), rough: true)
    let flow = model(ScriptedReader(pages: "soup from my gran"), extractor: extractor)
    await distill(flow, pages: pictures(1))
    #expect(try review(flow).draft.imported?.rough == true)
  }

  @Test func aBlankPageBetweenTwoGoodOnesIsLeftOut() async throws {
    let reader = ScriptedReader([
      .text(ImportFixtures.soupPageOne), .text("   \n"), .text(ImportFixtures.soupPageTwo),
    ])
    let flow = model(reader)
    await distill(flow, pages: pictures(3))
    #expect(try review(flow).draft.steps.count == 2)
  }

  @Test func theProgressNamesThePageBeingRead() async throws {
    let reader = ScriptedReader([.text(ImportFixtures.soupPageOne), .hold])
    let flow = model(reader)
    await flow.addPages(pictures(2))
    flow.start()
    while reader.startedCount < 2 { await Task.yield() }
    #expect(flow.phase == .working)
    #expect(flow.reading == ImportModel.ReadingProgress(page: 2, of: 2))
    flow.stop()
    await flow.finished()
    #expect(flow.reading == nil)
  }

  // MARK: Failures

  @Test func noTextFoundSaysSoAndOffersTryingAgainAndPasting() async throws {
    let reader = ScriptedReader(pages: "", "  ")
    let flow = model(reader, extractor: ScriptedExtractor(recipe: readRecipe()))
    await distill(flow, pages: pictures(2))

    let failed = try notice(flow)
    #expect(failed.message == Copy.importNative.noText)
    #expect(failed.canChangePhotos)
    #expect(failed.canPaste)
    #expect(!failed.canRetry)

    // Try again: the form, with the pages as they were.
    flow.changePhotos()
    #expect(flow.phase == .editing)
    #expect(flow.pages.count == 2)

    // Or paste: the pages go, the paste box is the way on.
    flow.start()
    await flow.finished()
    flow.pasteInstead()
    #expect(flow.phase == .editing)
    #expect(flow.pages.isEmpty)
    #expect(flow.prefersPaste)
    #expect(flow.text.isEmpty)
  }

  @Test func textThatIsTooLongForOneRecipeSaysSo() async throws {
    let long = String(repeating: "2 cups of flour, sifted twice.\n", count: 2_000)
    #expect(long.count > Distill.textMax)
    let flow = model(
      ScriptedReader(pages: long), extractor: ScriptedExtractor(recipe: readRecipe()))
    await distill(flow, pages: pictures(1))

    let failed = try notice(flow)
    #expect(failed.code == .tooLarge)
    #expect(failed.message == Copy.importNative.tooMuchText)
    #expect(failed.canChangePhotos)
    flow.pasteInstead()
    #expect(flow.text.isEmpty, "text too long for the paste path isn't carried over")
  }

  @Test func textThatIsntARecipeSaysSoAndLetsTheCookFixWhatWasRead() async throws {
    let extractor = ScriptedExtractor(recipe: ExtractedRecipe())
    let flow = model(ScriptedReader(pages: "Open daily 9 to 5"), extractor: extractor)
    await distill(flow, pages: pictures(1))

    let failed = try notice(flow)
    #expect(failed.message == Copy.importNative.noRecipeInPhotos)
    flow.pasteInstead()
    #expect(flow.text == "Open daily 9 to 5", "what was read comes along to be fixed")
    #expect(flow.pages.isEmpty)
  }

  @Test func aReaderThatFailsSaysTheTextCouldntBeReadAndNothingElseRuns() async throws {
    let extractor = ScriptedExtractor(recipe: readRecipe())
    let flow = model(ScriptedReader([.fail(.failed)]), extractor: extractor)
    await distill(flow, pages: pictures(1))

    let failed = try notice(flow)
    #expect(failed.message == Copy.importNative.couldntReadPhotos)
    #expect(failed.canPaste)
    #expect(extractor.inputs.isEmpty)
  }

  @Test func aModelThatCantBeReachedOffersAnotherTryOfTheSamePages() async throws {
    let extractor = ScriptedExtractor(failing: .unreachable)
    let flow = model(
      ScriptedReader(pages: "soup from my gran", "soup from my gran"), extractor: extractor)
    await distill(flow, pages: pictures(1))
    let failed = try notice(flow)
    #expect(failed.canRetry)
    #expect(!failed.canChangePhotos)
    #expect(failed.message == Copy.imports.failure(failed.code))
  }

  // MARK: Stopping

  @Test func stoppingMidReadLeavesNoDraftAndNothingStored() async throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let reader = ScriptedReader([.hold, .text(ImportFixtures.soupPage)])
    let flow = model(reader)
    await flow.addPages(pictures(1))
    flow.start()
    #expect(flow.phase == .working)
    while reader.startedCount == 0 { await Task.yield() }

    flow.stop()
    #expect(flow.phase == .editing)
    #expect(flow.stopped)
    #expect(flow.pages.count == 1, "the pages stay for another try")
    await flow.finished()
    #expect(flow.phase == .editing, "the stopped read didn't come back as a result")
    #expect(try context.fetchCount(FetchDescriptor<RecipeRecord>()) == 0)

    // And the form works again.
    flow.start()
    await flow.finished()
    #expect(try review(flow).draft.title == "Tomato soup")
  }

  @Test func closingTheSheetStopsTheReadAndDropsThePages() async throws {
    let reader = ScriptedReader([.hold])
    let flow = model(reader)
    await flow.addPages(pictures(1))
    flow.start()
    while reader.startedCount == 0 { await Task.yield() }
    flow.discard()
    await flow.finished()
    if case .ready = flow.phase { Issue.record("a closed sheet got a draft") }
    #expect(flow.pages.isEmpty)
  }

  // MARK: The picture

  @Test func theFirstPageCanBeKeptAsTheRecipePhoto() async throws {
    let flow = model(ScriptedReader(pages: ImportFixtures.soupPageOne, ImportFixtures.soupPageTwo))
    await flow.addPages(pictures(2))
    #expect(!flow.keepFirstPage, "off unless the cook turns it on")
    flow.keepFirstPage = true
    flow.start()
    await flow.finished()

    guard case .replace(let photo) = try review(flow).draft.photo else {
      Issue.record("the first page should be the photo")
      return
    }
    // The same downscaled JPEG the editor makes, of the first page.
    #expect(photo.width == 40 && photo.height == 30)
    #expect(photo.data.starts(with: [0xFF, 0xD8]))
  }

  @Test func withoutTheTogglePagesAreNeverTheRecipePhoto() async throws {
    let flow = model(ScriptedReader(pages: ImportFixtures.soupPage))
    await distill(flow, pages: pictures(1))
    #expect(try review(flow).draft.photo == .keep)
  }

  @Test func removingEveryPageTurnsTheToggleOff() async throws {
    let flow = model(ScriptedReader(pages: "x"))
    await flow.addPages(pictures(2))
    flow.keepFirstPage = true
    for page in flow.pages { flow.removePage(page.id) }
    #expect(flow.pages.isEmpty)
    #expect(!flow.keepFirstPage)
    #expect(!flow.canStart)
  }

  // MARK: Limits

  @Test func aRecipeHasAtMostTenPagesAndSaysSoWhenMoreAreChosen() async throws {
    let reader = ScriptedReader([])
    let flow = model(reader)
    await flow.addPages(pictures(12))
    #expect(flow.pages.count == ImportModel.pageLimit)
    #expect(flow.pages.count == 10)
    #expect(flow.photoMessage == Copy.importNative.pageLimit(10))
    // The first ten, in order.
    #expect(flow.pages.map(\.data) == Array(pictures(12).prefix(10)))

    flow.removePage(flow.pages[0].id)
    await flow.addPages(pictures(1))
    #expect(flow.pages.count == 10)
    #expect(flow.photoMessage == nil)
  }

  @Test func aPictureOverThePixelCapIsRefusedAndTheRestAreKept() async throws {
    // The cap is checked from the picture's header, as the photo picker's is. A real 100
    // megapixel file is too much to build here, so the cap is lowered to sit between two sizes.
    let flow = model(ScriptedReader([]), maxPixels: 2_000)
    let small = ImportFixtures.imageData(40, 30)
    await flow.addPages([ImportFixtures.imageData(64, 48), small])
    #expect(flow.pages.map(\.data) == [small])
    #expect(flow.photoMessage == PhotoError.tooBig.message)
  }

  @Test func theDefaultCapIsThePhotoPickersAndTakesAnOrdinaryPicture() async throws {
    #expect(PhotoProcessing.maxPixels == 100_000_000)
    let flow = model(ScriptedReader([]))
    await flow.addPages([ImportFixtures.imageData(3000, 4000)])
    #expect(flow.pages.count == 1)
    #expect(flow.photoMessage == nil)
  }

  @Test func somethingThatIsntAnImageIsRefusedWithoutBeingRead() async throws {
    let reader = ScriptedReader(pages: ImportFixtures.soupPage)
    let flow = model(reader)
    await flow.addPages([Data("not a picture".utf8)])
    #expect(flow.pages.isEmpty)
    #expect(flow.photoMessage == PhotoError.unsupported.message)
    #expect(!flow.canStart)
    #expect(reader.startedCount == 0)
  }

  @Test func aFileOverTheSizeLimitIsRefused() async throws {
    let flow = model(ScriptedReader([]))
    await flow.addPages([Data(count: PhotoProcessing.maxBytes + 1)])
    #expect(flow.pages.isEmpty)
    #expect(flow.photoMessage == PhotoError.tooLarge.message)
  }

  // MARK: The form

  @Test func pagesTakeThePlaceOfAnyLinkOrPastedTextUntilTheyAreTakenAway() async throws {
    let reader = ScriptedReader(pages: ImportFixtures.soupPage)
    let flow = model(reader)
    flow.link = "https://cook.example/tacos"
    flow.text = "pasted"
    #expect(!flow.pagesAreOn)
    await flow.addPages(pictures(1))
    #expect(flow.pagesAreOn)
    #expect(flow.link == "https://cook.example/tacos", "what was typed is kept")

    flow.start()
    await flow.finished()
    #expect(try review(flow).draft.title == "Tomato soup")
    #expect(reader.startedCount == 1)
  }

  @Test func anotherStartsAfreshWithoutPages() async throws {
    let flow = model(ScriptedReader(pages: ""))
    await distill(flow, pages: pictures(2))
    flow.another()
    #expect(flow.pages.isEmpty)
    #expect(flow.photoMessage == nil)
    #expect(flow.phase == .editing)
    #expect(!flow.canStart)
  }

  @Test func pagesCantBeAddedWhileARunIsGoing() async throws {
    let reader = ScriptedReader([.hold])
    let flow = model(reader)
    await flow.addPages(pictures(1))
    flow.start()
    await flow.addPages(pictures(1))
    #expect(flow.pages.count == 1)
    flow.discard()
    await flow.finished()
  }

  @Test func theScannerSaysWhyItCantOpen() {
    let ready = ScannerAvailability.resolve(
      hasUsageDescription: true, scannerSupported: true, authorization: .undecided)
    #expect(ready == .ready && ready.message == nil)
    #expect(
      ScannerAvailability.resolve(
        hasUsageDescription: true, scannerSupported: true, authorization: .allowed) == .ready)
    let refused = ScannerAvailability.resolve(
      hasUsageDescription: true, scannerSupported: true, authorization: .refused)
    #expect(refused == .refused && refused.message == Copy.importNative.cameraRefused)
    for (described, supported) in [(false, true), (true, false), (false, false)] {
      let none = ScannerAvailability.resolve(
        hasUsageDescription: described, scannerSupported: supported, authorization: .allowed)
      #expect(none == .unavailable && none.message == Copy.importNative.scannerUnavailable)
    }
    // Refused or not, a camera that isn't there is "unavailable".
    #expect(
      ScannerAvailability.resolve(
        hasUsageDescription: true, scannerSupported: false, authorization: .refused)
        == .unavailable)
  }

  @Test func imageFilesAreReadIntoMemoryAndTheOnesThatCantBeAreReported() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "cauldron-photo-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let picture = ImportFixtures.imageData(30, 20)
    let file = folder.appending(path: "page.png")
    try picture.write(to: file)
    let empty = folder.appending(path: "empty.png")
    try Data().write(to: empty)

    let found = await ImageFiles.read([file])
    #expect(found.images == [picture] && found.problem == nil)
    let mixed = await ImageFiles.read([empty, file, folder.appending(path: "gone.png")])
    #expect(mixed.images == [picture])
    #expect(mixed.problem == .unreadable)
    let web = await ImageFiles.read([URL(string: "https://cook.example/a.png")!])
    #expect(web.images.isEmpty && web.problem == .unreadable)
  }
}
