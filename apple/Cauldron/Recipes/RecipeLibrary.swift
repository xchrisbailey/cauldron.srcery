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

/// What the library shows: the recipes that haven't been banished, narrowed by a search and a
/// tag and put in order. Plain functions, so they run without a view.
enum RecipeLibrary {
  /// `tag` is a tag's name in lowercase; a recipe has to carry a tag by that name (in any case).
  /// The search is the web's, run on a `RecipeSearchIndex`. Pass the index a view keeps for the
  /// recipes; without one, an index is built from `recipes` for this call. Exact matches come
  /// first, then close ones, each tier in `sort` order.
  static func visible(
    _ recipes: [RecipeRecord], matching query: String, tag: String? = nil, sort: RecipeSort,
    index: RecipeSearchIndex? = nil
  ) -> [RecipeRecord] {
    visibleMatches(recipes, matching: query, tag: tag, sort: sort, index: index).map(\.recipe)
  }

  /// `visible`, with how each recipe matched.
  static func visibleMatches(
    _ recipes: [RecipeRecord], matching query: String, tag: String? = nil, sort: RecipeSort,
    index: RecipeSearchIndex? = nil
  ) -> [RecipeMatch] {
    found(recipes, matching: query, index: index)
      .filter { !$0.recipe.isBanished && $0.recipe.carries(tag: tag) }
      .sorted { a, b in
        a.tier != b.tier ? a.tier < b.tier : precedes(a.recipe, b.recipe, by: sort)
      }
  }

  /// The recipes ⌘K offers for what was typed, best first: a title that starts with it, then
  /// one with every word in the title, then the rest, each by title, and the close matches
  /// after them. Nothing for a blank search. Like the web's `search`, which stops at ten; the
  /// limit counts across the tiers.
  static func summon(
    _ recipes: [RecipeRecord], matching query: String, limit: Int = 10,
    index: RecipeSearchIndex? = nil
  ) -> [RecipeRecord] {
    summonMatches(recipes, matching: query, limit: limit, index: index).map(\.recipe)
  }

  /// `summon`, with how each recipe matched.
  static func summonMatches(
    _ recipes: [RecipeRecord], matching query: String, limit: Int = 10,
    index: RecipeSearchIndex? = nil
  ) -> [RecipeMatch] {
    guard RecipeSearchIndex.hasWords(query) else { return [] }
    return Array(
      found(recipes, matching: query, index: index).filter { !$0.recipe.isBanished }.prefix(limit))
  }

  /// The recipes the index finds for a search, in its order.
  private static func found(
    _ recipes: [RecipeRecord], matching query: String, index: RecipeSearchIndex?
  ) -> [RecipeMatch] {
    let index = index ?? RecipeSearchIndex(recipes.map(\.searchEntry))
    let byID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return index.search(query).compactMap { result in
      byID[result.id].map { RecipeMatch(recipe: $0, tier: result.tier, reason: result.reason) }
    }
  }

  /// The tags the library can filter on, with how many recipes carry each, by name. A tag no
  /// recipe carries is left out unless it is the one selected, as the web does.
  static func tagOptions(_ recipes: [RecipeRecord], selected: String? = nil) -> [TagOption] {
    var byKey: [String: (tags: [TagRecord], recipes: Set<UUID>)] = [:]
    for recipe in recipes where !recipe.isBanished {
      for tag in recipe.tags ?? [] {
        byKey[TagOption.key(tag.name), default: ([], [])].tags.append(tag)
        byKey[TagOption.key(tag.name), default: ([], [])].recipes.insert(recipe.id)
      }
    }
    var options = byKey.compactMap { key, group -> TagOption? in
      guard let keeper = Deduplication.keeper(of: group.tags) else { return nil }
      return TagOption(key: key, name: keeper.name, count: group.recipes.count)
    }
    if let selected, !options.contains(where: { $0.key == selected }) {
      options.append(TagOption(key: selected, name: selected, count: 0))
    }
    return options.sorted { ($0.key, $0.name) < ($1.key, $1.name) }
  }

  /// Banishes a recipe. It is soft-deleted, so it can be restored until it is purged. Its link
  /// leaves the saved-links index, so the share sheet no longer calls it a duplicate.
  static func banish(
    _ recipe: RecipeRecord, at date: Date = .now, index: SavedLinksIndex = .live
  ) {
    guard recipe.deletedAt == nil else { return }
    recipe.deletedAt = date
    rewrite(index, for: recipe)
  }

  /// Brings a banished recipe back. A recipe that wasn't banished is left alone.
  static func restore(_ recipe: RecipeRecord, index: SavedLinksIndex = .live) {
    guard recipe.deletedAt != nil else { return }
    recipe.deletedAt = nil
    rewrite(index, for: recipe)
  }

  private static func rewrite(_ index: SavedLinksIndex, for recipe: RecipeRecord) {
    guard let context = recipe.modelContext else { return }
    index.rewrite(from: context)
  }

  /// The web's order (`apps/api/src/Recipes.ts`): newest and last cooked break a tie by id,
  /// highest first; A to Z breaks one by id, lowest first.
  private static func precedes(_ a: RecipeRecord, _ b: RecipeRecord, by sort: RecipeSort) -> Bool {
    switch sort {
    case .recent:
      if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
      return a.id.uuidString > b.id.uuidString
    case .title:
      return titleOrder(a, b)
    case .lastCooked:
      // A recipe that was never cooked comes after every cooked one; the day keys sort as dates.
      let (x, y) = (a.lastCookedOnKey ?? "", b.lastCookedOnKey ?? "")
      if x != y { return x > y }
      return a.id.uuidString > b.id.uuidString
    }
  }

  private static func titleOrder(_ a: RecipeRecord, _ b: RecipeRecord) -> Bool {
    let (x, y) = (a.title.lowercased(), b.title.lowercased())
    return x != y ? x < y : a.id.uuidString < b.id.uuidString
  }
}

/// A recipe a search found, with how well it matched and why.
struct RecipeMatch: Identifiable {
  let recipe: RecipeRecord
  let tier: RecipeSearchIndex.Tier
  let reason: RecipeSearchIndex.Reason

  var id: UUID { recipe.id }

  /// Whether the recipe goes under Close matches.
  var isClose: Bool { tier != .exact }

  /// The line under its title, naming what it matched. Exact matches have none.
  var reasonLine: String? { reason.line?.text }

  /// The line shortened for a row of ⌘K.
  var shortReasonLine: String? { reason.shortLine?.text }
}

extension Array where Element == RecipeMatch {
  /// The recipes that matched exactly, in order.
  var exact: [RecipeMatch] { filter { !$0.isClose } }

  /// The close and partial matches, in order. They go under the Close matches heading.
  var close: [RecipeMatch] { filter(\.isClose) }
}

/// One entry in the library's tag menu.
struct TagOption: Identifiable, Equatable {
  /// The name in lowercase, which is what a filter holds: two tags whose names differ only in
  /// case are one tag.
  let key: String
  /// The name as it is written.
  let name: String
  /// How many recipes carry it.
  let count: Int

  var id: String { key }

  var label: String { Copy.library.tagOption(name, count).text }

  static func key(_ name: String) -> String { name.lowercased() }
}

extension RecipeRecord {
  /// Whether the recipe carries a tag by this lowercase name; any recipe does when `tag` is nil.
  fileprivate func carries(tag: String?) -> Bool {
    guard let tag else { return true }
    return (tags ?? []).contains { TagOption.key($0.name) == tag }
  }

  /// Everything a search looks through: the title, ingredient items and tag names (as
  /// `refreshSearchText` keeps them), the description and the hidden search keywords. The
  /// description is read here, so recipes saved before search looked at it are found by it too.
  /// Keywords that have gone stale still count until new ones are written.
  fileprivate var searchDocument: String {
    [searchText, summary, searchKeywords].compactMap { $0 }.filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  /// What the search index holds for the recipe.
  var searchEntry: RecipeSearchIndex.Entry {
    RecipeSearchIndex.Entry(id: id, title: title, document: searchDocument)
  }
}

/// What the library says after a banish or an undo.
enum RecipeNotice {
  case banished(RecipeRecord)
  case restored
  /// A copy was made and its editor opened.
  case duplicated

  var text: String {
    switch self {
    case .banished(let recipe): Copy.recipeView.banished(recipe.title).text
    case .restored: Copy.recipeView.restored.text
    case .duplicated: Copy.recipeView.duplicated.text
    }
  }

  /// The label of the button that takes the banish back; only the banish notice has one.
  var undoLabel: String? {
    switch self {
    case .banished: Copy.recipeView.undo.text
    case .restored, .duplicated: nil
    }
  }
}
