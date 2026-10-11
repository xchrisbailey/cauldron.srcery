import CauldronKit
import Foundation
import Testing

/// Ported from `packages/shared/test/recipeFacts.test.ts`.
struct MinutesCase: Sendable {
  let total: Int?
  let prep: Int?
  let cook: Int?
  let minutes: Int?
}

@Suite("recipeMinutes")
struct RecipeMinutesTests {
  static let cases: [MinutesCase] = [
    .init(total: 45, prep: 10, cook: 20, minutes: 45),
    .init(total: nil, prep: 10, cook: 20, minutes: 30),
    .init(total: nil, prep: 10, cook: nil, minutes: 10),
    .init(total: nil, prep: nil, cook: 20, minutes: 20),
    .init(total: nil, prep: nil, cook: nil, minutes: nil),
    .init(total: 0, prep: 10, cook: 20, minutes: 0),
  ]

  @Test(arguments: cases)
  func totalPrepAndCook(_ c: MinutesCase) {
    #expect(
      recipeMinutes(totalMinutes: c.total, prepMinutes: c.prep, cookMinutes: c.cook) == c.minutes)
  }
}

@Suite("servingFactor")
struct ServingFactorTests {
  @Test(
    arguments: [
      (4, 8, 2.0), (4, 2, 0.5), (4, 4, 1.0), (nil, 8, 1.0), (4, nil, 1.0), (nil, nil, 1.0),
    ] as [(Int?, Int?, Double)])
  func factor(recipe: Int?, wanted: Int?, factor: Double) {
    #expect(servingFactor(recipeServings: recipe, wanted: wanted) == factor)
  }
}

@Suite("toPlanRecipe")
struct ToPlanRecipeTests {
  @Test func carriesThePhotoAndWorksOutTheMinutes() throws {
    let id = try #require(UUID(uuidString: "6f1d7c1e-9a3b-4c55-8e0a-2b8f7f5d9a10"))
    let plan = toPlanRecipe(
      id: id, title: "Soup", servings: 4, totalMinutes: nil, prepMinutes: 5, cookMinutes: 25,
      photoKey: "photo-1", macros: .none)
    #expect(
      plan
        == PlanRecipe(
          id: id, title: "Soup", servings: 4, totalMinutes: 30, photoKey: "photo-1",
          macros: .none))
  }
}

@Suite("Scale")
struct ScaleTests {
  @Test func startsAtTheRecipesServingsOrUnscaled() {
    #expect(Scale.initial(servings: 4) == .servings(4))
    #expect(Scale.initial(servings: nil) == .multiplier(1))
  }

  @Test(
    arguments: [
      (Scale.servings(4), 2, 2.0),
      (.servings(4), nil, 1.0),
      (.multiplier(1.5), 2, 1.5),
      (.multiplier(0.25), nil, 0.25),
    ] as [(Scale, Int?, Double)])
  func factor(scale: Scale, recipe: Int?, factor: Double) {
    #expect(scale.factor(recipeServings: recipe) == factor)
  }

  @Test(
    arguments: [
      (Scale.servings(1), -1, false, Scale.servings(1)),
      (.servings(1), 1, true, .servings(2)),
      (.servings(2), -1, true, .servings(1)),
      (.servings(RecipeLimits.servings), 1, false, .servings(RecipeLimits.servings)),
      (.servings(RecipeLimits.servings - 1), 1, true, .servings(RecipeLimits.servings)),
    ] as [(Scale, Int, Bool, Scale)])
  func servingsBounds(scale: Scale, direction: Int, can: Bool, to: Scale) throws {
    let step = try #require(ScaleStep(rawValue: direction))
    #expect(scale.canStep(step) == can)
    #expect(scale.stepped(step) == to)
  }

  @Test func climbsAndDescendsTheMultiplierLadderOneRungAtATime() throws {
    var up: [Double] = []
    var scale = Scale.multiplier(try #require(Scale.multipliers.first))
    while true {
      if case .multiplier(let m) = scale { up.append(m) }
      guard scale.canStep(.up) else { break }
      scale = scale.stepped(.up)
    }
    #expect(up == [0.25, 0.5, 1, 1.5, 2, 3, 4, 6, 8])

    var down: [Double] = []
    scale = .multiplier(8)
    while true {
      if case .multiplier(let m) = scale { down.append(m) }
      guard scale.canStep(.down) else { break }
      scale = scale.stepped(.down)
    }
    #expect(down == up.reversed())
  }

  @Test(
    arguments: [
      (Scale.multiplier(0.25), -1, false, Scale.multiplier(0.25)),
      (.multiplier(8), 1, false, .multiplier(8)),
      (.multiplier(1), 1, true, .multiplier(1.5)),
      (.multiplier(1), -1, true, .multiplier(0.5)),
    ] as [(Scale, Int, Bool, Scale)])
  func multiplierBounds(scale: Scale, direction: Int, can: Bool, to: Scale) throws {
    let step = try #require(ScaleStep(rawValue: direction))
    #expect(scale.canStep(step) == can)
    #expect(scale.stepped(step) == to)
  }

  @Test(
    arguments: [Scale.servings(1), .servings(6), .servings(RecipeLimits.servings)]
      + Scale.multipliers.map(Scale.multiplier))
  func roundTripsThroughSearchParams(scale: Scale) {
    #expect(Scale(search: scale.search) == scale)
  }

  @Test func leavesAnUnscaledRecipeOutOfTheURL() {
    #expect(Scale.multiplier(1).search == ScaleSearch())
  }

  @Test(
    arguments: [
      (ScaleSearch(), Scale.multiplier(1)),
      (ScaleSearch(servings: "6"), .servings(6)),
      (ScaleSearch(multiplier: "1.5"), .multiplier(1.5)),
      (ScaleSearch(servings: 0), .multiplier(1)),
      (ScaleSearch(servings: .number(Double(RecipeLimits.servings + 1))), .multiplier(1)),
      (ScaleSearch(servings: 2.5), .multiplier(1)),
      (ScaleSearch(servings: ""), .multiplier(1)),
      (ScaleSearch(servings: true), .multiplier(1)),
      (ScaleSearch(multiplier: 2.5), .multiplier(1)),
      (ScaleSearch(multiplier: 100), .multiplier(1)),
      (ScaleSearch(multiplier: -1), .multiplier(1)),
      (ScaleSearch(servings: 4, multiplier: 2), .servings(4)),
    ] as [(ScaleSearch, Scale)])
  func readsSearchParams(search: ScaleSearch, scale: Scale) {
    #expect(Scale(search: search) == scale)
  }
}

@Suite("macroLine")
struct MacroLineTests {
  @Test func readsCaloriesThenProteinFatAndCarbs() {
    let line = macroLine(Macros(calories: 420, protein: 32, carbs: 30, fat: 18))
    #expect(
      line
        == MacroLine(
          text: "420 kcal · 32P · 18F · 30C",
          label: "Per serving: 420 kcal, 32 g protein, 18 g fat, 30 g carbs"))
  }

  @Test func roundsToWholeNumbersAndGroupsThousands() {
    #expect(
      macroLine(Macros(calories: 1249.6, protein: 31.5, carbs: 0.4, fat: 18.2))?.text
        == "1,250 kcal · 32P · 18F · 0C")
  }

  @Test func leavesOutWhatIsntKnown() {
    #expect(macroLine(Macros(calories: 380, fat: 12))?.text == "380 kcal · 12F")
    #expect(macroLine(Macros(protein: 0))?.text == "0P")
  }

  @Test func isNilWithNoMacros() {
    #expect(macroLine(.none) == nil)
  }
}
