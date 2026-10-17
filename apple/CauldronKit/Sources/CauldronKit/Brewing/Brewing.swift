// Start brewing: which ingredients each method step uses, so cook mode can show them with the
// step (`brewing.ts`).
//
// Words are compared as Unicode scalars, the way JavaScript's `===` compares code units, so
// canonically equivalent spellings stay different.

private typealias Word = Scalars

/// The text as lowercase singular words, with everything but letters, digits and hyphens read as
/// a break: `text.toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, " ").split(/\s+/)`.
private func words(of text: String) -> [Word] {
  var words: [Word] = []
  var current = Word()
  func finishWord() {
    if !current.isEmpty { words.append(Scalars(singularize(current.string))) }
    current = []
  }
  for c in Scalars(jsLowercased(text)) {
    if c.isLetterOrNumber || c == "-" {
      current.append(c)
    } else {
      finishWord()
    }
  }
  finishWord()
  return words
}

extension Unicode.Scalar {
  /// `\p{L}` or `\p{N}`.
  fileprivate var isLetterOrNumber: Bool {
    switch properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
      .decimalNumber, .letterNumber, .otherNumber:
      true
    default:
      false
    }
  }
}

/// Words that name a part of nearly anything and so can't identify an ingredient alone.
private let vague: Set<Word> = Set(
  ["juice", "zest", "leaf", "powder", "seed", "sauce", "stock", "water"].map { Scalars($0) })

/// Start positions where `needle` appears in `haystack` as whole words.
private func findAll(_ haystack: [Word], _ needle: [Word]) -> [Int] {
  guard !needle.isEmpty, haystack.count >= needle.count else { return [] }
  return (0...(haystack.count - needle.count)).filter { start in
    needle.indices.allSatisfy { haystack[start + $0] == needle[$0] }
  }
}

/// For each step, the indexes of the ingredients it mentions. A step mentions an ingredient when
/// it names the whole item ("red bell pepper") or its last word ("the pepper"). Longer names
/// claim their words first, so "green onions" doesn't also count as "onions" and "peanut
/// butter" isn't "butter". A last word only counts when no other ingredient sharing it is named
/// in full in that step, so "black pepper" doesn't pull in "red bell pepper".
public func stepIngredients(_ steps: [Step], _ ingredients: [Ingredient]) -> [[Int]] {
  let keys = ingredients.map { words(of: $0.itemKey) }
  // Equal lengths keep their list order, as JavaScript's stable sort does.
  let longestFirst = keys.indices.sorted {
    keys[$0].count != keys[$1].count ? keys[$0].count > keys[$1].count : $0 < $1
  }
  return steps.map { step in
    let text = words(of: step.text)
    var taken = [Bool](repeating: false, count: text.count)
    var found = Set<Int>()
    for i in longestFirst {
      let key = keys[i]
      for start in findAll(text, key) {
        // Only a span that is entirely claimed already is skipped; a half-claimed one still counts.
        if taken[start..<(start + key.count)].allSatisfy({ $0 }) { continue }
        found.insert(i)
        for at in start..<(start + key.count) { taken[at] = true }
      }
    }
    let namedHeads = Set(found.compactMap { keys[$0].last })
    for (i, key) in keys.enumerated() {
      guard let head = key.last, key.count >= 2, head.string.utf16.count >= 3,
        !vague.contains(head), !namedHeads.contains(head)
      else { continue }
      // Only a last word the longer names haven't already claimed.
      if text.indices.contains(where: { text[$0] == head && !taken[$0] }) { found.insert(i) }
    }
    return found.sorted()
  }
}
