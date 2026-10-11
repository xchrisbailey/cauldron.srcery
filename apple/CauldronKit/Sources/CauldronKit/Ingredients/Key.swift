// Normalized merge key for an ingredient's item text, stored as `itemKey` on a recipe's
// ingredients and on Gather items (`ingredients/key.ts`). Two lines with the same key are the
// same thing to buy: "2 Large Eggs" and "egg" both key to "egg".
//
// Lowercased, trimmed, whitespace collapsed, size words (large, medium, small, ...) dropped,
// and the last word singularized. Deliberately simple: it is a merge key, not a display
// string. The Gather list merges rows that share a key per unit dimension (volume, mass,
// count), never across them.

private let sizeWords: Set<String> = [
  "large", "medium", "small", "big", "extra-large", "extra", "jumbo", "mini",
]

/// Words that end in "s" but are already singular, or whose plural is irregular.
private let singularExceptions: [String: String] = [
  "hummus": "hummus",
  "couscous": "couscous",
  "asparagus": "asparagus",
  "molasses": "molasses",
  "watercress": "watercress",
  "swiss": "swiss",
  "lemongrass": "lemongrass",
  "brussels": "brussels",
  "grits": "grits",
  "oats": "oats",
  "leaves": "leaf",
  "loaves": "loaf",
  "halves": "half",
  "knives": "knife",
  "cloves": "clove",
  "olives": "olive",
  "chives": "chives",
  "greens": "greens",
  "cookies": "cookie",
  "pies": "pie",
  "radishes": "radish",
]

/// One word in its singular form, by the same simple rules as `ingredientKey`.
public func singularize(_ word: String) -> String {
  if let exact = singularExceptions[word] { return exact }
  // JavaScript counts UTF-16 units.
  if word.utf16.count <= 3 { return word }
  let s = Scalars(word)
  func ends(_ suffix: String) -> Bool { s.has(suffix, at: s.count - suffix.unicodeScalars.count) }
  func dropped(_ n: Int) -> String { s.dropping(last: n).string }
  // [^aeiou]ies
  if ends("ies"), let before = s.scalar(at: s.count - 4), !"aeiou".unicodeScalars.contains(before) {
    return dropped(3) + "y"
  }
  // (?:[sxz]|ch|sh)es
  if ends("ses") || ends("xes") || ends("zes") || ends("ches") || ends("shes") {
    return dropped(2)
  }
  if ends("oes") { return dropped(2) }
  if ends("ss") || ends("us") || ends("is") { return word }
  if ends("s") { return dropped(1) }
  return word
}

/// The merge key for an item: "Large Eggs" is "egg".
public func ingredientKey(_ item: String) -> String {
  let lowered = jsLowercased(item)
  let parenthesesAsSpaces = Scalars(lowered).map { $0 == "(" || $0 == ")" ? " " : $0 }
  var words: [String] = []
  var current = Scalars()
  func finishWord() {
    // Trim everything but a-z and 0-9 from both ends.
    func isAlphanumeric(_ c: Unicode.Scalar) -> Bool {
      (0x61...0x7A).contains(c.value) || c.isASCIIDigit
    }
    if let first = current.firstIndex(where: isAlphanumeric),
      let last = current.lastIndex(where: isAlphanumeric)
    {
      let word = Scalars(current[first...last]).string
      if !sizeWords.contains(word) { words.append(word) }
    }
    current = []
  }
  for c in parenthesesAsSpaces {
    if c.isJSSpace {
      finishWord()
    } else {
      current.append(c)
    }
  }
  finishWord()
  guard let last = words.last else {
    return Scalars(lowered).jsTrimmed.jsSpacesCollapsed.string
  }
  words[words.count - 1] = singularize(last)
  return words.joined(separator: " ")
}
