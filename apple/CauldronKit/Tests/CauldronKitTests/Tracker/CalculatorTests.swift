import CauldronKit
import Foundation
import Testing

/// Ported case for case from `packages/shared/test/calculator.test.ts`.
private func day(_ string: String) -> LocalDate { LocalDate(string)! }

private let base = CalculatorInput(
  sex: .male, birthDate: day("1996-03-15"), heightCm: 180, weightKg: 80, activity: .moderate,
  goal: .maintain, weeklyRateKg: 0, today: day("2026-10-05"))

private func close(_ a: Double, _ b: Double, within tolerance: Double = 1e-6) -> Bool {
  abs(a - b) <= tolerance
}

@Suite("ageOn")
struct AgeOnTests {
  @Test func countsWholeYearsAndRollsOverOnTheBirthday() {
    #expect(ageOn(birthDate: day("1996-10-06"), today: day("2026-10-05")) == 29)
    #expect(ageOn(birthDate: day("1996-10-05"), today: day("2026-10-05")) == 30)
    #expect(ageOn(birthDate: day("1996-10-04"), today: day("2026-10-05")) == 30)
    #expect(ageOn(birthDate: day("1996-11-01"), today: day("2026-10-05")) == 29)
  }

  @Test func treatsALeapDayBirthdayAsPassedOnMarchFirstInACommonYear() {
    #expect(ageOn(birthDate: day("2000-02-29"), today: day("2026-02-28")) == 25)
    #expect(ageOn(birthDate: day("2000-02-29"), today: day("2026-03-01")) == 26)
  }
}

@Suite("restingEnergy")
struct RestingEnergyTests {
  @Test func usesTheMifflinStJeorConstantsForEachSex() {
    // 10*80 + 6.25*180 - 5*30 = 800 + 1125 - 150 = 1775
    func resting(_ sex: Sex) -> Double {
      restingEnergy(sex: sex, ageYears: 30, heightCm: 180, weightKg: 80)
    }
    #expect(resting(.male) == 1780)
    #expect(resting(.female) == 1614)
    #expect(resting(.unspecified) == 1697)
  }
}

@Suite("calculateTargets")
struct CalculateTargetsTests {
  @Test func maintainsMale30At180cm80kgModerate() {
    let result = calculateTargets(base)
    // resting = 800 + 1125 - 150 + 5 = 1780
    #expect(result.restingEnergy == 1780)
    // expenditure = 1780 * 1.55 = 2759
    #expect(close(result.expenditure, 2759))
    #expect(result.dailyAdjustment == 0)
    #expect(result.weeklyRateKg == 0)
    #expect(result.floored == false)
    // calories = 2759 -> 2760
    // protein = 1.8 * 80 = 144 g; fat = 0.25 * 2760 / 9 = 76.67 -> 77 g
    // carbs = (2760 - 576 - 690) / 4 = 373.5 (rounding may fall either way)
    #expect(result.targets.calories == 2760)
    #expect(result.targets.protein == 144)
    #expect(result.targets.fat == 77)
    #expect(abs(Double(result.targets.carbs) - 373.5) <= 0.5)
  }

  @Test func losesFemale35At165cm70kgLightHalfAKiloAWeek() {
    var input = base
    input.sex = .female
    input.birthDate = day("1991-01-10")
    input.heightCm = 165
    input.weightKg = 70
    input.activity = .light
    input.goal = .lose
    input.weeklyRateKg = 0.5
    let result = calculateTargets(input)
    // resting = 700 + 1031.25 - 175 - 161 = 1395.25
    // expenditure = 1395.25 * 1.375 = 1918.47
    #expect(close(result.expenditure, 1918.46875, within: 5e-6))
    // adjustment = -0.5 * 7700 / 7 = -550
    #expect(close(result.dailyAdjustment, -550))
    #expect(result.weeklyRateKg == 0.5)
    #expect(result.floored == false)
    // calories = 1368.4 -> 1370
    // protein = 126 g; fat share gives 38 g but the minimum is 0.6 * 70 = 42 g
    // carbs = (1370 - 504 - 378) / 4 = 122 g
    #expect(result.targets == MacroTargets(calories: 1370, protein: 126, carbs: 122, fat: 42))
  }

  @Test func gainsUnspecified28At170cm65kgModerateQuarterKiloAWeek() {
    var input = base
    input.sex = .unspecified
    input.birthDate = day("1998-02-01")
    input.heightCm = 170
    input.weightKg = 65
    input.goal = .gain
    input.weeklyRateKg = 0.25
    let result = calculateTargets(input)
    // resting = 650 + 1062.5 - 140 - 78 = 1494.5; expenditure = 1494.5 * 1.55 = 2316.475
    #expect(result.restingEnergy == 1494.5)
    // adjustment = +0.25 * 7700 / 7 = +275
    #expect(close(result.dailyAdjustment, 275))
    // calories = 2591.475 -> 2590
    // protein = 117 g; fat = 0.25 * 2590 / 9 = 71.94 -> 72 g
    // carbs = (2590 - 468 - 647.5) / 4 = 368.6 -> 369 g
    #expect(result.targets == MacroTargets(calories: 2590, protein: 117, carbs: 369, fat: 72))
  }

  @Test func appliesTheCalorieFloorAndSaysSo() {
    var input = base
    input.sex = .female
    input.birthDate = day("2001-06-01")
    input.heightCm = 150
    input.weightKg = 45
    input.activity = .sedentary
    input.goal = .lose
    input.weeklyRateKg = 1
    let result = calculateTargets(input)
    // resting = 450 + 937.5 - 125 - 161 = 1101.5; expenditure = 1321.8
    // 1321.8 - 1100 = 221.8, below the 1200 floor for women
    #expect(result.floored)
    // protein = 81 g; fat = 0.25 * 1200 / 9 = 33.3 -> 33 g (minimum 27 g); carbs = (1200 - 324 - 300) / 4 = 144 g
    #expect(result.targets == MacroTargets(calories: 1200, protein: 81, carbs: 144, fat: 33))
  }

  @Test func usesEachSexsOwnFloor() {
    var small = base
    small.weightKg = 45
    small.heightCm = 150
    small.goal = .lose
    small.weeklyRateKg = 1
    #expect(calculateTargets(small).targets.calories == 1500)
    small.sex = .unspecified
    #expect(calculateTargets(small).targets.calories == 1350)
  }

  @Test func clampsTheWeeklyRateToTheGoalsMaximum() {
    var input = base
    input.goal = .lose
    input.weeklyRateKg = 2
    let lose = calculateTargets(input)
    #expect(lose.weeklyRateKg == 1)
    #expect(close(lose.dailyAdjustment, -1100))
    input.goal = .gain
    input.weeklyRateKg = 1
    let gain = calculateTargets(input)
    #expect(gain.weeklyRateKg == 0.5)
    #expect(close(gain.dailyAdjustment, 550))
  }

  @Test func ignoresTheRateWhenMaintaining() {
    var input = base
    input.goal = .maintain
    input.weeklyRateKg = 0.7
    let result = calculateTargets(input)
    #expect(result.weeklyRateKg == 0)
    #expect(result.dailyAdjustment == 0)
    #expect(result.targets.calories == 2760)
  }

  @Test func changesWithABirthday() {
    var input = base
    input.birthDate = day("1996-10-06")
    let before = calculateTargets(input)
    input.birthDate = day("1996-10-05")
    let after = calculateTargets(input)
    // One year older: resting energy drops by 5, expenditure by 5 * 1.55
    #expect(before.restingEnergy - after.restingEnergy == 5)
    #expect(
      close(
        before.expenditure - after.expenditure, 5 * ActivityLevel.moderate.multiplier,
        within: 5e-3))
  }

  @Test func honoursCustomProteinAndFatSettings() {
    var input = base
    input.proteinPerKg = 2.2
    input.fatShare = 0.35
    let result = calculateTargets(input)
    // protein = 176 g; fat = 0.35 * 2760 / 9 = 107.3 -> 107 g
    #expect(result.targets.protein == 176)
    #expect(result.targets.fat == 107)
  }

  @Test func multipliesRestingEnergyByTheActivityLevel() {
    #expect(ActivityLevel.sedentary.multiplier == 1.2)
    #expect(ActivityLevel.light.multiplier == 1.375)
    #expect(ActivityLevel.moderate.multiplier == 1.55)
    #expect(ActivityLevel.active.multiplier == 1.725)
    #expect(ActivityLevel.veryActive.multiplier == 1.9)
  }
}

@Suite("splitMacros")
struct SplitMacrosTests {
  @Test func usesTheDefaultProteinAndFatShare() {
    // protein 144, fat 0.25 * 2000 / 9 = 55.6, carbs (2000 - 576 - 500) / 4 = 231
    #expect(
      splitMacros(calories: 2000, weightKg: 80)
        == MacroTargets(calories: 2000, protein: 144, carbs: 231, fat: 56))
  }

  @Test func raisesFatToThePerKgMinimumAtALowFatShare() {
    // 0.2 * 2000 / 9 = 44.4 g, under 0.6 * 80 = 48 g
    let split = splitMacros(calories: 2000, weightKg: 80, fatShare: 0.2)
    #expect(split.fat == 48)
    // carbs = (2000 - 576 - 432) / 4 = 248
    #expect(split.carbs == 248)
  }

  @Test func neverReturnsNegativeCarbs() {
    // protein 180 g (720 kcal) + fat minimum 60 g (540 kcal) already exceed 1000 kcal
    let split = splitMacros(calories: 1000, weightKg: 100)
    #expect(split.carbs == 0)
    #expect(split.protein == 180)
    #expect(split.fat == 60)
  }
}

@Suite("calculator limits")
struct CalculatorLimitsTests {
  @Test func keepsTargetsInsideWhatTheTargetsAcceptAtTheExtremes() {
    let big = splitMacros(calories: 12000, weightKg: 400, proteinPerKg: 3, fatShare: 0.2)
    #expect(big.calories == 10000)
    #expect(big.protein == 1000)
    #expect(big.fat <= 1000)
    #expect(big.carbs <= 1000)
    let carbsHeavy = splitMacros(calories: 9000, weightKg: 50, proteinPerKg: 1.2, fatShare: 0.2)
    #expect(carbsHeavy.carbs == 1000)
  }
}
