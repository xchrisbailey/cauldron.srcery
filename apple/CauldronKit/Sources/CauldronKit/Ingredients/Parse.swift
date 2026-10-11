// Ingredient line parser (`ingredients/parse.ts`). Plain, synchronous, deterministic, never
// traps.
//
// "1 1/2 cups (190g) flour, sifted" becomes
//   quantity { min: 1.5, max: nil }, unit .cup, item "flour",
//   note "sifted", alt { quantity 190, unit .g }.
//
// Design choices:
// - Sizes ("large", "medium", "small") are not units. They stay in the item: "2 large eggs" is
//   item "large eggs", so nothing the author wrote is lost.
// - "plus": "1 cup plus 2 tablespoons milk" keeps the first measure and puts the rest in the
//   note ("plus 2 tablespoons"). It is not summed.
// - `alt` is a parenthetical measure: either the same amount in another unit
//   ("1 1/2 cups (190g) flour") or the per-container size ("1 (14 oz) can tomatoes" is
//   quantity 1, unit can, alt 14 oz). Other parentheticals become part of the note.
// - Thousands separators are read: "1,000 g flour" is 1000 g.
// - "400g/14oz tin tomatoes" (and "1 cup / 240 ml milk"): a slash after the unit gives the
//   alternate measure. "tin" is not a unit, so it stays in the item: quantity 400 g, alt
//   14 oz, item "tin tomatoes". "can" is a unit, so "400g/14oz can tomatoes" keeps the amount
//   and alt the same way with item "can tomatoes".
// - "2 x 400g cans chickpeas" is quantity 2, unit can, alt 400 g, item "chickpeas".
// - Preparation-style measure modifiers before a unit ("heaping", "heaped", "level", "scant",
//   "rounded") go to the note: "1 heaping tsp salt" is 1 tsp, note "heaping".
// - An article after a quantity is dropped: "1/2 an onion", "half a lemon" are 0.5 of "onion"
//   and "lemon". "half" is 0.5.
// - "dozen" is a multiplier, not a unit: "2 dozen eggs" is 24 "eggs" and "half a dozen eggs"
//   is 6.
// - "each" right after a unit moves to the note: "2 tbsp each salt and pepper" is 2 tbsp of
//   "salt and pepper", note "each".
// - "12 oz. package spaghetti": a weight followed by a container word is the weight as the
//   measure with the container left in the item: 12 oz, item "package spaghetti". (Only a
//   measure before a container, as in "1 (14 oz) can" or "1 14-ounce can", makes the container
//   the unit.)
// - Bare "oz" is weight; only "fl oz" or "fluid ounce" is volume. "T" is tbsp and "t" is tsp.
// - Lines with no leading quantity ("Juice of 1 lemon", "Salt, to taste") have quantity and
//   unit nil. Units are only recognized after a quantity.
// - `note` is tidied text: the part after the first top-level comma, loose trailing phrases
//   ("to taste", "for serving", "divided"), and parentheticals that are not measures, joined
//   with ", ".
//
// The TypeScript used regular expressions; this is the same grammar read by hand over Unicode
// scalars (JavaScript's regular expressions work on UTF-16 units and Swift's lack lookbehind),
// with `\s` as `isJSSpace`, `\d` and `\w` as ASCII, and `/i` as ASCII case folding.

private let vulgar: [Unicode.Scalar: String] = [
  "½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4", "⅕": "1/5", "⅖": "2/5",
  "⅗": "3/5", "⅘": "4/5", "⅙": "1/6", "⅚": "5/6", "⅛": "1/8", "⅜": "3/8", "⅝": "5/8",
  "⅞": "7/8",
]

private let numberWords: [String: Double] = [
  "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
  "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "half": 0.5,
]

/// "a few", "a couple of" are not quantities.
private let vagueAfterA: Set<String> = [
  "few", "couple", "little", "lot", "bit", "handful", "splash",
]

private let trailingPhrases = [
  "to taste", "for serving", "for garnish", "for garnishing", "for dusting", "for frying",
  "for greasing", "as needed", "divided",
]

private let bulletsWithMarkers: Set<Unicode.Scalar> = ["-", "*", "•", "·", "▪", "◦", "‣"]
private let bullets: Set<Unicode.Scalar> = ["•", "·", "▪", "◦", "‣"]

/// Vulgar fractions spelled out, every dash a hyphen, and runs of whitespace one space.
func normalize(_ line: String) -> Scalars {
  let input = Scalars(line)
  var out = Scalars()
  var i = 0
  while i < input.count {
    let c = input[i]
    if c.isASCIIDigit {
      // A whole number glued to a fraction: "1½" is "1 1/2".
      let digitsEnd = input.end(ofRunFrom: i, where: \.isASCIIDigit)
      let spaceEnd = input.end(ofRunFrom: digitsEnd, where: \.isJSSpace)
      if let glyph = input.scalar(at: spaceEnd), let fraction = vulgar[glyph] {
        out += input[i..<digitsEnd]
        out.append(" ")
        out += fraction.unicodeScalars
        i = spaceEnd + 1
      } else {
        out += input[i..<digitsEnd]
        i = digitsEnd
      }
    } else if let fraction = vulgar[c] {
      out.append(" ")
      out += fraction.unicodeScalars
      out.append(" ")
      i += 1
    } else {
      out.append(c)
      i += 1
    }
  }
  let dashed = out.map { (0x2010...0x2015).contains($0.value) || $0.value == 0x2212 ? "-" : $0 }
  return dashed.jsSpacesCollapsed.jsTrimmed
}

func stripBullet(_ text: Scalars) -> Scalars {
  let runEnd = text.end(ofRunFrom: 0, where: { bulletsWithMarkers.contains($0) })
  if runEnd > 0 {
    let spaceEnd = text.end(ofRunFrom: runEnd, where: \.isJSSpace)
    if spaceEnd > runEnd { return text.from(spaceEnd).jsTrimmed }
  }
  let markerEnd = text.end(ofRunFrom: 0, where: { bullets.contains($0) })
  return (markerEnd > 0 ? text.from(markerEnd) : text).jsTrimmed
}

private struct Parsed<Value> {
  let value: Value
  /// How many scalars of the input it read.
  let consumed: Int
}

private func number(_ text: some Sequence<Unicode.Scalar>) -> Double {
  Double(Scalars(Array(text)).string) ?? .nan
}

private func parseSingleNumber(_ s: Scalars) -> Parsed<Double>? {
  // Thousands separators: "1,000", "12,500.5". Must come before the plain number.
  let leading = s.end(ofRunFrom: 0, where: \.isASCIIDigit)
  if (1...3).contains(leading), s.scalar(at: leading) == "," {
    var end = leading
    var groups = 0
    while s.scalar(at: end) == ",",
      (1...3).allSatisfy({ s.scalar(at: end + $0)?.isASCIIDigit == true })
    {
      end += 4
      groups += 1
    }
    if groups > 0 {
      var decimalEnd: Int?
      if s.scalar(at: end) == ".", s.scalar(at: end + 1)?.isASCIIDigit == true {
        decimalEnd = s.end(ofRunFrom: end + 1, where: \.isASCIIDigit)
      } else if s.scalar(at: end)?.isASCIIDigit == true {
        // Another digit would follow the last group ("1,0000"): give the group back.
        groups -= 1
        end -= 4
      }
      if groups > 0 {
        let stop = decimalEnd ?? end
        return Parsed(value: number(s[0..<stop].filter { $0 != "," }), consumed: stop)
      }
    }
  }
  // Mixed number: "1 1/2", "1-1/2".
  if leading > 0 {
    var p = leading
    let spaceEnd = s.end(ofRunFrom: p, where: \.isJSSpace)
    if spaceEnd > p {
      p = spaceEnd
    } else if s.scalar(at: p) == "-" {
      p += 1
    } else {
      p = -1
    }
    if p >= 0 {
      let numeratorEnd = s.end(ofRunFrom: p, where: \.isASCIIDigit)
      if numeratorEnd > p, s.scalar(at: numeratorEnd) == "/" {
        let denominatorEnd = s.end(ofRunFrom: numeratorEnd + 1, where: \.isASCIIDigit)
        if denominatorEnd > numeratorEnd + 1 {
          let denominator = number(s[(numeratorEnd + 1)..<denominatorEnd])
          if denominator != 0 {
            let whole = number(s[0..<leading])
            let numerator = number(s[p..<numeratorEnd])
            return Parsed(value: whole + numerator / denominator, consumed: denominatorEnd)
          }
        }
      }
    }
    // Fraction: "3/4".
    if s.scalar(at: leading) == "/" {
      let denominatorEnd = s.end(ofRunFrom: leading + 1, where: \.isASCIIDigit)
      if denominatorEnd > leading + 1 {
        let denominator = number(s[(leading + 1)..<denominatorEnd])
        if denominator != 0 {
          return Parsed(value: number(s[0..<leading]) / denominator, consumed: denominatorEnd)
        }
      }
    }
  }
  // Decimal or whole number: "1.5", ".5", "2".
  if leading > 0, s.scalar(at: leading) == ".", s.scalar(at: leading + 1)?.isASCIIDigit == true {
    let end = s.end(ofRunFrom: leading + 1, where: \.isASCIIDigit)
    return Parsed(value: number(s[0..<end]), consumed: end)
  }
  if s.scalar(at: 0) == ".", s.scalar(at: 1)?.isASCIIDigit == true {
    let end = s.end(ofRunFrom: 1, where: \.isASCIIDigit)
    return Parsed(value: number(s[0..<end]), consumed: end)
  }
  if leading > 0 { return Parsed(value: number(s[0..<leading]), consumed: leading) }
  // A number word: "two", "half", "a".
  let wordEnd = s.end(ofRunFrom: 0, where: \.isASCIILetter)
  if wordEnd > 0, wordEnd == s.count || s[wordEnd].isJSSpace {
    let word = jsLowercased(Scalars(s[0..<wordEnd]).string)
    if let value = numberWords[word] {
      let nextStart = s.end(ofRunFrom: wordEnd, where: \.isJSSpace)
      let nextEnd = s.end(ofRunFrom: nextStart, where: \.isASCIILetter)
      let next = nextEnd > nextStart ? jsLowercased(Scalars(s[nextStart..<nextEnd]).string) : nil
      // "half and half" is an ingredient, not a quantity.
      if word == "half", next == "and" { return nil }
      if word == "a" || word == "an" {
        guard let next, !vagueAfterA.contains(next) else { return nil }
      }
      return Parsed(value: value, consumed: wordEnd)
    }
  }
  return nil
}

/// A number or a range ("2-3", "2 to 3") at the start of `s`.
private func parseQuantity(_ s: Scalars) -> Parsed<Quantity>? {
  guard let first = parseSingleNumber(s) else { return nil }
  let p = first.consumed
  let spaceEnd = s.end(ofRunFrom: p, where: \.isJSSpace)
  var separatorEnd: Int?
  if s.scalar(at: spaceEnd) == "-" {
    separatorEnd = s.end(ofRunFrom: spaceEnd + 1, where: \.isJSSpace)
  } else if spaceEnd > p, s.has("to", at: spaceEnd), s.scalar(at: spaceEnd + 2)?.isJSSpace == true {
    separatorEnd = s.end(ofRunFrom: spaceEnd + 2, where: \.isJSSpace)
  }
  if let separatorEnd, let second = parseSingleNumber(s.from(separatorEnd)),
    second.value >= first.value
  {
    return Parsed(
      value: Quantity(min: first.value, max: second.value),
      consumed: separatorEnd + second.consumed)
  }
  return Parsed(value: Quantity(min: first.value, max: nil), consumed: first.consumed)
}

/// A unit word or two at the start of `s`.
private func parseUnit(_ s: Scalars) -> Parsed<UnitCode>? {
  // "fl oz", "fl. oz.": the only unit of two words.
  let firstEnd = s.end(ofRunFrom: 0, where: \.isASCIILetter)
  if firstEnd > 0 {
    var p = firstEnd
    if s.scalar(at: p) == "." { p += 1 }
    let spaceEnd = s.end(ofRunFrom: p, where: \.isJSSpace)
    if spaceEnd > p {
      let secondEnd = s.end(ofRunFrom: spaceEnd, where: \.isASCIILetter)
      if secondEnd > spaceEnd {
        var q = secondEnd
        if s.scalar(at: q) == "." { q += 1 }
        if q == s.count || s[q].isJSSpace {
          let words =
            Scalars(s[0..<firstEnd]).string + " " + Scalars(s[spaceEnd..<secondEnd]).string
          if let code = lookupUnit(words), code.abbreviation == "fl oz" {
            return Parsed(value: code, consumed: q)
          }
        }
      }
    }
  }
  // A unit ends at a space, "(", "/" (alternate measure) or a dot glued to the next word
  // ("1 tsp.salt").
  if firstEnd > 0 {
    var consumed: Int?
    if s.scalar(at: firstEnd) == ".", s.scalar(at: firstEnd + 1)?.isASCIILetter == true {
      consumed = firstEnd + 1
    } else {
      let p = s.scalar(at: firstEnd) == "." ? firstEnd + 1 : firstEnd
      if p == s.count || s[p].isJSSpace || s[p] == "(" || s[p] == "/" { consumed = p }
    }
    if let consumed, let code = lookupUnit(Scalars(s[0..<firstEnd]).string) {
      return Parsed(value: code, consumed: consumed)
    }
  }
  return nil
}

/// "(190g)", "(28-ounce)", "(about 8 cups)": a whole parenthetical that is one measure.
private func parseMeasure(_ text: Scalars) -> AltMeasure? {
  var cleaned = text.jsTrimmed
  // The alternation was written `about|approx\.?|approximately|...`, so "approximately" is
  // read as "approx" and its "imately" then fails as a number. That is kept: the measure is
  // not read, and it lands in the note.
  for prefix in ["about", "approx.", "approx", "roughly", "around", "~"] {
    if cleaned.has(prefix, ignoringCase: true) {
      let after = prefix.unicodeScalars.count
      cleaned = cleaned.from(cleaned.end(ofRunFrom: after, where: \.isJSSpace))
      break
    }
  }
  // "28-ounce" is "28 ounce".
  if let first = cleaned.first, first.isASCIIDigit {
    var k = 1
    while k < cleaned.count {
      let c = cleaned[k]
      if c == "-" {
        if cleaned.scalar(at: k + 1)?.isASCIILetter == true {
          cleaned = Scalars(cleaned[0..<k]) + [" "] + cleaned.from(k + 1)
        }
        break
      }
      guard c.isASCIIDigit || c == "." || c == "/" || c == " " else { break }
      k += 1
    }
  }
  // " each" at the end.
  if cleaned.count >= 5, cleaned.has("each", at: cleaned.count - 4, ignoringCase: true),
    cleaned[cleaned.count - 5].isJSSpace
  {
    var start = cleaned.count - 5
    while start > 0, cleaned[start - 1].isJSSpace { start -= 1 }
    cleaned = Scalars(cleaned[0..<start])
  }
  guard let quantity = parseQuantity(cleaned) else { return nil }
  let rest = cleaned.from(quantity.consumed).jsTrimmed
  guard let unit = parseUnit(rest), rest.from(unit.consumed).jsTrimmed.isEmpty else { return nil }
  return AltMeasure(quantity: quantity.value, unit: unit.value)
}

/// The text before the first comma that is outside parentheses and not inside a number, and
/// the text after it.
private func splitAtComma(_ text: Scalars) -> (head: Scalars, tail: Scalars?) {
  var depth = 0
  for (i, c) in text.enumerated() {
    if c == "(" {
      depth += 1
    } else if c == ")" {
      depth = max(0, depth - 1)
    } else if c == ",", depth == 0 {
      let afterSpace = text.end(ofRunFrom: i + 1, where: \.isJSSpace)
      let digitAfter = text.scalar(at: afterSpace)?.isASCIIDigit == true
      let digitBefore = i > 0 && text[i - 1].isASCIIDigit
      if !digitAfter && !digitBefore {
        return (text.prefix(i).map { $0 }.jsTrimmed, text.from(i + 1).jsTrimmed)
      }
    }
  }
  return (text, nil)
}

private func tidy(_ s: Scalars) -> Scalars { s.jsSpacesCollapsed.jsTrimmed }

/// Where the word `word` (`\bword\b`, ignoring case) first appears at or after `from`.
private func findWord(_ word: String, in s: Scalars, from: Int = 0) -> Int? {
  let length = word.unicodeScalars.count
  var i = from
  while i + length <= s.count {
    if s.has(word, at: i, ignoringCase: true),
      i == 0 || !s[i - 1].isASCIIWord,
      i + length == s.count || !s[i + length].isASCIIWord
    {
      return i
    }
    i += 1
  }
  return nil
}

private func replacingWord(_ word: String, in s: Scalars, with replacement: Scalars) -> Scalars {
  var out = Scalars()
  var i = 0
  while let at = findWord(word, in: s, from: i) {
    out += s[i..<at]
    out += replacement
    i = at + word.unicodeScalars.count
  }
  return out + s.from(i)
}

private let noteEdges: Set<Unicode.Scalar> = [",", ";", ":", "-"]

private func cleanNote(_ note: Scalars) -> Scalars {
  // `(optional)` and `optional`, parentheses included.
  var out = Scalars()
  var i = 0
  while i < note.count {
    let hasParen = note[i] == "("
    let wordStart = hasParen ? i + 1 : i
    if note.has("optional", at: wordStart, ignoringCase: true),
      wordStart == 0 || hasParen || !note[wordStart - 1].isASCIIWord,
      wordStart + 8 == note.count || !note[wordStart + 8].isASCIIWord
    {
      var end = wordStart + 8
      if note.scalar(at: end) == ")" { end += 1 }
      out.append(" ")
      i = end
    } else {
      out.append(note[i])
      i += 1
    }
  }
  let tidied = tidy(out)
  func isEdge(_ c: Unicode.Scalar) -> Bool { noteEdges.contains(c) || c.isJSSpace }
  guard let first = tidied.firstIndex(where: { !isEdge($0) }),
    let last = tidied.lastIndex(where: { !isEdge($0) })
  else { return [] }
  return Scalars(tidied[first...last])
}

private func scale12(_ q: Quantity) -> Quantity {
  Quantity(min: q.min * 12, max: q.max.map { $0 * 12 })
}

private func blank(original: String, item: String) -> ParsedIngredient {
  ParsedIngredient(
    quantity: nil, unit: nil, item: item, note: nil, optional: false, alt: nil, original: original)
}

/// Parse one ingredient line. Always answers: a line it can't read is returned whole as the
/// `item`, with no quantity.
public func parseIngredientLine(_ line: String) -> ParsedIngredient {
  let text = stripBullet(normalize(line))
  if text.isEmpty { return blank(original: line, item: "") }

  let (headRaw, commaNote) = splitAtComma(text)
  var notes: [String] = []
  var optional = false
  var alt: AltMeasure?

  // Parentheticals in the head: optional flag, first measure as alt, the rest as notes.
  var parenNotes: [String] = []
  var head = Scalars()
  var i = 0
  while i < headRaw.count {
    if headRaw[i] == "(",
      let close = headRaw[(i + 1)...].firstIndex(where: { $0 == "(" || $0 == ")" }),
      headRaw[close] == ")"
    {
      let inner = Scalars(headRaw[(i + 1)..<close])
      let trimmedInner = inner.jsTrimmed
      if trimmedInner.count == 8 && trimmedInner.has("optional", ignoringCase: true) {
        optional = true
      } else {
        let measure = alt == nil ? parseMeasure(inner) : nil
        if let measure {
          alt = measure
        } else if !tidy(inner).isEmpty {
          parenNotes.append(tidy(inner).string)
        }
      }
      head.append(" ")
      i = close + 1
    } else {
      head.append(headRaw[i])
      i += 1
    }
  }
  head = tidy(head)
  if findWord("optional", in: head) != nil {
    optional = true
    head = tidy(replacingWord("optional", in: head, with: [" "]))
  }

  var trailing: String?
  for phrase in trailingPhrases {
    let length = phrase.unicodeScalars.count
    let start = head.count - length
    if start >= 1, head.has(phrase, at: start, ignoringCase: true), head[start - 1].isJSSpace {
      var spaceStart = start - 1
      while spaceStart > 0, head[spaceStart - 1].isJSSpace { spaceStart -= 1 }
      trailing = phrase
      head = Scalars(head[0..<spaceStart]).jsTrimmed
      break
    }
  }

  // Leading quantity, unit, and optional "plus <measure>".
  var quantity: Quantity?
  var unit: UnitCode?
  var unitText = Scalars()
  var plusNote: String?
  var item = head

  if let q = parseQuantity(head) {
    let after = head.from(q.consumed)
    let startsWell =
      after.isEmpty || after[0].isJSSpace || after[0].isASCIILetter || after[0] == "("
      || (after[0] == "-" && after.scalar(at: 1)?.isASCIILetter == true)
    if startsWell {
      var rest = after.jsTrimmed
      var hyphenWord: String?
      if rest.scalar(at: 0) == "-" {
        let end = rest.end(ofRunFrom: 1, where: \.isASCIILetter)
        if end > 1 { hyphenWord = Scalars(rest[1..<end]).string }
      }
      if let hyphenWord, lookupUnit(hyphenWord) == nil {
        // "5-minute sauce": not a quantity.
        rest = []
        item = head
      } else {
        if hyphenWord != nil { rest = rest.from(1) }
        quantity = q.value

        // "2 x 400g cans chickpeas": a count of packs, each with a size.
        if let c = rest.first, c == "x" || c == "X" || c == "×" {
          let spaceEnd = rest.end(ofRunFrom: 1, where: \.isJSSpace)
          if rest.scalar(at: spaceEnd)?.isASCIIDigit == true { rest = rest.from(spaceEnd) }
        }

        // "1/2 an onion", "half a lemon": the article adds nothing after a quantity.
        for article in ["an", "a"] where rest.has(article, ignoringCase: true) {
          let length = article.unicodeScalars.count
          let spaceEnd = rest.end(ofRunFrom: length, where: \.isJSSpace)
          if spaceEnd > length, spaceEnd < rest.count {
            rest = rest.from(spaceEnd)
            break
          }
        }

        // "2 dozen eggs": a multiplier.
        if rest.has("dozen", ignoringCase: true), rest.count == 5 || !rest[5].isASCIIWord,
          let current = quantity
        {
          quantity = scale12(current)
          rest = rest.from(rest.end(ofRunFrom: 5, where: \.isJSSpace))
        }

        // "1 14-ounce can tomatoes": size measure before a container unit.
        if alt == nil, let size = parseSize(rest) {
          alt = size.measure
          rest = size.rest
        }

        // "1 heaping tsp salt": how the measure is filled belongs in the note.
        var measureNote: String?
        for modifier in ["heaping", "heaped", "level", "scant", "rounded"]
        where rest.has(modifier, ignoringCase: true) {
          let length = modifier.unicodeScalars.count
          let spaceEnd = rest.end(ofRunFrom: length, where: \.isJSSpace)
          let afterModifier = rest.from(spaceEnd)
          if spaceEnd > length, afterModifier.first?.isASCIILetter == true,
            parseUnit(afterModifier) != nil
          {
            measureNote = modifier
            rest = afterModifier
            break
          }
        }

        if let u = parseUnit(rest) {
          unit = u.value
          unitText = Scalars(rest[0..<u.consumed]).jsTrimmed
          rest = rest.from(u.consumed).jsTrimmed
          if let measureNote { notes.append(measureNote) }
          // "400g/14oz tin tomatoes", "1 cup / 240 ml milk": alternate measure after a slash.
          if rest.first == "/" {
            let afterSlash = rest.from(rest.end(ofRunFrom: 1, where: \.isJSSpace))
            if let altQ = parseQuantity(afterSlash),
              let altU = parseUnit(afterSlash.from(altQ.consumed).jsTrimmed)
            {
              if alt == nil { alt = AltMeasure(quantity: altQ.value, unit: altU.value) }
              rest = afterSlash.from(altQ.consumed).jsTrimmed.from(altU.consumed).jsTrimmed
            }
          }
          // "2 tbsp each salt and pepper": "each" is a note.
          if rest.has("each", ignoringCase: true), rest.count == 4 || !rest[4].isASCIIWord {
            notes.append("each")
            rest = rest.from(rest.end(ofRunFrom: 4, where: \.isJSSpace))
          }
          let plusLength = rest.has("plus", ignoringCase: true) ? 4 : (rest.first == "+" ? 1 : 0)
          if plusLength > 0 {
            let spaceEnd = rest.end(ofRunFrom: plusLength, where: \.isJSSpace)
            if spaceEnd > plusLength, let extra = parseQuantity(rest.from(spaceEnd)) {
              let afterExtra = rest.from(spaceEnd + extra.consumed)
              let trimmedExtra = afterExtra.jsTrimmed
              let remaining: Scalars
              if let eu = parseUnit(trimmedExtra) {
                remaining = trimmedExtra.from(eu.consumed)
              } else {
                remaining = afterExtra
              }
              plusNote = Scalars(rest.dropping(last: remaining.count)).jsTrimmed.string
              rest = remaining.jsTrimmed
            }
          }
          if rest.has("of", ignoringCase: true) {
            let spaceEnd = rest.end(ofRunFrom: 2, where: \.isJSSpace)
            if spaceEnd > 2 { rest = rest.from(spaceEnd) }
          }
        }
        item = rest
      }
    }
  }

  if item.isEmpty {
    // "2 cups" / "3 cloves": nothing else to call the item, so the unit word is it.
    if unit != nil {
      item = unitText
      unit = nil
      quantity = nil
      alt = nil
    } else {
      let tidied = tidy(head)
      item = tidied.isEmpty ? text : tidied
      quantity = nil
    }
  }

  if let plusNote { notes.append(plusNote) }
  notes += parenNotes
  if let trailing { notes.append(trailing) }
  if let commaNote {
    if findWord("optional", in: commaNote) != nil { optional = true }
    let cleaned = cleanNote(commaNote)
    if !cleaned.isEmpty { notes.append(cleaned.string) }
  }

  return ParsedIngredient(
    quantity: quantity, unit: unit, item: item.string,
    note: notes.isEmpty ? nil : notes.joined(separator: ", "), optional: optional, alt: alt,
    original: line)
}

/// "14-ounce can tomatoes": a size and a unit of measure, then a container unit. The container
/// and what follows stay as the rest.
private func parseSize(_ rest: Scalars) -> (measure: AltMeasure, rest: Scalars)? {
  let wholeEnd = rest.end(ofRunFrom: 0, where: \.isASCIIDigit)
  guard wholeEnd > 0 else { return nil }
  var numberEnd = wholeEnd
  if rest.scalar(at: wholeEnd) == ".", rest.scalar(at: wholeEnd + 1)?.isASCIIDigit == true {
    numberEnd = rest.end(ofRunFrom: wholeEnd + 1, where: \.isASCIIDigit)
  }
  let unitStart = rest.end(ofRunFrom: numberEnd, where: { $0.isJSSpace || $0 == "-" })
  let unitEnd = rest.end(ofRunFrom: unitStart, where: \.isASCIILetter)
  guard unitEnd > unitStart else { return nil }
  var p = unitEnd
  if rest.scalar(at: p) == "." { p += 1 }
  let containerStart = rest.end(ofRunFrom: p, where: \.isJSSpace)
  guard containerStart > p else { return nil }
  let containerEnd = rest.end(ofRunFrom: containerStart, where: \.isASCIILetter)
  guard containerEnd > containerStart else { return nil }
  guard let sizeUnit = lookupUnit(Scalars(rest[unitStart..<unitEnd]).string),
    let container = lookupUnit(Scalars(rest[containerStart..<containerEnd]).string),
    sizeUnit.dimension != .count, container.dimension == .count
  else { return nil }
  return (
    AltMeasure(quantity: Quantity(min: number(rest[0..<numberEnd]), max: nil), unit: sizeUnit),
    rest.from(containerStart)
  )
}

/// Whether a line is a group heading rather than an ingredient: "For the sauce:", or "FOR THE
/// CRUST". Callers use it to start a new section.
public func isSectionHeading(_ line: String) -> Bool {
  let normalized = normalize(line)
  var text = stripBullet(normalized)
  if text.last == ":" { text.removeLast() }
  text = text.jsTrimmed
  if text.isEmpty || text.string.utf16.count > 60 { return false }
  if text.contains(where: { $0.isASCIIDigit || $0 == "," || $0 == "(" || $0 == ")" }) {
    return false
  }
  if normalized.last == ":" { return true }
  return text.has("for ", ignoringCase: true) && text.scalar(at: 4)?.isASCIIWord == true
    && text.filter { $0 == " " }.count + 1 <= 5
}
