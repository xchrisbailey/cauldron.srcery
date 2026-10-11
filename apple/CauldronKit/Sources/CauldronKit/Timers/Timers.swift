import Foundation

// Detect a cooking duration in a method step so the editor can offer a timer chip. Ported
// from `packages/shared/src/timers.ts`. Quantities are plain text, not copy-module strings.
//
// The reference is two regular expressions, one with a lookbehind and one sticky. This uses
// `NSRegularExpression` (ICU, in Foundation on every platform) because it has both, and
// replaces `\s`, `\w` and `\d` with the exact classes JavaScript means by them: ICU's are wider
// (every Unicode digit and letter) and a little different for whitespace.

private let maxSeconds = 60.0 * 60 * 72

private let vulgar: [Character: Double] = [
  "½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125,
]

/// JavaScript's `\s`.
private let space =
  #"[\t\n\u000B\f\r    -     　﻿]"#
private let fractions = "½¼¾⅓⅔⅛"
private let amount =
  "(?:[0-9]+\(space)+[0-9]+/[0-9]+|[0-9]+\(space)*[\(fractions)]|[0-9]+(?:\\.[0-9]+)?"
  + "|[0-9]+/[0-9]+|[\(fractions)]|half\(space)+an?|an?)"
private let range = "(\(amount))(?:\(space)*(?:-|–|—|to)\(space)*(\(amount)))?"
private let unit = "\(space)*(hours?|hrs?|h|minutes?|mins?|seconds?|secs?|s)(?![A-Za-z])\\.?"

private let first = try? NSRegularExpression(
  pattern: "(?<![A-Za-z0-9_./])\(range)\(unit)", options: [.caseInsensitive])
private let next = try? NSRegularExpression(
  pattern: "(?:\(space)*(?:,|and)?\(space)*)\(range)\(unit)", options: [.caseInsensitive])

private let mixedNumber = try? NSRegularExpression(
  pattern: "^([0-9]+)\(space)+([0-9]+)/([0-9]+)\\z")
private let mixedFraction = try? NSRegularExpression(
  pattern: "^([0-9]+)\(space)*([\(fractions)])\\z")
private let simpleFraction = try? NSRegularExpression(pattern: "^([0-9]+)/([0-9]+)\\z")

private func groups(of regex: NSRegularExpression?, in text: String) -> [Double]? {
  let ns = NSString(string: text)
  guard
    let match = regex?.firstMatch(
      in: text, options: [], range: NSRange(location: 0, length: ns.length))
  else { return nil }
  return (1..<match.numberOfRanges).map { Double(ns.substring(with: match.range(at: $0))) ?? .nan }
}

private func parseAmount(_ raw: String) -> Double? {
  let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  if s == "a" || s == "an" { return 1 }
  if s.hasPrefix("half") { return 0.5 }
  if let n = groups(of: mixedNumber, in: s) { return n[0] + n[1] / n[2] }
  if let fraction = groups(of: mixedFraction, in: s), let mark = s.last,
    let value = vulgar[mark]
  {
    return fraction[0] + value
  }
  if let n = groups(of: simpleFraction, in: s) { return n[1] == 0 ? nil : n[0] / n[1] }
  if s.count == 1, let mark = s.first, let value = vulgar[mark] { return value }
  guard let n = Double(s), n.isFinite else { return nil }
  return n
}

private func unitSeconds(_ unit: String) -> Double {
  let u = unit.lowercased()
  if u.hasPrefix("h") { return 3600 }
  if u.hasPrefix("m") { return 60 }
  return 1
}

private func isWord(_ raw: String) -> Bool {
  let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  return s.hasPrefix("a") || s.hasPrefix("half")
}

/// Seconds for one `amount[-amount] unit` match; the range's upper bound wins.
private func toSeconds(_ lo: String, _ hi: String?, _ unit: String) -> Double? {
  let raw = hi ?? lo
  // "a s" / "an h" are not durations; word amounts need a spelled-out unit.
  if isWord(raw) && unit.utf16.count <= 1 { return nil }
  guard let amount = parseAmount(raw) else { return nil }
  return amount * unitSeconds(unit)
}

/// Seconds for the first cooking duration in `text`, or nil. The upper bound of a range is
/// used so the timer covers it. Above 72 hours returns nil.
public func detectTimer(_ text: String) -> Int? {
  guard let first, let next else { return nil }
  let ns = NSString(string: text)

  func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
    let range = match.range(at: index)
    return range.location == NSNotFound ? nil : ns.substring(with: range)
  }

  for match in first.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
  {
    guard let lo = group(match, 1), let unit = group(match, 3),
      var total = toSeconds(lo, group(match, 2), unit)
    else { continue }
    var lastUnit = unitSeconds(unit)
    var end = match.range.location + match.range.length
    // "1 hr 15 min", "1 hour and 15 minutes": add smaller trailing units.
    while let more = next.firstMatch(
      in: text, options: [.anchored], range: NSRange(location: end, length: ns.length - end)),
      let moreLo = group(more, 1), let moreUnit = group(more, 3),
      unitSeconds(moreUnit) < lastUnit,
      let extra = toSeconds(moreLo, group(more, 2), moreUnit)
    {
      total += extra
      lastUnit = unitSeconds(moreUnit)
      end = more.range.location + more.range.length
    }
    let seconds = jsRound(total)
    // A sum that isn't a number ("1 0/0 minutes") has no timer; the reference returns NaN.
    guard seconds >= 1, seconds <= maxSeconds else { return nil }
    return Int(seconds)
  }
  return nil
}

/// Short plain label: "45 s", "25 min", "1 min 30 s", "1 h", "1 h 15 min".
public func formatTimer(_ seconds: Int) -> String {
  let total = max(0, seconds)
  let h = total / 3600
  let m = (total % 3600) / 60
  let s = total % 60
  if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
  if m > 0 { return s > 0 ? "\(m) min \(s) s" : "\(m) min" }
  return "\(s) s"
}

public func formatTimer(_ seconds: Double) -> String {
  guard seconds.isFinite else { return formatTimer(0) }
  return formatTimer(Int(min(max(0, jsRound(seconds)), 1e15)))
}
