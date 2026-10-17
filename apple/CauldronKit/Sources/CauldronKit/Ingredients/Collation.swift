import Foundation

// `a.localeCompare(b, undefined, { sensitivity: "base" })`, the order the Gather list sorts
// item names in: letters compare without regard to case or accents, and the same on every
// platform. This follows the Unicode root collation's primary order for the characters
// ingredient names hold: spaces, then punctuation and symbols, then digits, then letters.

/// Punctuation and symbols in root collation order.
private let punctuationOrder = Scalars("_-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$")

/// Letters that don't decompose but sort as another letter, or as two.
private let expansions: [Unicode.Scalar: String] = [
  "ß": "ss", "æ": "ae", "œ": "oe", "ø": "o", "đ": "d", "ł": "l", "ħ": "h", "ŧ": "t",
]

private func primaryKey(_ c: Unicode.Scalar) -> (group: Int, weight: UInt32) {
  if c.isJSSpace { return (0, c.value) }
  if let index = punctuationOrder.firstIndex(of: c) { return (1, UInt32(index)) }
  if c.properties.numericType == .decimal, let value = c.properties.numericValue {
    return (3, UInt32(value))
  }
  if c.properties.isAlphabetic { return (4, c.value) }
  return (2, c.value)
}

/// The scalars that count at base strength: decomposed, with accents dropped and letters
/// lowercased.
private func baseScalars(_ s: String) -> [(group: Int, weight: UInt32)] {
  var keys: [(group: Int, weight: UInt32)] = []
  for c in s.decomposedStringWithCompatibilityMapping.unicodeScalars {
    // Accents, other combining marks and invisible characters carry no weight.
    if c.properties.canonicalCombiningClass != .notReordered { continue }
    if !c.isJSSpace && [.format, .control].contains(c.properties.generalCategory) { continue }
    // Katakana sorts with the hiragana it spells.
    let kana = (0x30A1...0x30F6).contains(c.value) ? Unicode.Scalar(c.value - 0x60) ?? c : c
    for lowered in kana.properties.lowercaseMapping.unicodeScalars {
      for letter in expansions[lowered]?.unicodeScalars.map({ $0 }) ?? [lowered] {
        keys.append(primaryKey(letter))
      }
    }
  }
  return keys
}

/// Negative when `a` sorts before `b`, positive after, and zero when they differ only in case
/// or accents.
func compareBase(_ a: String, _ b: String) -> Int {
  let x = baseScalars(a)
  let y = baseScalars(b)
  for (l, r) in zip(x, y) {
    if l.group != r.group { return l.group < r.group ? -1 : 1 }
    if l.weight != r.weight { return l.weight < r.weight ? -1 : 1 }
  }
  return x.count == y.count ? 0 : (x.count < y.count ? -1 : 1)
}
