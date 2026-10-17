// One rule for ingredient section headings, used by the editor, the text importer and the
// seeds (`ingredients/sections.ts`). A heading is either a markdown heading ("## To serve"),
// or a line the parser reads as a group heading ("For the sauce:", "FOR THE CRUST",
// "**Dressing:**") that has no quantity, so "One onion:" stays an ingredient.

/// Unicode's `Extended_Pictographic` ranges, as the JavaScript engine the reference ran on
/// reports them (Swift's standard library has `isEmoji` but not this property).
private let extendedPictographic: [ClosedRange<UInt32>] = [
  0xA9...0xA9, 0xAE...0xAE, 0x203C...0x203C, 0x2049...0x2049, 0x2122...0x2122,
  0x2139...0x2139, 0x2194...0x2199, 0x21A9...0x21AA, 0x231A...0x231B, 0x2328...0x2328,
  0x23CF...0x23CF, 0x23E9...0x23F3, 0x23F8...0x23FA, 0x24C2...0x24C2, 0x25AA...0x25AB,
  0x25B6...0x25B6, 0x25C0...0x25C0, 0x25FB...0x25FE, 0x2600...0x2604, 0x260E...0x260E,
  0x2611...0x2611, 0x2614...0x2615, 0x2618...0x2618, 0x261D...0x261D, 0x2620...0x2620,
  0x2622...0x2623, 0x2626...0x2626, 0x262A...0x262A, 0x262E...0x262F, 0x2638...0x263A,
  0x2640...0x2640, 0x2642...0x2642, 0x2648...0x2653, 0x265F...0x2660, 0x2663...0x2663,
  0x2665...0x2666, 0x2668...0x2668, 0x267B...0x267B, 0x267E...0x267F, 0x2692...0x2697,
  0x2699...0x2699, 0x269B...0x269C, 0x26A0...0x26A1, 0x26A7...0x26A7, 0x26AA...0x26AB,
  0x26B0...0x26B1, 0x26BD...0x26BE, 0x26C4...0x26C5, 0x26C8...0x26C8, 0x26CE...0x26CF,
  0x26D1...0x26D1, 0x26D3...0x26D4, 0x26E9...0x26EA, 0x26F0...0x26F5, 0x26F7...0x26FA,
  0x26FD...0x26FD, 0x2702...0x2702, 0x2705...0x2705, 0x2708...0x270D, 0x270F...0x270F,
  0x2712...0x2712, 0x2714...0x2714, 0x2716...0x2716, 0x271D...0x271D, 0x2721...0x2721,
  0x2728...0x2728, 0x2733...0x2734, 0x2744...0x2744, 0x2747...0x2747, 0x274C...0x274C,
  0x274E...0x274E, 0x2753...0x2755, 0x2757...0x2757, 0x2763...0x2764, 0x2795...0x2797,
  0x27A1...0x27A1, 0x27B0...0x27B0, 0x27BF...0x27BF, 0x2934...0x2935, 0x2B05...0x2B07,
  0x2B1B...0x2B1C, 0x2B50...0x2B50, 0x2B55...0x2B55, 0x3030...0x3030, 0x303D...0x303D,
  0x3297...0x3297, 0x3299...0x3299, 0x1F004...0x1F004, 0x1F02C...0x1F02F, 0x1F094...0x1F09F,
  0x1F0AF...0x1F0B0, 0x1F0C0...0x1F0C0, 0x1F0CF...0x1F0D0, 0x1F0F6...0x1F0FF,
  0x1F170...0x1F171, 0x1F17E...0x1F17F, 0x1F18E...0x1F18E, 0x1F191...0x1F19A,
  0x1F1AE...0x1F1E5, 0x1F201...0x1F20F, 0x1F21A...0x1F21A, 0x1F22F...0x1F22F,
  0x1F232...0x1F23A, 0x1F23C...0x1F23F, 0x1F249...0x1F25F, 0x1F266...0x1F321,
  0x1F324...0x1F393, 0x1F396...0x1F397, 0x1F399...0x1F39B, 0x1F39E...0x1F3F0,
  0x1F3F3...0x1F3F5, 0x1F3F7...0x1F3FA, 0x1F400...0x1F4FD, 0x1F4FF...0x1F53D,
  0x1F549...0x1F54E, 0x1F550...0x1F567, 0x1F56F...0x1F570, 0x1F573...0x1F57A,
  0x1F587...0x1F587, 0x1F58A...0x1F58D, 0x1F590...0x1F590, 0x1F595...0x1F596,
  0x1F5A4...0x1F5A5, 0x1F5A8...0x1F5A8, 0x1F5B1...0x1F5B2, 0x1F5BC...0x1F5BC,
  0x1F5C2...0x1F5C4, 0x1F5D1...0x1F5D3, 0x1F5DC...0x1F5DE, 0x1F5E1...0x1F5E1,
  0x1F5E3...0x1F5E3, 0x1F5E8...0x1F5E8, 0x1F5EF...0x1F5EF, 0x1F5F3...0x1F5F3,
  0x1F5FA...0x1F64F, 0x1F680...0x1F6C5, 0x1F6CB...0x1F6D2, 0x1F6D5...0x1F6E5,
  0x1F6E9...0x1F6E9, 0x1F6EB...0x1F6F0, 0x1F6F3...0x1F6FF, 0x1F7DA...0x1F7FF,
  0x1F80C...0x1F80F, 0x1F848...0x1F84F, 0x1F85A...0x1F85F, 0x1F888...0x1F88F,
  0x1F8AE...0x1F8AF, 0x1F8BC...0x1F8BF, 0x1F8C2...0x1F8CF, 0x1F8D9...0x1F8FF,
  0x1F90C...0x1F93A, 0x1F93C...0x1F945, 0x1F947...0x1F9FF, 0x1FA58...0x1FA5F,
  0x1FA6E...0x1FAFF, 0x1FC00...0x1FFFD,
]

private func isPictographic(_ c: Unicode.Scalar) -> Bool {
  var low = 0
  var high = extendedPictographic.count - 1
  while low <= high {
    let mid = (low + high) / 2
    let range = extendedPictographic[mid]
    if c.value < range.lowerBound {
      high = mid - 1
    } else if c.value > range.upperBound {
      low = mid + 1
    } else {
      return true
    }
  }
  return false
}

/// Emoji presentation selector and zero-width joiner, which glue emoji together.
private func isEmojiGlue(_ c: Unicode.Scalar) -> Bool { c.value == 0xFE0F || c.value == 0x200D }

private let leadingMarks: Set<Unicode.Scalar> = [
  "*", "_", ">", "•", "·", "▪", "-", "–", "—", "=", "~", "|", "▢", "□", "◦", "‣",
]
private let trailingMarks: Set<Unicode.Scalar> = ["#", "*", "_", "=", "~", "|"]

private func isLeading(_ c: Unicode.Scalar) -> Bool {
  c.isJSSpace || leadingMarks.contains(c) || isPictographic(c) || isEmojiGlue(c)
}

private func isTrailing(_ c: Unicode.Scalar) -> Bool {
  c.isJSSpace || trailingMarks.contains(c) || isPictographic(c) || isEmojiGlue(c)
}

private func isColon(_ c: Unicode.Scalar) -> Bool { c.isJSSpace || c == ":" || c == "\u{FF1A}" }

private func strippingLeading(_ s: Scalars) -> Scalars {
  s.from(s.end(ofRunFrom: 0, where: isLeading))
}

private func strippingTrailing(_ s: Scalars, _ predicate: (Unicode.Scalar) -> Bool) -> Scalars {
  var end = s.count
  while end > 0, predicate(s[end - 1]) { end -= 1 }
  return Scalars(s[0..<end])
}

private func bare(_ text: Scalars) -> Scalars {
  let afterLeading = strippingLeading(text)
  let afterTrailing = strippingTrailing(afterLeading, isTrailing)
  let afterColon = strippingTrailing(afterTrailing, isColon)
  return strippingTrailing(afterColon, isTrailing).jsTrimmed
}

private func isLineTerminator(_ c: Unicode.Scalar) -> Bool {
  c.value == 0x0A || c.value == 0x0D || c.value == 0x2028 || c.value == 0x2029
}

/// The text after `#` to `######` and a space in a markdown heading, or nil for any other line.
private func markdownHeading(_ line: Scalars) -> Scalars? {
  let start = line.end(ofRunFrom: 0, where: \.isJSSpace)
  let hashesEnd = line.end(ofRunFrom: start, where: { $0 == "#" })
  guard (1...6).contains(hashesEnd - start) else { return nil }
  let textStart = line.end(ofRunFrom: hashesEnd, where: \.isJSSpace)
  guard textStart > hashesEnd else { return nil }
  let text = line.from(textStart)
  return text.contains(where: isLineTerminator) ? nil : text
}

/// The heading a line names ("For the sauce:" reads as "For the sauce"), or nil.
public func readHeading(_ line: String) -> String? {
  let scalars = Scalars(line)
  if let markdown = markdownHeading(scalars) {
    let heading = bare(markdown)
    return heading.isEmpty ? nil : heading.string
  }
  let text = strippingTrailing(strippingLeading(scalars), isTrailing).string
  if !isSectionHeading(text) || parseIngredientLine(text).quantity != nil { return nil }
  let heading = bare(Scalars(text))
  return heading.isEmpty ? nil : heading.string
}

/// Anything that sits in a section of a recipe's ingredients.
public protocol Sectioned {
  /// The heading above the line, or nil before the first one.
  var section: String? { get }
}

extension Ingredient: Sectioned {}

/// A parsed ingredient line and the heading above it.
@dynamicMemberLookup
public struct SectionedIngredient: Sendable, Hashable, Sectioned {
  public var parsed: ParsedIngredient
  public var section: String?

  public init(parsed: ParsedIngredient, section: String?) {
    self.parsed = parsed
    self.section = section
  }

  public subscript<Value>(dynamicMember keyPath: KeyPath<ParsedIngredient, Value>) -> Value {
    parsed[keyPath: keyPath]
  }
}

/// A block of ingredient lines, parsed. Headings become the `section` of the lines under them;
/// blank lines are dropped.
public func readIngredientBlock(_ lines: [String]) -> [SectionedIngredient] {
  var out: [SectionedIngredient] = []
  var section: String?
  for raw in lines {
    let line = jsTrim(raw)
    if line.isEmpty { continue }
    if let heading = readHeading(line) {
      section = heading
      continue
    }
    out.append(SectionedIngredient(parsed: parseIngredientLine(line), section: section))
  }
  return out
}

public enum SectionRow<Line> {
  case heading(String)
  case line(Line)
}

extension SectionRow: Sendable where Line: Sendable {}
extension SectionRow: Equatable where Line: Equatable {}

/// The other direction: lines that carry a `section`, with a heading row before each run of
/// lines in a new section.
public func withHeadings<Line: Sectioned>(_ lines: [Line]) -> [SectionRow<Line>] {
  var out: [SectionRow<Line>] = []
  var section: String?
  for line in lines {
    if line.section != section {
      section = line.section
      if let section { out.append(.heading(section)) }
    }
    out.append(.line(line))
  }
  return out
}
