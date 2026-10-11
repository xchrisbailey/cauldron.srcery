#if DEBUG
  import SwiftData

  /// A store with the debug seed in it, for previews.
  @MainActor
  enum RecipePreviewData {
    static func container() -> ModelContainer {
      do {
        let container = try CauldronStore.container(.inMemory)
        try DebugSeed.populate(ModelContext(container), today: DebugSeed.today())
        return container
      } catch {
        fatalError("The preview couldn't make its store: \(error)")
      }
    }

    static func firstRecipe(in container: ModelContainer) -> RecipeRecord {
      let all = (try? ModelContext(container).fetch(FetchDescriptor<RecipeRecord>())) ?? []
      guard let recipe = all.first else { fatalError("The preview store has no recipes.") }
      return recipe
    }
  }
#endif
