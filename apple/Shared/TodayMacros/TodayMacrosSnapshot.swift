import CauldronKit
import Foundation

/// What the macros widget shows, left by the app in the App Group container. The widget never
/// opens the store (that would run CloudKit mirroring inside an extension), so the app works out
/// the day's numbers and writes them here, and the widget only reads. Shared by the app and the
/// widget extension.
struct TodayMacrosSnapshot: Codable, Sendable, Equatable {
  /// The day the numbers are for, written `YYYY-MM-DD`.
  var day: LocalDate
  /// What the day's entries add up to, the same totals the diary's header shows.
  var eaten: MacroTotals
  /// The daily targets, or nil when none are set.
  var targets: MacroTargets?
  /// True while an entry still waits for its numbers to be estimated.
  var hasWaitingEntry: Bool
  /// When the app wrote it.
  var writtenAt: Date

  /// The snapshot for `day` from that day's entries. Entries of other days are left out, so a
  /// list that is wider than the day can't leak yesterday into today.
  static func make(
    day: LocalDate, entries: [DiaryEntry], hasWaitingEntry: Bool, targets: MacroTargets?,
    now: Date
  ) -> TodayMacrosSnapshot {
    TodayMacrosSnapshot(
      day: day, eaten: dayTotals(entries.filter { $0.date == day }), targets: targets,
      hasWaitingEntry: hasWaitingEntry, writtenAt: now)
  }

  /// This snapshot as seen on `today`. A snapshot of an earlier or later day says nothing about
  /// today's food: it reads as today with nothing eaten yet, against the same targets.
  func seen(on today: LocalDate) -> TodayMacrosSnapshot {
    guard day != today else { return self }
    return TodayMacrosSnapshot(
      day: today, eaten: .zero, targets: targets, hasWaitingEntry: false, writtenAt: writtenAt)
  }

  /// One macro's eaten amount and target, as the widget draws a ring or bar.
  func meter(_ key: MacroKey) -> TodayMacrosMeter {
    let target: Int?
    switch key {
    case .calories: target = targets?.calories
    case .protein: target = targets?.protein
    case .carbs: target = targets?.carbs
    case .fat: target = targets?.fat
    }
    return TodayMacrosMeter(key: key, eaten: eaten[key], target: target)
  }
}

/// One macro against its target. Mirrors the diary's `MacroMeter`, which is app-only because it
/// carries the screen's copy; this is only the arithmetic.
struct TodayMacrosMeter: Equatable, Sendable {
  let key: MacroKey
  let eaten: Double
  /// Nil when no targets are set.
  let target: Int?

  /// Eaten as a share of the target, held to 0...1 so a ring never wraps. 0 without a target.
  var fill: Double {
    guard let target, target > 0 else { return 0 }
    return min(1, max(0, eaten / Double(target)))
  }

  var isOver: Bool { target.map { eaten > Double($0) } ?? false }

  /// Whole numbers, rounded half away from zero the way the diary does.
  static func whole(_ value: Double) -> String {
    value.rounded(.toNearestOrAwayFromZero).formatted(.number.precision(.fractionLength(0)))
  }

  var eatenText: String { Self.whole(eaten) }
  var targetText: String? { target.map { Self.whole(Double($0)) } }
}
