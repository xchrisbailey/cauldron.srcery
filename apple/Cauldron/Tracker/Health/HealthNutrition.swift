import CauldronKit
import Foundation

/// A diary entry as Health sees it.
struct HealthEntry: Equatable, Sendable {
  var id: UUID
  var day: LocalDate
  var slot: MealSlot
  var name: String
  var servings: Double
  /// Per serving.
  var macros: Macros
  /// A described meal still waiting for its numbers: nothing to write yet.
  var pending: Bool

  init(
    id: UUID, day: LocalDate, slot: MealSlot, name: String, servings: Double, macros: Macros,
    pending: Bool = false
  ) {
    self.id = id
    self.day = day
    self.slot = slot
    self.name = name
    self.servings = servings
    self.macros = macros
    self.pending = pending
  }

  init?(_ record: DiaryEntryRecord) {
    guard let day = record.day else { return nil }
    self.init(
      id: record.id, day: day, slot: record.slot, name: record.name, servings: record.servings,
      macros: record.macros, pending: record.macrosPending)
  }
}

/// What to do in Health for one entry: save these samples (replacing the earlier ones with the
/// same ids) and delete these ids.
struct NutritionPlan: Equatable {
  var save: [NutritionSample]
  var delete: [String]
}

enum HealthNutrition {
  /// The name of an entry's sample of one nutrient, the same on every device and every save.
  static func syncID(entry: UUID, nutrient: Nutrient) -> String {
    "cauldron.entry.\(entry.uuidString.lowercased()).\(nutrient.rawValue)"
  }

  static func syncIDs(entry: UUID) -> [String] {
    Nutrient.allCases.map { syncID(entry: entry, nutrient: $0) }
  }

  /// When a meal is dated in Health: that day at a usual hour for the meal.
  static func hour(for slot: MealSlot) -> (hour: Int, minute: Int) {
    switch slot {
    case .breakfast: (8, 0)
    case .lunch: (12, 30)
    case .dinner: (19, 0)
    case .snack: (15, 30)
    }
  }

  static func date(day: LocalDate, slot: MealSlot, calendar: Calendar) -> Date {
    let time = hour(for: slot)
    return calendar.date(
      from: DateComponents(
        year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute))
      ?? .now
  }

  /// What an entry adds to Health: every nutrient it knows, times its servings. Unknown numbers
  /// and a meal still waiting for its numbers write nothing, and anything not finite or below 0
  /// is left out.
  static func plan(for entry: HealthEntry, calendar: Calendar = .current) -> NutritionPlan {
    let date = date(day: entry.day, slot: entry.slot, calendar: calendar)
    var save: [NutritionSample] = []
    var delete: [String] = []
    for nutrient in Nutrient.allCases {
      let id = syncID(entry: entry.id, nutrient: nutrient)
      if !entry.pending, entry.servings.isFinite, entry.servings > 0,
        let perServing = entry.macros[nutrient.macroKey]
      {
        let value = perServing * entry.servings
        if value.isFinite, value >= 0 {
          save.append(
            NutritionSample(
              syncID: id, nutrient: nutrient, value: value, date: date, name: entry.name))
          continue
        }
      }
      delete.append(id)
    }
    return NutritionPlan(save: save, delete: delete)
  }

  /// Taking an entry out of Health.
  static func removal(of entry: UUID) -> NutritionPlan {
    NutritionPlan(save: [], delete: syncIDs(entry: entry))
  }
}
