import CauldronKit
import Testing

@Suite("Macros")
struct MacrosTests {
  @Test func noMacrosAreAllUnknown() {
    for key in MacroKey.allCases { #expect(Macros.none[key] == nil) }
    #expect(Macros.none == Macros(calories: nil, protein: nil, carbs: nil, fat: nil))
  }

  @Test func readsEachNumberByKey() {
    let macros = Macros(calories: 520, protein: 31, carbs: nil, fat: 12.5)
    #expect(macros[.calories] == 520)
    #expect(macros[.protein] == 31)
    #expect(macros[.carbs] == nil)
    #expect(macros[.fat] == 12.5)
  }

  @Test func totalsStartAtZeroAndReadByKey() {
    var totals = MacroTotals.zero
    for key in MacroKey.allCases { #expect(totals[key] == 0) }
    totals[.protein] = 42
    #expect(totals == MacroTotals(calories: 0, protein: 42, carbs: 0, fat: 0))
  }
}
