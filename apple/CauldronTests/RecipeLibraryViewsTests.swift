import CauldronKit
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

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
