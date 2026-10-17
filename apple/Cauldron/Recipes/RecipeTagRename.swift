import CauldronKit
import Foundation
import SwiftData

/// Renaming a tag, as the web's API does it (`PATCH /tags/:id`): the new name is trimmed, can't
/// be blank or longer than a tag may be, and can't be the name of another tag in any case. It
/// may differ from the old one in case alone. Every recipe with the tag then reads and searches
/// under the new name.
enum RecipeTagRename {
  enum Failure: Error, Equatable {
    case blank
    case tooLong
    /// Another tag already has that name.
    case taken
    /// There is no tag by the old name.
    case missing

    var message: CopyString {
      switch self {
      case .blank: Copy.validation.required
      case .tooLong: Copy.validation.tooLong(RecipeLimits.tag)
      case .taken: Copy.recipes.tagNameTaken
      case .missing: Copy.errors.notFound
      }
    }
  }

  /// Renames the tag called `key` (its name in lowercase) to `name`. Returns the new key, which
  /// a filter on the tag has to move to.
  @discardableResult
  static func rename(
    _ key: String, to name: String, in context: ModelContext, at date: Date = .now
  ) -> Result<String, Failure> {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty { return .failure(.blank) }
    if name.count > RecipeLimits.tag { return .failure(.tooLong) }
    let all = (try? context.fetch(FetchDescriptor<TagRecord>())) ?? []
    let renaming = all.filter { TagOption.key($0.name) == key }
    if renaming.isEmpty { return .failure(.missing) }
    let newKey = TagOption.key(name)
    // Two rows with the same name are one tag that two devices made, so they never clash.
    if newKey != key, all.contains(where: { TagOption.key($0.name) == newKey }) {
      return .failure(.taken)
    }
    for tag in renaming where tag.name != name {
      tag.name = name
      tag.updatedAt = date
    }
    // The search text holds the tag names, so the recipes that carry them are rebuilt.
    var seen = Set<UUID>()
    for recipe in renaming.flatMap({ $0.recipes ?? [] }) where seen.insert(recipe.id).inserted {
      recipe.refreshSearchText()
    }
    return .success(newKey)
  }
}
