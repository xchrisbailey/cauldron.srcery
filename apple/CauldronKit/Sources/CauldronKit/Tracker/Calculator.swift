import Foundation

// Calorie and macro targets from body stats and a goal: Mifflin-St Jeor resting energy, an
// activity multiplier, a weekly rate of change and a macro split. Ported from
// `packages/shared/src/tracker/calculator.ts`.

extension ActivityLevel {
  /// Resting energy multiplier for this activity level.
  public var multiplier: Double {
    switch self {
    case .sedentary: 1.2
    case .light: 1.375
    case .moderate: 1.55
    case .active: 1.725
    case .veryActive: 1.9
    }
  }
}

/// Constants and guard rails the calculator applies (`CALCULATOR_LIMITS`).
public enum CalculatorLimits {
  public static let kcalPerKg = 7700.0
  public static let defaultProteinPerKg = 1.8
  public static let defaultFatShare = 0.25
  public static let minFatPerKg = 0.6

  /// The most a week the goal allows, in kilograms (0 for maintain).
  public static func maxWeeklyRateKg(for goal: Goal) -> Double {
    switch goal {
    case .lose: 1.0
    case .gain: 0.5
    case .maintain: 0
    }
  }

  public static func calorieFloor(for sex: Sex) -> Double {
    switch sex {
    case .female: 1200
    case .male: 1500
    case .unspecified: 1350
    }
  }
}

private let proteinKcal = 4.0
private let carbKcal = 4.0
private let fatKcal = 9.0

/// Whole years between `birthDate` and `today`.
public func ageOn(birthDate: LocalDate, today: LocalDate) -> Int {
  let hadBirthday =
    today.month > birthDate.month || (today.month == birthDate.month && today.day >= birthDate.day)
  return today.year - birthDate.year - (hadBirthday ? 0 : 1)
}

private func sexConstant(_ sex: Sex) -> Double {
  switch sex {
  case .male: 5
  case .female: -161
  case .unspecified: -78
  }
}

/// Resting energy in kcal per day (Mifflin-St Jeor).
public func restingEnergy(sex: Sex, ageYears: Int, heightCm: Double, weightKg: Double) -> Double {
  10 * weightKg + 6.25 * heightCm - 5 * Double(ageYears) + sexConstant(sex)
}

/// Daily calories and macro grams, all whole numbers.
public struct MacroTargets: Sendable, Hashable, Codable {
  public var calories: Int
  public var protein: Int
  public var carbs: Int
  public var fat: Int

  public init(calories: Int, protein: Int, carbs: Int, fat: Int) {
    self.calories = calories
    self.protein = protein
    self.carbs = carbs
    self.fat = fat
  }
}

/// Split a calorie target into macros: protein by bodyweight, fat as a share of calories (never
/// below the per-kg minimum), carbs fill the rest (never negative). Grams are whole numbers.
public func splitMacros(
  calories: Double, weightKg: Double, proteinPerKg: Double? = nil, fatShare: Double? = nil
) -> MacroTargets {
  let protein = (proteinPerKg ?? CalculatorLimits.defaultProteinPerKg) * weightKg
  let share = fatShare ?? CalculatorLimits.defaultFatShare
  let fat = max(share * calories / fatKcal, CalculatorLimits.minFatPerKg * weightKg)
  let carbs = max(0, (calories - proteinKcal * protein - fatKcal * fat) / carbKcal)
  // Held inside what the targets accept, so an extreme profile still saves.
  return MacroTargets(
    calories: clampedRound(calories, to: TrackerLimits.calories),
    protein: clampedRound(protein, to: TrackerLimits.grams),
    carbs: clampedRound(carbs, to: TrackerLimits.grams),
    fat: clampedRound(fat, to: TrackerLimits.grams))
}

/// The weekly rate in kg, clamped to what the goal allows (0 for maintain).
public func clampWeeklyRate(_ weeklyRateKg: Double, for goal: Goal) -> Double {
  goal == .maintain
    ? 0 : min(max(0, weeklyRateKg), CalculatorLimits.maxWeeklyRateKg(for: goal))
}

/// Signed daily kcal change for a goal at a weekly rate (negative to lose).
public func dailyAdjustment(for goal: Goal, weeklyRateKg: Double) -> Double {
  let rate = clampWeeklyRate(weeklyRateKg, for: goal)
  let sign: Double = goal == .lose ? -1 : 1
  return (sign * rate * CalculatorLimits.kcalPerKg) / 7
}

public struct GoalCalories: Sendable, Hashable {
  public var calories: Int
  /// True when the calorie floor raised the target.
  public var floored: Bool
  public var dailyAdjustment: Double
}

/// Calories for a goal: expenditure plus adjustment, floored, to the nearest 10.
public func goalCalories(sex: Sex, expenditure: Double, goal: Goal, weeklyRateKg: Double)
  -> GoalCalories
{
  let adjustment = dailyAdjustment(for: goal, weeklyRateKg: weeklyRateKg)
  let floor = CalculatorLimits.calorieFloor(for: sex)
  let raw = expenditure + adjustment
  let calories = min(TrackerLimits.calories.upperBound, jsRound(max(floor, raw) / 10) * 10)
  return GoalCalories(
    calories: Int(calories), floored: raw < floor, dailyAdjustment: adjustment)
}

public struct CalculatorInput: Sendable, Hashable {
  public var sex: Sex
  public var birthDate: LocalDate
  public var heightCm: Double
  public var weightKg: Double
  public var activity: ActivityLevel
  public var goal: Goal
  /// Positive kg per week; ignored for maintain and clamped to the goal's maximum.
  public var weeklyRateKg: Double
  public var proteinPerKg: Double?
  public var fatShare: Double?
  public var today: LocalDate

  public init(
    sex: Sex, birthDate: LocalDate, heightCm: Double, weightKg: Double, activity: ActivityLevel,
    goal: Goal, weeklyRateKg: Double, proteinPerKg: Double? = nil, fatShare: Double? = nil,
    today: LocalDate
  ) {
    self.sex = sex
    self.birthDate = birthDate
    self.heightCm = heightCm
    self.weightKg = weightKg
    self.activity = activity
    self.goal = goal
    self.weeklyRateKg = weeklyRateKg
    self.proteinPerKg = proteinPerKg
    self.fatShare = fatShare
    self.today = today
  }
}

public struct CalculatorResult: Sendable, Hashable {
  public var restingEnergy: Double
  public var expenditure: Double
  /// Signed kcal per day, negative to lose.
  public var dailyAdjustment: Double
  /// After clamping; 0 for maintain.
  public var weeklyRateKg: Double
  /// True when the calorie floor raised the target.
  public var floored: Bool
  public var targets: MacroTargets
}

/// Daily targets for a person and a goal.
public func calculateTargets(_ input: CalculatorInput) -> CalculatorResult {
  let resting = restingEnergy(
    sex: input.sex, ageYears: ageOn(birthDate: input.birthDate, today: input.today),
    heightCm: input.heightCm, weightKg: input.weightKg)
  let expenditure = resting * input.activity.multiplier
  let goal = goalCalories(
    sex: input.sex, expenditure: expenditure, goal: input.goal, weeklyRateKg: input.weeklyRateKg)
  return CalculatorResult(
    restingEnergy: resting, expenditure: expenditure, dailyAdjustment: goal.dailyAdjustment,
    weeklyRateKg: clampWeeklyRate(input.weeklyRateKg, for: input.goal), floored: goal.floored,
    targets: splitMacros(
      calories: Double(goal.calories), weightKg: input.weightKg, proteinPerKg: input.proteinPerKg,
      fatShare: input.fatShare))
}
