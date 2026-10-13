import Foundation

/// A JSON document, read the way `JSON.parse` reads it. `JSONSerialization` is more lenient
/// (it takes raw line breaks inside strings, for one), and the JSON-LD reader's fallback for
/// exactly that case depends on the first attempt failing.
enum JSONValue: Sendable, Hashable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  /// `JSON.parse(text)`, or nil where it would throw. Nesting past 512 levels is refused,
  /// where `JSON.parse` goes on until its stack ends.
  static func parse(_ text: String) -> JSONValue? {
    var reader = Reader(Array(text.unicodeScalars))
    reader.skipSpace()
    guard let value = reader.value(depth: 0) else { return nil }
    reader.skipSpace()
    return reader.atEnd ? value : nil
  }

  var object: [String: JSONValue]? {
    if case .object(let object) = self { return object }
    return nil
  }

  var string: String? {
    if case .string(let string) = self { return string }
    return nil
  }

  /// `String(value)` for the values a `@type` can hold.
  var jsString: String {
    switch self {
    case .null: "null"
    case .bool(let bool): bool ? "true" : "false"
    case .number(let number): CauldronKit.jsString(number)
    case .string(let string): string
    case .array(let items):
      items.map { item in
        switch item {
        case .null: ""
        default: item.jsString
        }
      }.joined(separator: ",")
    case .object: "[object Object]"
    }
  }

  private struct Reader {
    let chars: [Unicode.Scalar]
    var index = 0

    init(_ chars: [Unicode.Scalar]) { self.chars = chars }

    var atEnd: Bool { index >= chars.count }

    mutating func skipSpace() {
      while index < chars.count {
        switch chars[index] {
        case " ", "\t", "\n", "\r": index += 1
        default: return
        }
      }
    }

    mutating func value(depth: Int) -> JSONValue? {
      guard depth <= 512, index < chars.count else { return nil }
      switch chars[index] {
      case "{": return object(depth: depth)
      case "[": return array(depth: depth)
      case "\"": return string().map(JSONValue.string)
      case "t": return literal("true", .bool(true))
      case "f": return literal("false", .bool(false))
      case "n": return literal("null", .null)
      default: return number()
      }
    }

    mutating func literal(_ word: String, _ value: JSONValue) -> JSONValue? {
      let scalars = Array(word.unicodeScalars)
      guard index + scalars.count <= chars.count,
        Array(chars[index..<index + scalars.count]) == scalars
      else { return nil }
      index += scalars.count
      return value
    }

    mutating func number() -> JSONValue? {
      let start = index
      if index < chars.count, chars[index] == "-" { index += 1 }
      guard index < chars.count else { return nil }
      if chars[index] == "0" {
        index += 1
      } else if (0x31...0x39).contains(chars[index].value) {
        while index < chars.count, chars[index].isASCIIDigit { index += 1 }
      } else {
        return nil
      }
      if index < chars.count, chars[index] == "." {
        index += 1
        let digits = index
        while index < chars.count, chars[index].isASCIIDigit { index += 1 }
        guard index > digits else { return nil }
      }
      if index < chars.count, chars[index] == "e" || chars[index] == "E" {
        index += 1
        if index < chars.count, chars[index] == "+" || chars[index] == "-" { index += 1 }
        let digits = index
        while index < chars.count, chars[index].isASCIIDigit { index += 1 }
        guard index > digits else { return nil }
      }
      return Double(Array(chars[start..<index]).string).map(JSONValue.number)
    }

    mutating func hex4() -> UInt32? {
      guard index + 4 <= chars.count else { return nil }
      var value: UInt32 = 0
      for c in chars[index..<index + 4] {
        guard let digit = Int(String(c), radix: 16) else { return nil }
        value = value << 4 | UInt32(digit)
      }
      index += 4
      return value
    }

    mutating func string() -> String? {
      index += 1
      var out = String.UnicodeScalarView()
      while index < chars.count {
        let c = chars[index]
        index += 1
        switch c {
        case "\"": return String(out)
        case "\\":
          guard index < chars.count else { return nil }
          let escape = chars[index]
          index += 1
          switch escape {
          case "\"": out.append("\"")
          case "\\": out.append("\\")
          case "/": out.append("/")
          case "b": out.append("\u{8}")
          case "f": out.append("\u{C}")
          case "n": out.append("\n")
          case "r": out.append("\r")
          case "t": out.append("\t")
          case "u":
            guard var unit = hex4() else { return nil }
            if (0xD800...0xDBFF).contains(unit), index + 1 < chars.count, chars[index] == "\\",
              chars[index + 1] == "u"
            {
              let save = index
              index += 2
              if let low = hex4(), (0xDC00...0xDFFF).contains(low) {
                unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
              } else {
                index = save
              }
            }
            // A lone surrogate can't be held in a Swift string.
            out.append(Unicode.Scalar(unit) ?? "\u{FFFD}")
          default: return nil
          }
        default:
          if c.value < 0x20 { return nil }
          out.append(c)
        }
      }
      return nil
    }

    mutating func array(depth: Int) -> JSONValue? {
      index += 1
      var items: [JSONValue] = []
      skipSpace()
      if index < chars.count, chars[index] == "]" {
        index += 1
        return .array(items)
      }
      while true {
        skipSpace()
        guard let item = value(depth: depth + 1) else { return nil }
        items.append(item)
        skipSpace()
        guard index < chars.count else { return nil }
        if chars[index] == "," {
          index += 1
        } else if chars[index] == "]" {
          index += 1
          return .array(items)
        } else {
          return nil
        }
      }
    }

    mutating func object(depth: Int) -> JSONValue? {
      index += 1
      var members: [String: JSONValue] = [:]
      skipSpace()
      if index < chars.count, chars[index] == "}" {
        index += 1
        return .object(members)
      }
      while true {
        skipSpace()
        guard index < chars.count, chars[index] == "\"", let key = string() else { return nil }
        skipSpace()
        guard index < chars.count, chars[index] == ":" else { return nil }
        index += 1
        skipSpace()
        guard let member = value(depth: depth + 1) else { return nil }
        members[key] = member
        skipSpace()
        guard index < chars.count else { return nil }
        if chars[index] == "," {
          index += 1
        } else if chars[index] == "}" {
          index += 1
          return .object(members)
        } else {
          return nil
        }
      }
    }
  }
}
