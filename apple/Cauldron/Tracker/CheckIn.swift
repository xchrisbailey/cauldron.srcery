import CauldronKit
import Foundation
import SwiftData

// The weekly check-in's part that touches the store: reading what it needs and writing what the
// cook decides. The rules and the maths are `CauldronKit`'s (`CheckInRules`, `CheckInInputs`,
// `estimateExpenditure`, `proposeTargets`).

extension BodyProfileRecord {
  /// The profile as the calculator reads it; nil until it has a birth date and a height.
  var profile: BodyProfile? {
    guard let birthDate, let heightCm else { return nil }
    return BodyProfile(
      sex: sex, birthDate: birthDate, heightCm: heightCm, activity: activity, goal: goal,
      weeklyRateKg: weeklyRateKg, proteinPerKg: proteinPerKg, fatShare: fatShare,
      weightUnit: weightUnit, heightUnit: heightUnit)
  }
}

extension TargetsRecord {
  var targets: Targets {
    Targets(
      calories: calories, protein: protein, carbs: carbs, fat: fat,
      overridden: TargetOverrides(
        calories: caloriesOverridden, protein: proteinOverridden, carbs: carbsOverridden,
        fat: fatOverridden),
      checkedInOn: checkedInOn)
  }
}

extension CheckInInputs {
  /// Reads what a check-in needs from the store: the profile and targets (by the keeper rule), a
  /// year of weigh-ins one a day, and the days of food in the estimate's window.
  @MainActor
  static func gather(from context: ModelContext, today: LocalDate) throws -> CheckInInputs {
    let weighFrom = today.adding(days: -weighInDays).description
    let weighIns = try context.fetch(
      FetchDescriptor<WeighInRecord>(predicate: #Predicate { $0.dayKey >= weighFrom }))
    let foodFrom = CheckInRules.from(today: today).description
    let foodTo = today.description
    let meals = try context.fetch(
      FetchDescriptor<DiaryEntryRecord>(
        predicate: #Predicate { $0.dayKey >= foodFrom && $0.dayKey <= foodTo }))
    return CheckInInputs(
      profile: try context.current(BodyProfileRecord.self)?.profile,
      targets: try context.current(TargetsRecord.self)?.targets,
      weighIns: WeightHistory.weighIns(of: weighIns),
      // A meal still waiting for its numbers would count as a day of nothing eaten.
      intake: IntakeAverages.days(of: meals.filter { !$0.macrosPending }), today: today)
  }
}

/// What the cook does with a check-in: take the proposal, or not now. Either way it is checked
/// in for today, so it isn't offered again for a week.
enum CheckInWrites {
  enum Failure: Error {
    /// There are no targets to change.
    case noTargets
  }

  /// Sets the targets to the proposal, on the same row the targets form uses. Hand-set targets
  /// stay as they are when `keepOverrides`; otherwise every target is calculated again.
  @MainActor
  static func accept(
    _ check: CheckIn, keepOverrides: Bool, today: LocalDate, in context: ModelContext
  ) throws {
    guard let row = try context.current(TargetsRecord.self) else { throw Failure.noTargets }
    row.calories = check.proposal.targets.calories
    row.protein = check.proposal.targets.protein
    row.carbs = check.proposal.targets.carbs
    row.fat = check.proposal.targets.fat
    if !keepOverrides {
      row.caloriesOverridden = false
      row.proteinOverridden = false
      row.carbsOverridden = false
      row.fatOverridden = false
    }
    row.checkedInOn = today
    try commit(context)
  }

  /// Leaves the targets alone and asks again next week.
  @MainActor
  static func dismiss(today: LocalDate, in context: ModelContext) throws {
    guard let row = try context.current(TargetsRecord.self) else { throw Failure.noTargets }
    row.checkedInOn = today
    try commit(context)
  }

  @MainActor
  private static func commit(_ context: ModelContext) throws {
    do {
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
}
