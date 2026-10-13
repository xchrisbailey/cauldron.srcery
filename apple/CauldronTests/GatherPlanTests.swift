import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

#if DEBUG
  @MainActor
  @Suite("Gather plan")
  struct GatherPlanTests {
    private let monday = LocalDate("2026-10-05")!
    private let nextMonday = LocalDate("2026-10-12")!

    private func context() throws -> ModelContext {
      ModelContext(try CauldronStore.container(.inMemory))
    }

    /// A store holding the seeded week (the week of `monday`), with its list built.
    private func seeded() throws -> ModelContext {
      let context = try context()
      try DebugSeed.populate(context, today: monday)
      try GatherPlan.commit(in: context) { try GatherPlan.rebuild(week: monday, in: context) }
      return context
    }

    private func snapshot(_ context: ModelContext, week: LocalDate? = nil) throws -> GatherSnapshot
    {
      GatherSnapshot(
        start: week ?? monday,
        records: try context.fetch(FetchDescriptor<GatherItemRecord>()),
        pantry: try context.fetch(FetchDescriptor<PantryItemRecord>()))
    }

    private func item(_ key: String, in context: ModelContext) throws -> GatherItem {
      try #require(try snapshot(context).items.first { $0.itemKey == key }, "no \(key)")
    }

    private func entries(_ context: ModelContext) throws -> [PlanEntryRecord] {
      try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context)
    }

    private func recipe(_ title: String, in context: ModelContext) throws -> RecipeRecord {
      try #require(
        try context.fetch(FetchDescriptor<RecipeRecord>()).first { $0.title == title })
    }

    private func rebuild(_ context: ModelContext, week: LocalDate? = nil) throws -> Reconciled {
      var result = Reconciled(inserts: [], updates: [], removals: [])
      try GatherPlan.commit(in: context) {
        result = try GatherPlan.rebuild(week: week ?? monday, in: context)
      }
      return result
    }

    // MARK: Parity with the web app

    @Test func theSeededWeekMakesTheListTheWebAppMakes() throws {
      let context = try seeded()
      let snapshot = try snapshot(context)
      let rows = snapshot.items.map { item in
        let text = GatherRowText(item)
        return SeededGatherReference.ExpectedRow(
          item.aisle, item.item, text.amount, text.unit,
          item.sources.compactMap { SeededGatherReference.Recipe(rawValue: $0.title) })
      }
      #expect(rows.count == SeededGatherReference.rows.count)
      for (got, want) in zip(rows, SeededGatherReference.rows) {
        #expect(got == want)
      }
      #expect(try GatherPlan.planned(week: monday, in: context).recipeCount == 5)
      #expect(snapshot.items.allSatisfy { !$0.checked && !$0.manual && !$0.inPantry })
    }

    @Test func theListIsInStoreOrderAndGroupedByAisleInTheReferenceOrder() throws {
      let sections = try snapshot(seeded()).sections(hidingChecked: false)
      #expect(sections.map(\.aisle) == [.produce, .meat, .dairy, .pantry, .spices])
      #expect(
        sections.map(\.title.text) == [
          "Produce", "Meat and fish", "Dairy and eggs", "Pantry", "Spices",
        ])
    }

    // MARK: Rebuilding

    @Test func rebuildingAnUnchangedWeekChangesNothing() throws {
      let context = try seeded()
      let before = try context.fetchCount(FetchDescriptor<GatherItemRecord>())
      let sources = try context.fetchCount(FetchDescriptor<GatherSourceRecord>())
      let again = try rebuild(context)
      #expect(again == Reconciled(inserts: [], updates: [], removals: []))
      #expect(try context.fetchCount(FetchDescriptor<GatherItemRecord>()) == before)
      #expect(try context.fetchCount(FetchDescriptor<GatherSourceRecord>()) == sources)
    }

    @Test func aWeekWithNothingPlannedHasNoList() throws {
      let context = try context()
      let result = try rebuild(context)
      #expect(result == Reconciled(inserts: [], updates: [], removals: []))
      let snapshot = try snapshot(context)
      #expect(snapshot.isEmpty && snapshot.sections(hidingChecked: false).isEmpty)
      #expect(!snapshot.allChecked)
    }

    @Test func aWeekWithOnlyTextMealsHasNoList() throws {
      let context = try context()
      try WeekPlan.stirText("Leftovers", at: MealTarget(day: monday, slot: .lunch), into: context)
      try context.save()
      _ = try rebuild(context)
      #expect(try snapshot(context).isEmpty)
    }

    @Test func eachWeekHasItsOwnList() throws {
      let context = try seeded()
      #expect(try snapshot(context, week: nextMonday).isEmpty)
      _ = try rebuild(context, week: nextMonday)
      #expect(try snapshot(context, week: nextMonday).isEmpty)
      #expect(try snapshot(context).items.count == SeededGatherReference.rows.count)
    }

    @Test func rebuildingAfterThePlanChangesKeepsWhatWasTickedAndAddedByHand() throws {
      let context = try seeded()
      let garlic = try item("garlic", in: context)
      let beans = try item("cannellini bean", in: context)
      let oil = try item("olive oil", in: context)
      try GatherPlan.commit(in: context) {
        try GatherPlan.setChecked(garlic.id, true, in: context)
        try GatherPlan.setChecked(oil.id, true, in: context)
        try GatherPlan.add("2 lemons", week: monday, in: context)
      }

      // Take the soup off the week: its beans go, and garlic and oil need less.
      let soup = try #require(try entries(context).first { $0.title.hasPrefix("Tomato") })
      try GatherPlan.commit(in: context) { _ = try WeekPlan.remove(soup, in: context) }
      let result = try rebuild(context)
      #expect(result.removals.contains(beans.id))
      #expect(result.inserts.isEmpty)

      let after = try snapshot(context)
      #expect(!after.items.contains { $0.id == beans.id })
      #expect(try item("garlic", in: context).checked)
      #expect(try item("garlic", in: context).id == garlic.id)
      #expect(try item("olive oil", in: context).checked)
      let lemons = try #require(after.items.first { $0.manual })
      #expect(lemons.item == "lemons" && lemons.quantity == Quantity(min: 2, max: nil))
      #expect(after.items.filter(\.manual).count == 1)
    }

    @Test func aTickedLineThatTheWeekNowNeedsMoreOfIsUnticked() throws {
      let context = try seeded()
      let garlic = try item("garlic", in: context)
      try GatherPlan.commit(in: context) { try GatherPlan.setChecked(garlic.id, true, in: context) }
      let shakshuka = try #require(try entries(context).first { $0.title.hasPrefix("Shakshuka") })
      try GatherPlan.commit(in: context) {
        try WeekPlan.apply(EntryChange(servings: .some(8)), to: shakshuka, in: context)
      }
      let result = try rebuild(context)
      #expect(result.updates.contains { $0.id == garlic.id && $0.uncheck })
      let now = try item("garlic", in: context)
      #expect(!now.checked && now.id == garlic.id)
      #expect(now.quantity == Quantity(min: 16, max: nil))
      // Two recipes' worth of the line now come from a changed share of one of them.
      #expect(now.sources.map(\.title).contains("Shakshuka with feta"))
    }

    @Test func aNewRecipeAddsItsLinesAndMergesIntoExistingOnes() throws {
      let context = try seeded()
      let before = try snapshot(context).items.count
      let oats = try recipe("Overnight oats", in: context)
      try GatherPlan.commit(in: context) {
        try WeekPlan.stir(
          oats, at: MealTarget(day: monday.adding(days: 4), slot: .breakfast), servings: nil,
          into: context)
      }
      let result = try rebuild(context)
      #expect(result.inserts.isEmpty)
      #expect(result.updates.count > 0)
      #expect(try snapshot(context).items.count == before)
      #expect(try item("milk", in: context).quantity == Quantity(min: 2, max: nil))
    }

    @Test func aBanishedRecipeLeavesTheListAndComesBackWhenRestored() throws {
      let context = try seeded()
      let soup = try recipe("Tomato and white bean soup", in: context)
      RecipeLibrary.banish(soup)
      try context.save()
      let result = try rebuild(context)
      #expect(result.removals.count > 0)
      #expect(try snapshot(context).items.contains { $0.itemKey == "cannellini bean" } == false)
      #expect(
        try snapshot(context).items.flatMap(\.sources).allSatisfy {
          $0.title != "Tomato and white bean soup"
        })

      RecipeLibrary.restore(soup)
      try context.save()
      _ = try rebuild(context)
      #expect(try snapshot(context).items.contains { $0.itemKey == "cannellini bean" })
    }

    @Test func aDeletedRecipeLeavesTheListToo() throws {
      let context = try seeded()
      let soup = try recipe("Tomato and white bean soup", in: context)
      context.delete(soup)
      try context.save()
      _ = try rebuild(context)
      let after = try snapshot(context)
      #expect(!after.items.contains { $0.itemKey == "cannellini bean" })
      #expect(
        after.items.flatMap(\.sources).allSatisfy { $0.title != "Tomato and white bean soup" })
      #expect(try GatherPlan.planned(week: monday, in: context).recipeCount == 4)
    }

    @Test func rebuildingWritesTheSourcesEachRecipeAskedFor() throws {
      let context = try seeded()
      let garlic = try item("garlic", in: context)
      #expect(
        garlic.sources.map(\.title) == [
          "Shakshuka with feta", "Tomato and white bean soup",
          "Weeknight chicken thighs with lemon and garlic",
        ])
      #expect(garlic.sources.compactMap(\.quantity).map(\.min).reduce(0, +) == 13)
    }

    // MARK: Ticking

    @Test func tickingAnItemIsStoredOnItsRecord() throws {
      let context = try seeded()
      let garlic = try item("garlic", in: context)
      try GatherPlan.commit(in: context) { try GatherPlan.setChecked(garlic.id, true, in: context) }

      // Another context over the same store, as another window or a sync would read it.
      let record = try #require(
        try context.fetch(FetchDescriptor<GatherItemRecord>()).first { $0.id == garlic.id })
      #expect(record.checked)
      #expect(try item("garlic", in: context).checked)
      let after = try snapshot(context)
      #expect(after.checkedCount == 1 && !after.allChecked)
      #expect(after.progress.text == "1 of \(after.items.count) gathered")

      try GatherPlan.commit(in: context) {
        try GatherPlan.setChecked(garlic.id, false, in: context)
      }
      #expect(!(try item("garlic", in: context).checked))
    }

    @Test func tickingEverythingSaysTheShopIsDone() throws {
      let context = try seeded()
      try GatherPlan.commit(in: context) {
        for item in try snapshot(context).items {
          try GatherPlan.setChecked(item.id, true, in: context)
        }
      }
      let all = try snapshot(context)
      #expect(all.allChecked)
      #expect(all.progress == Copy.gather.allChecked)
      #expect(all.sections(hidingChecked: true).isEmpty)
      #expect(all.sections(hidingChecked: false).isEmpty == false)
    }

    @Test func hidingTickedItemsLeavesTheRestInTheirAisles() throws {
      let context = try seeded()
      let eggs = try item(ingredientKey("large eggs"), in: context)
      try GatherPlan.commit(in: context) { try GatherPlan.setChecked(eggs.id, true, in: context) }
      let sections = try snapshot(context).sections(hidingChecked: true)
      #expect(sections.flatMap(\.items).contains { $0.id == eggs.id } == false)
      #expect(sections.flatMap(\.items).count == SeededGatherReference.rows.count - 1)
    }

    @Test func tickingAnItemThatIsGoneRefusesAndChangesNothing() throws {
      let context = try seeded()
      #expect(throws: GatherError.missing) {
        try GatherPlan.commit(in: context) { try GatherPlan.setChecked(UUID(), true, in: context) }
      }
      #expect(try snapshot(context).checkedCount == 0)
    }

    // MARK: Adding by hand

    @Test func anItemAddedByHandIsParsedLikeAnIngredientLine() throws {
      let context = try context()
      try GatherPlan.commit(in: context) {
        try GatherPlan.add("  2 lemons ", week: monday, in: context)
        try GatherPlan.add("1 cup oat milk", week: monday, in: context)
        try GatherPlan.add("sourdough", week: monday, in: context)
      }
      let items = try snapshot(context).items
      #expect(items.allSatisfy { $0.manual })
      let lemons = try #require(items.first { $0.item == "lemons" })
      #expect(lemons.quantity == Quantity(min: 2, max: nil) && lemons.unit == nil)
      #expect(lemons.aisle == aisleFor(lemons.itemKey))
      let milk = try #require(items.first { $0.item == "oat milk" })
      #expect(milk.quantity == Quantity(min: 1, max: nil) && milk.unit == .cup)
      #expect(milk.aisle == .dairy)
      let bread = try #require(items.first { $0.item == "sourdough" })
      #expect(bread.quantity == nil && bread.aisle == .bakery)
      #expect(GatherRowText(milk).detail == "Added by you")
      #expect(GatherRowText(milk).amount == "1" && GatherRowText(milk).unit == "c")
    }

    @Test func aLineTheParserCantReadIsKeptWhole() throws {
      let context = try context()
      let record = try GatherPlan.add("1/2", week: monday, in: context)
      #expect(!record.item.isEmpty)
      #expect(record.manual)
    }

    @Test func aBlankLineIsRefused() throws {
      let context = try context()
      for text in ["", "   ", "\n\t "] {
        #expect(throws: GatherError.blank) { try GatherPlan.add(text, week: monday, in: context) }
      }
      #expect(try context.fetchCount(FetchDescriptor<GatherItemRecord>()) == 0)
    }

    @Test func aLineOverTheLimitIsRefusedAndOneAtTheLimitIsKept() throws {
      let context = try context()
      let long = String(repeating: "a", count: GatherLimits.line + 1)
      #expect(throws: GatherError.tooLong) { try GatherPlan.add(long, week: monday, in: context) }
      #expect(GatherError.tooLong.message.text == "Keep it to 1000 characters or fewer.")
      let fits = String(repeating: "a", count: GatherLimits.line)
      try GatherPlan.commit(in: context) { try GatherPlan.add(fits, week: monday, in: context) }
      #expect(try snapshot(context).items.count == 1)
    }

    @Test func aRefusedAddRollsBackWhatItShared() throws {
      let context = try context()
      try GatherPlan.add("milk", week: monday, in: context)
      #expect(throws: GatherError.blank) {
        try GatherPlan.commit(in: context) { try GatherPlan.add(" ", week: monday, in: context) }
      }
      // The unsaved first add went with the rollback.
      #expect(try context.fetchCount(FetchDescriptor<GatherItemRecord>()) == 0)
    }

    @Test func onlyItemsAddedByHandCanBeRemoved() throws {
      let context = try seeded()
      let hand = try GatherPlan.add("oat milk", week: monday, in: context)
      try context.save()
      let gathered = try item("garlic", in: context)
      #expect(throws: GatherError.notManual) {
        try GatherPlan.commit(in: context) { try GatherPlan.remove(gathered.id, in: context) }
      }
      try GatherPlan.commit(in: context) { try GatherPlan.remove(hand.id, in: context) }
      #expect(try snapshot(context).items.count == SeededGatherReference.rows.count)
      #expect(throws: GatherError.missing) {
        try GatherPlan.commit(in: context) { try GatherPlan.remove(hand.id, in: context) }
      }
    }

    @Test func twoItemsAddedByHandWithTheSameNameStayTwo() throws {
      let context = try context()
      try GatherPlan.commit(in: context) {
        try GatherPlan.add("milk", week: monday, in: context)
        try GatherPlan.add("milk", week: monday, in: context)
      }
      #expect(try snapshot(context).items.count == 2)
    }

    // MARK: Pantry

    @Test func markingAnItemInThePantryHoldsForEveryLineAndWeekOfThatItem() throws {
      let context = try seeded()
      try GatherPlan.commit(in: context) {
        try GatherPlan.add("2 cups milk", week: monday, in: context)
        try GatherPlan.add("milk", week: nextMonday, in: context)
      }
      let milks = try snapshot(context).items.filter { $0.itemKey == "milk" }
      #expect(milks.count == 2 && milks.allSatisfy { !$0.inPantry })

      try GatherPlan.commit(in: context) {
        try GatherPlan.setPantry(itemKey: "milk", true, in: context)
        try GatherPlan.setPantry(itemKey: "milk", true, in: context)
      }
      #expect(try context.fetchCount(FetchDescriptor<PantryItemRecord>()) == 1)
      #expect(try snapshot(context).items.filter { $0.itemKey == "milk" }.allSatisfy(\.inPantry))
      #expect(try snapshot(context, week: nextMonday).items.allSatisfy(\.inPantry))
      #expect(try snapshot(context).items.filter(\.inPantry).count == 2)

      try GatherPlan.commit(in: context) {
        try GatherPlan.setPantry(itemKey: "milk", false, in: context)
      }
      #expect(try snapshot(context).items.allSatisfy { !$0.inPantry })
    }

    @Test func aPantryMarkLeavesTheItemOnTheList() throws {
      let context = try seeded()
      try GatherPlan.commit(in: context) {
        try GatherPlan.setPantry(itemKey: "olive oil", true, in: context)
      }
      let oil = try item("olive oil", in: context)
      #expect(oil.inPantry && GatherRowText(oil).amount == "8")
      #expect(try snapshot(context).items.count == SeededGatherReference.rows.count)
    }

    @Test func unmarkingClearsEveryDuplicateMark() throws {
      let context = try context()
      context.insert(PantryItemRecord(itemKey: "salt"))
      context.insert(PantryItemRecord(itemKey: "salt"))
      try context.save()
      try GatherPlan.commit(in: context) {
        try GatherPlan.setPantry(itemKey: "salt", false, in: context)
      }
      #expect(try context.fetchCount(FetchDescriptor<PantryItemRecord>()) == 0)
    }

    // MARK: Duplicates

    /// A second row for the same line, as a second device would have built it.
    private func duplicate(
      of record: GatherItemRecord, changed: Date, in context: ModelContext
    ) -> GatherItemRecord {
      let copy = GatherItemRecord(
        weekStart: monday, item: record.item, itemKey: record.itemKey)
      copy.quantity = record.quantity
      copy.unit = record.unit
      copy.aisle = record.aisle
      copy.createdAt = changed
      copy.updatedAt = changed
      context.insert(copy)
      return copy
    }

    @Test func twoRowsForOneLineShowAsTheMostRecentlyChanged() throws {
      let context = try seeded()
      let records = try context.fetch(FetchDescriptor<GatherItemRecord>())
      let garlic = try #require(records.first { $0.itemKey == "garlic" })
      garlic.updatedAt = Date(timeIntervalSince1970: 2_000)
      let older = duplicate(of: garlic, changed: Date(timeIntervalSince1970: 1_000), in: context)
      older.checked = true
      try context.save()

      var shown = try snapshot(context).items.filter { $0.itemKey == "garlic" }
      #expect(shown.count == 1)
      #expect(shown[0].id == garlic.id && !shown[0].checked)

      // The other one is edited more recently, so now it is the answer.
      older.updatedAt = Date(timeIntervalSince1970: 3_000)
      shown = try snapshot(context).items.filter { $0.itemKey == "garlic" }
      #expect(shown.count == 1 && shown[0].id == older.id && shown[0].checked)
      #expect(try snapshot(context).items.count == SeededGatherReference.rows.count)
    }

    @Test func aTieBetweenDuplicatesIsBrokenByIdOnEveryDevice() throws {
      let context = try seeded()
      let garlic = try #require(
        try context.fetch(FetchDescriptor<GatherItemRecord>()).first { $0.itemKey == "garlic" })
      let stamp = Date(timeIntervalSince1970: 5_000)
      garlic.updatedAt = stamp
      let twin = duplicate(of: garlic, changed: stamp, in: context)
      try context.save()
      let winner = Deduplication.keeper(of: [garlic, twin])
      #expect(try item("garlic", in: context).id == winner?.id)
    }

    @Test func rebuildingKeepsTheShownRowUpToDateAndLeavesTheOthersAlone() throws {
      let context = try seeded()
      let garlic = try #require(
        try context.fetch(FetchDescriptor<GatherItemRecord>()).first { $0.itemKey == "garlic" })
      let twin = duplicate(of: garlic, changed: Date(timeIntervalSince1970: 1_000), in: context)
      twin.checked = true
      garlic.updatedAt = Date(timeIntervalSince1970: 2_000)
      try context.save()
      let before = try context.fetchCount(FetchDescriptor<GatherItemRecord>())

      let shakshuka = try #require(try entries(context).first { $0.title.hasPrefix("Shakshuka") })
      try GatherPlan.commit(in: context) {
        try WeekPlan.apply(EntryChange(servings: .some(8)), to: shakshuka, in: context)
      }
      let result = try rebuild(context)
      #expect(result.updates.map(\.id).contains(garlic.id))
      #expect(!result.updates.map(\.id).contains(twin.id) && result.removals.isEmpty)
      #expect(try context.fetchCount(FetchDescriptor<GatherItemRecord>()) == before)
      #expect(garlic.quantity == Quantity(min: 16, max: nil))
      // The duplicate was neither updated nor deleted.
      #expect(twin.quantity == Quantity(min: 13, max: nil) && twin.checked)
      #expect(try snapshot(context).items.filter { $0.itemKey == "garlic" }.count == 1)
    }

    @Test func anItemThatLeavesTheWeekTakesItsDuplicatesWithIt() throws {
      let context = try seeded()
      let beans = try #require(
        try context.fetch(FetchDescriptor<GatherItemRecord>()).first {
          $0.itemKey == "cannellini bean"
        })
      _ = duplicate(of: beans, changed: .now, in: context)
      try context.save()
      let soup = try #require(try entries(context).first { $0.title.hasPrefix("Tomato") })
      try GatherPlan.commit(in: context) { _ = try WeekPlan.remove(soup, in: context) }
      _ = try rebuild(context)
      let left = try context.fetch(FetchDescriptor<GatherItemRecord>())
      #expect(left.filter { $0.itemKey == "cannellini bean" }.isEmpty)
    }

    @Test func tidyingRemovesAGatheredDuplicateOnceItHasSettledButNeverALineAddedByHand() throws {
      let context = try seeded()
      let garlic = try #require(
        try context.fetch(FetchDescriptor<GatherItemRecord>()).first { $0.itemKey == "garlic" })
      garlic.updatedAt = Date(timeIntervalSince1970: 2_000)
      _ = duplicate(of: garlic, changed: Date(timeIntervalSince1970: 1_000), in: context)
      try GatherPlan.add("milk", week: monday, in: context)
      try GatherPlan.add("milk", week: monday, in: context)
      try context.save()
      let before = try context.fetchCount(FetchDescriptor<GatherItemRecord>())

      // Recent duplicates stay: a delete would beat an edit made on another device.
      #expect(try Deduplication.tidy(context, now: Date(timeIntervalSince1970: 1_500)) == 0)
      #expect(try Deduplication.tidy(context, now: Date(timeIntervalSince1970: 1_000_000)) == 1)
      #expect(try context.fetchCount(FetchDescriptor<GatherItemRecord>()) == before - 1)
      #expect(
        try context.fetch(FetchDescriptor<GatherItemRecord>()).filter { $0.manual }.count == 2)
    }

    // MARK: The week the rebuild is for

    @Test func theSignatureChangesWhenThePlanOrARecipesLinesChange() throws {
      let context = try seeded()
      func signature() throws -> GatherSignature {
        GatherSignature(week: monday, entries: try entries(context))
      }
      let first = try signature()
      #expect(first == (try signature()))
      let soup = try #require(try entries(context).first { $0.title.hasPrefix("Tomato") })
      try WeekPlan.apply(EntryChange(servings: .some(6)), to: soup, in: context)
      let servings = try signature()
      #expect(servings != first)
      let recipe = try recipe("Tomato and white bean soup", in: context)
      recipe.ingredients =
        recipe.ingredients + [
          Ingredient(
            section: nil, quantity: nil, unit: nil, item: "bay leaf", note: nil, optional: false,
            alt: nil, original: "bay leaf", itemKey: ingredientKey("bay leaf"))
        ]
      #expect(try signature() != servings)
      RecipeLibrary.banish(recipe)
      #expect(try signature().parts.contains { $0.banished })
    }
  }
#endif
