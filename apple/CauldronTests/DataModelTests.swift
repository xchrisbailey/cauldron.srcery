import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("SwiftData model")
struct DataModelTests {
  private func context() throws -> ModelContext {
    ModelContext(try CauldronStore.container(.inMemory))
  }

  // MARK: CloudKit rules

  @Test func everyAttributeIsOptionalOrDefaulted() {
    for entity in CauldronStore.schema.entities {
      for attribute in entity.attributes {
        #expect(
          attribute.isOptional || attribute.defaultValue != nil,
          "\(entity.name).\(attribute.name) needs a default or to be optional")
      }
    }
  }

  @Test func nothingIsUnique() {
    for entity in CauldronStore.schema.entities {
      #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name) has a uniqueness constraint")
      for attribute in entity.attributes {
        #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) is unique")
      }
    }
  }

  @Test func everyRelationshipIsOptionalWithAnInverse() {
    for entity in CauldronStore.schema.entities {
      for relationship in entity.relationships {
        #expect(relationship.isOptional, "\(entity.name).\(relationship.name) must be optional")
        #expect(
          relationship.inverseName != nil, "\(entity.name).\(relationship.name) needs an inverse")
        #expect(
          relationship.deleteRule != .deny, "\(entity.name).\(relationship.name) can't use deny")
      }
    }
  }

  @Test func photosAreStoredOutsideTheDatabase() throws {
    let photo = try #require(CauldronStore.schema.entities.first { $0.name == "PhotoRecord" })
    let image = try #require(photo.attributes.first { $0.name == "imageData" })
    #expect(image.options.contains(.externalStorage))
  }

  @Test func theSchemaHoldsEveryModel() {
    #expect(CauldronStore.schema.entities.count == CauldronStore.models.count)
  }

  // MARK: Recipes

  @Test func aRecipeKeepsItsIngredientsStructured() throws {
    let context = try context()
    let recipe = RecipeRecord(title: "Shakshuka with feta")
    let parsed = parseIngredientLine("1 1/2 cups (190g) flour, sifted")
    let ingredient = Ingredient(
      section: "For the base", quantity: parsed.quantity, unit: parsed.unit, item: parsed.item,
      note: parsed.note, optional: parsed.optional, alt: parsed.alt, original: parsed.original,
      itemKey: ingredientKey(parsed.item))
    recipe.ingredients = [ingredient]
    recipe.steps = [Step(section: nil, text: "Simmer for 10 minutes.", timerSeconds: 600)]
    recipe.macros = Macros(calories: 310, protein: 17, carbs: 18, fat: 19)
    recipe.macrosSource = .page
    recipe.lastCookedOn = LocalDate("2026-10-11")
    context.insert(recipe)
    try context.save()

    let saved = try #require(try context.fetch(FetchDescriptor<RecipeRecord>()).first)
    #expect(saved.ingredients == [ingredient])
    #expect(saved.ingredients.first?.quantity == Quantity(min: 1.5, max: nil))
    #expect(saved.ingredients.first?.unit == .cup)
    #expect(saved.ingredients.first?.original == "1 1/2 cups (190g) flour, sifted")
    #expect(saved.steps.first?.timerSeconds == 600)
    #expect(saved.macros == Macros(calories: 310, protein: 17, carbs: 18, fat: 19))
    #expect(saved.macrosSource == .page)
    #expect(saved.lastCookedOn == LocalDate("2026-10-11"))
    #expect(saved.sourcePlatform == .manual)
    #expect(!saved.isBanished)
  }

  @Test func aNewRecipeHasNoIngredientsOrSteps() {
    let recipe = RecipeRecord(title: "Empty")
    #expect(recipe.ingredients.isEmpty)
    #expect(recipe.steps.isEmpty)
    #expect(recipe.macros == .none)
  }

  @Test func deletingARecipeKeepsTheDiaryAndThePlan() throws {
    let context = try context()
    let day = try #require(LocalDate("2026-10-11"))
    let recipe = RecipeRecord(title: "Overnight oats")
    let photo = PhotoRecord(imageData: Data([1, 2, 3]), width: 4, height: 3)
    let cook = CookRecord(cookedOn: day)
    let plan = PlanEntryRecord(day: day, slot: .breakfast, title: "Overnight oats", servings: 2)
    let entry = DiaryEntryRecord(
      day: day, slot: .breakfast, name: "Overnight oats", source: .recipe)
    entry.macros = Macros(calories: 380, protein: 14, carbs: 58, fat: 10)
    let tag = TagRecord(name: "Breakfast", kind: .meal)
    for model in [recipe, photo, cook, plan, entry, tag] as [any PersistentModel] {
      context.insert(model)
    }
    recipe.photo = photo
    recipe.cooks = [cook]
    recipe.tags = [tag]
    plan.recipe = recipe
    entry.recipe = recipe
    try context.save()

    context.delete(recipe)
    try context.save()

    #expect(try context.fetchCount(FetchDescriptor<PhotoRecord>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<CookRecord>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<TagRecord>()) == 1)
    let keptPlan = try #require(try context.fetch(FetchDescriptor<PlanEntryRecord>()).first)
    #expect(keptPlan.recipe == nil)
    #expect(keptPlan.title == "Overnight oats")
    let keptEntry = try #require(try context.fetch(FetchDescriptor<DiaryEntryRecord>()).first)
    #expect(keptEntry.recipe == nil)
    #expect(keptEntry.macros == Macros(calories: 380, protein: 14, carbs: 58, fat: 10))
  }

  @Test func aGatherItemRemembersWhatEachRecipeAskedFor() throws {
    let context = try context()
    let week = try #require(LocalDate("2026-10-05"))
    let recipe = RecipeRecord(title: "Soup")
    let item = GatherItemRecord(weekStart: week, item: "onions", itemKey: "onion")
    item.quantity = Quantity(min: 2, max: 3)
    item.aisle = .produce
    let source = GatherSourceRecord(quantity: Quantity(min: 2, max: 3), unit: nil)
    context.insert(recipe)
    context.insert(item)
    context.insert(source)
    source.item = item
    source.recipe = recipe
    try context.save()

    #expect(item.sources?.count == 1)
    #expect(item.quantity == Quantity(min: 2, max: 3))
    #expect(item.weekStart == week)
    context.delete(item)
    try context.save()
    #expect(try context.fetchCount(FetchDescriptor<GatherSourceRecord>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<RecipeRecord>()) == 1)
  }

  @Test func aQueuedEstimateGoesWithItsDiaryEntry() throws {
    let context = try context()
    let day = try #require(LocalDate("2026-10-11"))
    let entry = DiaryEntryRecord(
      day: day, slot: .lunch, name: "Two eggs and toast", source: .described)
    entry.macrosPending = true
    let job = AIJobRecord(kind: .mealEstimate, input: "Two eggs and toast with butter")
    context.insert(entry)
    context.insert(job)
    job.diaryEntry = entry
    try context.save()

    #expect(job.status == .waiting)
    #expect(entry.aiJobs?.count == 1)
    context.delete(entry)
    try context.save()
    #expect(try context.fetchCount(FetchDescriptor<AIJobRecord>()) == 0)
  }

  @Test func theStoreHasItsOwnFolderAndNeverTheSharedDefault() throws {
    let url = try CauldronStore.storeURL()
    #expect(url.lastPathComponent == "Cauldron.store")
    #expect(url.deletingLastPathComponent().lastPathComponent == "computer.srcery.cauldron")
    #expect(url.lastPathComponent != "default.store")
  }

  @Test func theHostAppStaysInMemoryUnderTest() {
    guard case .inMemory = CauldronStore.launchMode else {
      Issue.record("a test run must not open the on-disk store")
      return
    }
  }

  @Test func eachInMemoryContainerIsSeparate() throws {
    let first = try context()
    let second = try context()
    first.insert(RecipeRecord(title: "Only here"))
    try first.save()
    #expect(try second.fetchCount(FetchDescriptor<RecipeRecord>()) == 0)
  }

  // MARK: Duplicates from two devices

  @Test func theMostRecentTargetsWin() throws {
    let context = try context()
    let older = TargetsRecord(calories: 1800, protein: 120, carbs: 180, fat: 60)
    older.updatedAt = Date(timeIntervalSince1970: 100)
    let newer = TargetsRecord(calories: 1450, protein: 134, carbs: 129, fat: 45)
    newer.updatedAt = Date(timeIntervalSince1970: 200)
    context.insert(older)
    context.insert(newer)

    #expect(try context.current(TargetsRecord.self)?.calories == 1450)
    #expect(try Deduplication.tidy(context) == 1)
    try context.save()
    #expect(try context.fetch(FetchDescriptor<TargetsRecord>()).map(\.calories) == [1450])
  }

  @Test func aTieIsBrokenTheSameWayEverywhere() throws {
    let context = try context()
    let stamp = Date(timeIntervalSince1970: 100)
    let rows = (0..<4).map { _ in BodyProfileRecord() }
    for row in rows {
      row.updatedAt = stamp
      context.insert(row)
    }
    let expected = rows.map(\.id.uuidString).min()
    #expect(Deduplication.keeper(of: rows)?.id.uuidString == expected)
    #expect(Deduplication.keeper(of: rows.reversed())?.id.uuidString == expected)
  }

  @Test func oneWeighInPerDaySurvives() throws {
    let context = try context()
    let day = try #require(LocalDate("2026-10-10"))
    let next = try #require(LocalDate("2026-10-11"))
    let phone = WeighInRecord(day: day, weightKg: 74.2)
    phone.updatedAt = Date(timeIntervalSince1970: 100)
    let mac = WeighInRecord(day: day, weightKg: 73.9)
    mac.updatedAt = Date(timeIntervalSince1970: 200)
    let other = WeighInRecord(day: next, weightKg: 73.8)
    for row in [phone, mac, other] { context.insert(row) }
    try context.save()

    #expect(try context.weighIn(on: day)?.weightKg == 73.9)
    #expect(try Deduplication.tidy(context) == 1)
    try context.save()
    let left = try context.fetch(FetchDescriptor<WeighInRecord>(sortBy: [SortDescriptor(\.dayKey)]))
    #expect(left.map(\.weightKg) == [73.9, 73.8])
  }

  @Test func duplicateTagsMergeTheirRecipes() throws {
    let context = try context()
    let soup = RecipeRecord(title: "Soup")
    let oats = RecipeRecord(title: "Oats")
    let first = TagRecord(name: "Vegan", kind: .diet)
    first.updatedAt = Date(timeIntervalSince1970: 100)
    let second = TagRecord(name: "vegan", kind: .diet)
    second.updatedAt = Date(timeIntervalSince1970: 200)
    for model in [soup, oats, first, second] as [any PersistentModel] { context.insert(model) }
    soup.tags = [first]
    oats.tags = [second]
    try context.save()

    #expect(try Deduplication.tidy(context) == 1)
    try context.save()
    let tags = try context.fetch(FetchDescriptor<TagRecord>())
    #expect(tags.map(\.name) == ["vegan"])
    #expect(Set((tags.first?.recipes ?? []).map(\.title)) == ["Soup", "Oats"])
  }

  @Test func favouritesPantryAndCooksAreDeduplicatedByKey() throws {
    let context = try context()
    let day = try #require(LocalDate("2026-10-11"))
    let recipe = RecipeRecord(title: "Soup")
    let other = RecipeRecord(title: "Oats")
    context.insert(recipe)
    context.insert(other)
    for _ in 0..<2 {
      context.insert(FavouriteRecord(key: "food:toast|", name: "Toast", source: .manual))
      context.insert(PantryItemRecord(itemKey: "salt"))
      let cook = CookRecord(cookedOn: day)
      context.insert(cook)
      cook.recipe = recipe
    }
    let otherCook = CookRecord(cookedOn: day)
    context.insert(otherCook)
    otherCook.recipe = other
    context.insert(FavouriteRecord(key: "food:eggs|2", name: "Eggs", source: .manual))
    try context.save()

    // Made a moment ago, so they are left for now.
    #expect(try Deduplication.tidy(context) == 0)
    let later = Date.now.addingTimeInterval(Deduplication.grace + 60)
    #expect(try Deduplication.tidy(context, now: later) == 3)
    try context.save()
    #expect(try context.fetchCount(FetchDescriptor<FavouriteRecord>()) == 2)
    #expect(try context.fetchCount(FetchDescriptor<PantryItemRecord>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<CookRecord>()) == 2)
    #expect(try Deduplication.tidy(context, now: later) == 0)
  }

  /// A delete syncs and beats a later edit of the same row, so a duplicate another device
  /// may still be editing is not deleted. Reads ignore it in the meantime.
  @Test func aRecentDuplicateIsLeftInPlace() throws {
    let context = try context()
    let day = try #require(LocalDate("2026-10-11"))
    let now = Date(timeIntervalSince1970: 1_000_000)
    let phone = WeighInRecord(day: day, weightKg: 74.2)
    phone.updatedAt = now.addingTimeInterval(-200)
    let mac = WeighInRecord(day: day, weightKg: 73.9)
    mac.updatedAt = now.addingTimeInterval(-100)
    context.insert(phone)
    context.insert(mac)
    try context.save()

    #expect(try Deduplication.tidy(context, now: now) == 0)
    #expect(try context.weighIn(on: day)?.weightKg == 73.9)

    // The phone's cook corrects their own row before the Mac's arrives: it now wins.
    phone.weightKg = 74.5
    phone.updatedAt = now
    #expect(try context.weighIn(on: day)?.weightKg == 74.5)

    let later = now.addingTimeInterval(Deduplication.grace + 1)
    #expect(try Deduplication.tidy(context, now: later) == 1)
    try context.save()
    #expect(try context.fetch(FetchDescriptor<WeighInRecord>()).map(\.weightKg) == [74.5])
  }

  // MARK: Change stamps

  @Test func savingAChangeStampsTheRow() throws {
    let context = try context()
    let stamp = Date(timeIntervalSince1970: 5_000)
    let stamps = ChangeStamps(on: context) { stamp }
    let targets = TargetsRecord(calories: 1800, protein: 120, carbs: 180, fat: 60)
    targets.updatedAt = Date(timeIntervalSince1970: 100)
    let untouched = RecipeRecord(title: "Soup")
    untouched.updatedAt = Date(timeIntervalSince1970: 100)
    context.insert(targets)
    context.insert(untouched)
    try context.save()
    #expect(targets.updatedAt == Date(timeIntervalSince1970: 100))

    targets.calories = 1450
    try context.save()
    #expect(targets.updatedAt == stamp)
    #expect(untouched.updatedAt == Date(timeIntervalSince1970: 100))

    let fresh = ModelContext(context.container)
    #expect(try fresh.current(TargetsRecord.self)?.updatedAt == stamp)
    withExtendedLifetime(stamps) {}
  }

  // MARK: Stored lists

  @Test func aListThatCannotBeEncodedLeavesTheStoredOneAlone() {
    let recipe = RecipeRecord(title: "Soup")
    recipe.ingredients = parseLines(["1 onion", "2 cups stock"])
    var broken = recipe.ingredients
    broken[0].quantity = Quantity(min: .infinity, max: nil)
    recipe.ingredients = broken
    #expect(recipe.ingredients.map(\.item) == ["onion", "stock"])
    #expect(recipe.ingredients.first?.quantity?.min == 1)
  }

  /// A newer build can write a line this one can't read. It costs only that line, and the
  /// recipe says it must not be rewritten from here.
  @Test func anUnreadableLineIsSkippedAndFlagged() throws {
    let recipe = RecipeRecord(title: "Soup")
    recipe.ingredients = parseLines(["1 onion", "2 cups stock"])
    #expect(recipe.canRewriteIngredients)

    var lines = try #require(
      JSONSerialization.jsonObject(with: recipe.ingredientsData) as? [[String: Any]])
    lines[1]["unit"] = "unit-from-the-future"
    recipe.ingredientsData = try JSONSerialization.data(withJSONObject: lines)

    #expect(recipe.ingredients.map(\.item) == ["onion"])
    #expect(!recipe.canRewriteIngredients)
  }

  @Test func searchTextCoversTitleIngredientsAndTags() throws {
    let context = try context()
    let recipe = RecipeRecord(title: "Tomato Soup")
    context.insert(recipe)
    recipe.ingredients = parseLines(["1 Onion"])
    let tag = TagRecord(name: "Weeknight", kind: .other)
    context.insert(tag)
    recipe.tags = [tag]
    recipe.refreshSearchText()
    #expect(recipe.searchText == "tomato soup onion weeknight")
  }

  private func parseLines(_ lines: [String]) -> [Ingredient] {
    readIngredientBlock(lines).map { line in
      Ingredient(
        section: line.section, quantity: line.quantity, unit: line.unit, item: line.item,
        note: line.note, optional: line.optional, alt: line.alt, original: line.original,
        itemKey: ingredientKey(line.item))
    }
  }
}

#if os(macOS)
  @Suite("Mac sandbox")
  struct MacSandboxTests {
    /// Sandboxed, every path the app can write resolves inside its own container, so no
    /// default location can land on a file another app owns.
    @Test("the Mac app runs sandboxed, in its own container")
    func sandboxed() {
      #expect(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)
      #expect(NSHomeDirectory().contains("/Library/Containers/"))
    }
  }
#endif
