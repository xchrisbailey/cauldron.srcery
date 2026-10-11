import Foundation

// The ingredient parser and its neighbours were written against JavaScript's string and number
// rules, and the TypeScript is the specification. These helpers are those rules, so the ports
// read like the originals and agree with them on the edges: which characters are whitespace,
// how a number prints, how `toFixed` and `Math.round` break ties, what lowercasing does to a
// Greek sigma.

typealias Scalars = [Unicode.Scalar]

extension Unicode.Scalar {
  /// What JavaScript's `\s` and `String.prototype.trim` call whitespace. It is not
  /// `Character.isWhitespace`: it has U+FEFF and not U+0085.
  var isJSSpace: Bool {
    switch value {
    case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
      0x3000, 0xFEFF:
      true
    default:
      false
    }
  }

  var isASCIIDigit: Bool { (0x30...0x39).contains(value) }

  var isASCIILetter: Bool { (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) }

  /// `\w`: ASCII letters, digits and the underscore.
  var isASCIIWord: Bool { isASCIILetter || isASCIIDigit || value == 0x5F }

  /// `a-z` lowercased and every other scalar left alone: what a `/i` regex flag compares by.
  var asciiLowercased: Unicode.Scalar {
    (0x41...0x5A).contains(value) ? Unicode.Scalar(value + 0x20) ?? self : self
  }
}

extension Array where Element == Unicode.Scalar {
  init(_ string: String) { self = Array(string.unicodeScalars) }

  var string: String {
    var view = String.UnicodeScalarView()
    view.append(contentsOf: self)
    return String(view)
  }

  /// `trim()`.
  var jsTrimmed: Scalars {
    guard let first = firstIndex(where: { !$0.isJSSpace }),
      let last = lastIndex(where: { !$0.isJSSpace })
    else { return [] }
    return Array(self[first...last])
  }

  /// `replace(/\s+/g, " ")`.
  var jsSpacesCollapsed: Scalars {
    var out = Scalars()
    var inSpace = false
    for c in self {
      if c.isJSSpace {
        if !inSpace { out.append(" ") }
        inSpace = true
      } else {
        out.append(c)
        inSpace = false
      }
    }
    return out
  }

  /// The index after the run of scalars from `start` that satisfy `predicate`.
  func end(ofRunFrom start: Int, where predicate: (Unicode.Scalar) -> Bool) -> Int {
    var i = start
    while i < count, predicate(self[i]) { i += 1 }
    return i
  }

  func scalar(at index: Int) -> Unicode.Scalar? { indices.contains(index) ? self[index] : nil }

  /// Whether `literal` is at `index`, comparing ASCII letters without regard to case when
  /// `ignoringCase` is set.
  func has(_ literal: String, at index: Int = 0, ignoringCase: Bool = false) -> Bool {
    guard index >= 0 else { return false }
    var i = index
    for c in literal.unicodeScalars {
      guard i < count else { return false }
      let here = self[i]
      guard ignoringCase ? here.asciiLowercased == c.asciiLowercased : here == c else {
        return false
      }
      i += 1
    }
    return true
  }

  func from(_ index: Int) -> Scalars { index >= count ? [] : Array(self[index...]) }

  func dropping(last n: Int) -> Scalars { Array(prefix(Swift.max(0, count - n))) }
}

/// `String.prototype.trim`.
func jsTrim(_ string: String) -> String { Scalars(string).jsTrimmed.string }

/// `Math.round`: halves go up, toward positive infinity (so -2.5 is -2, unlike
/// `.toNearestOrAwayFromZero`).
func jsRound(_ x: Double) -> Double {
  guard x.isFinite else { return x }
  let floor = x.rounded(.down)
  let rounded = x - floor >= 0.5 ? floor + 1 : floor
  // -0.4 rounds to -0, as it does there.
  return rounded == 0 && x < 0 ? -0.0 : rounded
}

/// `Math.max(a, b)`: NaN if either is.
func jsMax(_ a: Double, _ b: Double) -> Double {
  if a.isNaN || b.isNaN { return .nan }
  return Swift.max(a, b)
}

/// `Number.prototype.toFixed`, which rounds the exact value of the double and sends an exact
/// tie up, where `printf` sends it to the even digit.
func jsToFixed(_ x: Double, _ digits: Int) -> String {
  if x.isNaN { return "NaN" }
  if x.isInfinite || abs(x) >= 1e21 { return jsString(x) }
  if x < 0 { return "-" + jsToFixed(-x, digits) }
  // x * 10^digits is n + 1/2 exactly when x * 2^(digits + 1) is an odd integer, since the
  // powers of five cancel.
  let scaled = x * Double(sign: .plus, exponent: digits + 1, significand: 1)
  let isTie = scaled == scaled.rounded(.down) && scaled.truncatingRemainder(dividingBy: 2) == 1
  return String(format: "%.\(digits)f", isTie ? x.nextUp : x)
}

/// `Number.prototype.toPrecision(1)` as a number: the value rounded to one significant digit.
func jsRoundedToOneDigit(_ x: Double) -> Double {
  Double(String(format: "%.0e", x)) ?? x
}

/// `String(number)`: the shortest digits that read back the same, in plain notation from 1e-6
/// up to (not including) 1e21 and in exponent notation outside it.
func jsString(_ x: Double) -> String {
  if x.isNaN { return "NaN" }
  if x == 0 { return "0" }
  if x.isInfinite { return x < 0 ? "-Infinity" : "Infinity" }
  let (digits, n) = shortestDigits(abs(x))
  let k = digits.count
  let body: String
  if k <= n && n <= 21 {
    body = digits + String(repeating: "0", count: n - k)
  } else if 0 < n && n <= 21 {
    body = digits.prefix(n) + "." + digits.dropFirst(n)
  } else if -6 < n && n <= 0 {
    body = "0." + String(repeating: "0", count: -n) + digits
  } else {
    let e = n - 1
    let exponent = (e < 0 ? "-" : "+") + String(abs(e))
    body =
      k == 1
      ? digits + "e" + exponent : digits.prefix(1) + "." + digits.dropFirst() + "e" + exponent
  }
  return x < 0 ? "-" + body : body
}

/// The shortest round-trip digits of a positive finite number, and the exponent `n` such that
/// the value is `0.digits × 10^n` (the `n` of the ECMAScript algorithm).
private func shortestDigits(_ x: Double) -> (digits: String, n: Int) {
  // Swift prints the same shortest digits, as "123.45", "1.2345e+20" or "5e-324".
  let text = "\(x)"
  let parts = text.split(separator: "e", maxSplits: 1)
  let mantissa = parts[0]
  let exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
  let pieces = mantissa.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
  let whole = String(pieces[0])
  let fraction = pieces.count > 1 ? String(pieces[1]) : ""
  var digits = whole + fraction
  var n = whole.count + exponent
  while digits.hasPrefix("0") {
    digits.removeFirst()
    n -= 1
  }
  while digits.hasSuffix("0") { digits.removeLast() }
  return (digits.isEmpty ? "0" : digits, n)
}

/// `Math.round(value).toLocaleString("en")`: whole numbers with a comma between thousands.
func jsGroupedRounded(_ x: Double) -> String {
  let rounded = jsRound(x)
  if rounded.isNaN { return "NaN" }
  if rounded.isInfinite { return rounded < 0 ? "-∞" : "∞" }
  var digits: String
  if abs(rounded) < 1e21 {
    digits = jsString(abs(rounded))
  } else {
    // Intl prints the digits out in full where String() switches to an exponent.
    let (d, n) = shortestDigits(abs(rounded))
    digits = d + String(repeating: "0", count: Swift.max(0, n - d.count))
  }
  var grouped = ""
  for (offset, character) in digits.reversed().enumerated() {
    if offset > 0 && offset % 3 == 0 { grouped.append(",") }
    grouped.append(character)
  }
  digits = String(grouped.reversed())
  let negative = rounded < 0 || (rounded == 0 && rounded.sign == .minus)
  return negative ? "-" + digits : digits
}

/// `Number(string)` for the strings a URL or a form hands over: decimal literals, `Infinity`
/// and the `0x`, `0o` and `0b` integer forms, with the blank string as 0 and anything else NaN.
func jsNumber(_ string: String) -> Double {
  let s = Scalars(string).jsTrimmed
  if s.isEmpty { return 0 }
  var body = s[...]
  var negative = false
  if let first = body.first, first == "+" || first == "-" {
    negative = first == "-"
    body = body.dropFirst()
  }
  if Scalars(body) == Scalars("Infinity") { return negative ? -.infinity : .infinity }
  let signless = s.count == body.count
  if signless, s.count > 2, s[0] == "0",
    let radix = ["x": 16, "o": 8, "b": 2][String(s[1]).lowercased()]
  {
    var value = 0.0
    for c in s.dropFirst(2) {
      guard let digit = Int(String(c), radix: radix) else { return .nan }
      value = value * Double(radix) + Double(digit)
    }
    return value
  }
  // [digits] [. digits] [e [+-] digits], with at least one digit in the mantissa.
  let b = Scalars(body)
  var i = b.end(ofRunFrom: 0, where: \.isASCIIDigit)
  let whole = String(b[0..<i].map(Character.init))
  var fraction = ""
  if b.scalar(at: i) == "." {
    let end = b.end(ofRunFrom: i + 1, where: \.isASCIIDigit)
    fraction = String(b[(i + 1)..<end].map(Character.init))
    i = end
  }
  guard !whole.isEmpty || !fraction.isEmpty else { return .nan }
  var exponent = ""
  if let e = b.scalar(at: i), e == "e" || e == "E" {
    var j = i + 1
    if let sign = b.scalar(at: j), sign == "+" || sign == "-" { j += 1 }
    let end = b.end(ofRunFrom: j, where: \.isASCIIDigit)
    guard end > j else { return .nan }
    exponent = "e" + String(b[(i + 1)..<end].map(Character.init))
    i = end
  }
  guard i == b.count else { return .nan }
  let value = Double(
    "\(whole.isEmpty ? "0" : whole).\(fraction.isEmpty ? "0" : fraction)\(exponent)")
  guard let value else { return .nan }
  return negative ? -value : value
}

/// `String.prototype.toLowerCase`: the full Unicode mapping, with a sigma at the end of a word
/// written as ς.
func jsLowercased(_ string: String) -> String {
  let scalars = Scalars(string)
  var out = String.UnicodeScalarView()
  for (index, c) in scalars.enumerated() {
    if c.value == 0x3A3 {
      out.append(isFinalSigma(scalars, at: index) ? "\u{3C2}" : "\u{3C3}")
    } else {
      out.append(contentsOf: c.properties.lowercaseMapping.unicodeScalars)
    }
  }
  return String(out)
}

private func isFinalSigma(_ scalars: Scalars, at index: Int) -> Bool {
  var before = index - 1
  while before >= 0, scalars[before].properties.isCaseIgnorable { before -= 1 }
  guard before >= 0, scalars[before].properties.isCased else { return false }
  var after = index + 1
  while after < scalars.count, scalars[after].properties.isCaseIgnorable { after += 1 }
  return !(after < scalars.count && scalars[after].properties.isCased)
}
