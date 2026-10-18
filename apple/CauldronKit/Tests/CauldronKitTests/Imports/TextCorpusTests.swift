import Foundation
import Testing

@testable import CauldronKit

/// Ported from `apps/api/test/paste-corpus.test.ts`: messy recipes people paste from notes
/// apps, emails, chats, PDFs and blogs. Each `NN-name.txt` has an `NN-name.json` holding the
/// expected reading. Fixtures marked `needsModel` have no headings, so only the model reads
/// them reliably: the reader must not call them clear, which sends them to the model.
@Suite("Pasted recipe corpus")
struct PasteCorpusTests {
  static let names = (try? Fixtures.names(in: "paste", ext: "txt")) ?? []

  @Test func hasAtLeastTwentyFixtures() {
    #expect(Self.names.count >= 20)
  }

  @Test(arguments: names)
  func readsAsExpected(name: String) throws {
    let text = try Fixtures.text("paste/\(name).txt")
    let expected = try Fixtures.json("paste/\(name).json")
    let reading = TextRecipe.read(text)
    if expected["needsModel"] == .bool(true) {
      #expect(reading?.clarity != .clear, "\(name) is left for the model")
      return
    }
    #expect(reading?.clarity == .clear, "\(name) reads clearly")
    let recipe = try #require(reading).recipe
    #expect(recipe.title == expected["title"].string)
    #expect(recipe.ingredients.map(\.line) == expected["ingredients"].strings)
    #expect(recipe.steps.map(\.text) == expected["steps"].strings)
    if case .object(let sections) = expected["sections"] {
      var got: [String: String] = [:]
      for ingredient in recipe.ingredients {
        if let section = ingredient.section { got[ingredient.line] = section }
      }
      #expect(got == sections.compactMapValues(\.string))
    }
    if let servings = expected["servings"].number { #expect(recipe.servings == Int(servings)) }
  }
}

@Suite("Titles that look like page chrome or chatter")
struct TitleTests {
  @Test(arguments: [
    "Home-style chili", "So easy lemon cake", "Printable granola bars", "Okra and tomato stew",
  ])
  func keepsTheTitle(title: String) {
    let reading = TextRecipe.read("\(title)\n\nIngredients\n1 cup flour\n\nMethod\nMix it.")
    #expect(reading?.recipe.title == title)
  }

  @Test(arguments: [
    "Home » Recipes » Dinner", "Print", "Posted on May 3, 2026", "ok here is the recipe:",
  ])
  func skipsTheJunk(junk: String) {
    let reading = TextRecipe.read(
      "\(junk)\nDal\n\nIngredients\n1 cup lentils\n\nMethod\nSimmer.")
    #expect(reading?.recipe.title == "Dal")
  }
}

@Suite("Calls to action")
struct CallToActionTests {
  @Test func keepsRecipeLinesThatStartLikeOne() {
    let reading = TextRecipe.read(
      """
      Shortbread

      Ingredients
      200g flour
      100g butter

      Method
      Rub the butter into the flour.
      Save this dough for a second batch if you like.

      Notes
      Save it in an airtight tin for 3 days.
      """)
    #expect(
      reading?.recipe.steps.map(\.text).contains("Save this dough for a second batch if you like.")
        == true)
    #expect(reading?.recipe.notes == "Save it in an airtight tin for 3 days.")
  }
}

/// Ported from `apps/api/test/caption-corpus.test.ts`: Instagram and TikTok captions,
/// hand-written in the styles food posts use. Captions laid out with headings read without the
/// model; captions that aren't go to it; captions with no recipe fail as `noRecipe` (the social
/// importer reports that as `spokenOnly`).
@Suite("Caption corpus")
struct CaptionCorpusTests {
  static let names = (try? Fixtures.names(in: "captions", ext: "txt")) ?? []

  @Test func hasTwentyThreeCaptions() {
    #expect(Self.names.count == 23)
  }

  /// With only decoration above the ingredients there is no title to take: the caption goes to
  /// the model for one, or the cook fills it in.
  @Test func leavesTheTitleToTheModelWhenOnlyDecorationIsAboveTheRecipe() {
    let reading = TextRecipe.read(
      """
      ⇩ Full Recipe 🍳 ⇩
      #recipe #dinner

      Ingredients:
      - 2 eggs
      - 1 tbsp butter

      Method:
      1. Melt the butter.
      2. Scramble the eggs in it.
      """)
    #expect(reading?.recipe.title == nil)
    #expect(reading?.clarity == .rough)
  }

  @Test(arguments: names)
  func readsAsExpected(name: String) async throws {
    let want = try Fixtures.json("captions/\(name).json")
    let caption = try Fixtures.text("captions/\(name).txt")
    let reading = TextRecipe.read(caption)

    if want["noRecipe"] == .bool(true) {
      #expect(reading?.clarity != .clear)
      await #expect(throws: DistillError.failed(.noRecipe)) {
        try await Distill.fromText(caption, kind: .caption, extractor: nil)
      }
      return
    }
    if want["needsModel"] == .bool(true) {
      #expect(reading?.clarity != .clear)
      return
    }

    #expect(reading?.clarity == .clear)
    let recipe = try #require(reading).recipe
    if let title = want["title"].string { #expect(recipe.title == title) }
    #expect(recipe.ingredients.map(\.line) == want["ingredients"].strings)
    #expect(recipe.steps.map(\.text) == want["steps"].strings)
    if case .object(let sections) = want["sections"] {
      for (line, section) in sections {
        #expect(recipe.ingredients.first { $0.line == line }?.section == section.string, "\(line)")
      }
    }
  }
}

/// Ported from `apps/api/test/imports-text.test.ts`, "the text reader".
@Suite("The text reader")
struct TextReaderTests {
  @Test func keepsMethodStepsThatStartLikeATimeLine() {
    let reading = TextRecipe.read(
      """
      Onion soup

      Prep: 10 mins

      Ingredients
      - 4 onions, sliced
      - 1 litre stock

      Method
      - Cook the onions for 40 minutes until soft.
      - Bake for 10 minutes.
      - Cook pasta 10 minutes.
      """)
    #expect(reading?.recipe.prepMinutes == 10)
    #expect(reading?.recipe.cookMinutes == nil)
    #expect(
      reading?.recipe.steps.map(\.text) == [
        "Cook the onions for 40 minutes until soft.", "Bake for 10 minutes.",
        "Cook pasta 10 minutes.",
      ])
  }
}

/// The text reader over both corpora and a set of crafted texts, whole, against what the
/// reference reads.
@Suite("Text reader against the reference")
struct TextPinnedTests {
  static let corpus: [JSONValue] = (try? Fixtures.json("pinned/text-corpus.json").items) ?? []
  static let crafted: [JSONValue] = (try? Fixtures.json("pinned/text-crafted.json").items) ?? []

  private static func reading(_ text: String) -> JSONValue {
    guard let reading = TextRecipe.read(text) else { return .null }
    return .object([
      "clarity": .string(reading.clarity == .clear ? "clear" : "rough"),
      "recipe": .of(reading.recipe),
    ])
  }

  @Test(arguments: corpus)
  func readsTheCorpusLikeTheReference(entry: JSONValue) throws {
    let name = try #require(entry["name"].string)
    let text = try Fixtures.text(name)
    expectSame(Self.reading(text), entry["reading"], name)
  }

  @Test(arguments: Array(crafted.enumerated()).map { Crafted(index: $0.offset, entry: $0.element) })
  func readsCraftedTextLikeTheReference(case crafted: Crafted) throws {
    let text = try #require(crafted.entry["text"].string)
    expectSame(
      Self.reading(text), crafted.entry["reading"],
      "text #\(crafted.index): \(text.debugDescription)")
  }

  struct Crafted: Sendable, CustomTestStringConvertible {
    let index: Int
    let entry: JSONValue
    var testDescription: String { "#\(index) \(entry["text"].string?.debugDescription ?? "")" }
  }
}
