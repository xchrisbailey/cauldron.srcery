import CauldronKit
import Foundation

/// One line of the eaten-against-target header: how much of a target is eaten, how full the bar
/// is, and what is left or how far over. Ported from `DayHeader.tsx`.
struct MacroMeter: Equatable, Identifiable {
  let key: MacroKey
  let eaten: Double
  /// Nil when no targets are set.
  let target: Int?

  var id: MacroKey { key }

  /// Eaten as a share of the target; 0 without a target (or with a target of 0).
  var fraction: Double {
    guard let target, target != 0 else { return 0 }
    return eaten / Double(target)
  }

  var isOver: Bool { target.map { eaten > Double($0) } ?? false }

  /// How much of the bar is filled, at most all of it.
  var fill: Double { min(1, fraction) }

  /// How much of the bar is filled with "over", when it is.
  var overFill: Double { isOver ? min(1, fraction - 1) : 0 }

  /// Target minus eaten; negative when over. Nil without a target.
  var remaining: Double? { target.map { Double($0) - eaten } }

  var unit: CopyString {
    key == .calories ? Copy.tracker.macros.calories : Copy.tracker.macros.grams
  }

  var name: CopyString {
    let names = Copy.tracker.macroNames
    switch key {
    case .calories: return names.calories
    case .protein: return names.protein
    case .carbs: return names.carbs
    case .fat: return names.fat
    }
  }

  var eatenText: String { Self.whole(eaten) }

  var targetText: String? { target.map { Self.whole(Double($0)) } }

  /// "320 g left" or "45 g over"; nil without a target.
  var leftText: CopyString? {
    guard let remaining else { return nil }
    return isOver
      ? Copy.tracker.header.over("\(Self.whole(-remaining)) \(unit.text)")
      : Copy.tracker.header.left("\(Self.whole(remaining)) \(unit.text)")
  }

  static func whole(_ value: Double) -> String {
    value.rounded(.toNearestOrAwayFromZero).formatted(.number.precision(.fractionLength(0)))
  }

  /// The four meters for a day, calories first.
  static func meters(totals: MacroTotals, targets: MacroTargets?) -> [MacroMeter] {
    MacroKey.allCases.map { key in
      let target: Int?
      switch key {
      case .calories: target = targets?.calories
      case .protein: target = targets?.protein
      case .carbs: target = targets?.carbs
      case .fat: target = targets?.fat
      }
      return MacroMeter(key: key, eaten: totals[key], target: target)
    }
  }
}

extension TargetsRecord {
  var macroTargets: MacroTargets {
    MacroTargets(calories: calories, protein: protein, carbs: carbs, fat: fat)
  }
}
