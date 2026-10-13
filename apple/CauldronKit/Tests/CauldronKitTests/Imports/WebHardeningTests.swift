import Foundation
import Testing

@testable import CauldronKit

private let base = "https://cook.example/recipes/x"

private func ld(_ json: String) -> String {
  "<script type=\"application/ld+json\">\(json)</script>"
}

/// Ported from `apps/api/test/schema-org-macros.test.ts`.
@Suite("macrosOf")
struct SchemaOrgMacrosTests {
  private func object(_ pairs: [String: JSONValue]) -> JSONValue { .object(pairs) }

  @Test func readsNutritionInformationPerServing() {
    let got = SchemaOrg.macros(
      object([
        "@type": .string("NutritionInformation"), "calories": .string("1,250 kcal"),
        "proteinContent": .string("31.5 g"), "carbohydrateContent": .string("12,5 g"),
        "fatContent": .number(18),
      ]))
    #expect(got == Macros(calories: 1250, protein: 31.5, carbs: 12.5, fat: 18))
  }

  @Test func leavesWhatsMissingUnknown() {
    #expect(
      SchemaOrg.macros(object(["calories": .string("240 calories")]))
        == Macros(calories: 240, protein: nil, carbs: nil, fat: nil))
  }

  @Test func returnsNothingWhenThereIsNothingToRead() {
    #expect(SchemaOrg.macros(nil) == nil)
    #expect(SchemaOrg.macros(object(["servingSize": .string("1 bowl")])) == nil)
    #expect(SchemaOrg.macros(.string("lots")) == nil)
  }
}

/// Ported from `apps/api/test/web-hardening.test.ts`: hostile and awkward pages. Nothing here
/// may hang, blow the stack, or credit a recipe to another site.
@Suite("Hostile pages")
struct HostilePageTests {
  @Test func readsAHugeRunOfDigitsAsNoDurationQuickly() {
    let clock = ContinuousClock()
    let start = clock.now
    #expect(SchemaOrg.isoMinutes(.string(String(repeating: "1", count: 200_000))) == nil)
    #expect(
      SchemaOrg.isoMinutes(.string(String(repeating: "1", count: 200_000) + " minutes")) == nil)
    #expect(start.duration(to: clock.now) < .milliseconds(100))
    #expect(SchemaOrg.isoMinutes(.string("1 hr 20 mins")) == 80)
    #expect(SchemaOrg.isoMinutes(.string("PT1H20M")) == 80)
  }

  @Test func skipsAJSONLDScriptOfNewlinesQuickly() {
    let clock = ContinuousClock()
    let start = clock.now
    let document = HTMLDocument(
      "<script type=\"application/ld+json\">\(String(repeating: "\n", count: 200_000)){}</script>")
    #expect(SchemaOrg.jsonLDRecipe(document, base: base) == nil)
    #expect(start.duration(to: clock.now) < .milliseconds(500))
  }

  @Test func walksDeeplyNestedMarkupWithoutRecursion() {
    let depth = 20_000
    let html =
      "<body><article>\(String(repeating: "<div>", count: depth))1 onion\(String(repeating: "</div>", count: depth))</article></body>"
    #expect(PageText.readable(HTMLDocument(html), max: 1000) == "1 onion")
  }

  @Test func refusesJSONLDBiggerThanAMegabyte() {
    let big = "{\"@type\":\"Recipe\",\"name\":\"\(String(repeating: "x", count: 1_100_000))\"}"
    #expect(SchemaOrg.jsonLDRecipe(HTMLDocument("<head>\(ld(big))</head>"), base: base) == nil)
  }
}

@Suite("Structured data")
struct StructuredDataTests {
  @Test func doesntSplitAMicrodataStepOnSourceLineBreaks() {
    let document = HTMLDocument(
      """
      <div itemscope itemtype="https://schema.org/Recipe">
            <h1 itemprop="name">Pancakes</h1>
            <span itemprop="recipeIngredient">1 cup flour</span>
            <div itemprop="recipeInstructions">
              <p>Whisk the eggs and milk until
                smooth and pale.</p>
              <p>Fry in butter.</p>
            </div>
          </div>
      """)
    #expect(
      SchemaOrg.microdataRecipe(document, base: base)?.steps.map(\.text) == [
        "Whisk the eggs and milk until smooth and pale.", "Fry in butter.",
      ])
  }

  @Test func prefersFullMicrodataOverAStubJSONLDRecipe() async throws {
    let html = """
      <head>\(ld(#"{"@type":"Recipe","name":"Pancakes","image":"/p.jpg"}"#))</head>
            <body><div itemscope itemtype="https://schema.org/Recipe">
              <h1 itemprop="name">Pancakes</h1>
              <li itemprop="recipeIngredient">1 cup flour</li>
              <ol itemprop="recipeInstructions"><li>Mix.</li><li>Fry.</li></ol>
            </div></body>
      """
    let read = try await Distill.fromHTML(html, url: base, extractor: nil)
    #expect(read.extractor == .microdata)
    #expect(read.recipe.ingredients.map(\.line) == ["1 cup flour"])
  }

  @Test func onlyKeepsACanonicalLinkOnThePagesOwnSite() async throws {
    let recipe =
      #"{"@type":"Recipe","name":"Dal","recipeIngredient":["1 cup lentils"],"recipeInstructions":["Simmer."]}"#
    let elsewhere = try await Distill.fromHTML(
      "<head>\(ld(recipe))<link rel=\"canonical\" href=\"https://other.example/dal\"></head>",
      url: base, extractor: nil)
    #expect(elsewhere.recipe.canonicalUrl == nil)
    let own = try await Distill.fromHTML(
      "<head>\(ld(recipe))<link rel=\"canonical\" href=\"https://www.cook.example/dal\"></head>",
      url: base, extractor: nil)
    #expect(own.recipe.canonicalUrl == "https://www.cook.example/dal")
  }

  @Test func acceptsASubdomainOfThePagesSiteAndTheOtherWayRound() {
    #expect(Distill.sameSite("https://blog.cook.example/x", "https://cook.example/y") != nil)
    #expect(Distill.sameSite("https://cook.example/x", "https://blog.cook.example/y") != nil)
    #expect(Distill.sameSite("https://notcook.example/x", "https://cook.example/y") == nil)
    #expect(
      Distill.sameSite("https://cook.example.evil.example/x", "https://cook.example/y") == nil)
    #expect(Distill.sameSite("", "https://cook.example/y") == nil)
    #expect(Distill.sameSite(nil, "https://cook.example/y") == nil)
  }
}

/// Ported from the same file's "fetching a page": the charset a response declares, then the
/// one the page does.
@Suite("Decoding a fetched page")
struct DecodeTests {
  private static let latin1: [UInt8] =
    Array("<p>Cr".utf8) + [0xE8] + Array("me br".utf8)

  private func page(_ bytes: [UInt8], type: String) async throws -> String {
    let fetcher = FakeFetcher([
      base: .page(FetchedPage(bytes: Data(bytes), contentType: type, url: base))
    ])
    return try await Distill.fetchPage(base, fetcher, DistillOptions()).html
  }

  @Test func decodesTheCharsetTheResponseDeclares() async throws {
    let html = try await page(Self.latin1, type: "text/html; charset=iso-8859-1")
    #expect(html.contains("Crème"))
  }

  @Test func decodesTheCharsetThePageDeclaresWhenTheResponseDoesnt() async throws {
    let bytes = Array(#"<meta charset="windows-1252">"#.utf8) + Self.latin1
    let html = try await page(bytes, type: "text/html")
    #expect(html.contains("Crème"))
  }
}
