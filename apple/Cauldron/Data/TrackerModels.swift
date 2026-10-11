import CauldronKit
import Foundation
import SwiftData

/// Something eaten. It snapshots its macros, so editing or deleting the recipe it came from
/// never changes a day already logged.
@Model
final class DiaryEntryRecord {
  var id: UUID = UUID()
  var dayKey: String = ""
  var slotRaw: String = MealSlot.snack.rawValue
  var name: String = ""
  var amount: String?
  var servings: Double = 1
  var calories: Double?
  var protein: Double?
  var carbs: Double?
  var fat: Double?
  var sourceRaw: String = DiarySource.manual.rawValue
  var position: Int = 0
  /// True while a described meal waits for the model; its macros are empty until then.
  var macrosPending: Bool = false
  var createdAt: Date = Date.now
  var updatedAt: Date = Date.now
  var recipe: RecipeRecord?

  @Relationship(deleteRule: .cascade, inverse: \AIJobRecord.diaryEntry)
  var aiJobs: [AIJobRecord]? = []

  init(day: LocalDate, slot: MealSlot, name: String, servings: Double = 1, source: DiarySource) {
    self.dayKey = day.description
    self.slotRaw = slot.rawValue
    self.name = name
    self.servings = servings
    self.sourceRaw = source.rawValue
  }

  var day: LocalDate? {
    get { LocalDate(dayKey) }
    set { dayKey = newValue?.description ?? "" }
  }

  var slot: MealSlot {
    get { MealSlot(rawValue: slotRaw) ?? .snack }
    set { slotRaw = newValue.rawValue }
  }

  var source: DiarySource {
    get { DiarySource(rawValue: sourceRaw) ?? .manual }
    set { sourceRaw = newValue.rawValue }
  }

  var macros: Macros {
    get { Macros(calories: calories, protein: protein, carbs: carbs, fat: fat) }
    set {
      calories = newValue.calories
      protein = newValue.protein
      carbs = newValue.carbs
      fat = newValue.fat
    }
  }
}

/// A food kept for one-tap logging. One per `key`; see `Deduplication`.
@Model
final class FavouriteRecord {
  var id: UUID = UUID()
  var key: String = ""
  var name: String = ""
  var amount: String?
  var servings: Double = 1
  var calories: Double?
  var protein: Double?
  var carbs: Double?
  var fat: Double?
  var sourceRaw: String = DiarySource.manual.rawValue
  var createdAt: Date = Date.now
  var updatedAt: Date = Date.now
  var recipe: RecipeRecord?

  init(key: String, name: String, servings: Double = 1, source: DiarySource) {
    self.key = key
    self.name = name
    self.servings = servings
    self.sourceRaw = source.rawValue
  }

  var source: DiarySource {
    get { DiarySource(rawValue: sourceRaw) ?? .manual }
    set { sourceRaw = newValue.rawValue }
  }

  var macros: Macros {
    get { Macros(calories: calories, protein: protein, carbs: carbs, fat: fat) }
    set {
      calories = newValue.calories
      protein = newValue.protein
      carbs = newValue.carbs
      fat = newValue.fat
    }
  }
}

/// A weigh-in. One per day; see `Deduplication`.
@Model
final class WeighInRecord {
  var id: UUID = UUID()
  var dayKey: String = ""
  var weightKg: Double = 0
  /// The HealthKit sample this came from, when it wasn't typed in.
  var healthSampleID: String?
  var createdAt: Date = Date.now
  var updatedAt: Date = Date.now

  init(day: LocalDate, weightKg: Double) {
    self.dayKey = day.description
    self.weightKg = weightKg
  }

  var day: LocalDate? { LocalDate(dayKey) }
}

/// The inputs to the macro calculator. There is one; see `Deduplication`.
@Model
final class BodyProfileRecord {
  var id: UUID = UUID()
  var sexRaw: String = Sex.unspecified.rawValue
  var birthDateKey: String?
  var heightCm: Double?
  var activityRaw: String = ActivityLevel.light.rawValue
  var goalRaw: String = Goal.maintain.rawValue
  var weeklyRateKg: Double = 0
  var proteinPerKg: Double = CalculatorLimits.defaultProteinPerKg
  var fatShare: Double = CalculatorLimits.defaultFatShare
  var weightUnitRaw: String = WeightUnit.kg.rawValue
  var heightUnitRaw: String = HeightUnit.cm.rawValue
  var createdAt: Date = Date.now
  var updatedAt: Date = Date.now

  init() {}

  var sex: Sex {
    get { Sex(rawValue: sexRaw) ?? .unspecified }
    set { sexRaw = newValue.rawValue }
  }

  var birthDate: LocalDate? {
    get { birthDateKey.flatMap { LocalDate($0) } }
    set { birthDateKey = newValue?.description }
  }

  var activity: ActivityLevel {
    get { ActivityLevel(rawValue: activityRaw) ?? .light }
    set { activityRaw = newValue.rawValue }
  }

  var goal: Goal {
    get { Goal(rawValue: goalRaw) ?? .maintain }
    set { goalRaw = newValue.rawValue }
  }

  var weightUnit: WeightUnit {
    get { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
    set { weightUnitRaw = newValue.rawValue }
  }

  var heightUnit: HeightUnit {
    get { HeightUnit(rawValue: heightUnitRaw) ?? .cm }
    set { heightUnitRaw = newValue.rawValue }
  }
}

/// Daily targets. There is one; see `Deduplication`.
@Model
final class TargetsRecord {
  var id: UUID = UUID()
  var calories: Int = 0
  var protein: Int = 0
  var carbs: Int = 0
  var fat: Int = 0
  var caloriesOverridden: Bool = false
  var proteinOverridden: Bool = false
  var carbsOverridden: Bool = false
  var fatOverridden: Bool = false
  var checkedInOnKey: String?
  var createdAt: Date = Date.now
  var updatedAt: Date = Date.now

  init(calories: Int, protein: Int, carbs: Int, fat: Int) {
    self.calories = calories
    self.protein = protein
    self.carbs = carbs
    self.fat = fat
  }

  var checkedInOn: LocalDate? {
    get { checkedInOnKey.flatMap { LocalDate($0) } }
    set { checkedInOnKey = newValue?.description }
  }
}

/// Choices that should follow the cook to every device. There is one; see `Deduplication`.
@Model
final class PreferencesRecord {
  var id: UUID = UUID()
  var weekStartsOnRaw: Int = WeekStartDay.monday.rawValue
  var unitSystemRaw: String = UnitSystemChoice.asWritten.rawValue
  var createdAt: Date = Date.now
  var updatedAt: Date = Date.now

  init() {}

  var weekStartsOn: WeekStartDay {
    get { WeekStartDay(rawValue: weekStartsOnRaw) ?? .monday }
    set { weekStartsOnRaw = newValue.rawValue }
  }

  var unitSystem: UnitSystemChoice {
    get { UnitSystemChoice(rawValue: unitSystemRaw) ?? .asWritten }
    set { unitSystemRaw = newValue.rawValue }
  }
}

/// A macro estimate waiting for the cloud model. Estimates are never guessed on the device,
/// so the job stays here until the model is reachable again.
@Model
final class AIJobRecord {
  var id: UUID = UUID()
  var kindRaw: String = AIJobKind.recipeMacros.rawValue
  var statusRaw: String = AIJobStatus.waiting.rawValue
  /// The meal as described, for a `mealEstimate`.
  var input: String?
  var attempts: Int = 0
  var lastError: String?
  var createdAt: Date = Date.now
  var updatedAt: Date = Date.now
  var recipe: RecipeRecord?
  var diaryEntry: DiaryEntryRecord?

  init(kind: AIJobKind, input: String? = nil) {
    self.kindRaw = kind.rawValue
    self.input = input
  }

  var kind: AIJobKind {
    get { AIJobKind(rawValue: kindRaw) ?? .recipeMacros }
    set { kindRaw = newValue.rawValue }
  }

  var status: AIJobStatus {
    get { AIJobStatus(rawValue: statusRaw) ?? .waiting }
    set { statusRaw = newValue.rawValue }
  }
}

enum AIJobKind: String, CaseIterable, Sendable {
  /// Per-serving macros for `recipe`, from its ingredients.
  case recipeMacros
  /// Macros for the meal described in `input`, for `diaryEntry`.
  case mealEstimate
}

enum AIJobStatus: String, CaseIterable, Sendable {
  case waiting
  case running
  case failed
}
