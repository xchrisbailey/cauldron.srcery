import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron
@testable import CauldronImports

/// The Distill sheet's logic with a scripted fetcher and model: nothing here touches the
/// network or a real store.
@MainActor
@Suite("Distill flow")
struct ImportModelTests {
  private let fixed = Date(timeIntervalSince1970: 1_800_000_000)

  private func model(
    _ fetcher: ScriptedFetcher = ScriptedFetcher(), extractor: (any RecipeExtracting)? = nil,
    duplicate: @escaping @MainActor ([String?]) -> ImportReview.Duplicate? = { _ in nil }
  ) -> ImportModel {
    let date = fixed
    return ImportModel(
      fetcher: fetcher, extractor: extractor, options: ImportFixtures.quick,
      findDuplicate: duplicate, now: { date })
  }

  private func run(_ model: ImportModel, link: String = "", text: String = "") async {
    model.link = link
    model.text = text
    model.start()
    await model.finished()
  }

  private func review(_ model: ImportModel) throws -> ImportReview {
    guard case .ready(let review) = model.phase else {
      throw Failure("not ready: \(model.phase)")
    }
    return review
  }

  private func notice(_ model: ImportModel) throws -> ImportFailureNotice {
    guard case .failed(let notice) = model.phase else {
      throw Failure("not failed: \(model.phase)")
    }
    return notice
  }

  private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }

  // MARK: Reading

  @Test func aLinkThePageReadsFullyNeedsNoModel() async throws {
    let fetcher = ScriptedFetcher([
      ImportFixtures.tacosLink: ImportFixtures.tacos(),
      ImportFixtures.tacosImage: .image(ImportFixtures.imageData()),
    ])
    let extractor = ScriptedExtractor(recipe: readRecipe())
    let flow = model(fetcher, extractor: extractor)
    await run(flow, link: ImportFixtures.tacosLink)

    let ready = try review(flow)
    #expect(ready.draft.title == "Smoky black bean tacos")
    #expect(ready.draft.imported?.platform == .web)
    #expect(ready.draft.imported?.fetchedAt == fixed)
    #expect(ready.draft.imported?.rough == false)
    #expect(ready.draft.sourceURL == ImportFixtures.tacosLink)
    #expect(ready.duplicate == nil)
    #expect(extractor.inputs.isEmpty)
    if case .replace = ready.draft.photo {
    } else {
      Issue.record("the cover photo should be in the draft")
    }
  }

  @Test func aLinkThePageDoesntReadGoesToTheModelAndCanComeBackRough() async throws {
    let fetcher = ScriptedFetcher([ImportFixtures.soupLink: ImportFixtures.soup])
    let extractor = ScriptedExtractor(recipe: readRecipe(), rough: true)
    let flow = model(fetcher, extractor: extractor)
    await run(flow, link: ImportFixtures.soupLink)

    let ready = try review(flow)
    #expect(extractor.inputs.count == 1)
    #expect(ready.draft.title == "Grandma's soup")
    #expect(ready.draft.imported?.rough == true)
  }

  @Test func withNoModelAPageTheTextReaderCanReadComesBackFlaggedForReview() async throws {
    let fetcher = ScriptedFetcher([ImportFixtures.soupLink: ImportFixtures.soup])
    let flow = model(fetcher, extractor: nil)
    await run(flow, link: ImportFixtures.soupLink)
    let ready = try review(flow)
    #expect(ready.draft.needsReview, "a rough reading is flagged for the cook")
  }

  @Test func aPageWithNothingLikeARecipeIsAPlainFailureWithThePasteFallback() async throws {
    let fetcher = ScriptedFetcher([
      ImportFixtures.soupLink: .html("<article><h1>Our shop</h1><p>Open daily.</p></article>")
    ])
    let flow = model(fetcher, extractor: nil)
    await run(flow, link: ImportFixtures.soupLink)
    let failed = try notice(flow)
    #expect(failed.message == Copy.imports.failure(failed.code))
    #expect(failed.canPaste)
  }

  @Test func pastedTextGoesThroughTheSamePathWithNoSourceLink() async throws {
    let extractor = ScriptedExtractor(recipe: readRecipe(title: "Pasted pie"))
    let flow = model(extractor: extractor)
    await run(flow, text: "some pie my aunt makes, flour and plums, bake it")

    let ready = try review(flow)
    #expect(ready.draft.title == "Pasted pie")
    #expect(ready.draft.imported?.platform == .text)
    #expect(ready.draft.imported?.fetchedAt == nil)
    #expect(ready.draft.sourceURL.isEmpty)
    #expect(ready.draft.photo == .keep)
  }

  @Test func aLinkWinsOverPastedText() async throws {
    let fetcher = ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)])
    let flow = model(fetcher)
    #expect(flow.pasteIsOff == false)
    flow.link = ImportFixtures.tacosLink
    #expect(flow.pasteIsOff)
    flow.text = "ignored"
    flow.start()
    await flow.finished()
    #expect(try review(flow).draft.title == "Smoky black bean tacos")
  }

  @Test func aLinkThatIsntOneIsRefusedBeforeAnythingIsFetched() async {
    let fetcher = ScriptedFetcher()
    let flow = model(fetcher)
    flow.link = "not a link"
    flow.start()
    #expect(flow.linkError == Copy.validation.link)
    #expect(flow.phase == .editing)
    #expect(fetcher.requests.isEmpty)
    flow.link = "https://example.com"
    #expect(flow.linkError == nil)
  }

  @Test func nothingTypedCantStart() {
    let flow = model()
    #expect(!flow.canStart)
    flow.text = "  \n "
    #expect(!flow.canStart)
    flow.start()
    #expect(flow.phase == .editing)
  }

  // MARK: Failures

  @Test func aBlockedFetchSaysSoAndOffersThePasteFallback() async throws {
    let fetcher = ScriptedFetcher([ImportFixtures.soupLink: .fail(.blocked(detail: "tls"))])
    let flow = model(fetcher)
    await run(flow, link: ImportFixtures.soupLink)
    let failed = try notice(flow)
    #expect(failed.code == .blocked)
    #expect(failed.message == Copy.imports.blocked)
    #expect(failed.canPaste)
    #expect(!failed.canRetry)
  }

  @Test func aTimeoutSaysSoAndOffersAnotherTryAndThePasteFallback() async throws {
    let fetcher = ScriptedFetcher([ImportFixtures.soupLink: .fail(.timeout)])
    let flow = model(fetcher)
    await run(flow, link: ImportFixtures.soupLink)
    let failed = try notice(flow)
    #expect(failed.code == .timeout)
    #expect(failed.message == Copy.imports.timeout)
    #expect(failed.canPaste && failed.canRetry)
    // A timeout is worth retrying, which the pipeline did before giving up.
    #expect(fetcher.requests.count == 3)

    fetcher.set(ImportFixtures.soupLink, ImportFixtures.soup)
    flow.retry()
    await flow.finished()
    #expect(flow.phase != .working)
    #expect(fetcher.requests.count > 3)
  }

  @Test func aPageThatIsTooLargeSaysSo() async throws {
    let fetcher = ScriptedFetcher([ImportFixtures.soupLink: .fail(.tooLarge)])
    let flow = model(fetcher)
    await run(flow, link: ImportFixtures.soupLink)
    let failed = try notice(flow)
    #expect(failed.code == .tooLarge)
    #expect(failed.message == Copy.imports.tooLarge)
    #expect(failed.canPaste)
  }

  @Test func aPageOverTheSizeLimitThePipelineChecksSaysSoToo() async throws {
    let big = FetchedPage(
      bytes: Data(repeating: 65, count: 300), contentType: "text/html", url: "")
    let fetcher = ScriptedFetcher([ImportFixtures.soupLink: .page(big)])
    let flow = ImportModel(
      fetcher: fetcher, extractor: nil,
      options: DistillOptions(
        timeout: .seconds(20), retryDelay: .milliseconds(1), maxPageBytes: 100)
    )
    await run(flow, link: ImportFixtures.soupLink)
    #expect(try notice(flow).message == Copy.imports.tooLarge)
  }

  @Test func aResponseThatIsntAPageSaysItCouldntBeRead() async throws {
    let pdf = FetchedPage(bytes: Data([37, 80, 68, 70]), contentType: "application/pdf", url: "")
    let fetcher = ScriptedFetcher([ImportFixtures.soupLink: .page(pdf)])
    let flow = model(fetcher)
    await run(flow, link: ImportFixtures.soupLink)
    let failed = try notice(flow)
    #expect(failed.code == .couldntRead)
    #expect(failed.message == Copy.imports.couldntRead)
    #expect(failed.canPaste)
  }

  @Test func aServerThatCantBeReachedAndAnErrorStatusEndAsCouldntRead() async throws {
    for error in [FetchError.unreachable(detail: "dns"), .status(404), .status(403)] {
      let fetcher = ScriptedFetcher([ImportFixtures.soupLink: .fail(error)])
      let flow = model(fetcher)
      await run(flow, link: ImportFixtures.soupLink)
      #expect(try notice(flow).message == Copy.imports.couldntRead, "\(error)")
    }
  }

  @Test func textWithNoRecipeGetsTheMessageForPastedText() async throws {
    let flow = model(extractor: ScriptedExtractor(recipe: ExtractedRecipe()))
    await run(flow, text: "just a few words about nothing in particular")
    let failed = try notice(flow)
    #expect(failed.code == .noRecipe)
    #expect(failed.message == Copy.imports.noRecipeInText)
    #expect(!failed.canPaste, "there's nothing to paste instead")
  }

  @Test func theFailureOfAModelThatIsntThereIsPlainToo() async throws {
    let flow = model(extractor: ScriptedExtractor(failing: .failed(detail: "bad")))
    await run(flow, text: "just a few words about nothing in particular")
    let failed = try notice(flow)
    #expect(failed.message == Copy.imports.failure(failed.code))
  }

  // MARK: The paste fallback

  @Test func pastingInsteadKeepsTheLinkAsTheSource() async throws {
    let fetcher = ScriptedFetcher([ImportFixtures.soupLink: .fail(.blocked())])
    let extractor = ScriptedExtractor(recipe: readRecipe())
    let flow = model(fetcher, extractor: extractor)
    await run(flow, link: "https://blog.example/soup?utm_source=x")
    flow.pasteInstead()

    #expect(flow.phase == .editing)
    #expect(flow.pastingFor == "https://blog.example/soup?utm_source=x")
    #expect(flow.link.isEmpty)
    #expect(!flow.pasteIsOff)

    flow.text = "Soup. 1 onion, 2 carrots. Chop them and simmer for twenty minutes."
    flow.start()
    await flow.finished()
    let ready = try review(flow)
    #expect(ready.draft.sourceURL == "https://blog.example/soup")
    #expect(ready.draft.imported?.platform == .web)
    #expect(ready.draft.imported?.fetchedAt == nil, "nothing was fetched")
  }

  @Test func theLinkKeptForAPasteOfAnInstagramPostIsStillAnInstagramSource() async throws {
    let fetcher = ScriptedFetcher([:])
    let flow = model(fetcher, extractor: ScriptedExtractor(recipe: readRecipe()))
    await run(flow, link: "https://www.instagram.com/p/C8QzE3fyN3J/")
    flow.pasteInstead()
    flow.text = "Soup. 1 onion, 2 carrots. Chop them and simmer for twenty minutes."
    flow.start()
    await flow.finished()
    #expect(try review(flow).draft.imported?.platform == .instagram)
  }

  @Test func anotherStartsAfreshButKeepsPastedTextThatFailed() async throws {
    let flow = model(extractor: nil)
    await run(flow, text: "just a few words about nothing in particular")
    _ = try notice(flow)
    flow.another()
    #expect(flow.phase == .editing)
    #expect(flow.text == "just a few words about nothing in particular")

    let fetcher = ScriptedFetcher([ImportFixtures.soupLink: .fail(.blocked())])
    let linked = model(fetcher)
    await run(linked, link: ImportFixtures.soupLink, text: "kept?")
    linked.another()
    #expect(linked.link.isEmpty && linked.pastingFor == nil)
    #expect(linked.text.isEmpty)
  }

  // MARK: Stopping

  @Test func stoppingMidFetchLeavesNoDraftAndNothingStored() async throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let fetcher = ScriptedFetcher([ImportFixtures.soupLink: .hold])
    let flow = model(fetcher, extractor: ScriptedExtractor(recipe: readRecipe()))
    flow.link = ImportFixtures.soupLink
    flow.start()
    #expect(flow.phase == .working)
    while fetcher.startedCount == 0 { await Task.yield() }

    flow.stop()
    #expect(flow.phase == .editing)
    #expect(flow.stopped)
    #expect(flow.link == ImportFixtures.soupLink, "what was typed stays")
    await flow.finished()
    #expect(flow.phase == .editing, "the stopped run didn't come back as a result")
    #expect(try context.fetchCount(FetchDescriptor<RecipeRecord>()) == 0)

    // The form works again.
    fetcher.set(ImportFixtures.soupLink, ImportFixtures.soup)
    flow.start()
    await flow.finished()
    #expect(!flow.stopped)
    #expect(flow.phase != .editing)
  }

  @Test func closingTheSheetStopsTheRunToo() async throws {
    let fetcher = ScriptedFetcher([ImportFixtures.soupLink: .hold])
    let flow = model(fetcher)
    flow.link = ImportFixtures.soupLink
    flow.start()
    while fetcher.startedCount == 0 { await Task.yield() }
    flow.discard()
    await flow.finished()
    if case .ready = flow.phase { Issue.record("a closed sheet got a draft") }
  }

  // MARK: Duplicates

  @Test func aLinkYouAlreadyHaveIsReportedWithTheRecipe() async throws {
    let existing = UUID()
    var asked: [String?] = []
    let fetcher = ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)])
    let flow = model(fetcher) { links in
      asked = links
      return ImportReview.Duplicate(id: existing, title: "Tacos from before")
    }
    await run(flow, link: ImportFixtures.tacosLink)
    let ready = try review(flow)
    #expect(ready.duplicate == ImportReview.Duplicate(id: existing, title: "Tacos from before"))
    #expect(asked.contains(ImportFixtures.tacosLink))
  }

  // MARK: The cover photo

  private func coverResult(_ reply: ScriptedFetcher.Reply?) async throws -> ImportReview {
    var replies: [String: ScriptedFetcher.Reply] = [
      ImportFixtures.tacosLink: ImportFixtures.tacos()
    ]
    if let reply { replies[ImportFixtures.tacosImage] = reply }
    let flow = model(ScriptedFetcher(replies))
    await run(flow, link: ImportFixtures.tacosLink)
    return try review(flow)
  }

  @Test func aCoverPhotoThatFailsToFetchNeverFailsTheImport() async throws {
    for reply: ScriptedFetcher.Reply? in [
      nil, .fail(.tooLarge), .fail(.timeout), .fail(.blocked()), .fail(.status(500)),
      .image(Data("<html>nope</html>".utf8), type: "text/html"),
      .image(Data("not an image".utf8), type: "image/png"),
      .image(Data(), type: "image/png"),
    ] {
      let ready = try await coverResult(reply)
      #expect(ready.draft.photo == .keep, "\(String(describing: reply))")
      #expect(ready.draft.title == "Smoky black bean tacos")
    }
  }

  @Test func aPasteIsNotAttributedToALinkTheCookHasMovedOnFrom() async throws {
    let fetcher = ScriptedFetcher([
      "https://a.example/soup": .fail(.blocked())
    ])
    let flow = model(fetcher, extractor: ScriptedExtractor(recipe: readRecipe()))
    await run(flow, link: "https://a.example/soup")
    flow.pasteInstead()
    #expect(flow.pastingFor == "https://a.example/soup")

    // Typing another link ends it; clearing that link again doesn't bring A back.
    flow.link = "https://b.example/pie"
    #expect(flow.pastingFor == nil)
    flow.link = ""
    flow.text = "Soup. 1 onion, 2 carrots. Chop them and simmer for twenty minutes."
    flow.start()
    await flow.finished()
    let ready = try review(flow)
    #expect(ready.draft.sourceURL.isEmpty)
    #expect(ready.draft.imported?.platform == .text)
  }

  @Test func clearingTheLinkFieldAfterPasteInsteadKeepsTheLink() async throws {
    let fetcher = ScriptedFetcher(["https://a.example/soup": .fail(.blocked())])
    let flow = model(fetcher, extractor: ScriptedExtractor(recipe: readRecipe()))
    await run(flow, link: "https://a.example/soup")
    flow.pasteInstead()
    flow.link = ""
    #expect(flow.pastingFor == "https://a.example/soup")
  }
}
