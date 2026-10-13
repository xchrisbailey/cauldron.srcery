import Foundation

// JavaScript regular expressions, run on ICU through `NSRegularExpression` (in Foundation on
// every platform). ICU's `\s`, `\w`, `\d`, `\b`, `.` and `$` differ from JavaScript's, so the
// ported patterns spell those out with the pieces below instead of using them.

enum JS {
  /// JavaScript's `\s`, as the inside of a character class.
  static let space =
    #"\t\n\u000B\f\r    -     　﻿"#
  /// `.`: anything but a line terminator, as the inside of a character class (negated).
  static let lineBreaks = #"\n\r  "#
  /// The line terminators `.` refuses.
  static let lineBreakScalars: Set<Unicode.Scalar> = ["\n", "\r", "\u{2028}", "\u{2029}"]
  /// `\w`, as the inside of a character class.
  static let word = "A-Za-z0-9_"
  /// `\s` as an atom.
  static let s = "[\(space)]"
  /// `.` as an atom.
  static let dot = "[^\(lineBreaks)]"
  /// `\b` after a word character (so the next one must not be a word character).
  static let endWord = "(?![\(word)])"
  /// `\b` before a word character.
  static let startWord = "(?<![\(word)])"
}

/// One match: where it is and what its groups captured.
struct JSMatch {
  let text: NSString
  let result: NSTextCheckingResult

  /// The text of group `index` (0 is the whole match), or nil when the group didn't take part.
  func group(_ index: Int) -> String? {
    guard index < result.numberOfRanges else { return nil }
    let range = result.range(at: index)
    return range.location == NSNotFound ? nil : text.substring(with: range)
  }

  var range: NSRange { result.range }
  var value: String { text.substring(with: result.range) }
}

struct JSRegex: Sendable {
  private let regex: NSRegularExpression

  /// A pattern is a literal in the source, so one that doesn't compile is a bug found by the
  /// first test that touches it.
  init(_ pattern: String, ignoreCase: Bool = false) {
    do {
      regex = try NSRegularExpression(
        pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
    } catch {
      preconditionFailure("Bad regular expression: \(pattern)")
    }
  }

  func firstMatch(in string: String) -> JSMatch? {
    let text = NSString(string: string)
    guard
      let result = regex.firstMatch(
        in: string, options: [], range: NSRange(location: 0, length: text.length))
    else { return nil }
    return JSMatch(text: text, result: result)
  }

  func test(_ string: String) -> Bool { firstMatch(in: string) != nil }

  func matches(in string: String) -> [JSMatch] {
    let text = NSString(string: string)
    return regex.matches(
      in: string, options: [], range: NSRange(location: 0, length: text.length)
    ).map { JSMatch(text: text, result: $0) }
  }

  /// `replace(regex, fn)` with the `g` flag: every match, in order.
  func replacing(in string: String, using replacement: (JSMatch) -> String) -> String {
    let text = NSString(string: string)
    var out = ""
    var last = 0
    for match in matches(in: string) {
      let range = match.range
      out += text.substring(with: NSRange(location: last, length: range.location - last))
      out += replacement(match)
      last = range.location + range.length
    }
    out += text.substring(from: last)
    return out
  }

  /// `replace(regex, "literal")` with the `g` flag.
  func replacing(in string: String, with literal: String) -> String {
    replacing(in: string) { _ in literal }
  }

  /// `replace(regex, literal)` without the `g` flag: the first match only.
  func replacingFirst(in string: String, with literal: String) -> String {
    guard let match = firstMatch(in: string) else { return string }
    let range = match.range
    return match.text.replacingCharacters(in: range, with: literal)
  }

  /// `split(regex)` for a pattern with no groups that never matches the empty string.
  func split(_ string: String) -> [String] {
    let text = NSString(string: string)
    var pieces: [String] = []
    var last = 0
    for match in matches(in: string) {
      let range = match.range
      pieces.append(text.substring(with: NSRange(location: last, length: range.location - last)))
      last = range.location + range.length
    }
    pieces.append(text.substring(from: last))
    return pieces
  }
}

extension String {
  /// `replace(/\s+/g, " ")`.
  func jsSpacesCollapsed() -> String { Array(unicodeScalars).jsSpacesCollapsed.string }
}
