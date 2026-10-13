import Foundation
import Testing

@testable import CauldronKit

/// Crafted pages and captions, read by the reference under Bun. They reach what the saved
/// corpus doesn't: how two HTML parsers disagree about unclosed tags and entities, what counts
/// as noise, odd structured data.
@Suite("Pages against the reference")
struct PinnedPageTests {
  static let pages: [JSONValue] = (try? Fixtures.json("pinned/pages.json").items) ?? []

  private static let flourRecipe = ExtractedRecipe(
    ingredients: [ExtractedLine(line: "1 cup flour", section: nil, unsure: false)],
    steps: [ExtractedStep(text: "Mix and bake.", section: nil, unsure: false)])

  /// Pages the reference could not even parse: it throws on a document with no `<html>`. The
  /// Swift reader has a body for any input, so it reads these.
  private static func referenceThrew(_ entry: JSONValue) -> Bool {
    entry["result"]["threw"] == .bool(true)
  }

  @Test(arguments: pages)
  func readsThePageLikeTheReference(entry: JSONValue) async throws {
    let name = try #require(entry["name"].string)
    let html = try #require(entry["html"].string)
    let url = try #require(entry["url"].string)
    let model: FakeExtractor? =
      entry["model"].string == "none" ? nil : FakeExtractor(recipe: Self.flourRecipe)

    if Self.referenceThrew(entry) {
      // Nothing to compare: the reference crashes the job. Reading it must not.
      _ = try? await Distill.fromHTML(html, url: url, extractor: model)
      return
    }

    let ok = entry["result"]["ok"]
    do {
      let got = try await Distill.fromHTML(html, url: url, extractor: model)
      #expect(ok != .null, "\(name) should have failed as \(entry["result"]["failure"])")
      expectSame(.of(got.recipe), ok["recipe"], "\(name) recipe")
      #expect(got.extractor.rawValue == ok["extractor"].string, "\(name) extractor")
      #expect(got.raw == ok["raw"].string, "\(name) raw")
      #expect((got.usage != nil) == (ok["hasUsage"] == .bool(true)), "\(name) usage")
    } catch let error as DistillError {
      #expect(error.code?.rawValue == entry["result"]["failure"].string, "\(name) failure")
    }
  }

  @Test(arguments: pages)
  func readsThePagesMetaLikeTheReference(entry: JSONValue) throws {
    guard entry["meta"] != .string("__threw__") else { return }
    let html = try #require(entry["html"].string)
    let url = try #require(entry["url"].string)
    expectSame(
      .of(PageText.pageMeta(HTMLDocument(html), base: url)), entry["meta"],
      "\(entry["name"]) meta")
  }

  @Test(arguments: pages)
  func readsThePagesTextLikeTheReference(entry: JSONValue) throws {
    guard entry["readable"] != .string("__threw__") else { return }
    let html = try #require(entry["html"].string)
    #expect(
      PageText.readable(HTMLDocument(html), max: 40000) == entry["readable"].string,
      "\(entry["name"])")
  }

  @Test func readsTextFromADocumentWithNoHTMLElement() {
    // The reference throws on these; here the text is the page.
    #expect(
      PageText.readable(HTMLDocument("Ingredients\n1 onion\nMethod\nChop it."), max: 1000)
        == "Ingredients 1 onion Method Chop it.")
    #expect(PageText.readable(HTMLDocument(""), max: 1000) == "")
  }
}

@Suite("Posts against the reference")
struct PinnedSocialTests {
  static let social: JSONValue = (try? Fixtures.json("pinned/social.json")) ?? .null

  struct Case: Sendable, CustomTestStringConvertible {
    let entry: JSONValue
    var testDescription: String {
      (entry["html"].string ?? entry["json"].string ?? "").debugDescription
    }
  }

  @Test(arguments: social["og"].items.map(Case.init))
  func readsOpenGraph(case c: Case) throws {
    let source = try #require(ImportSource(rawValue: c.entry["source"].string ?? ""))
    let got = Distill.readOpenGraph(html: c.entry["html"].string ?? "", source: source)
    // The reference kept a relative og:image as written ("/rel.jpg"), which nothing can fetch.
    // Here an image link is http(s) or nil, so that one pin is read as nil.
    var want = c.entry["out"]
    if case .object(var object) = want, let image = want["imageUrl"].string,
      !image.hasPrefix("http")
    {
      object["imageUrl"] = .null
      want = .object(object)
    }
    expectSame(got.map { .of($0) } ?? .null, want, "og \(c.testDescription)")
  }

  @Test(arguments: social["oembed"].items.map(Case.init))
  func readsOEmbed(case c: Case) {
    let got = Distill.readOEmbed(c.entry["json"].string ?? "")
    expectSame(got.map { .of($0) } ?? .null, c.entry["out"], "oembed \(c.testDescription)")
  }
}
