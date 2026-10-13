import Foundation
import Testing

@testable import CauldronKit

/// Ported from `apps/api/test/web-corpus.test.ts`: the website importer against saved pages,
/// hand-written to look like what popular recipe sites publish, with no network. Each
/// `NN-name.html` has an `NN-name.json` of what a cook should get back. Pages with structured
/// recipe data are read without the model; the rest go to a fake model, and the readable text
/// it is sent must hold the recipe and none of the page chrome.

private let flourRecipe = ExtractedRecipe(
  ingredients: [ExtractedLine(line: "1 cup flour", section: nil, unsure: false)],
  steps: [ExtractedStep(text: "Mix and bake.", section: nil, unsure: false)])

private func pageURL(_ name: String) -> String {
  "https://example.com/recipes/" + name.replacing(/^\d+-/, with: "")
}

@Suite("Website corpus")
struct WebCorpusTests {
  static let names = (try? Fixtures.names(in: "web", ext: "html")) ?? []

  @Test func hasThirtyPages() {
    #expect(Self.names.count == 30)
  }

  @Test(arguments: names)
  func readsThePage(name: String) async throws {
    let want = try Fixtures.json("web/\(name).json")
    let model = FakeExtractor(recipe: flourRecipe)
    let got = try await Distill.fromHTML(
      try Fixtures.text("web/\(name).html"), url: pageURL(name), extractor: model)
    let recipe = got.recipe

    #expect(got.extractor.rawValue == want["extractor"].string)
    if want["extractor"].string == "model" {
      #expect(await model.calls.count == 1)
      #expect(await model.calls.last?.kind == .page)
      #expect(got.raw == (await model.calls.last?.text))
    } else {
      #expect(await model.calls.count == 0)
      #expect(got.raw == nil)
      #expect(got.usage == nil)
    }

    if let title = want["title"].string { #expect(recipe.title == title) }
    if want["ingredients"] != .null {
      #expect(recipe.ingredients.map(\.line) == want["ingredients"].strings)
    }
    if want["steps"] != .null { #expect(recipe.steps.map(\.text) == want["steps"].strings) }
    if case .object(let sections) = want["sections"] {
      for (text, section) in sections {
        #expect(recipe.steps.first { $0.text == text }?.section == section.string, "\(text)")
      }
    }
    if let servings = want["servings"].number { #expect(recipe.servings == Int(servings)) }
    if let n = want["prepMinutes"].number { #expect(recipe.prepMinutes == Int(n)) }
    if let n = want["cookMinutes"].number { #expect(recipe.cookMinutes == Int(n)) }
    if let n = want["totalMinutes"].number { #expect(recipe.totalMinutes == Int(n)) }
    if let author = want["author"].string { #expect(recipe.author == author) }
    if let siteName = want["siteName"].string { #expect(recipe.siteName == siteName) }
    if let imageUrl = want["imageUrl"].string { #expect(recipe.imageUrl == imageUrl) }
    if let canonicalUrl = want["canonicalUrl"].string {
      #expect(recipe.canonicalUrl == canonicalUrl)
    }
    if want["tags"] != .null { #expect(recipe.tags == want["tags"].strings) }

    for text in want["textIncludes"].strings {
      #expect(got.raw?.contains(text) == true, "should include \(text)")
    }
    for text in want["textExcludes"].strings {
      #expect(got.raw?.contains(text) == false, "should not include \(text)")
    }
  }

  @Test func keepsTheIngredientsOfAPageWithNoMethodWhenThereIsNoModel() async throws {
    let got = try await Distill.fromHTML(
      try Fixtures.text("web/20-jsonld-ingredients-only.html"), url: pageURL("20-x"),
      extractor: nil)
    #expect(got.extractor == .jsonLD)
    #expect(
      got.recipe.ingredients.map(\.line) == [
        "4 tomatoes, diced", "1/2 onion, minced", "1 jalapeno, minced", "1/4 cup cilantro",
        "1 lime, juiced",
      ])
    #expect(got.recipe.steps.isEmpty)
    #expect(got.recipe.title == "Pico de Gallo")
    #expect(got.recipe.unsure.contains(.title))
  }

  @Test func failsWithNoRecipeForAPageWithoutStructuredDataAndNoModel() async {
    await #expect(throws: DistillError.failed(.noRecipe)) {
      try await Distill.fromHTML(
        "<html><body><nav>Home</nav><p>Our story, and a photo of the shop.</p></body></html>",
        url: "https://example.com/recipes/x", extractor: nil)
    }
  }
}

/// Every page's whole result, pinned to what the reference produced under Bun.
@Suite("Website corpus against the reference")
struct WebCorpusPinnedTests {
  static let entries: [JSONValue] = (try? Fixtures.json("pinned/web-drafts.json").items) ?? []

  @Test func coversEveryPage() {
    #expect(Self.entries.count == 30)
  }

  @Test(arguments: entries)
  func matchesTheReferenceDraft(entry: JSONValue) async throws {
    let name = try #require(entry["name"].string)
    let url = try #require(entry["url"].string)
    let got = try await Distill.fromHTML(
      try Fixtures.text("web/\(name).html"), url: url,
      extractor: FakeExtractor(recipe: flourRecipe))
    let sourceUrl = got.recipe.canonicalUrl ?? url
    let draft = ImportDraft(
      reading: got.recipe,
      from: DraftSource(source: .web, sourceUrl: Distill.normalizeURL(sourceUrl)))

    #expect(got.extractor.rawValue == entry["extractor"].string, "\(name) extractor")
    #expect(got.raw == entry["raw"].string, "\(name) raw")
    expectSame(.of(got.recipe), entry["recipe"], "\(name) recipe")
    #expect(sourceUrl == entry["sourceUrl"].string, "\(name) source link")
    expectSame(.of(draft), entry["draft"], "\(name) draft")
  }
}

extension JSONValue: CustomTestStringConvertible {
  public var testDescription: String { self["name"].string ?? "\(self)" }
}
