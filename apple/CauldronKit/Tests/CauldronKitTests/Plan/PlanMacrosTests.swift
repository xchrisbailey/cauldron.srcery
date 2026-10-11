import CauldronKit
import Foundation
import Testing

/// Ported case for case from `packages/shared/test/planMacros.test.ts`.
private func day(_ string: String) -> LocalDate { LocalDate(string)! }

private func recipe(_ macros: Macros) -> PlanRecipe {
  PlanRecipe(
    id: UUID(uuidString: "8f0c2a4e-1b6d-4c1e-9a53-0d2f6b7a9c11")!, title: "Chili", servings: 5,
    totalMinutes: 60, photoKey: nil, macros: macros)
}

private func entry(
  recipe: PlanRecipe? = recipe(Macros(calories: 500, protein: 30, carbs: 40, fat: 20)),
  title: String = "Chili", servings: Int? = 1
) -> PlanEntry {
  PlanEntry(
    id: UUID(), date: day("2026-10-05"), slot: .dinner, title: title, recipe: recipe,
    servings: servings, position: 0, brewed: false)
}

@Suite("tallyMacros")
struct TallyMacrosTests {
  @Test func multipliesPerServingMacrosByTheServingsPlanned() {
    let tally = tallyMacros([entry(servings: 2), entry(servings: 1)])
    #expect(tally.totals == MacroTotals(calories: 1500, protein: 90, carbs: 120, fat: 60))
    #expect(tally.counted == 2)
    #expect(tally.missing == 0)
  }

  @Test func usesTheRecipesServingsWhenTheEntryFollowsTheRecipe() {
    #expect(tallyMacros([entry(servings: nil)]).totals.calories == 2500)
  }

  @Test func addsWhatAPartialRecipeHasAndReportsItAsMissing() {
    let tally = tallyMacros([
      entry(),
      entry(recipe: recipe(Macros(calories: 300, protein: nil, carbs: nil, fat: nil))),
      entry(recipe: recipe(.none)),
    ])
    #expect(tally.totals.calories == 800)
    #expect(tally.totals.protein == 30)
    #expect(tally.counted == 1)
    #expect(tally.missing == 2)
  }

  @Test func leavesFreeTextMealsOutOfTheTotalsAndTheGaps() {
    let tally = tallyMacros([entry(recipe: nil, title: "Leftovers")])
    #expect(tally.freeText == 1)
    #expect(tally.missing == 0)
    #expect(hasMacros(tally) == false)
  }
}

@Suite("oneADay")
struct OneADayTests {
  let days = ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09"].map(day)

  @Test func givesOneServingADayFromTheStartDayUntilTheServingsRunOut() {
    #expect(
      oneADay(days: days, from: day("2026-10-06"), servings: 3)
        == [
          DayServings(date: day("2026-10-06"), servings: 1),
          DayServings(date: day("2026-10-07"), servings: 1),
          DayServings(date: day("2026-10-08"), servings: 1),
        ])
  }

  @Test func stopsAtTheEndOfTheWeek() {
    #expect(
      oneADay(days: days, from: day("2026-10-08"), servings: 5).map(\.date)
        == [day("2026-10-08"), day("2026-10-09")])
  }

  @Test func isJustTheStartDayWhenTheRecipesServingsAreUnknown() {
    #expect(
      oneADay(days: days, from: day("2026-10-05"), servings: nil)
        == [DayServings(date: day("2026-10-05"), servings: 1)])
  }
}
