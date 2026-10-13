import CauldronKit
import Foundation

/// A recipe already in the box from the same link (`duplicateOf` in the reference's
/// `Imports.ts`).
enum DuplicateLinks {
  /// The newest live recipe whose source is any of `links`, as given or without the parts that
  /// don't change the page (`Distill.normalizeURL`). A saved link is compared both ways too, so
  /// one typed in by hand with a trailing slash still matches.
  static func find(in recipes: [RecipeRecord], links: [String?]) -> RecipeRecord? {
    var candidates = Set<String>()
    for link in links.compactMap({ $0 }).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    where !link.isEmpty {
      candidates.insert(link)
      candidates.insert(Distill.normalizeURL(link))
    }
    guard !candidates.isEmpty else { return nil }
    return recipes.filter { recipe in
      guard !recipe.isBanished, let saved = recipe.sourceURL, !saved.isEmpty else { return false }
      return candidates.contains(saved) || candidates.contains(Distill.normalizeURL(saved))
    }.max { $0.createdAt < $1.createdAt }
  }
}
