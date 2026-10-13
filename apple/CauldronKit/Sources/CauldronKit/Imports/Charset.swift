import Foundation

// Turning a fetched page's bytes into text (`decodeHtml` in the API): the charset the response
// declares, else the one the page declares in its first 2 KB, else UTF-8, and UTF-8 again for
// a name nobody knows. `TextDecoder` follows the WHATWG Encoding Standard, where "latin1" and
// "ascii" mean windows-1252, so those labels are decoded here the same way.

enum Charset {
  private static let declaredInHeader = JSRegex(
    "charset=[\"']?([\(JS.word)-]+)", ignoreCase: true)
  private static let declaredInPage = JSRegex(
    "<meta[^>]+charset=[\"']?([\(JS.word)-]+)", ignoreCase: true)

  /// The text of a response or page body.
  static func decodeHTML(_ bytes: Data, contentType: String?) -> String {
    let declared = contentType.flatMap { declaredInHeader.firstMatch(in: $0)?.group(1) }
    var label = declared
    if label == nil {
      // The page is sniffed as windows-1252, which never fails on a byte.
      let head = decodeWindows1252(bytes.prefix(2048))
      label = declaredInPage.firstMatch(in: head)?.group(1)
    }
    return decode(bytes, label: label ?? "utf-8") ?? decodeUTF8(bytes)
  }

  /// `new TextDecoder(label).decode(bytes)`, or nil for a label it doesn't know.
  static func decode(_ bytes: Data, label: String) -> String? {
    let name = label.lowercased().jsTrimmed()
    switch name {
    case "utf-8", "utf8", "unicode-1-1-utf-8", "unicode11utf8", "unicode20utf8", "x-unicode20utf8":
      return decodeUTF8(bytes)
    case "windows-1252", "cp1252", "x-cp1252", "iso-8859-1", "iso8859-1", "iso88591",
      "iso_8859-1", "iso_8859-1:1987", "iso-ir-100", "latin1", "l1", "ascii", "us-ascii",
      "ansi_x3.4-1968", "cp819", "ibm819", "csisolatin1", "iso8859_1":
      return decodeWindows1252(bytes)
    case "utf-16", "utf-16le", "ucs-2", "unicode", "csunicode", "iso-10646-ucs-2",
      "unicodefeff":
      return decodeUTF16(bytes, bigEndian: false)
    case "utf-16be", "unicodefffe":
      return decodeUTF16(bytes, bigEndian: true)
    default:
      guard let encoding = foundationEncodings[name] else { return nil }
      return String(data: bytes, encoding: encoding)
    }
  }

  private static func decodeUTF8(_ bytes: Data) -> String {
    var body = bytes[...]
    if body.starts(with: [0xEF, 0xBB, 0xBF]) { body = body.dropFirst(3) }
    return String(decoding: body, as: UTF8.self)
  }

  private static func decodeUTF16(_ bytes: Data, bigEndian: Bool) -> String {
    var body = Array(bytes)
    let bom: [UInt8] = bigEndian ? [0xFE, 0xFF] : [0xFF, 0xFE]
    if body.starts(with: bom) { body.removeFirst(2) }
    var units: [UInt16] = []
    var i = 0
    while i + 1 < body.count {
      let pair = (body[i], body[i + 1])
      units.append(
        bigEndian ? UInt16(pair.0) << 8 | UInt16(pair.1) : UInt16(pair.1) << 8 | UInt16(pair.0))
      i += 2
    }
    // A stray last byte is one replacement character.
    var text = String(decoding: units, as: UTF16.self)
    if i < body.count { text += "\u{FFFD}" }
    return text
  }

  /// The C1 range of windows-1252, where it differs from ISO 8859-1.
  private static let windows1252High: [UInt32] = [
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160,
    0x2039, 0x0152, 0x008D, 0x017D, 0x008F, 0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022,
    0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
  ]

  private static func decodeWindows1252(_ bytes: some Sequence<UInt8>) -> String {
    var out = String.UnicodeScalarView()
    for byte in bytes {
      let value = (0x80...0x9F).contains(byte) ? windows1252High[Int(byte) - 0x80] : UInt32(byte)
      if let scalar = Unicode.Scalar(value) { out.append(scalar) }
    }
    return String(out)
  }

  /// The other names pages declare that Foundation can read. A name outside this table, or
  /// bytes Foundation can't read in that encoding, are read as UTF-8 instead.
  private static let foundationEncodings: [String: String.Encoding] = [
    "shift_jis": .shiftJIS, "shift-jis": .shiftJIS, "sjis": .shiftJIS, "x-sjis": .shiftJIS,
    "ms_kanji": .shiftJIS, "windows-31j": .shiftJIS, "euc-jp": .japaneseEUC,
    "iso-2022-jp": .iso2022JP, "iso-8859-2": .isoLatin2, "windows-1250": .windowsCP1250,
    "windows-1251": .windowsCP1251, "windows-1253": .windowsCP1253,
    "windows-1254": .windowsCP1254, "gbk": String.Encoding(rawValue: 0x8000_0632),
    "gb2312": String.Encoding(rawValue: 0x8000_0632),
    "gb18030": String.Encoding(rawValue: 0x8000_0632),
    "big5": String.Encoding(rawValue: 0x8000_0A03),
    "euc-kr": String.Encoding(rawValue: 0x8000_0940),
  ]
}
