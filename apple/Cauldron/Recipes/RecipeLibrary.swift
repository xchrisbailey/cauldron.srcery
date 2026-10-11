import CauldronKit
import Foundation

/// How the library orders its recipes.
enum RecipeSort: String, CaseIterable, Identifiable, Sendable {
  case recent
  case title
  case lastCooked

  var id: Self { self }

  var label: CopyString {
    switch self {
    case .recent: Copy.library.sortRecent
    case .title: Copy.library.sortTitle
    case .lastCooked: Copy.library.sortLastCooked
    }
  }
}

/// What the library shows: the recipes that haven't been banished, narrowed by a search and
/// put in order. Plain functions, so they run without a view.
enum RecipeLibrary {
  static func visible(
    _ recipes: [RecipeRecord], matching query: String, sort: RecipeSort
  ) -> [RecipeRecord] {
    let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    return
      recipes
      .filter { !$0.isBanished && words.allSatisfy($0.searchText.contains) }
      .sorted { precedes($0, $1, by: sort) }
  }

  /// Banishes a recipe. It is soft-deleted, so it can be restored until it is purged.
  static func banish(_ recipe: RecipeRecord, at date: Date = .now) {
    guard recipe.deletedAt == nil else { return }
    recipe.deletedAt = date
  }

  /// Brings a banished recipe back. A recipe that wasn't banished is left alone.
  static func restore(_ recipe: RecipeRecord) {
    guard recipe.deletedAt != nil else { return }
    recipe.deletedAt = nil
  }

  private static func precedes(_ a: RecipeRecord, _ b: RecipeRecord, by sort: RecipeSort) -> Bool {
    switch sort {
    case .recent:
      if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
    case .title:
      break
    case .lastCooked:
      // A recipe that was never cooked comes after every cooked one; the day keys sort as dates.
      let (x, y) = (a.lastCookedOnKey ?? "", b.lastCookedOnKey ?? "")
      if x != y { return x > y }
    }
    let (x, y) = (a.title.lowercased(), b.title.lowercased())
    return x != y ? x < y : a.id.uuidString < b.id.uuidString
  }
}

/// What the library says after a banish or an undo.
enum RecipeNotice {
  case banished(RecipeRecord)
  case restored

  var text: String {
    switch self {
    case .banished(let recipe): Copy.recipeView.banished(recipe.title).text
    case .restored: Copy.recipeView.restored.text
    }
  }

  /// The label of the button that takes the banish back; only the banish notice has one.
  var undoLabel: String? {
    switch self {
    case .banished: Copy.recipeView.undo.text
    case .restored: nil
    }
  }
}
