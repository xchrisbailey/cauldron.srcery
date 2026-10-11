import CauldronKit
import Foundation
import Testing

// Ported from `packages/shared/test/gather.test.ts`. The TypeScript named recipes and rows with
// plain strings ("a", "eggs"); here they are UUIDs made from the same letters.

func recipeId(_ name: String) -> RecipeId {
  var bytes = [UInt8](repeating: 0, count: 16)
  for (offset, byte) in name.utf8.enumerated() where offset < 16 { bytes[15 - offset] = byte }
  return UUID(
    uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8],
      bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}

private func line(_ recipe: String, _ text: String) -> GatherLine {
  let p = parseIngredientLine(text)
  return GatherLine(
    recipeId: recipeId(recipe), item: p.item, itemKey: ingredientKey(p.item),
    quantity: p.quantity, unit: p.unit)
}

private func gather(_ entries: (String, String)...) -> [GatheredRow] {
  gatherLines(entries.map { line($0.0, $0.1) })
}

private func find(_ rows: [GatheredRow], _ itemKey: String) -> [GatheredRow] {
  rows.filter { $0.itemKey == itemKey }
}

private func q(_ min: Double, _ max: Double? = nil) -> Quantity { Quantity(min: min, max: max) }

@Suite("measureGroup and mergeKeyOf")
struct MeasureGroupTests {
  @Test func groupsMeasuresByHowTheyAddUp() {
    #expect(measureGroup(nil, nil) == "none")
    // A unit with no amount adds nothing, like no unit at all.
    #expect(measureGroup(nil, .cup) == "none")
    #expect(measureGroup(q(2), nil) == "count")
    #expect(measureGroup(q(2), .cup) == "volume")
    #expect(measureGroup(q(2), .tbsp) == "volume")
    #expect(measureGroup(q(2), .g) == "mass")
    #expect(measureGroup(q(2), .lb) == "mass")
    #expect(measureGroup(q(2), .clove) == "unit:clove")
    #expect(measureGroup(q(2), .can) == "unit:can")
  }

  @Test func buildsTheMergeKeyFromItemKeyAndGroup() {
    #expect(mergeKeyOf("flour", q(1), .cup) == "flour|volume")
    #expect(mergeKeyOf("flour", q(200), .g) == "flour|mass")
    #expect(mergeKeyOf("salt", nil, nil) == "salt|none")
  }
}

@Suite("gatherLines merging")
struct GatherMergingTests {
  @Test func addsTheSameItemInTheSameUnit() {
    let rows = gather(("a", "2 cups flour"), ("b", "1 cup flour"))
    #expect(rows.count == 1)
    #expect(rows[0].itemKey == "flour")
    #expect(rows[0].quantity == q(3))
    #expect(rows[0].unit == .cup)
  }

  @Test func addsBareCountsThroughTheItemKey() {
    let rows = gather(("a", "2 onions"), ("b", "1 onion"))
    #expect(rows.count == 1)
    #expect(rows[0].itemKey == "onion")
    #expect(rows[0].quantity == q(3))
    #expect(rows[0].unit == nil)
  }

  @Test func keeps200gAnd1CupOfFlourAsTwoRows() throws {
    let rows = gather(("a", "200 g flour"), ("b", "1 cup flour"))
    let flour = find(rows, "flour")
    #expect(flour.count == 2)
    #expect(flour.compactMap { $0.unit?.rawValue }.sorted() == ["cup", "g"])
    #expect(try #require(flour.first { $0.unit == .g }).quantity == q(200))
    #expect(try #require(flour.first { $0.unit == .cup }).quantity == q(1))
    #expect(flour[0].mergeKey != flour[1].mergeKey)
  }

  @Test func keepsABareCountAndAMeasuredAmountOfTheSameItemApart() {
    let rows = gather(("a", "2 lemons"), ("b", "1 tbsp lemon"))
    #expect(find(rows, "lemon").count == 2)
  }

  @Test func sumsTbspAndCupIntoOneRowInAUSUnit() throws {
    let rows = gather(("a", "4 tbsp olive oil"), ("b", "1 cup olive oil"))
    #expect(rows.count == 1)
    #expect(rows[0].unit == .cup)
    #expect(closeTo(try #require(rows[0].quantity).min, 1.25, digits: 1))
    #expect(rows[0].quantity?.max == nil)
  }

  @Test func stepsASmallMixedUSVolumeDownToAUnitThatReadsWell() throws {
    let rows = gather(("a", "1 tsp vanilla extract"), ("b", "1 tbsp vanilla extract"))
    #expect(rows.count == 1)
    #expect(rows[0].unit == .tbsp)
    #expect(closeTo(try #require(rows[0].quantity).min, 1.333, digits: 2))
  }

  @Test func sumsGAndKgIntoOneMetricRow() throws {
    let rows = gather(("a", "500 g rice"), ("b", "1.5 kg rice"))
    #expect(rows.count == 1)
    // Already-metric units are kept as is, so this reads "2000 g" rather than "2 kg".
    let row = rows[0]
    #expect(row.unit == .g || row.unit == .kg)
    let min = try #require(row.quantity).min
    #expect(closeTo(min * (row.unit == .kg ? 1000 : 1), 2000, digits: 6))
  }

  @Test func sumsLbAndOzIntoAUSMass() throws {
    let rows = gather(("a", "1 lb potatoes"), ("b", "8 oz potatoes"))
    #expect(rows.count == 1)
    #expect(rows[0].unit == .lb)
    #expect(closeTo(try #require(rows[0].quantity).min, 1.5, digits: 2))
  }

  @Test func addsRangesUsingMinWhereMaxIsAbsent() {
    let same = gather(("a", "1-2 tbsp maple syrup"), ("b", "1-2 tbsp maple syrup"))
    #expect(same[0].quantity == q(2, 4))
    let mixed = gather(("a", "1-2 tbsp maple syrup"), ("b", "1 tbsp maple syrup"))
    #expect(mixed[0].quantity == q(2, 3))
    let reversed = gather(("a", "1 tbsp maple syrup"), ("b", "1-3 tbsp maple syrup"))
    #expect(reversed[0].quantity == q(2, 4))
  }

  @Test func addsRangesThroughAUnitConversion() throws {
    let rows = gather(("a", "1-2 cups milk"), ("b", "8 tbsp milk"))
    #expect(rows.count == 1)
    #expect(rows[0].unit == .cup)
    #expect(closeTo(try #require(rows[0].quantity).min, 1.5, digits: 1))
    #expect(closeTo(try #require(rows[0].quantity?.max), 2.5, digits: 1))
  }

  @Test func mergesClovesWithClovesAndKeepsClovesApartFromCans() {
    let rows = gather(("a", "3 cloves garlic"), ("b", "4 cloves garlic"))
    #expect(rows.count == 1)
    #expect(rows[0].unit == .clove)
    #expect(rows[0].quantity == q(7))
    let apart = gather(("a", "3 cloves garlic"), ("b", "1 can garlic"))
    #expect(find(apart, "garlic").count == 2)
  }

  @Test func keepsClovesAndBareGarlicApart() {
    let rows = gather(("a", "3 cloves garlic"), ("b", "1 garlic"))
    #expect(find(rows, "garlic").count == 2)
  }

  @Test func joinsAToTasteLineToAMeasuredRowForTheSameItem() throws {
    let rows = gather(("a", "1 tsp salt"), ("b", "Salt, to taste"))
    #expect(rows.count == 1)
    #expect(rows[0].itemKey == "salt")
    #expect(rows[0].quantity == q(1))
    #expect(rows[0].unit == .tsp)
    #expect(
      rows[0].sources.map(\.recipeId.uuidString).sorted() == [
        recipeId("a").uuidString, recipeId("b").uuidString,
      ])
    let b = try #require(rows[0].sources.first { $0.recipeId == recipeId("b") })
    #expect(b.quantity == nil)
    #expect(b.unit == nil)
  }

  @Test func joinsAToTasteLineRegardlessOfOrder() {
    let rows = gather(("b", "Salt, to taste"), ("a", "1 tsp salt"))
    #expect(rows.count == 1)
    #expect(rows[0].quantity == q(1))
  }

  @Test func givesAToTasteLineItsOwnRowWithNoAmountWhenNothingIsMeasured() {
    let rows = gather(("a", "Salt, to taste"), ("b", "salt, to taste"))
    #expect(rows.count == 1)
    #expect(rows[0].quantity == nil)
    #expect(rows[0].unit == nil)
    #expect(rows[0].sources.count == 2)
  }

  @Test func doesNotJoinAToTasteLineToADifferentItemKey() {
    let rows = gather(("a", "1 tsp kosher salt"), ("b", "Salt, to taste"))
    #expect(rows.count == 2)
    #expect(find(rows, "salt")[0].quantity == nil)
  }

  @Test func keepsAMeasuredRowWhenTheHostIsOneOfSeveralMeasureGroups() {
    let rows = gather(
      ("a", "1 cup flour"), ("b", "200 g flour"), ("c", "Flour, for dusting"))
    let flour = find(rows, "flour")
    #expect(flour.count == 2)
    #expect(flour.reduce(0) { $0 + $1.sources.count } == 3)
  }

  @Test func returnsNothingForNoLines() {
    #expect(gatherLines([]).isEmpty)
  }
}

@Suite("gatherLines sources")
struct GatherSourcesTests {
  @Test func groupsPerRecipeWithEachRecipesOwnTotal() throws {
    let rows = gather(
      ("a", "1 cup flour"), ("b", "1/2 cup flour"), ("a", "1 cup flour"), ("c", "4 tbsp flour"))
    #expect(rows.count == 1)
    let row = rows[0]
    #expect(row.sources.count == 3)
    let a = try #require(row.sources.first { $0.recipeId == recipeId("a") })
    let b = try #require(row.sources.first { $0.recipeId == recipeId("b") })
    let c = try #require(row.sources.first { $0.recipeId == recipeId("c") })
    #expect(a.unit == .cup && a.quantity == q(2))
    #expect(b.unit == .cup && b.quantity == q(0.5))
    #expect(c.unit == .tbsp && c.quantity == q(4))
    #expect(row.unit == .cup)
    #expect(closeTo(try #require(row.quantity).min, 2.75, digits: 1))
  }

  @Test func totalsARecipesOwnMixedUnitsForItsSource() throws {
    let rows = gather(("a", "1 cup milk"), ("a", "4 tbsp milk"))
    #expect(rows[0].sources.count == 1)
    #expect(rows[0].sources[0].unit == .cup)
    #expect(closeTo(try #require(rows[0].sources[0].quantity).min, 1.25, digits: 1))
  }
}

private struct AisleRow: AisleSortable, Equatable {
  let aisle: Aisle
  let item: String
}

@Suite("gatherLines naming and order")
struct GatherNamingTests {
  @Test func picksTheMostCommonSpellingOfTheItem() {
    let rows = gather(("a", "2 eggs"), ("b", "1 large egg"), ("c", "3 eggs"))
    #expect(rows.count == 1)
    #expect(rows[0].item == "eggs")
  }

  @Test func letsTheFirstSeenWinATie() {
    let rows = gather(("a", "2 large eggs"), ("b", "1 egg"))
    #expect(rows[0].item == "large eggs")
  }

  @Test func sortsByAisleOrderThenByItemName() {
    let rows = gather(
      ("a", "1 cup rice"), ("a", "2 carrots"), ("a", "1 tsp cumin"), ("a", "1 apple"),
      ("a", "1 lb chicken thighs"), ("a", "1 cup milk"), ("a", "1 loaf bread"),
      ("a", "1 frozen pizza"), ("a", "1 cup coffee"), ("a", "1 widget"))
    let aisles = rows.map(\.aisle)
    let order = Aisle.allCases
    #expect(
      aisles == aisles.sorted { order.firstIndex(of: $0) ?? 0 < order.firstIndex(of: $1) ?? 0 })
    #expect(Set(aisles).count >= 8)
    let produce = rows.filter { $0.aisle == .produce }.map(\.item)
    #expect(produce == produce.sorted())
    #expect(Array(produce.prefix(2)) == ["apple", "carrots"])
  }

  @Test func sortsItemNamesCaseInsensitively() {
    let rows = sortRows([
      AisleRow(aisle: .pantry, item: "Sugar"),
      AisleRow(aisle: .pantry, item: "flour"),
      AisleRow(aisle: .produce, item: "zucchini"),
      AisleRow(aisle: .pantry, item: "Baking soda"),
    ])
    #expect(rows.map(\.item) == ["zucchini", "Baking soda", "flour", "Sugar"])
  }

  @Test func doesNotMutateTheRowsItSorts() {
    let input = [AisleRow(aisle: .pantry, item: "b"), AisleRow(aisle: .produce, item: "a")]
    _ = sortRows(input)
    #expect(input[0].item == "b")
  }
}

@Suite("gatherWeek")
struct GatherWeekTests {
  private func planned(
    _ recipe: String, _ recipeServings: Int?, _ servings: Int?, _ texts: String...
  ) -> PlannedEntry {
    PlannedEntry(
      recipeId: recipeId(recipe), recipeServings: recipeServings, servings: servings,
      ingredients: texts.map {
        let l = line(recipe, $0)
        return PlannedIngredient(
          item: l.item, itemKey: l.itemKey, quantity: l.quantity, unit: l.unit)
      })
  }

  @Test func scalesEachEntryByItsServingsAgainstTheRecipes() {
    let rows = gatherWeek([planned("a", 4, 8, "1 cup flour", "1-2 eggs")])
    #expect(find(rows, "flour")[0].quantity == q(2))
    #expect(find(rows, "egg")[0].quantity == q(2, 4))
  }

  @Test func leavesAnEntryUnscaledWhenEitherServingCountIsUnknown() {
    let rows = gatherWeek([
      planned("a", nil, 8, "1 cup flour"),
      planned("b", 4, nil, "100 g sugar"),
    ])
    #expect(find(rows, "flour")[0].quantity == q(1))
    #expect(find(rows, "sugar")[0].quantity == q(100))
  }

  @Test func sumsARecipePlannedTwiceIntoOneSourceAndKeepsAmountLessLinesBare() {
    let rows = gatherWeek([
      planned("a", 2, 2, "1 cup milk", "salt"),
      planned("a", 2, 4, "1 cup milk", "salt"),
    ])
    let milk = find(rows, "milk")[0]
    #expect(milk.quantity == q(3))
    #expect(
      milk.sources == [GatherContribution(recipeId: recipeId("a"), quantity: q(3), unit: .cup)])
    #expect(find(rows, "salt")[0].quantity == nil)
  }

  @Test func returnsNothingForAnEmptyWeek() {
    #expect(gatherWeek([]).isEmpty)
  }
}

@Suite("reconcile")
struct ReconcileTests {
  /// Storage's rounding: numeric(12, 4).
  private let round: (Double) -> Double = { ($0 * 10_000).rounded() / 10_000 }

  private func id(_ name: String) -> GatherItemId { recipeId(name) }

  /// A row as the list holds it after a previous sync.
  private func held(
    _ name: String, _ row: GatheredRow, checked: Bool = false,
    changing change: (inout ExistingGatherRow) -> Void = { _ in }
  ) -> ExistingGatherRow {
    var existing = ExistingGatherRow(
      id: id(name), item: row.item, itemKey: row.itemKey, quantity: row.quantity,
      unit: row.unit, aisle: row.aisle, checked: checked, sources: row.sources)
    change(&existing)
    return existing
  }

  @Test func changesNothingWhenTheWeekIsTheSame() {
    let rows = gather(("a", "200 g spaghetti"), ("a", "2 eggs"), ("b", "2 eggs"))
    let existing = rows.enumerated().map {
      held("id\($0.offset)", $0.element, checked: $0.offset == 0)
    }
    #expect(
      reconcile(existing: existing, wanted: rows, round: round)
        == Reconciled(inserts: [], updates: [], removals: []))
  }

  @Test func addsRowsThatAreNewAndRemovesLeftovers() throws {
    let eggs = try #require(gather(("a", "2 eggs")).first)
    let lettuce = try #require(gather(("b", "2 lettuce")).first)
    let rice = try #require(gather(("c", "1 cup rice")).first)
    let result = reconcile(
      existing: [held("eggs", eggs), held("lettuce", lettuce)], wanted: [eggs, rice], round: round)
    #expect(result.inserts == [rice])
    #expect(result.updates.isEmpty)
    #expect(result.removals == [id("lettuce")])
  }

  @Test func unchecksACheckedRowWhenTheWeekNeedsMore() throws {
    let before = try #require(gather(("a", "1 cup flour")).first)
    let after = try #require(gather(("a", "2 cups flour")).first)
    let result = reconcile(
      existing: [held("flour", before, checked: true)], wanted: [after], round: round)
    #expect(
      result.updates == [
        GatherUpdate(id: id("flour"), row: after, changed: true, uncheck: true, sources: true)
      ])
  }

  @Test func unchecksWhenAnotherRecipeAddsToACheckedRow() throws {
    let before = try #require(gather(("a", "2 eggs")).first)
    let after = try #require(gather(("a", "2 eggs"), ("b", "3 eggs")).first)
    let result = reconcile(
      existing: [held("eggs", before, checked: true)], wanted: [after], round: round)
    #expect(
      result.updates == [
        GatherUpdate(id: id("eggs"), row: after, changed: true, uncheck: true, sources: true)
      ])
  }

  @Test func countsMoreThroughAUnitChange() throws {
    let before = try #require(gather(("a", "1 cup milk")).first)
    let after = try #require(gather(("a", "20 tbsp milk")).first)
    let result = reconcile(
      existing: [held("milk", before, checked: true)], wanted: [after], round: round)
    #expect(result.updates[0].changed)
    #expect(result.updates[0].uncheck)
  }

  @Test func keepsTheCheckWhenTheWeekNeedsLess() throws {
    let before = try #require(gather(("a", "2 cups flour")).first)
    let after = try #require(gather(("a", "1.5 cups flour")).first)
    let result = reconcile(
      existing: [held("flour", before, checked: true)], wanted: [after], round: round)
    #expect(
      result.updates == [
        GatherUpdate(id: id("flour"), row: after, changed: true, uncheck: false, sources: true)
      ])
  }

  @Test func neverUnchecksARowThatIsntChecked() throws {
    let before = try #require(gather(("a", "1 cup flour")).first)
    let after = try #require(gather(("a", "2 cups flour")).first)
    let result = reconcile(existing: [held("flour", before)], wanted: [after], round: round)
    #expect(result.updates[0].changed)
    #expect(!result.updates[0].uncheck)
  }

  @Test func updatesARowWhoseNameUnitOrAisleChangedButWhoseAmountDidnt() throws {
    let row = try #require(gather(("a", "2 eggs")).first)
    let changes: [(inout ExistingGatherRow) -> Void] = [
      { $0.item = "large eggs" }, { $0.aisle = nil }, { $0.aisle = .pantry },
    ]
    for change in changes {
      let result = reconcile(
        existing: [held("eggs", row, checked: true, changing: change)], wanted: [row],
        round: round)
      #expect(
        result.updates == [
          GatherUpdate(id: id("eggs"), row: row, changed: true, uncheck: false, sources: false)
        ])
    }
    let cups = try #require(gather(("a", "1 cup milk")).first)
    let result = reconcile(
      existing: [held("milk", cups) { $0.unit = .ml }], wanted: [cups], round: round)
    #expect(result.updates[0].changed)
    #expect(!result.updates[0].sources)
  }

  @Test func rewritesOnlyTheSourcesWhenTheTotalHoldsButWhoNeedsItMoved() throws {
    let before = try #require(gather(("a", "2 eggs"), ("b", "2 eggs")).first)
    let after = try #require(gather(("c", "4 eggs")).first)
    let result = reconcile(
      existing: [held("eggs", before, checked: true)], wanted: [after], round: round)
    #expect(
      result.updates == [
        GatherUpdate(id: id("eggs"), row: after, changed: false, uncheck: false, sources: true)
      ])
  }

  @Test func matchesSourcesWhateverOrderTheyWereReadIn() throws {
    let row = try #require(gather(("a", "2 eggs"), ("b", "3 eggs")).first)
    let existing = held("eggs", row) { $0.sources = row.sources.reversed() }
    #expect(reconcile(existing: [existing], wanted: [row], round: round).updates.isEmpty)
  }

  @Test func keepsTheFirstRowForAMergeKeyAndRemovesAnyThatRepeatIt() throws {
    let eggs = try #require(gather(("a", "2 eggs")).first)
    let result = reconcile(
      existing: [held("first", eggs, checked: true), held("again", eggs), held("third", eggs)],
      wanted: [eggs], round: round)
    #expect(result.inserts.isEmpty)
    #expect(result.updates.isEmpty)
    #expect(result.removals == [id("again"), id("third")])
  }

  @Test func keysRowsByMeasureSoCupsAndGramsOfOneItemAreTwoRows() throws {
    let rows = gather(("a", "1 cup flour"), ("b", "200 g flour"))
    let cups = try #require(rows.first { $0.unit == .cup })
    let result = reconcile(existing: [held("cups", cups)], wanted: rows, round: round)
    #expect(result.inserts.map(\.unit) == [.g])
    #expect(result.removals.isEmpty)
  }

  @Test func comparesAmountsAsStoredSoAThirdDoesntFlapOnEverySync() {
    let rows = gatherWeek([
      PlannedEntry(
        recipeId: recipeId("a"), recipeServings: 6, servings: 2,
        ingredients: [
          PlannedIngredient(item: "flour", itemKey: "flour", quantity: q(1), unit: .cup),
          PlannedIngredient(item: "onion", itemKey: "onion", quantity: q(1), unit: nil),
        ])
    ])
    let first = reconcile(existing: [], wanted: rows, round: round)
    #expect(first.inserts.map(\.quantity) == [q(0.3333), q(0.3333)])
    #expect(first.inserts[0].sources[0].quantity == q(0.3333))
    // Stored rounded down, checked: the next sync wants 1/3 again and leaves it be.
    let existing = first.inserts.enumerated().map {
      held("id\($0.offset)", $0.element, checked: true)
    }
    #expect(
      reconcile(existing: existing, wanted: rows, round: round)
        == Reconciled(inserts: [], updates: [], removals: []))
  }
}

@Suite("aisleFor")
struct AisleForTests {
  static let cases: [(String, Aisle)] = [
    ("garlic powder", .spices),
    ("onion powder", .spices),
    ("freshly ground pepper", .spices),
    ("cream of tartar", .spices),
    ("apple cider vinegar", .pantry),
    ("coconut cream", .pantry),
    ("egg noodles", .pantry),
    ("orange juice", .drinks),
    ("garlic cloves", .produce),
    ("onion", .produce),
    ("2 red onions", .produce),
    ("garlic", .produce),
    ("fresh ginger", .produce),
    ("cherry tomatoes", .produce),
    ("red bell pepper", .produce),
    ("jalapeno", .produce),
    ("eggplant", .produce),
    ("aubergine", .produce),
    ("baby spinach", .produce),
    ("fresh basil", .produce),
    ("lemons", .produce),
    ("sweet potatoes", .produce),
    ("chicken thighs", .meat),
    ("chicken breast", .meat),
    ("ground beef", .meat),
    ("salmon fillets", .meat),
    ("bacon", .meat),
    ("milk", .dairy),
    ("large eggs", .dairy),
    ("unsalted butter", .dairy),
    ("greek yogurt", .dairy),
    ("crumbled feta", .dairy),
    ("sour cream", .dairy),
    ("baguette", .bakery),
    ("flour tortillas", .bakery),
    ("chicken stock", .pantry),
    ("vegetable broth", .pantry),
    ("crushed tomatoes", .pantry),
    ("tomato paste", .pantry),
    ("olive oil", .pantry),
    ("all-purpose flour", .pantry),
    ("brown sugar", .pantry),
    ("canned chickpeas", .pantry),
    ("peanut butter", .pantry),
    ("black pepper", .spices),
    ("chili flakes", .spices),
    ("red pepper flakes", .spices),
    ("kosher salt", .spices),
    ("ground cumin", .spices),
    ("smoked paprika", .spices),
    ("bay leaves", .spices),
    ("dried oregano", .spices),
    ("frozen peas", .frozen),
    ("ice cream", .frozen),
    ("sparkling water", .drinks),
    ("white wine", .drinks),
    ("xanthan gum", .other),
    ("", .other),
  ]

  @Test(arguments: cases)
  func findsTheAisle(text: String, aisle: Aisle) {
    #expect(aisleFor(ingredientKey(text)) == aisle)
  }

  @Test func isNeverDairyForEggplantAndKeepsPepperKindsApart() {
    #expect(aisleFor(ingredientKey("eggplant")) != .dairy)
    #expect(aisleFor(ingredientKey("black pepper")) != aisleFor(ingredientKey("red bell pepper")))
  }
}
