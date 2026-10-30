import CauldronKit
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron
@testable import CauldronImports

#if DEBUG
  @MainActor
  @Suite("Recipe library views")
  struct RecipeLibraryViewsTests {
    private func seeded() throws -> (container: ModelContainer, recipes: [RecipeRecord]) {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      try DebugSeed.populate(context, today: DebugSeed.today())
      return (container, try context.fetch(FetchDescriptor<RecipeRecord>()))
    }

    private func renders(_ view: some View, width: CGFloat = 480, height: CGFloat = 600) -> Bool {
      ImageRenderer(content: view.frame(width: width, height: height)).cgImage != nil
    }

    @Test func theNoMatchesStateRendersInBothAppearances() {
      for scheme in [ColorScheme.light, .dark] {
        #expect(renders(NoMatchesView {}.environment(\.colorScheme, scheme)))
      }
    }

    @Test func closeMatchesRenderUnderTheirHeadingInBothAppearances() throws {
      let (_, recipes) = try seeded()
      let recipe = try #require(recipes.first)
      for scheme in [ColorScheme.light, .dark] {
        let view = VStack(alignment: .leading, spacing: 8) {
          CloseMatchesHeader()
          RecipeCardView(recipe: recipe, reason: "Matched chicken")
          MatchReasonLine(text: "Matched aubergine, another name for eggplant")
        }
        .environment(\.colorScheme, scheme)
        #expect(renders(view))
      }
    }

    @Test func aTypoShowsTheChickenRecipesAsCloseMatchesOnTheSeedBox() throws {
      let (_, recipes) = try seeded()
      let found = RecipeLibrary.visibleMatches(recipes, matching: "chiken", sort: .title)
      #expect(found.exact.isEmpty)
      #expect(found.close.contains { $0.recipe.title.lowercased().contains("chicken") })
      #expect(found.close.allSatisfy { $0.reasonLine == "Matched chicken" })
      // Spelt right, the same recipes are exact and carry no reason.
      let spelt = RecipeLibrary.visibleMatches(recipes, matching: "chicken", sort: .title)
      #expect(spelt.close.isEmpty)
      #expect(spelt.allSatisfy { $0.reasonLine == nil })
    }

    // MARK: The line about recipes still being read

    private func waitingRunner(
      _ outcome: SearchKeywordOutcome, recipes: Int = 3
    ) async throws -> SearchKeywordRunner {
      let context = ModelContext(try CauldronStore.container(.inMemory))
      for number in 1...recipes {
        var draft = RecipeDraft()
        draft.title = "Recipe \(number)"
        draft.setIngredientText(draft.ingredients[0].id, "1 cup rice")
        draft.setStepText(draft.steps[0].id, "Cook it.")
        try RecipeSaver.save(draft, into: nil, context: context)
      }
      let runner = SearchKeywordRunner(writer: StubSearchKeywordWriter(outcome))
      runner.refreshPending(in: context)
      if case .unavailable = outcome { await runner.drain(in: context) }
      return runner
    }

    @Test func theLineShowsWhileSearchingAndRecipesAreStillBeingRead() async throws {
      let runner = try await waitingRunner(.written("rice"))
      #expect(runner.stillReading == 3)
      let line = RecipeLibrary.readingNotice(stillReading: runner.stillReading, search: "rice")
      #expect(line == .plain("Still reading 3 recipes for search. Results may grow."))
      #expect(line?.tone == .plain)
    }

    @Test func theEmptyResultsSayTheyAreStillReadingWhileASearchIsTyped() {
      let reading = NoMatchesView(stillReading: 3, search: "rice") {}
      #expect(
        reading.readingNotice == .plain("Still reading 3 recipes for search. Results may grow."))
      #expect(NoMatchesView(stillReading: 3, search: "  ") {}.readingNotice == nil)
      #expect(NoMatchesView(stillReading: nil, search: "rice") {}.readingNotice == nil)
      #expect(NoMatchesView {}.readingNotice == nil)
      for scheme in [ColorScheme.light, .dark] {
        #expect(renders(reading.environment(\.colorScheme, scheme)))
      }
    }

    @Test func theLineIsHiddenWithoutASearchOrWithNothingWaiting() async throws {
      #expect(RecipeLibrary.readingNotice(stillReading: 3, search: "") == nil)
      #expect(RecipeLibrary.readingNotice(stillReading: 3, search: "   ") == nil)
      #expect(RecipeLibrary.readingNotice(stillReading: nil, search: "rice") == nil)
      #expect(RecipeLibrary.readingNotice(stillReading: 0, search: "rice") == nil)
    }

    @Test(arguments: [SearchKeywordUnavailability.unavailable, .notEligible, .downloading])
    func theLineIsHiddenWhenTheModelIsUnavailable(_ reason: SearchKeywordUnavailability)
      async throws
    {
      let runner = try await waitingRunner(.unavailable(reason))
      // The recipes are still waiting, but nothing is reading them.
      #expect(runner.pending == 3)
      #expect(RecipeLibrary.readingNotice(stillReading: runner.stillReading, search: "rice") == nil)
    }

    @Test func theLineRendersInBothAppearances() {
      for scheme in [ColorScheme.light, .dark] {
        #expect(renders(SearchReadingFooter(count: 140).environment(\.colorScheme, scheme)))
      }
    }

    @Test func theRenameSheetRendersInBothAppearances() {
      for scheme in [ColorScheme.light, .dark] {
        #expect(
          renders(TagRenameSheet(name: "Dinner") { _ in nil }.environment(\.colorScheme, scheme)))
      }
    }

    @Test func theSummonSheetRendersEmptyAndWithMatchesInBothAppearances() throws {
      let (container, recipes) = try seeded()
      for scheme in [ColorScheme.light, .dark] {
        let view = RecipeSummonSheet(recipes: recipes) { _ in }
          .modelContainer(container)
          .environment(\.colorScheme, scheme)
        #expect(renders(view))
      }
    }

    @Test func theSummonSheetMakesNoSearchCacheOfItsOwnUnlessItIsNotGivenOne() throws {
      let (_, recipes) = try seeded()
      #expect(RecipeSummonSheet(recipes: recipes) { _ in }.searchCache == nil)
      let cache = RecipeSearchCache()
      #expect(
        RecipeSummonSheet(recipes: recipes, searchCache: cache) { _ in }.searchCache === cache)
    }

    @Test func theCloseMatchesSectionRendersInBothLayoutsAndBothAppearances() throws {
      let (_, recipes) = try seeded()
      let found = RecipeLibrary.visibleMatches(recipes, matching: "chiken", sort: .title)
      #expect(!found.close.isEmpty)
      for scheme in [ColorScheme.light, .dark] {
        let list = List {
          CloseMatchesSection(matches: found) { match in
            Text(verbatim: match.recipe.title)
          }
        }
        let stack = VStack(alignment: .leading) {
          CloseMatchesSection(matches: found, layout: .stack) { match in
            Text(verbatim: match.recipe.title)
          }
        }
        #expect(renders(list.environment(\.colorScheme, scheme)))
        #expect(renders(stack.environment(\.colorScheme, scheme)))
      }
    }

    @Test func theLibraryHasTagsToFilterBySoItsMenuHasEntries() throws {
      let (_, recipes) = try seeded()
      let options = RecipeLibrary.tagOptions(recipes)
      #expect(!options.isEmpty)
      #expect(options.allSatisfy { $0.count > 0 })
      // Choosing a tag keeps only recipes that carry it.
      let tag = try #require(options.first)
      let shown = RecipeLibrary.visible(recipes, matching: "", tag: tag.key, sort: .title)
      #expect(shown.count == tag.count)
    }
  }
#endif
