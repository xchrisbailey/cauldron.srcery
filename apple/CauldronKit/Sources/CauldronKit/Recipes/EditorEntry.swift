import Foundation

// What the cook types into the editor's small correction fields, read the way the web editor
// reads them (`parseQuantity` in `recipe-form.ts`, the timer field in `StepRows.tsx`).

/// A quantity typed by hand, as "1 1/2", "½", "2-3" or "3".
public enum QuantityEntry: Sendable, Hashable {
  /// Nothing typed: the line has no amount.
  case blank
  case value(Quantity)
  /// Something that isn't an amount.
  case invalid
}

/// Reads a typed quantity with the ingredient line parser, so the field accepts what a line
/// does. A blank field is no amount at all; anything the parser doesn't take as a lone amount
/// is invalid.
public func readQuantityEntry(_ text: String) -> QuantityEntry {
  let typed = text.jsTrimmed()
  if typed.isEmpty { return .blank }
  let parsed = parseIngredientLine("\(typed) x")
  guard let quantity = parsed.quantity, parsed.item == "x" else { return .invalid }
  return .value(quantity)
}

/// A quantity as the correction field shows it: fractions for most units, and a plain hyphen
/// in a range so it can be typed back.
public func quantityEntryText(_ quantity: Quantity, unit: UnitCode?) -> String {
  formatQuantity(quantity, unit: unit).replacingOccurrences(of: "–", with: "-")
}

extension UnitCode {
  /// How the editor names a unit in a chip or a picker: its short form, or its name when it
  /// has none (`unitLabel` in `IngredientRows.tsx`).
  public var editorLabel: String { abbreviation ?? singular }
}

/// What a step's timer field says after a change.
public enum StepTimerEntry: Sendable, Hashable {
  /// Blank, zero or negative: the step has no timer.
  case clear
  /// The timer's length, at most `RecipeLimits.timerSeconds`.
  case set(seconds: Int)
  /// Not a number: the timer stays as it was until the cook types one.
  case unchanged
}

/// Reads minutes typed into a step's timer field. A blank or non-positive entry removes the
/// timer; a number becomes seconds, rounded, and is held to the limit (`StepRows.tsx`). A comma
/// stands in for the decimal point, as a keyboard in some regions types it.
public func readStepTimerEntry(minutes text: String) -> StepTimerEntry {
  var typed = text.jsTrimmed()
  if typed.filter({ $0 == "," }).count == 1, !typed.contains(".") {
    typed = typed.replacingOccurrences(of: ",", with: ".")
  }
  let value = jsNumber(typed)
  if typed.isEmpty || value <= 0 { return .clear }
  guard value.isFinite else { return .unchanged }
  let seconds = jsRound(value * 60)
  return .set(seconds: Int(min(seconds, Double(RecipeLimits.timerSeconds))))
}

/// A timer's length in minutes as the field shows it: "25", or "1.5" for ninety seconds.
public func stepTimerMinutesText(_ seconds: Int?) -> String {
  guard let seconds else { return "" }
  return jsString(jsRound(Double(seconds) / 60 * 10) / 10)
}
