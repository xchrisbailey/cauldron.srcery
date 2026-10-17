import CauldronKit
import Testing

/// The correction fields of the editor. `readQuantityEntry` is ported from the `parseQuantity`
/// cases in `apps/web/test/recipe-form.test.ts`; the timer field from `StepRows.tsx`.
@Suite("Editor entry")
struct EditorEntryTests {
  // MARK: Quantity

  @Test func readsMixedNumbersRangesAndVulgarFractions() {
    #expect(readQuantityEntry("1 1/2") == .value(Quantity(min: 1.5, max: nil)))
    #expect(readQuantityEntry("2-3") == .value(Quantity(min: 2, max: 3)))
    #expect(readQuantityEntry("½") == .value(Quantity(min: 0.5, max: nil)))
    #expect(readQuantityEntry("3") == .value(Quantity(min: 3, max: nil)))
  }

  @Test func aBlankQuantityIsNoAmountAndJunkIsInvalid() {
    #expect(readQuantityEntry("") == .blank)
    #expect(readQuantityEntry("   ") == .blank)
    #expect(readQuantityEntry("abc") == .invalid)
  }

  @Test func theAmountAloneIsWhatTheFieldTakes() {
    // As in the web editor, the parser decides: a number or a word for one is an amount, and
    // anything it leaves as an item is not.
    #expect(readQuantityEntry("two") == .value(Quantity(min: 2, max: nil)))
    #expect(readQuantityEntry("1/0") == .invalid)
    #expect(readQuantityEntry("a few") == .invalid)
    // A range that runs backwards isn't one.
    #expect(readQuantityEntry("5-2") == .invalid)
  }

  @Test func aQuantityShownInTheFieldReadsBackTheSame() {
    for quantity in [
      Quantity(min: 1.5, max: nil), Quantity(min: 2, max: 3), Quantity(min: 0.25, max: nil),
    ] {
      let shown = quantityEntryText(quantity, unit: nil)
      #expect(readQuantityEntry(shown) == .value(quantity), "\(shown)")
    }
    #expect(quantityEntryText(Quantity(min: 2, max: 3), unit: nil) == "2-3")
  }

  @Test func metricQuantitiesAreShownAsDecimals() {
    #expect(quantityEntryText(Quantity(min: 250, max: nil), unit: .g) == "250")
    #expect(quantityEntryText(Quantity(min: 1.5, max: nil), unit: .l) == "1.5")
    #expect(readQuantityEntry("1.5") == .value(Quantity(min: 1.5, max: nil)))
  }

  // MARK: Timer

  @Test func minutesBecomeSecondsRounded() {
    #expect(readStepTimerEntry(minutes: "25") == .set(seconds: 1500))
    #expect(readStepTimerEntry(minutes: "1.5") == .set(seconds: 90))
    #expect(readStepTimerEntry(minutes: " 10 ") == .set(seconds: 600))
    #expect(readStepTimerEntry(minutes: "0.01") == .set(seconds: 1))
  }

  @Test func aCommaCanStandInForTheDecimalPoint() {
    #expect(readStepTimerEntry(minutes: "1,5") == .set(seconds: 90))
    #expect(readStepTimerEntry(minutes: "1,5,5") == .unchanged)
  }

  @Test func aBlankZeroOrNegativeEntryRemovesTheTimer() {
    #expect(readStepTimerEntry(minutes: "") == .clear)
    #expect(readStepTimerEntry(minutes: "  ") == .clear)
    #expect(readStepTimerEntry(minutes: "0") == .clear)
    #expect(readStepTimerEntry(minutes: "-5") == .clear)
  }

  @Test func aTimerIsHeldToTheLimit() {
    #expect(readStepTimerEntry(minutes: "4320") == .set(seconds: RecipeLimits.timerSeconds))
    #expect(readStepTimerEntry(minutes: "99999") == .set(seconds: RecipeLimits.timerSeconds))
    #expect(readStepTimerEntry(minutes: "1e300") == .set(seconds: RecipeLimits.timerSeconds))
  }

  @Test func somethingThatIsNotANumberLeavesTheTimerAlone() {
    #expect(readStepTimerEntry(minutes: "abc") == .unchanged)
    #expect(readStepTimerEntry(minutes: "1.2.3") == .unchanged)
    #expect(readStepTimerEntry(minutes: "Infinity") == .unchanged)
  }

  @Test func aTimerShowsInMinutesToOneDecimal() {
    #expect(stepTimerMinutesText(nil) == "")
    #expect(stepTimerMinutesText(1500) == "25")
    #expect(stepTimerMinutesText(90) == "1.5")
    #expect(stepTimerMinutesText(45) == "0.8")
    #expect(readStepTimerEntry(minutes: stepTimerMinutesText(1500)) == .set(seconds: 1500))
  }
}
