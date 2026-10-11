import CauldronKit
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

#if DEBUG
  @MainActor
  @Suite("Recipe editor views")
  struct RecipeEditorViewsTests {
    private func seeded() throws -> (container: ModelContainer, recipes: [RecipeRecord]) {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      try DebugSeed.populate(context, today: DebugSeed.today())
      return (container, try context.fetch(FetchDescriptor<RecipeRecord>()))
    }

    private func renders(_ view: some View) -> Bool {
      ImageRenderer(content: view.frame(width: 600, height: 900)).cgImage != nil
    }

    @Test func theEditorRendersNewAndEveryRecipeInBothAppearances() throws {
      let (container, recipes) = try seeded()
      for scheme in [ColorScheme.light, .dark] {
        for recipe in [nil] + recipes.map(Optional.some) {
          let view = RecipeEditorSheet(recipe: recipe)
            .modelContainer(container)
            .environment(\.colorScheme, scheme)
          #expect(renders(view), "\(recipe?.title ?? "new") in \(scheme)")
        }
      }
    }

    @Test func theEditorRendersARecipeWithListsItCantRead() throws {
      let (container, recipes) = try seeded()
      let recipe = try #require(recipes.first)
      recipe.ingredientsData = Data(
        #"[{"item":"x","original":"x","itemKey":"x","optional":false},{"new":1}]"#.utf8)
      recipe.stepsData = Data(#"[{"new":1}]"#.utf8)
      #expect(renders(RecipeEditorSheet(recipe: recipe).modelContainer(container)))
    }

    @Test func theFormShowsProblemsOnceSaveWasTried() throws {
      let container = try CauldronStore.container(.inMemory)
      var draft = RecipeDraft()
      draft.title = ""
      let form = RecipeEditorForm(
        draft: .constant(draft), recipe: nil, errors: draft.validate(), couldntSave: true
      ).modelContainer(container)
      #expect(renders(form))
    }
  }
#endif
