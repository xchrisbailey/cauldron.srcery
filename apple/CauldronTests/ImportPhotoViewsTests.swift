import CauldronKit
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron
@testable import CauldronImports

/// The photo parts of the Distill sheet in each of their states, drawn in both appearances.
@MainActor
@Suite("Distill from a photo views")
struct ImportPhotoViewsTests {
  private func renders(_ view: some View) -> Bool {
    ImageRenderer(content: view.frame(width: 600, height: 900)).cgImage != nil
  }

  private func model(_ reader: ScriptedReader, extractor: (any RecipeExtracting)? = nil)
    -> ImportModel
  {
    ImportModel(
      fetcher: ScriptedFetcher(), extractor: extractor, reader: reader,
      options: ImportFixtures.quick)
  }

  private func eachAppearance(_ flow: ImportModel, _ what: String) throws {
    let container = try CauldronStore.container(.inMemory)
    for scheme in [ColorScheme.light, .dark] {
      #expect(
        renders(
          ImportSheet(model: flow).modelContainer(container).environment(\.colorScheme, scheme)),
        "\(what) in \(scheme)")
    }
  }

  @Test func theFormShowsThePhotoSectionEmptyWithPagesAndWithAMessage() async throws {
    let flow = model(ScriptedReader([]))
    try eachAppearance(flow, "no pages")

    await flow.addPages([ImportFixtures.imageData(60, 80), ImportFixtures.imageData(61, 80)])
    flow.keepFirstPage = true
    try eachAppearance(flow, "two pages")

    await flow.addPages([Data("nope".utf8)])
    #expect(flow.photoMessage != nil)
    try eachAppearance(flow, "a refused picture")

    flow.reportPhotoProblem(Copy.importNative.scannerUnavailable)
    try eachAppearance(flow, "no scanner")
  }

  @Test func theFormWithTenPagesRendersAndOffersNoMore() async throws {
    let flow = model(ScriptedReader([]))
    await flow.addPages((0..<10).map { ImportFixtures.imageData(60 + $0, 80) })
    #expect(flow.pages.count == 10)
    try eachAppearance(flow, "ten pages")
  }

  @Test func theWaitNamesThePageBeingRead() async throws {
    let reader = ScriptedReader([.text("one"), .hold])
    let flow = model(reader)
    await flow.addPages([ImportFixtures.imageData(60, 80), ImportFixtures.imageData(61, 80)])
    flow.start()
    while reader.startedCount < 2 { await Task.yield() }
    #expect(flow.reading?.page == 2)
    try eachAppearance(flow, "reading page 2 of 2")
    flow.stop()
    await flow.finished()
    try eachAppearance(flow, "stopped")
  }

  @Test func eachPhotoFailureRendersInBothAppearances() async throws {
    let cases: [(String, ScriptedReader)] = [
      ("no text", ScriptedReader(pages: "")),
      ("unreadable", ScriptedReader([.fail(.unreadable)])),
      ("too long", ScriptedReader(pages: String(repeating: "flour and water. ", count: 4_000))),
      ("not a recipe", ScriptedReader(pages: "Open daily 9 to 5")),
    ]
    for (what, reader) in cases {
      let flow = model(reader, extractor: ScriptedExtractor(recipe: ExtractedRecipe()))
      await flow.addPages([ImportFixtures.imageData(60, 80)])
      flow.start()
      await flow.finished()
      guard case .failed(let notice) = flow.phase else {
        Issue.record("\(what) should fail: \(flow.phase)")
        continue
      }
      #expect(notice.canChangePhotos && notice.canPaste, "\(what)")
      try eachAppearance(flow, what)
    }
  }

  @Test func theDraftFromPhotosOpensInTheEditorWithTheFirstPageAsItsPhoto() async throws {
    let flow = model(ScriptedReader(pages: ImportFixtures.soupPage))
    await flow.addPages([ImportFixtures.imageData(60, 80)])
    flow.keepFirstPage = true
    flow.start()
    await flow.finished()
    guard case .ready(let review) = flow.phase else {
      Issue.record("should be ready: \(flow.phase)")
      return
    }
    #expect(review.draft.sourceURL.isEmpty)
    try eachAppearance(flow, "the editor on a draft from photos")
  }
}
