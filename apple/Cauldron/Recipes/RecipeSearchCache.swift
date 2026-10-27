import CauldronKit

/// The search index for the recipes a view shows, kept between renders. It is rebuilt only when
/// a recipe's id or searchable text changes, not on every render or keystroke. A view holds one
/// in `@State`; reading it from `body` doesn't invalidate the view.
@MainActor
final class RecipeSearchCache {
  private var index = RecipeSearchIndex([])

  /// The index for these recipes, built now if they differ from the ones it was last built for.
  func index(for recipes: [RecipeRecord]) -> RecipeSearchIndex {
    let entries = recipes.map(\.searchEntry)
    if entries != index.entries { index = RecipeSearchIndex(entries) }
    return index
  }
}
