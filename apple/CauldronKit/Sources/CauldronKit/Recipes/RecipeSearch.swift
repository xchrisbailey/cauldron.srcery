import Foundation

// Recipe search, as the web's library does it (`apps/api/src/Recipes.ts`): every word typed has
// to match the start of a word in the recipe's title, tags, ingredients or description, with
// English stemming so "tomatoes" finds "tomato" and the other way round, and a plain substring
// of the title also matches. The web leaves the stemming to Postgres's `english` text search;
// this is a small version of it that runs anywhere.

public enum RecipeSearch {
  /// The web keeps the first eight words of what was typed.
  public static let maxWords = 8

  /// Words Postgres's English search ignores. A subset of its list; the ones that turn up in a
  /// search for a recipe.
  private static let stopWords: Set<String> = [
    "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "if", "in", "into", "is", "it",
    "no", "not", "of", "on", "or", "such", "that", "the", "their", "then", "there", "these",
    "they", "this", "to", "was", "will", "with",
  ]

  /// The words in some text: runs of letters and digits, lowercased.
  public static func words(_ text: String) -> [String] {
    text.lowercased()
      .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
      .map(String.init)
  }

  /// The stem of a lowercase word: plurals, `-ing`, `-ed` and a trailing `e` or `y` are
  /// folded away, so the forms of a word share a stem. The stem is only for comparing; it is
  /// not always a word ("berries" and "berry" are both "berri").
  public static func stem(_ word: String) -> String {
    // Numbers and mixed words like "100g" are left alone.
    guard word.count > 2, word.allSatisfy(\.isLetter) else { return word }
    var stem = word
    if stem.count > 3 {
      if stem.hasSuffix("sses") {
        stem.removeLast(2)
      } else if stem.hasSuffix("ies") {
        stem.removeLast(3)
        stem += stem.count > 1 ? "i" : "ie"
      } else if stem.hasSuffix("es"), let before = stem.dropLast(2).last,
        "sxzo".contains(before) || stem.hasSuffix("ches") || stem.hasSuffix("shes")
      {
        stem.removeLast(2)
      } else if stem.hasSuffix("s"), !stem.hasSuffix("ss"), !stem.hasSuffix("us"),
        !stem.hasSuffix("is")
      {
        stem.removeLast()
      }
      for ending in ["ing", "ed"] where stem.hasSuffix(ending) {
        let base = String(stem.dropLast(ending.count))
        // "string" and "bed" aren't verbs in -ing or -ed.
        guard base.count >= 3, base.contains(where: { vowels.contains($0) }) else { break }
        stem = base
        // "chopped" and "running" double the last letter.
        if let last = stem.last, stem.dropLast().last == last, !vowels.contains(last),
          !"lsz".contains(last)
        {
          stem.removeLast()
        }
        break
      }
    }
    if stem.count > 2, stem.hasSuffix("e") {
      stem.removeLast()
    } else if stem.count > 2, stem.hasSuffix("y"), let before = stem.dropLast().last,
      !vowels.contains(before)
    {
      stem.removeLast()
      stem += "i"
    }
    return stem
  }

  private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

  /// What someone typed into a search box, ready to test recipes against.
  public struct Query: Sendable, Equatable {
    /// One word of the query, as typed and stemmed.
    private struct Term: Sendable, Equatable {
      let typed: String
      let stem: String
    }

    /// The query, trimmed and lowercased: what a title may contain whole.
    private let phrase: String
    private let terms: [Term]
    /// Whether the query has any words at all. A query with none (blank, or only punctuation)
    /// matches every recipe.
    public let hasWords: Bool

    public init(_ text: String) {
      phrase = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let typed = RecipeSearch.words(text).prefix(RecipeSearch.maxWords)
      hasWords = !typed.isEmpty
      terms = typed.filter { !RecipeSearch.stopWords.contains($0) }.map {
        Term(typed: $0, stem: RecipeSearch.stem($0))
      }
    }

    /// Whether a recipe matches. `document` is all the text that can match, the title, tags,
    /// ingredients and description, and `title` is the title alone, which also matches when it
    /// contains the whole query as typed.
    public func matches(title: String, document: String) -> Bool {
      guard hasWords else { return true }
      if title.lowercased().contains(phrase) { return true }
      guard !terms.isEmpty else { return false }
      let found = RecipeSearch.words(document).map { ($0, RecipeSearch.stem($0)) }
      return terms.allSatisfy { term in
        found.contains { $0.0.hasPrefix(term.typed) || $0.1.hasPrefix(term.stem) }
      }
    }

    /// How well a title fits, for ordering results: 2 when it starts with the query, 1 when
    /// every word of the query starts a word of it, otherwise 0.
    public func titleRank(_ title: String) -> Int {
      guard hasWords else { return 0 }
      let lowered = title.lowercased()
      if lowered.hasPrefix(phrase) { return 2 }
      guard !terms.isEmpty else { return 0 }
      let found = RecipeSearch.words(title).map { ($0, RecipeSearch.stem($0)) }
      let every = terms.allSatisfy { term in
        found.contains { $0.0.hasPrefix(term.typed) || $0.1.hasPrefix(term.stem) }
      }
      return every ? 1 : 0
    }
  }
}
