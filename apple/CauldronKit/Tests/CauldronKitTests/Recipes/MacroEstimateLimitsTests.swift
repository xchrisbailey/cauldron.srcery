import CauldronKit
import Testing

/// The limits a macro estimate's input is held to, as the web editor and `withMacros` in
/// `apps/api/src/imports/distill.ts` hold it.
@Suite("Macro estimate limits")
struct MacroEstimateLimitsTests {
  @Test func linesAreTrimmedAndBlankOnesDropped() {
    let input = MacroEstimateInput.limited(
      title: "Soup", servings: 4, lines: ["  2 onions ", "", "   ", "400 g tomatoes"])
    #expect(
      input
        == MacroEstimateInput(
          title: "Soup", servings: 4, ingredients: ["2 onions", "400 g tomatoes"]))
  }

  @Test func noLineWithAnythingInItIsNoAsk() {
    #expect(MacroEstimateInput.limited(title: "Soup", servings: 4, lines: []) == nil)
    #expect(MacroEstimateInput.limited(title: "Soup", servings: 4, lines: ["", "  "]) == nil)
  }

  @Test func aLongLineIsCutToTheLineLimit() throws {
    let long = String(repeating: "a", count: RecipeLimits.line + 500)
    let input = try #require(MacroEstimateInput.limited(title: nil, servings: nil, lines: [long]))
    #expect(input.ingredients == [String(repeating: "a", count: RecipeLimits.line)])
  }

  @Test func atMostTheLimitOfLinesIsKept() throws {
    let lines = (1...(RecipeLimits.ingredients + 40)).map { "\($0) eggs" }
    let input = try #require(MacroEstimateInput.limited(title: nil, servings: nil, lines: lines))
    #expect(input.ingredients.count == RecipeLimits.ingredients)
    #expect(input.ingredients.first == "1 eggs")
    #expect(input.ingredients.last == "\(RecipeLimits.ingredients) eggs")
  }

  @Test func blankLinesDoNotCountAgainstTheLimit() throws {
    let lines = Array(repeating: "", count: 500) + ["1 egg"]
    let input = try #require(MacroEstimateInput.limited(title: nil, servings: nil, lines: lines))
    #expect(input.ingredients == ["1 egg"])
  }

  @Test func servingsOutsideTheLimitsAreLeftOut() throws {
    func servings(_ value: Int?) throws -> Int? {
      try #require(MacroEstimateInput.limited(title: nil, servings: value, lines: ["1 egg"]))
        .servings
    }
    #expect(try servings(1) == 1)
    #expect(try servings(RecipeLimits.servings) == RecipeLimits.servings)
    #expect(try servings(0) == nil)
    #expect(try servings(-3) == nil)
    #expect(try servings(RecipeLimits.servings + 1) == nil)
    #expect(try servings(nil) == nil)
  }

  @Test func theTitleIsTrimmedCutAndLeftOutWhenBlank() throws {
    func title(_ value: String?) throws -> String? {
      try #require(MacroEstimateInput.limited(title: value, servings: nil, lines: ["1 egg"])).title
    }
    #expect(try title("  Soup  ") == "Soup")
    #expect(try title("   ") == nil)
    #expect(try title(nil) == nil)
    let long = String(repeating: "t", count: RecipeLimits.title + 10)
    #expect(try title(long) == String(repeating: "t", count: RecipeLimits.title))
  }
}
