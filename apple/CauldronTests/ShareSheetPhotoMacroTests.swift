import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron
@testable import CauldronImports

/// The share sheet's cover photo and macros (#203). The sheet shows a small thumbnail and asks
/// for the macro estimate only when the cloud provider can be reached; the finished recipe
/// carries the photo's link, and the app fetches the full-size photo when it adds the recipe.
/// Folders are temporary, the store is in memory, and the network is a scripted fetcher.
@MainActor
@Suite("Share sheet photo and macros")
struct ShareSheetPhotoMacroTests {
  private let estimate = Macros(calories: 310, protein: 17, carbs: 18, fat: 19)
  private let container: ModelContainer
  private let context: ModelContext
  private let finished: URL
  private let drafts: URL

  init() throws {
    container = try CauldronStore.container(.inMemory)
    context = ModelContext(container)
    finished = try Self.folder("finished")
    drafts = try Self.folder("drafts")
  }

  private static func folder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "ShareSheetPhotoMacroTests-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
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

  private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }

  // MARK: The sheet

  private let tacos = SharedItem(url: ImportFixtures.tacosLink)

  /// The sheet as the extension builds it: a thumbnail for a cover, and the macro estimate asked
  /// of `estimator` within `wait`.
  private func sheet(
    _ item: SharedItem, fetcher: ScriptedFetcher, extractor: (any RecipeExtracting)? = nil,
    estimator: (any RecipeAI)? = nil, wait: Duration = .seconds(30), id: UUID = UUID()
  ) -> ShareSheetModel {
    var options = ImportFixtures.quick
    options.macroTimeout = wait
    return ShareSheetModel(
      item: item,
      importer: ImportModel(
        fetcher: fetcher, extractor: extractor, estimator: estimator, options: options,
        cover: .sheetThumbnail),
      finishedFolder: finished, inboxFolder: drafts, id: id, closeDelay: .milliseconds(1),
      close: { _ in })
  }

  private func tacosFetcher(
    nutrition: Bool = false, cover: ScriptedFetcher.Reply? = nil
  ) -> ScriptedFetcher {
    ScriptedFetcher([
      ImportFixtures.tacosLink: ImportFixtures.tacos(nutrition: nutrition, image: true),
      ImportFixtures.tacosImage: cover ?? .image(ImportFixtures.imageData(64, 48)),
    ])
  }

  private func review(_ sheet: ShareSheetModel) async throws -> ShareSheetModel.Review {
    sheet.start()
    await sheet.finished()
    guard case .ready(let review) = sheet.phase else {
      throw Failure("not ready: \(sheet.phase)")
    }
    return review
  }

  @Test func theSheetShowsASmallThumbnailOfTheCover() async throws {
    defer { tidy() }
    // A large cover: the sheet must not hold it at full size.
    let big = ImportFixtures.imageData(1600, 1200, as: .jpeg)
    let fetcher = tacosFetcher(cover: .image(big, type: "image/jpeg"))
    let review = try await review(sheet(tacos, fetcher: fetcher))

    let thumbnail = try #require(review.thumbnail)
    #expect(max(thumbnail.width, thumbnail.height) == 320)
    #expect(thumbnail.data.count < big.count)
    #expect(review.coverLink == ImportFixtures.tacosImage)
    // The draft itself carries no photo: the app fetches the full-size one.
    #expect(review.draft.photo == .keep)
  }

  @Test func removingAPhotoBeforeItsQueuedCoverStartsSurvivesRestart() async throws {
    defer { tidy() }
    let payload = try payload(cover: coverLink)
    let queue = SharedImportQueue(folder: drafts, finishedFolder: finished, enabled: true)
    #expect(queue.pickUp(in: context) == 1)
    let saved = try #require(try context.fetch(FetchDescriptor<RecipeRecord>()).first)
    var draft = payload.recipeDraft
    draft.photo = .remove
    try RecipeSaver.save(draft, into: saved, context: context, index: SavedLinksIndex(folder: nil))
    // The queue already holds a cover request, so its attachment path must check before fetching.
    let fetcher = coverFetcher()
    await queue.fetchCovers(into: context, using: fetcher)
    #expect(fetcher.requests.isEmpty)
    #expect(try recipes().first?.photo == nil)
    // A fresh receiver must also respect the choice if the original payload is delivered again.
    try FinishedInbox.add(payload, in: finished)
    let restarted = SharedImportQueue(folder: drafts, finishedFolder: finished, enabled: true)
    let restartedContext = ModelContext(container)
    #expect(restarted.pickUp(in: restartedContext) == 0)
    await restarted.fetchCovers(into: restartedContext, using: fetcher)
    #expect(fetcher.requests.isEmpty)
    #expect(try recipes().first?.photo == nil)
  }

  @Test func aCoverThatCantBeHadLeavesNoThumbnailAndStillSaves() async throws {
    defer { tidy() }
    let fetcher = tacosFetcher(cover: .fail(.status(404)))
    let sheet = sheet(tacos, fetcher: fetcher)
    let review = try await review(sheet)

    #expect(review.thumbnail == nil)
    #expect(review.canSave)
    // The link is still left for the app, which may have better luck.
    #expect(review.coverLink == ImportFixtures.tacosImage)
    sheet.save()
    #expect(sheet.phase == .saved)
  }

  @Test func aPageWithNoCoverHasNoThumbnailOrLink() async throws {
    defer { tidy() }
    let fetcher = ScriptedFetcher([
      ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)
    ])
    let review = try await review(sheet(tacos, fetcher: fetcher))
    #expect(review.thumbnail == nil && review.coverLink == nil)
  }

  @Test func theFinishedRecipeCarriesTheCoversLinkAndNotItsPhoto() async throws {
    defer { tidy() }
    let id = UUID()
    let sheet = sheet(tacos, fetcher: tacosFetcher(), id: id)
    _ = try await review(sheet)
    sheet.save()

    let payload = try #require(FinishedInbox.pending(from: finished).first?.recipe)
    #expect(payload.id == id)
    #expect(payload.coverLink == ImportFixtures.tacosImage)
    #expect(payload.draft.photo == nil)
    #expect(payload.recipeDraft.photo == .keep)
  }

  @Test func anOlderPayloadWithNoCoverLinkStillReads() throws {
    var draft = RecipeDraft()
    draft.title = "Toast"
    let payload = FinishedRecipe(draft: draft)
    var json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
    json["coverLink"] = nil
    let back = try JSONDecoder().decode(
      FinishedRecipe.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(back.coverLink == nil)
    #expect(back.draft.title == "Toast")
  }

  // MARK: The macros

  @Test func whenTheProviderIsReachableTheEstimateIsInTheSummary() async throws {
    defer { tidy() }
    let estimator = ScriptedEstimator(.macros(estimate))
    let sheet = sheet(tacos, fetcher: tacosFetcher(), estimator: estimator)
    let review = try await review(sheet)

    #expect(review.macros == estimate)
    #expect(review.macrosEstimated)
    #expect(!review.macrosPending)
    #expect(estimator.inputs.count == 1)

    // It travels with the recipe as an estimate, with nothing left for the app to ask.
    sheet.save()
    let payload = try #require(FinishedInbox.pending(from: finished).first?.recipe)
    #expect(payload.draft.estimatedMacros == estimate)
    #expect(!payload.recipeDraft.estimateOnSave)
  }

  @Test func whenTheProviderCantBeReachedTheEstimateIsPendingNotGuessed() async throws {
    defer { tidy() }
    let estimator = ScriptedEstimator(.fail(.unreachable))
    let sheet = sheet(tacos, fetcher: tacosFetcher(), estimator: estimator)
    let review = try await review(sheet)

    #expect(estimator.inputs.count == 1)
    #expect(review.macros == nil)
    #expect(review.macrosPending)
    #expect(review.draft.estimatedMacros == nil)

    sheet.save()
    let payload = try #require(FinishedInbox.pending(from: finished).first?.recipe)
    #expect(payload.recipeDraft.estimateOnSave)
    #expect(payload.recipeDraft.typedMacros == Macros())
  }

  @Test func aProviderThatDoesntAnswerInTimeIsLeftForTheApp() async throws {
    defer { tidy() }
    let sheet = sheet(
      tacos, fetcher: tacosFetcher(), estimator: ScriptedEstimator(.hang), wait: .milliseconds(30))
    let review = try await review(sheet)
    #expect(review.macros == nil)
    #expect(review.macrosPending)
  }

  @Test func withNoEstimatorNothingIsAskedAndTheEstimateIsPending() async throws {
    defer { tidy() }
    let review = try await review(sheet(tacos, fetcher: tacosFetcher()))
    #expect(review.macros == nil)
    #expect(review.macrosPending)
  }

  @Test func nutritionThePagePublishedIsShownAndNothingIsAsked() async throws {
    defer { tidy() }
    let estimator = ScriptedEstimator(.macros(estimate))
    let review = try await review(
      sheet(tacos, fetcher: tacosFetcher(nutrition: true), estimator: estimator))
    #expect(review.macros == Macros(calories: 350, protein: 20, carbs: 30, fat: 10))
    #expect(!review.macrosEstimated)
    #expect(!review.macrosPending)
    #expect(estimator.inputs.isEmpty)
  }

  @Test func aRecipeTheOnDeviceModelReadIsNotAskedForAnEstimate() async throws {
    defer { tidy() }
    // The on-device model only reads a recipe when the cloud provider couldn't be reached, so
    // the estimate is not tried at all.
    let estimator = ScriptedEstimator(.macros(estimate))
    let fetcher = ScriptedFetcher([ImportFixtures.soupLink: ImportFixtures.soup])
    let sheet = sheet(
      SharedItem(url: ImportFixtures.soupLink), fetcher: fetcher,
      extractor: ScriptedExtractor(recipe: readRecipe(), rough: true), estimator: estimator)
    let review = try await review(sheet)

    #expect(review.draft.imported?.rough == true)
    #expect(estimator.inputs.isEmpty)
    #expect(review.macros == nil)
    #expect(review.macrosPending)
  }

  @Test func theCloudProviderIsAskedOnlyWithAKey() {
    let keyless = RecipeAIService.offline(key: nil)
    #expect(ShareSheetModel.macroEstimator(for: keyless) == nil)
    let keyed = RecipeAIService.offline(key: "test-key")
    #expect(ShareSheetModel.macroEstimator(for: keyed) != nil)
  }

  @Test func theSummaryWithAThumbnailAndMacrosRendersInBothAppearances() async throws {
    defer { tidy() }
    let withEverything = sheet(
      tacos, fetcher: tacosFetcher(), estimator: ScriptedEstimator(.macros(estimate)))
    let waiting = sheet(tacos, fetcher: tacosFetcher())
    for model in [withEverything, waiting] {
      model.start()
      await model.finished()
      for scheme in [ColorScheme.light, .dark] {
        let view = ShareSheetView(model: model).environment(\.colorScheme, scheme)
        #expect(ImageRenderer(content: view.frame(width: 380, height: 520)).cgImage != nil)
      }
    }
  }

  // MARK: The box

  @discardableResult
  private func payload(
    cover: String?, estimateOnSave: Bool = false, id: UUID = UUID()
  ) throws -> FinishedRecipe {
    var draft = RecipeDraft()
    draft.title = "Shakshuka"
    draft.servings = "4"
    draft.sourceURL = "https://eats.example/shakshuka"
    draft.setIngredientText(draft.ingredients[0].id, "2 tbsp olive oil")
    draft.setStepText(draft.steps[0].id, "Simmer for 10 minutes.")
    draft.estimateOnSave = estimateOnSave
    let recipe = FinishedRecipe(draft: draft, id: id, coverLink: cover)
    try FinishedInbox.add(recipe, in: finished)
    return recipe
  }

  private func recipes() throws -> [RecipeRecord] {
    try ModelContext(container).fetch(FetchDescriptor<RecipeRecord>())
  }

  private let coverLink = "https://eats.example/img/shakshuka.jpg"

  private func coverFetcher(_ reply: ScriptedFetcher.Reply? = nil) -> ScriptedFetcher {
    ScriptedFetcher([
      coverLink: reply
        ?? .image(ImportFixtures.imageData(1600, 1200, as: .jpeg), type: "image/jpeg")
    ])
  }

  @Test func aPayloadWithACoverLinkGetsItsFullSizePhotoAndThenItsFileGoes() async throws {
    defer { tidy() }
    let saved = try payload(cover: coverLink)
    let received = FinishedRecipeReceiver.receive(
      from: finished, into: context, draftsFolder: drafts)

    // In the box at once, without a photo; the file waits for the photo.
    #expect(received.added == 1 && received.covers.count == 1)
    #expect(try recipes().first?.photo == nil)
    #expect(files(in: finished).count == 1)

    let fetcher = coverFetcher()
    await FinishedRecipeReceiver.attach(received.covers, into: context, using: fetcher)
    let recipe = try #require(try recipes().first)
    #expect(recipe.id == saved.id)
    let photo = try #require(recipe.photo)
    // The full-size photo, as an import in the app keeps it, not the sheet's thumbnail.
    #expect(photo.width == 1600 && photo.height == 1200)
    #expect(photo.imageData?.isEmpty == false)
    #expect(fetcher.requests.map(\.url) == [coverLink])
    #expect(files(in: finished).isEmpty)
  }

  @Test func aCoverThatCantBeHadLeavesTheRecipeWithoutAPhotoAndTheFileGoes() async throws {
    defer { tidy() }
    try payload(cover: coverLink)
    let received = FinishedRecipeReceiver.receive(
      from: finished, into: context, draftsFolder: drafts)
    await FinishedRecipeReceiver.attach(
      received.covers, into: context, using: coverFetcher(.fail(.status(404))))

    #expect(try recipes().count == 1)
    #expect(try recipes().first?.photo == nil)
    #expect(files(in: finished).isEmpty)
  }

  @Test func aPayloadWithNoCoverLinkAsksForNoPhoto() async throws {
    defer { tidy() }
    try payload(cover: nil)
    let received = FinishedRecipeReceiver.receive(
      from: finished, into: context, draftsFolder: drafts)
    #expect(received.added == 1 && received.covers.isEmpty)
    #expect(files(in: finished).isEmpty)
  }

  @Test func aCrashBeforeThePhotoIsFetchedFetchesItTheNextTimeAndAddsNothingTwice() async throws {
    defer { tidy() }
    try payload(cover: coverLink)
    // The first pick-up saves the recipe and is stopped before the photo.
    FinishedRecipeReceiver.receive(from: finished, into: context, draftsFolder: drafts)
    #expect(files(in: finished).count == 1)

    let again = FinishedRecipeReceiver.receive(
      from: finished, into: context, draftsFolder: drafts)
    #expect(again.added == 0 && again.covers.count == 1)
    await FinishedRecipeReceiver.attach(again.covers, into: context, using: coverFetcher())
    #expect(try recipes().count == 1)
    #expect(try recipes().first?.photo != nil)
    #expect(files(in: finished).isEmpty)
  }

  @Test func aRecipeThatAlreadyHasItsPhotoIsNotFetchedForAgain() async throws {
    defer { tidy() }
    let id = UUID()
    try payload(cover: coverLink, id: id)
    let first = FinishedRecipeReceiver.receive(from: finished, into: context, draftsFolder: drafts)
    await FinishedRecipeReceiver.attach(first.covers, into: context, using: coverFetcher())

    // The file came back (a crash between the photo and the delete).
    try payload(cover: coverLink, id: id)
    let again = FinishedRecipeReceiver.receive(
      from: finished, into: context, draftsFolder: drafts)
    #expect(again.added == 0 && again.covers.isEmpty)
    #expect(files(in: finished).isEmpty)
  }

  @Test func aRecipeBanishedBeforeItsPhotoArrivesStaysWithoutOne() async throws {
    defer { tidy() }
    try payload(cover: coverLink)
    let received = FinishedRecipeReceiver.receive(
      from: finished, into: context, draftsFolder: drafts)
    let saved = try #require(try context.fetch(FetchDescriptor<RecipeRecord>()).first)
    saved.deletedAt = .now
    try context.save()

    await FinishedRecipeReceiver.attach(received.covers, into: context, using: coverFetcher())
    #expect(try recipes().first?.photo == nil)
    #expect(files(in: finished).isEmpty)
  }

  @Test func aPendingEstimateIsQueuedAndTheCoverFetchedThroughTheQueue() async throws {
    defer { tidy() }
    try payload(cover: coverLink, estimateOnSave: true)
    let queue = SharedImportQueue(folder: drafts, finishedFolder: finished, enabled: true)

    #expect(queue.pickUp(in: context) == 1)
    let waiting = try #require(try recipes().first)
    #expect(waiting.macrosPending)
    #expect(try ModelContext(container).fetchCount(FetchDescriptor<AIJobRecord>()) == 1)
    #expect(waiting.photo == nil)

    await queue.fetchCovers(into: context, using: coverFetcher())
    #expect(try recipes().first?.photo != nil)
    #expect(files(in: finished).isEmpty)
  }

  @Test func aQueueWithNoCoversFetchesNothing() async throws {
    defer { tidy() }
    let fetcher = coverFetcher()
    let queue = SharedImportQueue(folder: drafts, finishedFolder: finished, enabled: true)
    await queue.fetchCovers(into: context, using: fetcher)
    #expect(fetcher.requests.isEmpty)
  }
}
