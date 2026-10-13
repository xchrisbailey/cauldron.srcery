import Foundation

// An http or https URL as the WHATWG URL standard reads and writes it, which is what the
// reference's `new URL(...)` did. Foundation's `URL` is a different grammar (it keeps
// "https://example.com" as is where `new URL` adds the slash, and it escapes differently), and
// the draft's source link, the canonical-link checks and the tracking-parameter strip all
// compare the written form, so the standard's rules are applied here directly. Only http and
// https are understood; any other scheme fails to parse, which is how every caller treats it.
// Internationalised host names are lower-cased but not converted to punycode: Foundation does
// that when the link is fetched.

struct WebURL: Sendable, Hashable {
  var scheme: String
  var username: String
  var password: String
  /// Lower-case, with square brackets round an IPv6 address (the URL's `hostname`).
  var host: String
  /// Nil for the scheme's default port.
  var port: Int?
  var path: String
  /// Without the "?".
  var query: String?
  /// Without the "#".
  var fragment: String?

  /// `href`.
  var string: String {
    var out = scheme + "://"
    if !username.isEmpty || !password.isEmpty {
      out += username
      if !password.isEmpty { out += ":" + password }
      out += "@"
    }
    out += host
    if let port { out += ":\(port)" }
    out += path
    if let query { out += "?" + query }
    if let fragment { out += "#" + fragment }
    return out
  }

  /// `new URL(input, base)`, or nil where that would throw (or the scheme isn't http or https).
  static func parse(_ input: String, base: WebURL? = nil) -> WebURL? {
    var chars = Array(input.unicodeScalars)
    while let first = chars.first, first.value <= 0x20 { chars.removeFirst() }
    while let last = chars.last, last.value <= 0x20 { chars.removeLast() }
    chars.removeAll { $0 == "\t" || $0 == "\n" || $0 == "\r" }

    var rest = Part(base: chars, bounds: chars.startIndex..<chars.endIndex)
    var scheme: String?
    if let first = rest.first, first.isASCIILetter,
      let colon = rest.firstIndex(of: ":"),
      rest[rest.startIndex..<colon].allSatisfy({
        $0.isASCIILetter || $0.isASCIIDigit || $0 == "+" || $0 == "-" || $0 == "."
      })
    {
      scheme = rest[rest.startIndex..<colon].string.lowercased()
      rest = rest[(colon + 1)...]
    }

    if let scheme {
      guard scheme == "http" || scheme == "https" else { return nil }
      // "https:foo" against an https base is a relative reference.
      if let base, base.scheme == scheme, !startsWithSlash(rest) {
        return relative(rest, to: base)
      }
      return authority(skippingSlashes(rest), scheme: scheme)
    }
    guard let base else { return nil }
    if startsWithSlash(rest), startsWithSlash(rest.dropFirst()) {
      return authority(skippingSlashes(rest), scheme: base.scheme)
    }
    return relative(rest, to: base)
  }

  // MARK: Parsing pieces

  private typealias Part = Slice<[Unicode.Scalar]>

  private static func isSlash(_ c: Unicode.Scalar) -> Bool { c == "/" || c == "\\" }

  private static func startsWithSlash(_ part: Part) -> Bool {
    part.first.map(isSlash) ?? false
  }

  private static func skippingSlashes(_ part: Part) -> Part {
    var rest = part
    while let first = rest.first, isSlash(first) { rest = rest.dropFirst() }
    return rest
  }

  private static func relative(_ input: Part, to base: WebURL) -> WebURL? {
    var url = base
    url.fragment = nil
    if input.isEmpty { return url }
    if input.first == "#" {
      url.fragment = encode(input.dropFirst(), fragmentSet)
      return url
    }
    if input.first == "?" {
      let (query, fragment) = splitFragment(input.dropFirst())
      url.query = encode(query, querySet)
      url.fragment = fragment
      return url
    }
    var (rest, fragment) = splitFragment(input)
    url.fragment = fragment
    url.query = nil
    if let mark = rest.firstIndex(of: "?") {
      url.query = encode(rest[(mark + 1)...], querySet)
      rest = rest[..<mark]
    }
    var segments: [String] = []
    if !startsWithSlash(rest) {
      // The base's path without its last segment.
      segments = base.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        .map(String.init)
      if !segments.isEmpty { segments.removeLast() }
    }
    url.path = resolve(path: rest, startingWith: segments)
    return url
  }

  private static func authority(_ input: Part, scheme: String) -> WebURL? {
    let end =
      input.firstIndex(where: { isSlash($0) || $0 == "?" || $0 == "#" }) ?? input.endIndex
    var authority = input[..<end]
    var username = ""
    var password = ""
    if let at = authority.lastIndex(of: "@") {
      let userinfo = authority[..<at]
      authority = authority[(at + 1)...]
      if let colon = userinfo.firstIndex(of: ":") {
        username = encode(userinfo[..<colon], userinfoSet)
        password = encode(userinfo[(colon + 1)...], userinfoSet)
      } else {
        username = encode(userinfo, userinfoSet)
      }
    }
    var hostPart = authority
    var portPart: Part?
    var inBrackets = false
    for index in authority.indices {
      if authority[index] == "[" { inBrackets = true }
      if authority[index] == "]" { inBrackets = false }
      if authority[index] == ":" && !inBrackets {
        hostPart = authority[..<index]
        portPart = authority[(index + 1)...]
        break
      }
    }
    guard let host = parseHost(hostPart) else { return nil }
    var port: Int?
    if let portPart, !portPart.isEmpty {
      guard portPart.allSatisfy(\.isASCIIDigit), portPart.count <= 10,
        let number = Int(portPart.string), number <= 65535
      else { return nil }
      port = number == (scheme == "http" ? 80 : 443) ? nil : number
    }
    var url = WebURL(
      scheme: scheme, username: username, password: password, host: host, port: port,
      path: "/", query: nil, fragment: nil)
    var (rest, fragment) = splitFragment(input[end...])
    url.fragment = fragment
    if let mark = rest.firstIndex(of: "?") {
      url.query = encode(rest[(mark + 1)...], querySet)
      rest = rest[..<mark]
    }
    if !rest.isEmpty { url.path = resolve(path: rest, startingWith: []) }
    return url
  }

  private static func splitFragment(_ input: Part) -> (Part, String?) {
    guard let hash = input.firstIndex(of: "#") else { return (input, nil) }
    return (input[..<hash], encode(input[(hash + 1)...], fragmentSet))
  }

  /// The host, lower-cased, or nil when it is empty or holds a character no host can.
  private static func parseHost(_ input: Part) -> String? {
    if input.first == "[" {
      guard input.last == "]", input.count > 2 else { return nil }
      let inner = input.dropFirst().dropLast()
      guard inner.allSatisfy({ $0.isASCIIHexDigit || $0 == ":" || $0 == "." }) else { return nil }
      return "[" + inner.string.lowercased() + "]"
    }
    let decoded = percentDecoded(input)
    guard !decoded.isEmpty else { return nil }
    let forbidden: Set<Unicode.Scalar> = [
      " ", "#", "%", "/", ":", "<", ">", "?", "@", "[", "\\", "]", "^", "|", "\u{7F}",
    ]
    guard !decoded.contains(where: { $0.value <= 0x20 || forbidden.contains($0) }) else {
      return nil
    }
    let host = decoded.string.lowercased()
    guard decoded.contains(where: { $0.value > 0x7F }) else { return host }
    // Names with letters outside ASCII are written as punycode, label by label.
    let labels = host.precomposedStringWithCanonicalMapping.components(separatedBy: ".")
    var out: [String] = []
    for label in labels {
      if label.unicodeScalars.allSatisfy({ $0.value < 0x80 }) {
        out.append(label)
      } else if let encoded = punycode(Array(label.unicodeScalars.map(\.value))) {
        out.append("xn--" + encoded)
      } else {
        return nil
      }
    }
    return out.joined(separator: ".")
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

  private static func percentDecoded(_ input: Part) -> Scalars {
    var bytes: [UInt8] = []
    let scalars = Array(input)
    var i = 0
    while i < scalars.count {
      if scalars[i] == "%", i + 2 < scalars.count,
        let high = hexValue(scalars[i + 1]), let low = hexValue(scalars[i + 2])
      {
        bytes.append(UInt8(high << 4 | low))
        i += 3
      } else {
        bytes.append(contentsOf: Array(String(scalars[i]).utf8))
        i += 1
      }
    }
    return Array(String(decoding: bytes, as: UTF8.self).unicodeScalars)
  }

  private static func hexValue(_ c: Unicode.Scalar) -> Int? {
    switch c.value {
    case 0x30...0x39: Int(c.value) - 0x30
    case 0x41...0x46: Int(c.value) - 0x41 + 10
    case 0x61...0x66: Int(c.value) - 0x61 + 10
    default: nil
    }
  }

  /// A path split on slashes, dot segments applied, percent-encoded, written back with a
  /// leading slash.
  private static func resolve(path: Part, startingWith base: [String]) -> String {
    var segments = base
    var pieces = path.split(omittingEmptySubsequences: false, whereSeparator: isSlash)
    if startsWithSlash(path) { pieces.removeFirst() }
    for (index, piece) in pieces.enumerated() {
      let isLast = index == pieces.count - 1
      let lowered = piece.string.lowercased()
      if ["..", ".%2e", "%2e.", "%2e%2e"].contains(lowered) {
        if !segments.isEmpty { segments.removeLast() }
        if isLast { segments.append("") }
      } else if lowered == "." || lowered == "%2e" {
        if isLast { segments.append("") }
      } else {
        segments.append(encode(piece, pathSet))
      }
    }
    return "/" + segments.joined(separator: "/")
  }

  // MARK: Percent-encoding

  private static func isControlOrNonASCII(_ c: Unicode.Scalar) -> Bool {
    c.value <= 0x1F || c.value > 0x7E
  }

  private static let fragmentSet: @Sendable (Unicode.Scalar) -> Bool = {
    isControlOrNonASCII($0) || [" ", "\"", "<", ">", "`"].contains($0)
  }
  private static let querySet: @Sendable (Unicode.Scalar) -> Bool = {
    isControlOrNonASCII($0) || [" ", "\"", "#", "<", ">", "'"].contains($0)
  }
  private static let pathSet: @Sendable (Unicode.Scalar) -> Bool = {
    isControlOrNonASCII($0) || [" ", "\"", "#", "<", ">", "?", "`", "{", "}"].contains($0)
  }
  private static let userinfoSet: @Sendable (Unicode.Scalar) -> Bool = {
    pathSet($0) || ["/", ":", ";", "=", "@", "[", "\\", "]", "^", "|"].contains($0)
  }

  private static func encode(_ input: Part, _ needsEncoding: (Unicode.Scalar) -> Bool) -> String {
    var out = ""
    for c in input {
      if needsEncoding(c) {
        for byte in String(c).utf8 { out += "%" + hex(byte) }
      } else {
        out.unicodeScalars.append(c)
      }
    }
    return out
  }

  private static func hex(_ byte: UInt8) -> String {
    let digits = Array("0123456789ABCDEF")
    return String(digits[Int(byte >> 4)]) + String(digits[Int(byte & 0xF)])
  }

  // MARK: Search parameters

  /// `searchParams` as `application/x-www-form-urlencoded` pairs.
  var searchParams: [(name: String, value: String)] {
    guard let query, !query.isEmpty else { return [] }
    return query.utf8.split(separator: UInt8(ascii: "&"), omittingEmptySubsequences: true).map {
      pair in
      let parts = pair.split(
        separator: UInt8(ascii: "="), maxSplits: 1, omittingEmptySubsequences: false)
      return (
        Self.formDecoded(parts[0]), parts.count > 1 ? Self.formDecoded(parts[1]) : ""
      )
    }
  }

  /// `searchParams.get(name)`.
  func searchParam(_ name: String) -> String? {
    searchParams.first { $0.name == name }?.value
  }

  /// `searchParams.delete(...)` for every name `isTracking` says is: the query is written back
  /// from the pairs that are left, or dropped when none are. Without a match the query is
  /// untouched, as the standard leaves it.
  func removingParams(where isTracking: (String) -> Bool) -> WebURL {
    let pairs = searchParams
    guard pairs.contains(where: { isTracking($0.name) }) else { return self }
    var url = self
    let kept = pairs.filter { !isTracking($0.name) }
    url.query =
      kept.isEmpty
      ? nil
      : kept.map { Self.formEncoded($0.name) + "=" + Self.formEncoded($0.value) }
        .joined(separator: "&")
    return url
  }

  private static func formDecoded(_ bytes: some Sequence<UInt8>) -> String {
    var out: [UInt8] = []
    let input = Array(bytes)
    var i = 0
    while i < input.count {
      let byte = input[i]
      if byte == UInt8(ascii: "+") {
        out.append(0x20)
        i += 1
      } else if byte == UInt8(ascii: "%"), i + 2 < input.count,
        let high = hexValue(Unicode.Scalar(input[i + 1])),
        let low = hexValue(Unicode.Scalar(input[i + 2]))
      {
        out.append(UInt8(high << 4 | low))
        i += 3
      } else {
        out.append(byte)
        i += 1
      }
    }
    return String(decoding: out, as: UTF8.self)
  }

  private static func formEncoded(_ text: String) -> String {
    var out = ""
    for byte in text.utf8 {
      switch byte {
      case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
        UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "*"), UInt8(ascii: "-"),
        UInt8(ascii: "."), UInt8(ascii: "_"):
        out.unicodeScalars.append(Unicode.Scalar(byte))
      case 0x20: out += "+"
      default: out += "%" + hex(byte)
      }
    }
    return out
  }

  // MARK: Edits

  /// `url.hash = ""`.
  func withoutFragment() -> WebURL {
    var url = self
    url.fragment = nil
    return url
  }

  /// `url.pathname = url.pathname.replace(/\/+$/, "")` when the path is longer than "/".
  func withoutTrailingSlashes() -> WebURL {
    guard path.count > 1 else { return self }
    var trimmed = Substring(path)
    while trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
    var url = self
    url.path = trimmed.isEmpty ? "/" : String(trimmed)
    return url
  }
}

extension Unicode.Scalar {
  fileprivate var isASCIIHexDigit: Bool {
    isASCIIDigit || (0x41...0x46).contains(value) || (0x61...0x66).contains(value)
  }
}

extension Slice where Base == [Unicode.Scalar] {
  fileprivate var string: String { Array(self).string }
}
