import CauldronKit
import Foundation

extension DiaryEntryRecord {
  /// The entry as plain values, or nil when its day key isn't a real day.
  var entry: DiaryEntry? {
    guard let day else { return nil }
    return DiaryEntry(
      id: id, date: day, slot: slot, name: name, amount: amount, servings: servings,
      macros: macros, source: source, recipeId: recipe?.id, position: position)
  }
}

/// One day of the diary as the screen draws it: the entries by meal and the day's totals.
/// Plain values, so the widget and the weigh-in views can read the same numbers.
struct DayLog: Equatable {
  /// A meal slot's entries and what they add up to.
  struct Section: Equatable, Identifiable {
    var slot: MealSlot
    var entries: [DiaryEntry]
    var subtotal: MacroTotals

    var id: MealSlot { slot }
  }

  let day: LocalDate
  /// Breakfast, lunch, dinner and snack, each with the entries of that meal in order.
  let sections: [Section]
  let totals: MacroTotals

  var isEmpty: Bool { sections.allSatisfy { $0.entries.isEmpty } }

  /// Entries in a meal are in `position` order; the id keeps two with the same position (added
  /// on two devices) in the same order everywhere.
  init(day: LocalDate, entries: [DiaryEntry]) {
    self.init(
      day: day,
      ordered: entries.sorted { ($0.position, $0.id.uuidString) < ($1.position, $1.id.uuidString) })
  }

  /// From the stored rows of `day`. Two entries with the same position are ordered by when they
  /// were added, then by id.
  init(day: LocalDate, records: [DiaryEntryRecord]) {
    let ordered = records.sorted {
      ($0.position, $0.createdAt, $0.id.uuidString) < ($1.position, $1.createdAt, $1.id.uuidString)
    }
    self.init(day: day, ordered: ordered.compactMap(\.entry))
  }

  private init(day: LocalDate, ordered: [DiaryEntry]) {
    self.day = day
    sections = MealSlot.allCases.map { slot in
      let inSlot = ordered.filter { $0.slot == slot }
      return Section(slot: slot, entries: inSlot, subtotal: dayTotals(inSlot))
    }
    totals = dayTotals(ordered)
  }
}
