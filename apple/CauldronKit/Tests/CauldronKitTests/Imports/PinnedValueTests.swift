import Foundation
import Testing

@testable import CauldronKit

/// Values the reference gave under Bun for a spread of inputs, including ones its own tests
/// don't reach.
@Suite("Reference values")
struct PinnedValueTests {
  static let values: JSONValue = (try? Fixtures.json("pinned/values.json")) ?? .null

  struct Case: Sendable, CustomTestStringConvertible {
    let entry: JSONValue
    var testDescription: String { "\(entry["in"])\(entry["contentType"])" }
  }

  static func cases(_ key: String) -> [Case] { values[key].items.map { Case(entry: $0) } }

  @Test(arguments: cases("iso"))
  func readsDurations(case c: Case) {
    let got = SchemaOrg.isoMinutes(c.entry["in"])
    // A hostile "99999999999999999999H" is held at 2^53 here; the reference's number is bigger
    // and is refused downstream all the same.
    let want = c.entry["out"].number.map { Swift.min($0, 9_007_199_254_740_992) }
    #expect(got.map(Double.init) == want, "\(c.entry["in"])")
  }

  @Test(arguments: cases("macros"))
  func readsNutrition(case c: Case) {
    let input: JSONValue? = c.entry["in"] == .string("__undefined__") ? nil : c.entry["in"]
    let got = SchemaOrg.macros(input).map { JSONValue.of($0) } ?? .null
    expectSame(got, c.entry["out"], "\(c.entry["in"])")
  }

  @Test(arguments: cases("plain"))
  func stripsMarkupAndEntities(case c: Case) throws {
    let input = try #require(c.entry["in"].string)
    #expect(PageText.plain(input) == c.entry["out"].string, "\(input.debugDescription)")
  }

  @Test(arguments: cases("decode"))
  func decodesTheCharset(case c: Case) {
    let bytes = Data(c.entry["bytes"].items.compactMap { $0.number.map { UInt8($0) } })
    let got = Charset.decodeHTML(bytes, contentType: c.entry["contentType"].string)
    #expect(got == c.entry["out"].string, "\(c.entry["contentType"])")
  }
}

/// Links: `new URL` against the hand-written WHATWG reader.
@Suite("Reference links")
struct PinnedLinkTests {
  static let urls: JSONValue = (try? Fixtures.json("pinned/urls.json")) ?? .null

  struct Case: Sendable, CustomTestStringConvertible {
    let entry: JSONValue
    var testDescription: String { "\(entry["in"].string ?? "\(entry)")" }
  }

  static func cases(_ key: String) -> [Case] { urls[key].items.map { Case(entry: $0) } }

  @Test(arguments: cases("normalize"))
  func normalizes(case c: Case) throws {
    let input = try #require(c.entry["in"].string)
    #expect(Distill.normalizeURL(input) == c.entry["out"].string, "\(input.debugDescription)")
  }

  @Test(arguments: cases("classify"))
  func classifies(case c: Case) throws {
    let input = try #require(c.entry["in"].string)
    #expect(Distill.classify(input).rawValue == c.entry["out"].string, "\(input)")
  }

  @Test(arguments: cases("absolute"))
  func resolvesLinks(case c: Case) throws {
    let href = try #require(c.entry["href"].string)
    let base = try #require(c.entry["base"].string)
    #expect(
      PageText.absolute(href, base: base) == c.entry["out"].string,
      "\(href.debugDescription) against \(base)")
  }

  @Test(arguments: cases("tracking"))
  func stripsTracking(case c: Case) {
    #expect(
      PageText.withoutTracking(c.entry["in"].string) == c.entry["out"].string,
      "\(c.entry["in"])")
  }

  @Test(arguments: cases("posts"))
  func findsThePost(case c: Case) throws {
    let source = try #require(ImportSource(rawValue: c.entry["source"].string ?? ""))
    let url = try #require(c.entry["url"].string)
    #expect(Distill.canonicalPost(source, url: url) == c.entry["out"].string, "\(url)")
  }
}

@Suite("Reference drafts")
struct PinnedDraftTests {
  static let drafts: [JSONValue] = (try? Fixtures.json("pinned/drafts.json").items) ?? []

  @Test(arguments: drafts)
  func tidiesLikeTheReference(entry: JSONValue) throws {
    let recipe = try JSONDecoder().decode(
      ExtractedRecipe.self, from: Data("\(try jsonText(entry["recipe"]))".utf8))
    let source = entry["source"]
    let draft = ImportDraft(
      reading: recipe,
      from: DraftSource(
        source: try #require(ImportSource(rawValue: source["source"].string ?? "")),
        sourceUrl: source["sourceUrl"].string, photoKey: source["photoKey"].string))
    expectSame(.of(draft), entry["draft"], entry["name"].string ?? "")
  }

  /// JSON text for a value (the decoder wants bytes).
  private func jsonText(_ value: JSONValue) throws -> String {
    switch value {
    case .null: return "null"
    case .bool(let bool): return bool ? "true" : "false"
    case .number(let number): return jsString(number)
    case .string(let string):
      let data = try JSONEncoder().encode([string])
      let text = try #require(String(data: data, encoding: .utf8))
      return String(text.dropFirst().dropLast())
    case .array(let items): return "[" + (try items.map(jsonText).joined(separator: ",")) + "]"
    case .object(let object):
      return "{"
        + (try object.map { try jsonText(.string($0.key)) + ":" + jsonText($0.value) }
          .joined(separator: ",")) + "}"
    }
  }
}
