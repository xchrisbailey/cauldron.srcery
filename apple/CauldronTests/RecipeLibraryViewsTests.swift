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
