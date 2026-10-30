import Foundation

// Typo matching for recipe search: how far a typed word may be from a word in the box, and how
// text is folded so accents never count as a mistake. Both are plain functions over strings.

extension RecipeSearch {
  /// The text with accents taken off: "jalapeño" is "jalapeno" and "crème" is "creme". Search
  /// folds the recipes' words and what was typed the same way, so an accent is never a typo.
  static func folded(_ text: String) -> String {
    guard text.utf8.contains(where: { $0 >= 0x80 }) else { return text }
    let plain = text.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
      $0.properties.generalCategory != .nonspacingMark
    }
    return String(String.UnicodeScalarView(plain))
  }
}

enum RecipeSearchTypo {
  /// How many mistakes a typed word may have: none up to four letters, one from five and two
  /// from nine. A word with a digit in it, like "100g", is never forgiven.
  static func allowedEdits(for typed: String) -> Int {
    if typed.contains(where: \.isNumber) { return 0 }
    switch typed.count {
    case ..<5: return 0
    case 5..<9: return 1
    default: return 2
    }
  }

  /// A typed word, ready to be measured against many words of the box. It keeps its working
  /// rows, so measuring a word allocates nothing.
  struct Measure {
    private let typed: [UInt32]
    private let limit: Int
    private var beforePrevious: [Int]
    private var previous: [Int]
    private var current: [Int]

    init(_ word: String, limit: Int) {
      typed = word.unicodeScalars.map(\.value)
      self.limit = limit
      let rows = [Int](repeating: 0, count: typed.count + 1)
      (beforePrevious, previous, current) = (rows, rows, rows)
    }

    /// The fewest edits that turn the typed word into the start of `word`, or nil when that takes
    /// more than the limit. An edit is a letter added, dropped or changed, and two neighbouring
    /// letters swapped count as one. Only the start of `word` is compared, so a word still being
    /// typed ("chikc") is close to the whole word ("chicken") if its letters so far are.
    mutating func edits(toStartOf word: String) -> Int? {
      let m = typed.count
      guard m > 0 else { return 0 }
      // Column j of the table holds the cost of turning the typed letters into the first j
      // letters of the word, so the answer is the best of the last row's cells.
      for i in 0...m { previous[i] = i }
      var best = m
      var smallestBefore = 0
      var last: UInt32 = 0
      var j = 0
      for letter in word.unicodeScalars.lazy.map(\.value) {
        j += 1
        current[0] = j
        var smallest = j
        for i in 1...m {
          var cost = previous[i - 1] + (typed[i - 1] == letter ? 0 : 1)
          cost = min(cost, previous[i] + 1, current[i - 1] + 1)
          if i > 1, j > 1, typed[i - 1] == last, typed[i - 2] == letter {
            cost = min(cost, beforePrevious[i - 2] + 1)
          }
          current[i] = cost
          smallest = min(smallest, cost)
        }
        best = min(best, current[m])
        // A swap looks two columns back, so give up only when this column and the last are
        // both over the limit.
        if smallest > limit, smallestBefore > limit { break }
        smallestBefore = smallest
        last = letter
        swap(&beforePrevious, &previous)
        swap(&previous, &current)
      }
      return best <= limit ? best : nil
    }
  }
}
