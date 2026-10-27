import Foundation

/// Other names for the same thing, as groups: every name in a group stands for every other in
/// it, both ways, so "eggplant" finds a recipe that says "aubergine" and the other way round.
/// A name can be several words ("spring onion"). Groups never chain: a typed name reaches the
/// names of its own group, and never the names those are in another group with.
///
/// Names are matched by their words, as search matches everything: accents are folded, case and
/// punctuation do not count, and a plural is the same word. A name's words must be typed one
/// after the other, and the last may still be being typed.
public struct RecipeSearchSynonyms: Sendable {
  /// The groups as given.
  public let groups: [[String]]

  /// One name of a group, ready to be compared with what was typed.
  struct Name: Sendable {
    /// The name as a recipe would say it, lowercase and without accents.
    let text: String
    let terms: [RecipeSearch.Query.Term]
    /// The names of the same group (or groups) that are not this one, by position in `names`.
    var others: [Int] = []
  }

  /// A stretch of the typed words that is a known name.
  struct Span: Sendable, Equatable {
    /// The positions in the typed words.
    let range: Range<Int>
    /// The other names it stands for, by position in `names`.
    let others: [Int]
  }

  private(set) var names: [Name] = []

  public init(groups: [[String]]) {
    self.groups = groups
    var numbers: [[Int]] = []
    for group in groups {
      var inGroup: [Int] = []
      for name in group {
        let folded = RecipeSearch.folded(name).lowercased().trimmingCharacters(
          in: .whitespacesAndNewlines)
        let terms = RecipeSearch.Query(folded).terms
        guard !terms.isEmpty else { continue }
        inGroup.append(names.count)
        names.append(Name(text: folded, terms: terms))
      }
      numbers.append(inGroup)
    }
    for group in numbers {
      for number in group {
        for other in group where other != number {
          let same = names[other].terms == names[number].terms
          if !same && !names[number].others.contains(other) { names[number].others.append(other) }
        }
      }
    }
  }

  /// Whether a typed word is the name's word: the same word or stem, or, for the word at the
  /// end of the query, the start of it (three letters at least when the name is one word).
  private func matches(
    _ term: RecipeSearch.Query.Term, _ word: RecipeSearch.Query.Term, beingTyped: Bool,
    alone: Bool
  ) -> Bool {
    if term.typed == word.typed || term.stem == word.stem { return true }
    guard beingTyped, !alone || term.typed.count >= 3 else { return false }
    return word.typed.hasPrefix(term.typed)
  }

  /// The names found in the typed words, left to right without overlapping, the longest name
  /// first at each place. `usable` says whether a stretch may be replaced by other names: a
  /// name some recipe already holds whole is not.
  func spans(in terms: [RecipeSearch.Query.Term], usable: (Range<Int>) -> Bool) -> [Span] {
    var found: [Span] = []
    var start = 0
    while start < terms.count {
      var here: [Int: [Int]] = [:]
      for (number, name) in names.enumerated() where !name.others.isEmpty {
        let end = start + name.terms.count
        guard end <= terms.count else { continue }
        let alone = name.terms.count == 1
        let all = name.terms.indices.allSatisfy { place in
          matches(
            terms[start + place], name.terms[place],
            beingTyped: end == terms.count && place == name.terms.count - 1, alone: alone)
        }
        if all { here[name.terms.count, default: []].append(number) }
      }
      var taken: Span?
      for length in here.keys.sorted(by: >) {
        let range = start..<start + length
        guard usable(range) else { continue }
        var others: [Int] = []
        for number in here[length] ?? [] {
          for other in names[number].others where !others.contains(other) { others.append(other) }
        }
        taken = Span(range: range, others: others)
        break
      }
      if let taken {
        found.append(taken)
        start = taken.range.upperBound
      } else {
        start += 1
      }
    }
    return found
  }
}
