import CauldronKit
import Foundation
import SwiftData

/// What the "set your targets" screen holds while it is open: the text as typed, the checks on
/// it, the numbers the calculator makes from it, and what gets saved. Ported from
/// `apps/web/src/routes/_authed/tracker/targets.tsx`; the screen only draws it.
struct TargetsForm: Equatable {
  /// Where an error belongs.
  enum Field: Hashable {
    case sex
    case birthDate
    case height
    case weight
    case proteinPerKg
    case fatPercent
    case target(TargetKey)
  }

  /// The four targets after the cook's own numbers are laid over the calculated ones.
  struct Resolved: Equatable {
    var values: [TargetKey: Double]
    var overridden: Set<TargetKey>
  }

  /// The form can't be saved as it stands; the screen shows the field errors.
  struct Invalid: Error {}

  static let earliestBirthYear = 1900
  /// How far back the latest weigh-in is looked for.
  static let weighInWindowDays = 365

  let today: LocalDate
  /// Nil until chosen; the web asks for it outright.
  var sex: Sex?
  var birthDate: LocalDate?
  var heightUnit: HeightUnit
  var cm = ""
  var feet = ""
  var inches = ""
  var weightUnit: WeightUnit
  var weight = ""
  var activity = ActivityLevel.light
  var goal = Goal.maintain
  /// In the weight unit (0.5 kg, 1 lb a week); nil when maintaining.
  var rate: Double?
  var proteinPerKg = showNumber(CalculatorLimits.defaultProteinPerKg)
  var fatPercent = showNumber(CalculatorLimits.defaultFatShare * 100, digits: 0)
  /// Targets typed by hand, as typed. A key is here only while it is overridden.
  var overrides: [TargetKey: String] = [:]
  /// The most recent weigh-in in the window, as it was when the form opened.
  private(set) var latestWeighInKg: Double?
  /// True when a body profile was already saved.
  private(set) var hasProfile = false

  /// A blank form, in metric (cm and kg) whatever the region, as the web's is. A cook who
  /// chooses pounds or feet and inches keeps them: the saved profile wins when the form opens.
  init(today: LocalDate) {
    self.today = today
    weightUnit = .kg
    heightUnit = .cm
  }

  /// Today in the cook's own calendar.
  static func today(now: Date = .now, calendar: Calendar = .current) -> LocalDate? {
    let parts = calendar.dateComponents([.year, .month, .day], from: now)
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    return LocalDate(year: year, month: month, day: day)
  }

  /// The weight the form opens with: the latest weigh-in. Weights from Health are imported as
  /// weigh-ins (`HealthSync`), so this includes them.
  static func startingWeightKg(latestWeighIn: Double?) -> Double? {
    latestWeighIn
  }

  /// The form as saved: the body profile and targets (if any) and the latest weigh-in.
  static func load(from context: ModelContext, today: LocalDate) throws -> TargetsForm {
    var form = TargetsForm(today: today)
    let from = today.adding(days: -weighInWindowDays).description
    let to = today.description
    let recent = try context.fetch(
      FetchDescriptor<WeighInRecord>(
        predicate: #Predicate { $0.dayKey >= from && $0.dayKey <= to },
        sortBy: [SortDescriptor(\.dayKey, order: .reverse)]))
    if let day = recent.first?.day {
      form.latestWeighInKg = try context.weighIn(on: day)?.weightKg
    }
    if let startingKg = startingWeightKg(latestWeighIn: form.latestWeighInKg) {
      form.weight = showWeight(startingKg, unit: form.weightUnit)
    }

    guard let profile = try context.current(BodyProfileRecord.self) else { return form }
    form.hasProfile = true
    form.sex = profile.sex
    form.birthDate = profile.birthDate
    form.heightUnit = profile.heightUnit
    form.setHeight(cm: profile.heightCm ?? 0)
    form.weightUnit = profile.weightUnit
    form.weight =
      startingWeightKg(latestWeighIn: form.latestWeighInKg)
      .map { showWeight($0, unit: profile.weightUnit) } ?? ""
    form.activity = profile.activity
    form.goal = profile.goal
    form.rate = nearestRate(
      goal: profile.goal, unit: profile.weightUnit, kg: profile.weeklyRateKg)
    form.proteinPerKg = showNumber(profile.proteinPerKg)
    form.fatPercent = showNumber(profile.fatShare * 100, digits: 0)
    if let targets = try context.current(TargetsRecord.self) {
      let saved: [TargetKey: (Int, Bool)] = [
        .calories: (targets.calories, targets.caloriesOverridden),
        .protein: (targets.protein, targets.proteinOverridden),
        .carbs: (targets.carbs, targets.carbsOverridden),
        .fat: (targets.fat, targets.fatOverridden),
      ]
      for (key, (value, overridden)) in saved where overridden {
        form.overrides[key] = String(value)
      }
    }
    return form
  }

  /// Open on the targets, with the profile as an editable summary, when there is already
  /// enough to calculate from.
  var startsOnTargets: Bool { hasProfile && latestWeighInKg != nil }

  // MARK: Reading what was typed

  var weightKg: Double? {
    parseNumber(weight).map { toKg($0, unit: weightUnit) }
  }

  var heightCm: Double? {
    switch heightUnit {
    case .cm:
      return parseNumber(cm)
    case .ftin:
      let feet = parseNumber(feet)
      let inches =
        self.inches.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : parseNumber(inches)
      guard let feet, let inches else { return nil }
      return feetInchesToCm(feet: feet, inches: inches)
    }
  }

  /// The grams-per-kilo and fat share, unless what was typed is outside what is accepted.
  private var proteinPerKgValue: Double? {
    adjustErrors()[.proteinPerKg] == nil ? parseNumber(proteinPerKg) : nil
  }

  private var fatShareValue: Double? {
    adjustErrors()[.fatPercent] == nil ? parseNumber(fatPercent).map { $0 / 100 } : nil
  }

  // MARK: Changing units and goals

  private mutating func setHeight(cm value: Double) {
    let feetInches = cmToFeetInches(value)
    cm = showNumber(value)
    feet = String(feetInches.feet)
    inches = showNumber(feetInches.inches)
  }

  /// Switching the unit converts what was typed, so the person keeps the same height.
  mutating func switchHeightUnit(to unit: HeightUnit) {
    if let current = heightCm { setHeight(cm: current) }
    heightUnit = unit
  }

  mutating func switchWeightUnit(to unit: WeightUnit) {
    if let typed = parseNumber(weight) {
      weight = showWeight(toKg(typed, unit: weightUnit), unit: unit)
    }
    weightUnit = unit
    rate = defaultRate(goal: goal, unit: unit)
  }

  mutating func choose(goal: Goal) {
    self.goal = goal
    rate = defaultRate(goal: goal, unit: weightUnit)
  }

  // MARK: Checks

  /// Messages for the first step; empty when it is good.
  func aboutErrors() -> [Field: CopyString] {
    var errors: [Field: CopyString] = [:]
    if sex == nil { errors[.sex] = Copy.validation.required }
    if let birthDate {
      if birthDate > today || birthDate.year < Self.earliestBirthYear {
        errors[.birthDate] = Copy.validation.date
      }
    } else {
      errors[.birthDate] = Copy.validation.required
    }
    if let height = heightCm {
      if !TrackerLimits.heightCm.contains(height) {
        errors[.height] = Copy.validation.numberBetween(
          TrackerLimits.heightCm.lowerBound, TrackerLimits.heightCm.upperBound)
      }
    } else {
      errors[.height] = Copy.validation.required
    }
    if let kg = weightKg {
      if !TrackerLimits.weightKg.contains(kg) {
        errors[.weight] = Copy.validation.numberBetween(
          roundWeight(fromKg(TrackerLimits.weightKg.lowerBound, unit: weightUnit)),
          roundWeight(fromKg(TrackerLimits.weightKg.upperBound, unit: weightUnit)))
      }
    } else {
      errors[.weight] = Copy.validation.required
    }
    return errors
  }

  /// Messages for the protein and fat settings.
  func adjustErrors() -> [Field: CopyString] {
    var errors: [Field: CopyString] = [:]
    let protein = parseNumber(proteinPerKg)
    if protein.map(TrackerLimits.proteinPerKg.contains) != true {
      errors[.proteinPerKg] = Copy.validation.numberBetween(
        TrackerLimits.proteinPerKg.lowerBound, TrackerLimits.proteinPerKg.upperBound)
    }
    let fat = parseNumber(fatPercent).map { $0 / 100 }
    if fat.map(TrackerLimits.fatShare.contains) != true {
      errors[.fatPercent] = Copy.validation.numberBetween(
        TrackerLimits.fatShare.lowerBound * 100, TrackerLimits.fatShare.upperBound * 100)
    }
    return errors
  }

  /// Messages for targets typed by hand.
  func targetErrors() -> [Field: CopyString] {
    var errors: [Field: CopyString] = [:]
    for (key, text) in overrides {
      guard let value = parseNumber(text) else {
        errors[.target(key)] = Copy.validation.required
        continue
      }
      let range = key == .calories ? TrackerLimits.calories : TrackerLimits.grams
      if value != value.rounded() || !range.contains(value) {
        errors[.target(key)] = Copy.validation.wholeNumber(
          Int(range.lowerBound), Int(range.upperBound))
      }
    }
    return errors
  }

  // MARK: Calculating

  /// What the calculator makes of the form, once the first step is good.
  var calculation: CalculatorResult? {
    guard aboutErrors().isEmpty, let sex, let birthDate, let heightCm, let weightKg else {
      return nil
    }
    let fatShare = fatShareValue
    return calculateTargets(
      CalculatorInput(
        sex: sex, birthDate: birthDate, heightCm: heightCm, weightKg: weightKg,
        activity: activity, goal: goal, weeklyRateKg: toKg(rate ?? 0, unit: weightUnit),
        proteinPerKg: proteinPerKgValue, fatShare: fatShare == 0 ? nil : fatShare, today: today))
  }

  /// The four targets: what was calculated, with the cook's own numbers on top. When calories
  /// are overridden the other macros are split again from that number, so the grams still add
  /// up; macros the cook set stay as set.
  var resolved: Resolved? {
    guard let calculation, let weightKg else { return nil }
    let typed = { (key: TargetKey) in self.overrides[key].flatMap(parseNumber) }
    let calories = typed(.calories) ?? Double(calculation.targets.calories)
    let split =
      typed(.calories) == nil
      ? calculation.targets
      : splitMacros(
        calories: calories, weightKg: weightKg, proteinPerKg: proteinPerKgValue,
        fatShare: fatShareValue.flatMap { $0 == 0 ? nil : $0 })
    return Resolved(
      values: [
        .calories: calories,
        .protein: typed(.protein) ?? Double(split.protein),
        .carbs: typed(.carbs) ?? Double(split.carbs),
        .fat: typed(.fat) ?? Double(split.fat),
      ],
      overridden: Set(overrides.keys))
  }

  // MARK: Saving

  /// Saves the profile, today's weigh-in (when the weight is new or changed) and the targets,
  /// then tells the macros widget. Throws `Invalid` without touching anything when the form
  /// isn't good.
  @MainActor
  func save(in context: ModelContext, publishing publisher: TodayMacrosPublisher = .shared) throws {
    guard aboutErrors().isEmpty, adjustErrors().isEmpty, targetErrors().isEmpty,
      let sex, let birthDate, let heightCm, let weightKg, let calculation, let resolved
    else { throw Invalid() }

    let profile =
      try context.current(BodyProfileRecord.self) ?? Self.inserted(BodyProfileRecord(), context)
    profile.sex = sex
    profile.birthDate = birthDate
    profile.heightCm = (heightCm * 10).rounded() / 10
    profile.activity = activity
    profile.goal = goal
    profile.weeklyRateKg = (calculation.weeklyRateKg * 1000).rounded() / 1000
    profile.proteinPerKg = proteinPerKgValue ?? CalculatorLimits.defaultProteinPerKg
    profile.fatShare = fatShareValue ?? CalculatorLimits.defaultFatShare
    profile.weightUnit = weightUnit
    profile.heightUnit = heightUnit

    if weighsIn {
      let kg = (weightKg * 100).rounded() / 100
      if let existing = try context.weighIn(on: today) {
        // Only a weight the cook changed makes it theirs; one left as shown (a Health reading,
        // say) stays as it is.
        if showWeight(existing.weightKg, unit: weightUnit)
          != showNumber(roundWeight(parseNumber(weight) ?? 0))
        {
          existing.weightKg = kg
          WeightWrites.claim(existing, in: context)
        }
      } else {
        context.insert(WeighInRecord(day: today, weightKg: kg))
      }
    }

    let values = resolved.values.mapValues { Int($0) }
    let targets =
      try context.current(TargetsRecord.self)
      ?? Self.inserted(TargetsRecord(calories: 0, protein: 0, carbs: 0, fat: 0), context)
    targets.calories = values[.calories] ?? 0
    targets.protein = values[.protein] ?? 0
    targets.carbs = values[.carbs] ?? 0
    targets.fat = values[.fat] ?? 0
    targets.caloriesOverridden = resolved.overridden.contains(.calories)
    targets.proteinOverridden = resolved.overridden.contains(.protein)
    targets.carbsOverridden = resolved.overridden.contains(.carbs)
    targets.fatOverridden = resolved.overridden.contains(.fat)
    try context.save()
    publisher.publish(from: context)
  }

  /// Weigh in only when the weight is new or changed, in the unit it was shown in.
  private var weighsIn: Bool {
    guard let latestWeighInKg, let typed = parseNumber(weight) else { return true }
    return showWeight(latestWeighInKg, unit: weightUnit) != showNumber(roundWeight(typed))
  }

  private static func inserted<Row: PersistentModel>(_ row: Row, _ context: ModelContext) -> Row {
    context.insert(row)
    return row
  }
}
