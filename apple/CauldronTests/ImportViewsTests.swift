import CauldronKit
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

/// The Distill sheet in each of its states, drawn in both appearances.
@MainActor
@Suite("Distill views")
struct ImportViewsTests {
  private func renders(_ view: some View) -> Bool {
    ImageRenderer(content: view.frame(width: 600, height: 900)).cgImage != nil
  }

  private func model(_ fetcher: ScriptedFetcher, extractor: (any RecipeExtracting)? = nil)
    -> ImportModel
  {
    ImportModel(fetcher: fetcher, extractor: extractor, options: ImportFixtures.quick)
  }

  private func eachAppearance(_ draw: (ColorScheme) -> Bool, _ what: String) {
    for scheme in [ColorScheme.light, .dark] { #expect(draw(scheme), "\(what) in \(scheme)") }
  }

  @Test func theFormRendersEmptyFilledAndAfterAStop() throws {
    let container = try CauldronStore.container(.inMemory)
    let flow = model(ScriptedFetcher())
    eachAppearance(
      { scheme in
        renders(
          ImportSheet(model: flow).modelContainer(container).environment(\.colorScheme, scheme))
      }, "empty")
    flow.link = "https://cook.example/tacos"
    flow.text = "pasted"
    eachAppearance(
      { scheme in
        renders(
          ImportSheet(model: flow).modelContainer(container).environment(\.colorScheme, scheme))
      }, "filled")
    flow.link = "nonsense"
    flow.start()
    eachAppearance(
      { scheme in
        renders(
          ImportSheet(model: flow).modelContainer(container).environment(\.colorScheme, scheme))
      }, "with a link error")
  }

  @Test func theWaitRendersWithItsStopButton() async throws {
    let container = try CauldronStore.container(.inMemory)
    let fetcher = ScriptedFetcher(["https://hold.example/a": .hold])
    let flow = model(fetcher)
    flow.link = "https://hold.example/a"
    flow.start()
    #expect(flow.phase == .working)
    eachAppearance(
      { scheme in
        renders(
          ImportSheet(model: flow).modelContainer(container).environment(\.colorScheme, scheme))
      }, "working")
    flow.stop()
    await flow.finished()
    eachAppearance(
      { scheme in
        renders(
          ImportSheet(model: flow).modelContainer(container).environment(\.colorScheme, scheme))
      }, "stopped")
  }

  @Test func everyFailureRendersInBothAppearances() async throws {
    let container = try CauldronStore.container(.inMemory)
    let errors: [FetchError] = [.blocked(), .timeout, .tooLarge, .status(404)]
    for error in errors {
      let flow = model(ScriptedFetcher(["https://fails.example/a": .fail(error)]))
      flow.link = "https://fails.example/a"
      flow.start()
      await flow.finished()
      guard case .failed = flow.phase else {
        Issue.record("\(error) should fail")
        continue
      }
      eachAppearance(
        { scheme in
          renders(
            ImportSheet(model: flow).modelContainer(container).environment(\.colorScheme, scheme))
        }, "\(error)")
    }
  }

  @Test func theDraftOpensInTheEditorWithTheSourceAndWhatToCheck() async throws {
    let container = try CauldronStore.container(.inMemory)
    let fetcher = ScriptedFetcher([ImportFixtures.soupLink: ImportFixtures.soup])
    var recipe = readRecipe()
    recipe.unsure = [.servings]
    recipe.ingredients[0].unsure = true
    let flow = ImportModel(
      fetcher: fetcher, extractor: ScriptedExtractor(recipe: recipe, rough: true),
      options: ImportFixtures.quick,
      findDuplicate: { _ in ImportReview.Duplicate(id: UUID(), title: "Soup from before") })
    flow.link = ImportFixtures.soupLink
    flow.start()
    await flow.finished()
    guard case .ready(let review) = flow.phase else {
      Issue.record("should be ready: \(flow.phase)")
      return
    }
    #expect(review.draft.needsReview)
    eachAppearance(
      { scheme in
        renders(
          ImportSheet(model: flow).modelContainer(container).environment(\.colorScheme, scheme))
      }, "the editor on an import")
  }

  @Test func theEditorRendersAPastedImportWithNoSource() async throws {
    let container = try CauldronStore.container(.inMemory)
    let flow = model(ScriptedFetcher(), extractor: ScriptedExtractor(recipe: readRecipe()))
    flow.text = "some soup my gran makes, onions and carrots, boil them"
    flow.start()
    await flow.finished()
    guard case .ready(let review) = flow.phase else {
      Issue.record("should be ready: \(flow.phase)")
      return
    }
    #expect(review.draft.sourceURL.isEmpty)
    #expect(renders(ImportSheet(model: flow).modelContainer(container)))
  }
}
