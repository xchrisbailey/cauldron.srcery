import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

@MainActor
@Suite("Targets form")
struct TargetsFormTests {
  private let today = LocalDate(year: 2026, month: 10, day: 10)!
  private let container: ModelContainer
  private let context: ModelContext

  init() throws {
    container = try CauldronStore.container(.inMemory)
    context = ModelContext(container)
  }

  /// A cook who can be calculated: a 36-year-old woman, 168 cm, 74.2 kg, losing half a kilo a
  /// week. The numbers it makes (1450 kcal, 134 g protein, 129 g carbs, 45 g fat) are the
  /// debug seed's, worked out by hand against the web calculator.
  private func filled(measurement: Locale.MeasurementSystem = .metric) -> TargetsForm {
    var form = TargetsForm(today: today, measurement: measurement)
    form.sex = .female
    form.birthDate = LocalDate(year: 1990, month: 5, day: 14)
    form.cm = "168"
    form.weight = "74.2"
    form.activity = .light
    form.choose(goal: .lose)
    return form
  }

  private func targets() throws -> TargetsRecord {
    try #require(try context.current(TargetsRecord.self))
  }

  private func count<Row: PersistentModel>(_ type: Row.Type) throws -> Int {
    try context.fetchCount(FetchDescriptor<Row>())
  }

  // MARK: What gets saved

  @Test func savesTheCalculatedTargets() throws {
    try filled().save(in: context)
    let saved = try targets()
    let numbers: [Int] = [saved.calories, saved.protein, saved.carbs, saved.fat]
    #expect(numbers == [1450, 134, 129, 45])
    #expect(
      !saved.caloriesOverridden && !saved.proteinOverridden && !saved.carbsOverridden
        && !saved.fatOverridden)
    #expect(saved.checkedInOn == nil)
  }

  @Test func savedTargetsEqualTheCalculatorForTheSameInputs() throws {
    var form = filled()
    form.sex = .male
    form.activity = .active
    form.cm = "181.5"
    form.weight = "88.4"
    form.choose(goal: .gain)
    form.rate = 0.25
    form.proteinPerKg = "2"
    form.fatPercent = "30"
    try form.save(in: context)

    let expected = calculateTargets(
      CalculatorInput(
        sex: .male, birthDate: LocalDate(year: 1990, month: 5, day: 14)!, heightCm: 181.5,
        weightKg: 88.4, activity: .active, goal: .gain, weeklyRateKg: 0.25, proteinPerKg: 2,
        fatShare: 0.3, today: today)
    ).targets
    let saved = try targets()
    #expect(
      MacroTargets(
        calories: saved.calories, protein: saved.protein, carbs: saved.carbs, fat: saved.fat)
        == expected)
  }

  @Test func savesTheProfileInMetricWithTheUnitsShown() throws {
    var form = filled(measurement: .us)
    form.feet = "5"
    form.inches = "6"
    form.weight = "163.6"
    form.choose(goal: .lose)
    try form.save(in: context)

    let profile = try #require(try context.current(BodyProfileRecord.self))
    #expect(profile.weightUnit == .lb)
    #expect(profile.heightUnit == .ftin)
    #expect(profile.heightCm == 167.6)
    #expect(profile.weeklyRateKg == 0.454)
    #expect(profile.sex == .female)
    #expect(profile.birthDate == LocalDate(year: 1990, month: 5, day: 14))
    #expect(profile.goal == .lose)
    #expect(profile.proteinPerKg == 1.8)
    #expect(profile.fatShare == 0.25)

    // The weight went in as pounds and was calculated from kilograms.
    let kg = toKg(163.6, unit: .lb)
    let expected = calculateTargets(
      CalculatorInput(
        sex: .female, birthDate: LocalDate(year: 1990, month: 5, day: 14)!,
        heightCm: 5 * 30.48 + 6 * 2.54, weightKg: kg, activity: .light, goal: .lose,
        weeklyRateKg: toKg(1, unit: .lb), today: today)
    ).targets
    #expect(try targets().calories == expected.calories)
    #expect(try targets().protein == expected.protein)
  }

  @Test func aMaintainGoalSavesNoRate() throws {
    var form = filled()
    form.choose(goal: .maintain)
    try form.save(in: context)
    #expect(try #require(try context.current(BodyProfileRecord.self)).weeklyRateKg == 0)
  }

  @Test func savingAgainChangesTheRowsInsteadOfAddingMore() throws {
    try filled().save(in: context)
    var again = filled()
    again.activity = .moderate
    try again.save(in: context)
    #expect(try count(TargetsRecord.self) == 1)
    #expect(try count(BodyProfileRecord.self) == 1)
    #expect(try count(WeighInRecord.self) == 1)
    #expect(try #require(try context.current(BodyProfileRecord.self)).activity == .moderate)
  }

  @Test func savingKeepsTheLastCheckInDay() throws {
    try filled().save(in: context)
    try targets().checkedInOn = LocalDate(year: 2026, month: 10, day: 3)
    try filled().save(in: context)
    #expect(try targets().checkedInOn == LocalDate(year: 2026, month: 10, day: 3))
  }

  // MARK: The weight is today's weigh-in

  @Test func theWeightBecomesTodaysWeighIn() throws {
    var form = filled()
    form.weight = "74.256"
    try form.save(in: context)
    let weighIn = try #require(try context.weighIn(on: today))
    #expect(weighIn.weightKg == 74.26)
  }

  @Test func aWeighInAlreadyMadeTodayIsUpdated() throws {
    context.insert(WeighInRecord(day: today, weightKg: 75))
    try context.save()
    try filled().save(in: context)
    #expect(try count(WeighInRecord.self) == 1)
    #expect(try context.weighIn(on: today)?.weightKg == 74.2)
  }

  @Test func anUnchangedWeightIsNotWeighedInAgain() throws {
    context.insert(WeighInRecord(day: today.adding(days: -2), weightKg: 74.2))
    try context.save()
    var form = try TargetsForm.load(from: context, today: today, measurement: .metric)
    #expect(form.weight == "74.2")
    form.sex = .female
    form.birthDate = LocalDate(year: 1990, month: 5, day: 14)
    form.cm = "168"
    try form.save(in: context)
    #expect(try count(WeighInRecord.self) == 1)
  }

  @Test func aChangedWeightIsWeighedInOnTopOfTheLastOne() throws {
    context.insert(WeighInRecord(day: today.adding(days: -2), weightKg: 74.2))
    try context.save()
    var form = try TargetsForm.load(from: context, today: today, measurement: .metric)
    form.sex = .female
    form.birthDate = LocalDate(year: 1990, month: 5, day: 14)
    form.cm = "168"
    form.weight = "73.5"
    try form.save(in: context)
    #expect(try count(WeighInRecord.self) == 2)
    #expect(try context.weighIn(on: today)?.weightKg == 73.5)
    #expect(try context.weighIn(on: today.adding(days: -2))?.weightKg == 74.2)
  }

  // MARK: Overrides

  @Test func nothingIsOverriddenUntilTheCookTypesIt() {
    let resolved = filled().resolved
    #expect(resolved?.overridden == [])
    #expect(resolved?.values == [.calories: 1450, .protein: 134, .carbs: 129, .fat: 45])
  }

  @Test func aTypedMacroStaysAsTyped() throws {
    var form = filled()
    form.overrides[.protein] = "150"
    #expect(
      form.resolved?.values == [.calories: 1450, .protein: 150, .carbs: 129, .fat: 45])
    try form.save(in: context)
    let saved = try targets()
    #expect(saved.protein == 150 && saved.proteinOverridden)
    #expect(!saved.caloriesOverridden && !saved.carbsOverridden && !saved.fatOverridden)
  }

  @Test func typedCaloriesSplitTheMacrosAgain() throws {
    var form = filled()
    form.overrides[.calories] = "2000"
    #expect(
      form.resolved?.values == [.calories: 2000, .protein: 134, .carbs: 241, .fat: 56])
    form.overrides[.fat] = "70"
    #expect(
      form.resolved?.values == [.calories: 2000, .protein: 134, .carbs: 241, .fat: 70])
    #expect(form.resolved?.overridden == [.calories, .fat])
  }

  @Test func overridesSurviveLoadingAndRecalculating() throws {
    var form = filled()
    form.overrides[.fat] = "60"
    form.overrides[.calories] = "1800"
    try form.save(in: context)

    var reopened = try TargetsForm.load(from: context, today: today, measurement: .metric)
    #expect(reopened.overrides == [.fat: "60", .calories: "1800"])
    #expect(reopened.startsOnTargets)

    // A new weight changes what is calculated, not what was typed.
    reopened.weight = "80"
    let resolved = try #require(reopened.resolved)
    #expect(resolved.values[.calories] == 1800)
    #expect(resolved.values[.fat] == 60)
    #expect(resolved.overridden == [.calories, .fat])
    #expect(
      resolved.values[.protein]
        == Double(splitMacros(calories: 1800, weightKg: 80).protein))

    // Resetting one hands it back to the calculator.
    reopened.overrides[.fat] = nil
    #expect(reopened.resolved?.values[.fat] != 60)
    #expect(reopened.resolved?.overridden == [.calories])
  }

  @Test func anEditedProfileLeavesNonOverriddenTargetsToTheCalculator() throws {
    try filled().save(in: context)
    var reopened = try TargetsForm.load(from: context, today: today, measurement: .metric)
    #expect(reopened.overrides.isEmpty)
    reopened.activity = .veryActive
    try reopened.save(in: context)
    let expected = calculateTargets(
      CalculatorInput(
        sex: .female, birthDate: LocalDate(year: 1990, month: 5, day: 14)!, heightCm: 168,
        weightKg: 74.2, activity: .veryActive, goal: .lose, weeklyRateKg: 0.5, today: today)
    ).targets
    #expect(try targets().calories == expected.calories)
    #expect(try !targets().caloriesOverridden)
  }

  // MARK: Checks

  @Test func aBlankFormAsksForEveryField() {
    let errors = TargetsForm(today: today, measurement: .metric).aboutErrors()
    let required = Copy.validation.required
    #expect(errors[.sex] == required)
    #expect(errors[.birthDate] == required)
    #expect(errors[.height] == required)
    #expect(errors[.weight] == required)
    #expect(TargetsForm(today: today, measurement: .metric).calculation == nil)
  }

  @Test func aGoodFormHasNoErrors() {
    let form = filled()
    #expect(form.aboutErrors().isEmpty)
    #expect(form.adjustErrors().isEmpty)
    #expect(form.targetErrors().isEmpty)
  }

  @Test func weightAndHeightHaveLimitsInTheUnitShown() {
    var form = filled()
    form.weight = "10"
    form.cm = "99"
    #expect(form.aboutErrors()[.weight]?.text == "Use a number from 20 to 400.")
    #expect(form.aboutErrors()[.height]?.text == "Use a number from 100 to 250.")
    form.weightUnit = .lb
    form.weight = "30"
    #expect(form.aboutErrors()[.weight]?.text == "Use a number from 44.1 to 881.8.")
  }

  @Test func aBirthDateMustBeARealPastDay() {
    var form = filled()
    form.birthDate = today.adding(days: 1)
    #expect(form.aboutErrors()[.birthDate] == Copy.validation.date)
    form.birthDate = LocalDate(year: 1899, month: 12, day: 31)
    #expect(form.aboutErrors()[.birthDate] == Copy.validation.date)
    form.birthDate = today
    #expect(form.aboutErrors()[.birthDate] == nil)
  }

  @Test func aDecimalCommaIsRead() {
    var form = filled()
    form.weight = "74,2"
    #expect(form.weightKg == 74.2)
    #expect(form.aboutErrors().isEmpty)
    form.weight = "seventy"
    #expect(form.aboutErrors()[.weight] == Copy.validation.required)
  }

  @Test func feetWithNoInchesCountAsWholeFeet() {
    var form = filled(measurement: .us)
    form.feet = "5"
    form.inches = ""
    #expect(form.heightCm == 152.4)
    form.feet = ""
    #expect(form.heightCm == nil)
  }

  @Test func proteinAndFatSettingsHaveLimits() {
    var form = filled()
    form.proteinPerKg = "5"
    form.fatPercent = "10"
    let errors = form.adjustErrors()
    #expect(errors[.proteinPerKg]?.text == "Use a number from 1.2 to 3.")
    #expect(errors[.fatPercent]?.text == "Use a number from 20 to 40.")
    // Out of range, so the calculator falls back to its defaults.
    #expect(form.resolved?.values[.protein] == 134)
  }

  @Test func typedTargetsMustBeWholeNumbersInRange() {
    var form = filled()
    form.overrides[.calories] = "500"
    form.overrides[.protein] = "12.5"
    form.overrides[.carbs] = ""
    form.overrides[.fat] = "1001"
    let errors = form.targetErrors()
    #expect(errors[.target(.calories)]?.text == "Use a whole number from 800 to 10000.")
    #expect(errors[.target(.protein)]?.text == "Use a whole number from 0 to 1000.")
    #expect(errors[.target(.carbs)] == Copy.validation.required)
    #expect(errors[.target(.fat)]?.text == "Use a whole number from 0 to 1000.")
  }

  @Test func aFormWithErrorsSavesNothing() throws {
    var form = filled()
    form.overrides[.calories] = "500"
    #expect(throws: TargetsForm.Invalid.self) { try form.save(in: context) }
    var blank = TargetsForm(today: today, measurement: .metric)
    blank.weight = "70"
    #expect(throws: TargetsForm.Invalid.self) { try blank.save(in: context) }
    #expect(try count(TargetsRecord.self) == 0)
    #expect(try count(BodyProfileRecord.self) == 0)
    #expect(try count(WeighInRecord.self) == 0)
  }

  // MARK: Units

  @Test func unitsFollowTheRegion() {
    let american = TargetsForm(today: today, measurement: .us)
    #expect(american.weightUnit == .lb && american.heightUnit == .ftin)
    for system in [Locale.MeasurementSystem.metric, .uk] {
      let form = TargetsForm(today: today, measurement: system)
      #expect(form.weightUnit == .kg && form.heightUnit == .cm)
    }
  }

  @Test func switchingUnitsKeepsTheSameBody() {
    var form = filled()
    form.weight = "74.8"
    form.switchWeightUnit(to: .lb)
    #expect(form.weight == "164.9")
    #expect(form.rate == 1)
    form.switchWeightUnit(to: .kg)
    #expect(form.weight == "74.8")
    #expect(form.rate == 0.5)

    form.cm = "175"
    form.switchHeightUnit(to: .ftin)
    #expect(form.feet == "5" && form.inches == "8.9")
    form.switchHeightUnit(to: .cm)
    #expect(form.cm == "175")
  }

  @Test func changingTheGoalPicksItsDefaultRate() {
    var form = filled()
    form.choose(goal: .gain)
    #expect(form.rate == 0.5)
    form.choose(goal: .maintain)
    #expect(form.rate == nil)
    #expect(rateChoices(goal: .lose, unit: .lb).map(\.amount) == [0.5, 1, 1.5, 2])
    #expect(rateChoices(goal: .gain, unit: .kg).map(\.amount) == [0.25, 0.5])
    #expect(rateChoices(goal: .maintain, unit: .kg).isEmpty)
  }

  // MARK: Opening

  @Test func aNewCookStartsOnTheFirstStepWithNothingFilledIn() throws {
    let form = try TargetsForm.load(from: context, today: today, measurement: .us)
    #expect(!form.startsOnTargets)
    #expect(form.weight.isEmpty && form.sex == nil && form.overrides.isEmpty)
    #expect(form.weightUnit == .lb)
  }

  @Test func theWeightComesFromTheLatestWeighInInTheLastYear() throws {
    context.insert(WeighInRecord(day: today.adding(days: -400), weightKg: 90))
    context.insert(WeighInRecord(day: today.adding(days: -20), weightKg: 72))
    context.insert(WeighInRecord(day: today.adding(days: -3), weightKg: 71.4))
    try context.save()
    let form = try TargetsForm.load(from: context, today: today, measurement: .metric)
    #expect(form.weight == "71.4")
    // No profile yet, so the cook still starts at the beginning.
    #expect(!form.startsOnTargets)

    context.insert(WeighInRecord(day: today.adding(days: -1), weightKg: 71.0))
    try context.save()
    #expect(
      try TargetsForm.load(from: context, today: today, measurement: .metric).weight == "71")
  }

  @Test func aWeighInOlderThanAYearIsNotUsed() throws {
    context.insert(WeighInRecord(day: today.adding(days: -366), weightKg: 90))
    try context.save()
    #expect(
      try TargetsForm.load(from: context, today: today, measurement: .metric).weight.isEmpty)
  }

  @Test func aSavedCookReopensInTheirOwnUnits() throws {
    var form = filled(measurement: .us)
    form.feet = "5"
    form.inches = "6"
    form.weight = "163.6"
    try form.save(in: context)

    // The region says metric now, but the saved choice wins.
    let reopened = try TargetsForm.load(from: context, today: today, measurement: .metric)
    #expect(reopened.weightUnit == .lb && reopened.heightUnit == .ftin)
    #expect(reopened.weight == "163.6")
    #expect(reopened.feet == "5" && reopened.inches == "6")
    #expect(reopened.sex == .female)
    #expect(reopened.goal == .lose && reopened.rate == 1)
    #expect(reopened.startsOnTargets)
    #expect(reopened.aboutErrors().isEmpty)
  }
}

@Suite("Reading numbers")
struct TargetsNumbersTests {
  @Test func readsPlainDecimalsAndAComma() {
    #expect(parseNumber("74.2") == 74.2)
    #expect(parseNumber(" 74,2 ") == 74.2)
    #expect(parseNumber("12") == 12)
    #expect(parseNumber("") == nil)
    #expect(parseNumber("  ") == nil)
    #expect(parseNumber("abc") == nil)
    #expect(parseNumber("0x10") == nil)
    #expect(parseNumber("inf") == nil)
    #expect(parseNumber("1,2,3") == nil)
  }

  @Test func showsNumbersWithoutATrailingZero() {
    #expect(showNumber(74) == "74")
    #expect(showNumber(74.25) == "74.3")
    #expect(showNumber(1.8) == "1.8")
    #expect(showNumber(25, digits: 0) == "25")
    #expect(showNumber(1.375, digits: 3) == "1.375")
  }

  @Test func theNearestRateIsPickedForAStoredOne() {
    #expect(nearestRate(goal: .lose, unit: .kg, kg: 0.5) == 0.5)
    #expect(nearestRate(goal: .lose, unit: .lb, kg: 0.45) == 1)
    #expect(nearestRate(goal: .gain, unit: .kg, kg: 0.9) == 0.5)
    #expect(nearestRate(goal: .maintain, unit: .kg, kg: 0) == nil)
  }
}

@MainActor
@Suite("Targets screen")
struct TargetsScreenTests {
  private let today = LocalDate(year: 2026, month: 10, day: 10)!

  private func complete() -> TargetsForm {
    var form = TargetsForm(today: today, measurement: .us)
    form.sex = .female
    form.birthDate = LocalDate(year: 1990, month: 5, day: 14)
    form.feet = "5"
    form.inches = "6"
    form.weight = "163.6"
    form.choose(goal: .lose)
    form.overrides[.protein] = "150"
    return form
  }

  @Test func everyStepDrawsInBothAppearances() {
    for step in 0...2 {
      for scheme in [ColorScheme.light, .dark] {
        let view = TargetsEditor(form: .constant(complete()), saveError: nil, step: step) {}
          .environment(\.colorScheme, scheme)
          .frame(width: 390, height: 800)
        #expect(ImageRenderer(content: view).cgImage != nil, "step \(step) in \(scheme)")
      }
    }
  }

  @Test func aBlankFormDrawsEveryStepWithItsErrors() {
    let blank = TargetsForm(today: today, measurement: .metric)
    for step in 0...2 {
      let view = TargetsEditor(
        form: .constant(blank), saveError: Copy.tracker.targets.fixThese, step: step
      ) {}
      .frame(width: 390, height: 800)
      #expect(ImageRenderer(content: view).cgImage != nil, "step \(step)")
    }
  }
}
