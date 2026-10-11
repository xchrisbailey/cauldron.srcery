import CauldronKit
import Foundation
import Testing

/// No cases in the TypeScript suite cover these helpers; the expected values are what the
/// reference (`Tracker.ts`) returns when run under Bun.
private let chili = UUID(uuidString: "8f0c2a4e-1b6d-4c1e-9a53-0d2f6b7a9c11")!

private func entry(_ macros: Macros, servings: Double) -> DiaryEntry {
  DiaryEntry(
    id: UUID(), date: LocalDate("2026-10-05")!, slot: .lunch, name: "Lunch", amount: nil,
    servings: servings, macros: macros, source: .manual, recipeId: nil, position: 0)
}

@Suite("entryTotals and dayTotals")
struct TotalsTests {
  @Test func multipliesPerServingNumbersByServingsAndCountsUnknownsAsNothing() {
    let macros = Macros(calories: 520, protein: 31, carbs: nil, fat: 12.5)
    #expect(
      entryTotals(macros: macros, servings: 1.5)
        == MacroTotals(calories: 780, protein: 46.5, carbs: 0, fat: 18.75))
    #expect(entryTotals(macros: .none, servings: 3) == .zero)
  }

  @Test func readsAnEntryOrAQuickFood() {
    let macros = Macros(calories: 520, protein: 31, carbs: nil, fat: 12.5)
    #expect(entryTotals(entry(macros, servings: 1.5)) == entryTotals(macros: macros, servings: 1.5))
    let food = QuickFood(
      name: "Chili", amount: nil, servings: 1.5, macros: macros, source: .recipe, recipeId: chili)
    #expect(entryTotals(food) == entryTotals(macros: macros, servings: 1.5))
  }

  @Test func addsUpADay() {
    let entries = [
      entry(Macros(calories: 100, protein: 10, carbs: nil, fat: 2), servings: 2),
      entry(Macros(calories: 50.5, protein: nil, carbs: 7, fat: nil), servings: 0.5),
    ]
    #expect(dayTotals(entries) == MacroTotals(calories: 225.25, protein: 20, carbs: 3.5, fat: 4))
    #expect(dayTotals([DiaryEntry]()) == .zero)
  }
}

@Suite("hasGaps")
struct HasGapsTests {
  @Test func isTrueWhenAnyNumberIsUnknown() {
    #expect(hasGaps(Macros(calories: 1, protein: 2, carbs: 3, fat: 4)) == false)
    #expect(hasGaps(Macros(calories: 1, protein: 2, carbs: nil, fat: 4)))
    #expect(hasGaps(Macros(calories: 1, protein: 2, carbs: 0, fat: 4)) == false)
    #expect(hasGaps(.none))
  }

  @Test func readsAnEntry() {
    #expect(hasGaps(entry(Macros(calories: 1), servings: 1)))
  }
}

@Suite("quickFoodKey")
struct QuickFoodKeyTests {
  @Test func matchesARecipeByItsId() {
    #expect(
      quickFoodKey(recipeId: chili, name: "Chili", amount: nil)
        == "recipe:\(chili.uuidString.lowercased())")
  }

  @Test func matchesAFoodByNameAndAmountIgnoringCaseAndEdgeSpace() {
    #expect(
      quickFoodKey(recipeId: nil, name: "  Greek Yogurt ", amount: " 1 CUP ")
        == "food:greek yogurt|1 cup")
    #expect(quickFoodKey(recipeId: nil, name: "Egg", amount: nil) == "food:egg|")
    #expect(quickFoodKey(recipeId: nil, name: "Egg", amount: "   ") == "food:egg|")
  }

  @Test func trimsExactlyWhatJavaScriptTrims() {
    // The reference's `trim()` strips U+FEFF but keeps U+0085, the opposite of Foundation.
    #expect(
      quickFoodKey(recipeId: nil, name: "  Greek Yoghurt\u{FEFF}", amount: " 1 CUP ")
        == "food:greek yoghurt|1 cup")
    #expect(quickFoodKey(recipeId: nil, name: "\u{85}Toast", amount: nil) == "food:\u{85}toast|")
    #expect(
      quickFoodKey(recipeId: nil, name: "\u{A0}Toast\u{A0}", amount: "\u{2003} 2 slices\u{3000}")
        == "food:toast|2 slices")
    #expect(
      quickFoodKey(recipeId: nil, name: "\u{180E}Toast", amount: nil) == "food:\u{180E}toast|")
    #expect(
      quickFoodKey(recipeId: nil, name: "\u{200B}Toast", amount: nil) == "food:\u{200B}toast|")
    #expect(
      quickFoodKey(recipeId: nil, name: "\u{2028}Toast\u{2029}", amount: "\u{0B}1\u{0C}")
        == "food:toast|1")
    #expect(
      quickFoodKey(recipeId: nil, name: "\u{1680}Toast\u{202F}", amount: "\u{205F}1")
        == "food:toast|1")
    #expect(quickFoodKey(recipeId: nil, name: "Toast\u{0}", amount: nil) == "food:toast\u{0}|")
  }

  @Test func readsAQuickFoodOrAnEntry() {
    let food = QuickFood(
      name: "Egg", amount: "2 large", servings: 1, macros: .none, source: .manual, recipeId: nil)
    #expect(quickFoodKey(food) == "food:egg|2 large")
    var logged = entry(.none, servings: 1)
    logged.name = "Egg"
    logged.amount = "2 LARGE"
    #expect(quickFoodKey(logged) == quickFoodKey(food))
  }
}
