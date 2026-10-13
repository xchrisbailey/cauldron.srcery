import Foundation

// A URL's host as the WHATWG URL standard reads it: percent-decoded, mapped to ASCII, and if it
// is an IPv4 or IPv6 address, written in its canonical form. The app decides whether a link
// points at the cook's own network from the host this gives, so "0x7f.1", "2130706433" and
// "[0:0:0:0:0:0:0:1]" have to come out as 127.0.0.1 and [::1], as `new URL` writes them.
//
// Internationalised names go through a reduced UTS 46: the characters it ignores are dropped,
// the ideographic full stops become dots, and the name is folded with NFKC and lower case
// (which covers fullwidth and other compatibility forms) before each non-ASCII label is
// written as punycode. Not covered: the rest of the UTS 46 mapping table (a few thousand
// historic and script-specific mappings that NFKC does not make), the validity checks (bidi,
// contextual joiner rules, label length), and decoding of labels that already start "xn--".

enum WebHost {
  /// The written host for the characters between "//" and the port, or nil when the standard
  /// refuses it.
  static func parse(_ input: [Unicode.Scalar]) -> String? {
    if input.first == "[" {
      guard input.last == "]" else { return nil }
      return parseIPv6(Array(input.dropFirst().dropLast())).map { "[" + serialize($0) + "]" }
    }
    let decoded = percentDecoded(input)
    guard let domain = toASCII(decoded), !domain.isEmpty else { return nil }
    let forbidden: Set<Unicode.Scalar> = [
      " ", "#", "/", ":", "<", ">", "?", "@", "[", "\\", "]", "^", "|", "%", "\u{7F}",
    ]
    guard !domain.unicodeScalars.contains(where: { $0.value <= 0x1F || forbidden.contains($0) })
    else { return nil }
    if endsInANumber(domain) {
      return parseIPv4(domain).map(serialize)
    }
    return domain
  }

  // MARK: Percent-decoding and IDNA

  private static func percentDecoded(_ input: [Unicode.Scalar]) -> String {
    var bytes: [UInt8] = []
    var i = 0
    while i < input.count {
      if input[i] == "%", i + 2 < input.count, let high = hex(input[i + 1]),
        let low = hex(input[i + 2])
      {
        bytes.append(UInt8(high << 4 | low))
        i += 3
      } else {
        bytes.append(contentsOf: Array(String(input[i]).utf8))
        i += 1
      }
    }
    return String(decoding: bytes, as: UTF8.self)
  }

  private static func hex(_ c: Unicode.Scalar) -> Int? {
    switch c.value {
    case 0x30...0x39: Int(c.value) - 0x30
    case 0x41...0x46: Int(c.value) - 0x41 + 10
    case 0x61...0x66: Int(c.value) - 0x61 + 10
    default: nil
    }
  }

  private static func toASCII(_ name: String) -> String? {
    if name.unicodeScalars.allSatisfy({ $0.value < 0x80 }) { return name.lowercased() }
    var mapped = String.UnicodeScalarView()
    for c in name.unicodeScalars {
      switch c.value {
      case 0xAD, 0x200B, 0x2060, 0xFEFF: continue
      // Joiners are only valid in contexts a plain name never has.
      case 0x200C, 0x200D: return nil
      case 0x3002, 0xFF0E, 0xFF61: mapped.append(".")
      default: mapped.append(c)
      }
    }
    let folded = String(mapped).precomposedStringWithCompatibilityMapping.lowercased()
      .precomposedStringWithCompatibilityMapping.lowercased()
    var labels: [String] = []
    for label in folded.components(separatedBy: ".") {
      if label.unicodeScalars.allSatisfy({ $0.value < 0x80 }) {
        labels.append(label)
      } else if let encoded = punycode(label.unicodeScalars.map(\.value)) {
        labels.append("xn--" + encoded)
      } else {
        return nil
      }
    }
    return labels.joined(separator: ".")
  }

  /// RFC 3492 Punycode for one label.
  private static func punycode(_ input: [UInt32]) -> String? {
    let base: UInt32 = 36
    let tMin: UInt32 = 1
    let tMax: UInt32 = 26
    let skew: UInt32 = 38
    let damp: UInt32 = 700
    func digit(_ d: UInt32) -> Character {
      Character(Unicode.Scalar(d < 26 ? d + 97 : d + 22) ?? "a")
    }
    func adapt(_ delta: UInt32, _ points: UInt32, _ first: Bool) -> UInt32 {
      var delta = first ? delta / damp : delta / 2
      delta += delta / points
      var k: UInt32 = 0
      while delta > ((base - tMin) * tMax) / 2 {
        delta /= base - tMin
        k += base
      }
      return k + (base - tMin + 1) * delta / (delta + skew)
    }
    var output = input.filter { $0 < 0x80 }.compactMap { Unicode.Scalar($0).map(Character.init) }
    let basic = UInt32(output.count)
    var handled = basic
    if basic > 0 { output.append("-") }
    var n: UInt32 = 128
    var delta: UInt32 = 0
    var bias: UInt32 = 72
    while handled < UInt32(input.count) {
      guard let m = input.filter({ $0 >= n }).min() else { return nil }
      let (step, overflow) = (m - n).multipliedReportingOverflow(by: handled + 1)
      guard !overflow else { return nil }
      delta += step
      n = m
      for c in input {
        if c < n { delta += 1 }
        if c == n {
          var q = delta
          var k = base
          while true {
            let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
            if q < t { break }
            output.append(digit(t + (q - t) % (base - t)))
            q = (q - t) / (base - t)
            k += base
          }
          output.append(digit(q))
          bias = adapt(delta, handled + 1, handled == basic)
          delta = 0
          handled += 1
        }
      }
      delta += 1
      n += 1
    }
    return String(output)
  }

  // MARK: IPv4

  private static func ipv4Number(_ part: Substring) -> UInt64? {
    if part.isEmpty { return nil }
    var digits = part
    var radix = 10
    if digits.count >= 2, digits.hasPrefix("0x") || digits.hasPrefix("0X") {
      digits = digits.dropFirst(2)
      radix = 16
    } else if digits.count >= 2, digits.hasPrefix("0") {
      digits = digits.dropFirst()
      radix = 8
    }
    if digits.isEmpty { return 0 }
    guard digits.unicodeScalars.allSatisfy({ hex($0).map { $0 < radix } ?? false }) else {
      return nil
    }
    // A value this long is past 2^32 whatever its digits.
    if digits.count > 12 { return UInt64.max }
    return UInt64(digits, radix: radix)
  }

  /// Whether the last label is a number, so the whole name must be read as IPv4.
  private static func endsInANumber(_ domain: String) -> Bool {
    var parts = domain.split(separator: ".", omittingEmptySubsequences: false)
    if parts.last?.isEmpty == true {
      if parts.count == 1 { return false }
      parts.removeLast()
    }
    guard let last = parts.last, !last.isEmpty else { return false }
    if last.unicodeScalars.allSatisfy(\.isASCIIDigit) { return true }
    return ipv4Number(last) != nil
  }

  private static func parseIPv4(_ domain: String) -> UInt32? {
    var parts = domain.split(separator: ".", omittingEmptySubsequences: false)
    if parts.last?.isEmpty == true, parts.count > 1 { parts.removeLast() }
    guard parts.count <= 4 else { return nil }
    var numbers: [UInt64] = []
    for part in parts {
      guard let number = ipv4Number(part) else { return nil }
      numbers.append(number)
    }
    if numbers.dropLast().contains(where: { $0 > 255 }) { return nil }
    guard let last = numbers.last else { return nil }
    var limit: UInt64 = 1
    for _ in 0..<(5 - numbers.count) { limit *= 256 }
    if last >= limit { return nil }
    var address = last
    for (index, number) in numbers.dropLast().enumerated() {
      var scale: UInt64 = 1
      for _ in 0..<(3 - index) { scale *= 256 }
      address += number * scale
    }
    return UInt32(address)
  }

  private static func serialize(_ address: UInt32) -> String {
    [24, 16, 8, 0].map { String((address >> UInt32($0)) & 0xFF) }.joined(separator: ".")
  }

  // MARK: IPv6

  private static func parseIPv6(_ c: [Unicode.Scalar]) -> [UInt16]? {
    var address = [UInt16](repeating: 0, count: 8)
    var pieceIndex = 0
    var compress: Int?
    var pointer = 0
    func at(_ index: Int) -> Unicode.Scalar? { index < c.count ? c[index] : nil }
    if at(0) == ":" {
      guard at(1) == ":" else { return nil }
      pointer += 2
      pieceIndex += 1
      compress = pieceIndex
    }
    while pointer < c.count {
      if pieceIndex == 8 { return nil }
      if at(pointer) == ":" {
        if compress != nil { return nil }
        pointer += 1
        pieceIndex += 1
        compress = pieceIndex
        continue
      }
      var value = 0
      var length = 0
      while length < 4, let ch = at(pointer), let digit = hex(ch) {
        value = value * 16 + digit
        pointer += 1
        length += 1
      }
      if at(pointer) == "." {
        if length == 0 { return nil }
        pointer -= length
        if pieceIndex > 6 { return nil }
        var numbersSeen = 0
        while pointer < c.count {
          var piece: Int?
          if numbersSeen > 0 {
            guard at(pointer) == ".", numbersSeen < 4 else { return nil }
            pointer += 1
          }
          guard let first = at(pointer), first.isASCIIDigit else { return nil }
          while let ch = at(pointer), ch.isASCIIDigit {
            let number = Int(ch.value) - 0x30
            if let current = piece {
              if current == 0 { return nil }
              piece = current * 10 + number
            } else {
              piece = number
            }
            if let current = piece, current > 255 { return nil }
            pointer += 1
          }
          address[pieceIndex] = address[pieceIndex] &* 0x100 &+ UInt16(piece ?? 0)
          numbersSeen += 1
          if numbersSeen == 2 || numbersSeen == 4 { pieceIndex += 1 }
        }
        if numbersSeen != 4 { return nil }
        break
      } else if at(pointer) == ":" {
        pointer += 1
        if pointer >= c.count { return nil }
      } else if pointer < c.count {
        return nil
      }
      address[pieceIndex] = UInt16(value)
      pieceIndex += 1
    }
    if let compress {
      var swaps = pieceIndex - compress
      pieceIndex = 7
      while pieceIndex != 0, swaps > 0 {
        address.swapAt(pieceIndex, compress + swaps - 1)
        pieceIndex -= 1
        swaps -= 1
      }
    } else if pieceIndex != 8 {
      return nil
    }
    return address
  }

  private static func serialize(_ address: [UInt16]) -> String {
    // The first longest run of two or more zero pieces is written "::".
    var bestStart = -1
    var bestLength = 0
    var start = -1
    for index in 0...8 {
      if index < 8, address[index] == 0 {
        if start < 0 { start = index }
      } else if start >= 0 {
        if index - start > bestLength {
          bestStart = start
          bestLength = index - start
        }
        start = -1
      }
    }
    if bestLength < 2 { bestStart = -1 }
    var out = ""
    var index = 0
    while index < 8 {
      if index == bestStart {
        out += index == 0 ? "::" : ":"
        index += bestLength
        continue
      }
      out += String(address[index], radix: 16)
      if index != 7 { out += ":" }
      index += 1
    }
    return out
  }
}
