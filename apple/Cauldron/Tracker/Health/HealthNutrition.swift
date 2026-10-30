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
    return DayKeyCalendar.make(timeZone: calendar.timeZone).date(
      from: DateComponents(
        year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute))
      ?? .now
  }

  /// What an entry adds to Health: every nutrient it knows, times its servings. Unknown numbers
  /// and a meal still waiting for its numbers write nothing, and anything not finite or below 0
  /// is left out.
  static func plan(for entry: HealthEntry, calendar: Calendar = DayKeyCalendar.current)
    -> NutritionPlan
  {
    guard !entry.day.isLegacyCalendarKey else { return NutritionPlan(save: [], delete: []) }
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

  /// The prefix of every sample Cauldron writes.
  static let syncPrefix = "cauldron.entry."

  /// The nutrient a Cauldron sample id is for; nil for a sample that isn't Cauldron's.
  static func nutrient(of syncID: String) -> Nutrient? {
    guard syncID.hasPrefix(syncPrefix), let suffix = syncID.split(separator: ".").last else {
      return nil
    }
    return Nutrient(rawValue: String(suffix))
  }

  /// Taking an entry out of Health.
  static func removal(of entry: UUID) -> NutritionPlan {
    NutritionPlan(save: [], delete: syncIDs(entry: entry))
  }
}

/// Making Health match the diary. Given the entries in a window and Cauldron's samples Health
/// holds for it, this says what to write and what to delete, whatever got them out of step: an
/// entry changed on another device, added before Health was connected, a write that failed. It
/// does the same again afterwards (a second run on the result is empty).
enum HealthReconcile {
  /// The diary is reconciled this many days back, today included.
  static let windowDays = 30

  /// - Writes every sample an entry should have that Health lacks or holds differently (a
  ///   different value, time or name).
  /// - Deletes every sample in `held` that no entry in `entries` should have any more: its
  ///   entry is gone, moved out of the window, its numbers are unknown, or it is a described
  ///   meal still waiting for them.
  /// - Leaves alone nutrients that aren't in `writable`, and samples that aren't Cauldron's.
  static func plan(
    entries: [HealthEntry], held: [HeldNutrition], writable: Set<Nutrient> = Set(Nutrient.allCases),
    calendar: Calendar = DayKeyCalendar.current
  ) -> NutritionPlan {
    let legacyIDs = Set(
      entries.filter { $0.day.isLegacyCalendarKey }
        .flatMap { HealthNutrition.syncIDs(entry: $0.id) })
    let held = held.filter { !legacyIDs.contains($0.syncID) }
    var wanted: [NutritionSample] = []
    for entry in entries {
      guard !entry.day.isLegacyCalendarKey else { continue }
      wanted += HealthNutrition.plan(for: entry, calendar: calendar).save
    }
    wanted = wanted.filter { writable.contains($0.nutrient) }
    let wantedIDs = Set(wanted.map(\.syncID))
    let heldByID = Dictionary(held.map { ($0.syncID, $0) }, uniquingKeysWith: { first, _ in first })

    let save = wanted.filter { sample in
      guard let have = heldByID[sample.syncID] else { return true }
      return abs(have.value - sample.value) > 1e-6
        || abs(have.date.timeIntervalSince(sample.date)) > 1
        || have.name != sample.name
    }
    let delete = held.compactMap { have -> String? in
      guard let nutrient = HealthNutrition.nutrient(of: have.syncID), writable.contains(nutrient),
        !wantedIDs.contains(have.syncID)
      else { return nil }
      return have.syncID
    }
    return NutritionPlan(save: save, delete: Array(Set(delete)).sorted())
  }
}
