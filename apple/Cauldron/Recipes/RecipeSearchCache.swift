import CauldronKit
import Foundation

/// The search index for the recipes a view shows, kept between renders. It is rebuilt only when
/// the key of a recipe changes: its id and the things search reads (the title, the search text,
/// the description and the search keywords), or when recipes come or go or change order. Not on
/// every render or keystroke, and not when something search doesn't read changes. A view holds
/// one in `@State`; reading it from `body` doesn't invalidate the view.
@MainActor
final class RecipeSearchCache {
  /// What a recipe contributes to the index, compared instead of the documents built from it.
  private struct Key: Equatable {
    let id: UUID
    let title: String
    let searchText: String
    let summary: String?
    let keywords: String?

    init(_ recipe: RecipeRecord) {
      id = recipe.id
      title = recipe.title
      searchText = recipe.searchText
      summary = recipe.summary
      keywords = recipe.searchKeywords
    }
  }

  private var index = RecipeSearchIndex([])
  private var keys: [Key] = []
  /// How many times the index has been built.
  private(set) var builds = 0

  /// The index for these recipes, built now if their key differs from the one it was last built
  /// for.
  func index(for recipes: [RecipeRecord]) -> RecipeSearchIndex {
    let next = recipes.map(Key.init)
    guard next != keys else { return index }
    index = RecipeSearchIndex(recipes.map(\.searchEntry))
    keys = next
    builds += 1
    return index
  }
}
