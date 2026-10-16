import CauldronKit
import Foundation

/// A recipe already in the box from the same link (`duplicateOf` in the reference's
/// `Imports.ts`).
enum DuplicateLinks {
  /// The newest live recipe whose source is any of `links`, as given or without the parts that
  /// don't change the page (`Distill.normalizeURL`). A saved link is compared both ways too, so
  /// one typed in by hand with a trailing slash still matches. The share sheet's check reads the
  /// same rules from the saved-links index (`SavedLinks`).
  static func find(in recipes: [RecipeRecord], links: [String?]) -> RecipeRecord? {
    let candidates = SavedLinks.keys(of: links)
    guard !candidates.isEmpty else { return nil }
    return recipes.filter { recipe in
      !recipe.isBanished && !candidates.isDisjoint(with: SavedLinks.keys(of: recipe.sourceURL))
    }.max { $0.createdAt < $1.createdAt }
  }
}
