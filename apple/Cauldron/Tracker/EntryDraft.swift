import CauldronKit
import Foundation

/// An entry as typed, before it is checked: the text of each field, kept as text while it is
/// edited. `errors` says what is wrong and `valid` gives the numbers once nothing is, so a
/// number that is not finite or not in range never reaches the store. Ported from
/// `MacroFields.tsx` and the entry sheets.
struct EntryDraft: Equatable {
  enum Field: Hashable {
    case name
    case amount
    case servings
    case macro(MacroKey)
  }

  /// What a good draft says.
  struct Valid: Equatable {
    var name: String
    var amount: String?
    var servings: Double
    var macros: Macros
    var slot: MealSlot
    /// The day to move the entry to; nil leaves it where it is (and for a new entry).
    var day: LocalDate?
  }

  var name = ""
  var amount = ""
  var servings = "1"
  var calories = ""
  var protein = ""
  var carbs = ""
  var fat = ""
  var slot: MealSlot
  /// The entry's day, which an edit can change. Nil for a new entry.
  var day: LocalDate?

  /// Servings change by this much with the plus and minus buttons.
  static let servingStep = 0.25

  init(slot: MealSlot) {
    self.slot = slot
  }

  /// An existing entry's fields as text, ready to edit.
  init(_ record: DiaryEntryRecord) {
    name = record.name
    amount = record.amount ?? ""
    servings = showNumber(record.servings, digits: 2)
    calories = record.calories.map { showNumber($0, digits: 0) } ?? ""
    protein = record.protein.map { showNumber($0) } ?? ""
    carbs = record.carbs.map { showNumber($0) } ?? ""
    fat = record.fat.map { showNumber($0) } ?? ""
    slot = record.slot
    day = record.day
  }

  /// The text of one macro field.
  subscript(macro key: MacroKey) -> String {
    get {
      switch key {
      case .calories: calories
      case .protein: protein
      case .carbs: carbs
      case .fat: fat
      }
    }
    set {
      switch key {
      case .calories: calories = newValue
      case .protein: protein = newValue
      case .carbs: carbs = newValue
      case .fat: fat = newValue
      }
    }
  }

  private enum Reading {
    case value(Double?)
    case invalid(CopyString)
  }

  /// A macro field as a number: nil when blank, and an error when it isn't a usable one.
  private func macro(_ key: MacroKey) -> Reading {
    let text = self[macro: key].trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return .value(nil) }
    let failure: CopyString =
      key == .calories
      ? Copy.validation.wholeNumber(0, RecipeLimits.calories)
      : Copy.validation.numberBetween(0, Double(RecipeLimits.grams))
    guard let typed = parseNumber(text), typed >= 0 else { return .invalid(failure) }
    // Calories are whole numbers and grams have one decimal, as the web rounds them.
    let rounded =
      key == .calories
      ? typed.rounded(.toNearestOrAwayFromZero)
      : (typed * 10).rounded(.toNearestOrAwayFromZero) / 10
    let limit = Double(key == .calories ? RecipeLimits.calories : RecipeLimits.grams)
    return rounded <= limit ? .value(rounded) : .invalid(failure)
  }

  private var servingsValue: Double? {
    guard let value = parseNumber(servings), value > 0, value <= Double(TrackerLimits.servings)
    else { return nil }
    return value
  }

  /// What is wrong, by field. Calories must be filled in when `requireCalories` is true (a quick
  /// add), as the web asks.
  func errors(requireCalories: Bool) -> [Field: CopyString] {
    var errors: [Field: CopyString] = [:]
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedName.isEmpty {
      errors[.name] = Copy.validation.required
    } else if trimmedName.count > TrackerLimits.name {
      errors[.name] = Copy.validation.tooLong(TrackerLimits.name)
    }
    if amount.trimmingCharacters(in: .whitespacesAndNewlines).count > TrackerLimits.amount {
      errors[.amount] = Copy.validation.tooLong(TrackerLimits.amount)
    }
    if servingsValue == nil {
      errors[.servings] = Copy.validation.numberBetween(0, Double(TrackerLimits.servings))
    }
    for key in MacroKey.allCases {
      switch macro(key) {
      case .invalid(let message): errors[.macro(key)] = message
      case .value(nil) where requireCalories && key == .calories:
        errors[.macro(key)] = Copy.validation.required
      case .value: break
      }
    }
    return errors
  }

  /// The entry's values, or nil while anything is wrong.
  func valid(requireCalories: Bool) -> Valid? {
    guard errors(requireCalories: requireCalories).isEmpty, let servings = servingsValue else {
      return nil
    }
    func number(_ key: MacroKey) -> Double? {
      if case .value(let value) = macro(key) { return value }
      return nil
    }
    let note = amount.trimmingCharacters(in: .whitespacesAndNewlines)
    return Valid(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      amount: note.isEmpty ? nil : note, servings: servings,
      macros: Macros(
        calories: number(.calories), protein: number(.protein), carbs: number(.carbs),
        fat: number(.fat)),
      slot: slot, day: day)
  }

  /// The servings after the plus (`by` positive) or minus button.
  mutating func nudgeServings(by amount: Double) {
    let current = parseNumber(servings) ?? 1
    servings = showNumber(max(Self.servingStep, current + amount), digits: 2)
  }
}
