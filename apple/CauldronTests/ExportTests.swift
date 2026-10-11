#if DEBUG
  import CauldronKit
  import Foundation
  import SwiftData
  import Testing

  @testable import Cauldron

  /// What a zip holds, read from its central directory.
  private func zipEntries(_ url: URL) throws -> [String: Data] {
    let bytes = [UInt8](try Data(contentsOf: url))
    func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
    func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
    let end = bytes.count - 22
    try #require(end >= 0 && u32(end) == 0x0605_4b50)
    var entries: [String: Data] = [:]
    var cursor = u32(end + 16)
    for _ in 0..<u16(end + 10) {
      let size = u32(cursor + 24)
      let nameLength = u16(cursor + 28)
      let skip = u16(cursor + 30) + u16(cursor + 32)
      let offset = u32(cursor + 42)
      let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
      let start = offset + 30 + u16(offset + 26) + u16(offset + 28)
      entries[name] = Data(bytes[start..<(start + size)])
      cursor += 46 + nameLength + skip
    }
    return entries
  }

  @MainActor
  @Suite("Export")
  struct ExportTests {
    private let today: LocalDate
    private let now = Date(timeIntervalSince1970: 1_791_711_000)  // 2026-10-11T09:30:00Z
    private let utc: Calendar = {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = .gmt
      return calendar
    }()

    init() throws {
      today = try #require(LocalDate("2026-10-11"))
    }

    private func folder() -> URL {
      FileManager.default.temporaryDirectory
        .appending(path: "ExportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func export(
      _ container: ModelContainer, into folder: URL,
      progress: @escaping @Sendable (ExportProgress) -> Void = { _ in }
    ) throws -> ExportResult {
      try StoreExporter.export(
        from: container, into: folder, now: now, appVersion: "1.2.3", calendar: utc,
        progress: progress)
    }

    private func read(_ result: ExportResult) throws -> CauldronExport {
      try CauldronExport.decode(Data(contentsOf: result.jsonURL))
    }

    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 7, 8, 9])

    /// A seeded store with a photo, a duplicate pair of weigh-ins and of tags, and a
    /// banished recipe.
    private struct Fixture {
      var container: ModelContainer
      var context: ModelContext
      var cooked: RecipeRecord
      var banished: RecipeRecord
      var photo: PhotoRecord
    }

    private func fixture() throws -> Fixture {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      try DebugSeed.populate(context, today: today)

      let recipes = try context.fetch(FetchDescriptor<RecipeRecord>())
      let cooked = try #require(recipes.first { $0.title.hasPrefix("Shakshuka") })

      let photo = PhotoRecord(imageData: jpeg, width: 1600, height: 1200)
      context.insert(photo)
      photo.recipe = cooked

      let banished = RecipeRecord(title: "Banished stew")
      banished.ingredients = [
        Ingredient(
          section: nil, quantity: Quantity(min: 1, max: nil), unit: .cup, item: "stock",
          note: nil, optional: false, alt: nil, original: "1 cup stock",
          itemKey: ingredientKey("stock"))
      ]
      banished.deletedAt = now
      context.insert(banished)

      // Two devices each weighed in on the same day; the later change wins.
      let older = WeighInRecord(day: today, weightKg: 80)
      older.updatedAt = now.addingTimeInterval(-100)
      let newer = WeighInRecord(day: today, weightKg: 79.5)
      newer.updatedAt = now
      context.insert(older)
      context.insert(newer)

      // Two devices each made the tag "Dinner".
      let dinner = TagRecord(name: "Dinner", kind: .meal)
      dinner.updatedAt = now.addingTimeInterval(-100)
      let loser = TagRecord(name: "dinner", kind: .meal)
      loser.updatedAt = now.addingTimeInterval(-200)
      context.insert(dinner)
      context.insert(loser)
      cooked.tags = (cooked.tags ?? []) + [loser]

      try context.save()
      return Fixture(
        container: container, context: context, cooked: cooked, banished: banished, photo: photo)
    }

    // MARK: Everything is in

    @Test func aSeededStoreExportsEveryRecordAndPhoto() throws {
      let fixture = try fixture()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let result = try export(fixture.container, into: folder)
      let document = try read(result)

      // The debug seed's own numbers: five recipes, a planned week, 28 days of tracking.
      #expect(document.recipes.count == 6)
      #expect(result.recipeCount == 5)
      #expect(document.planEntries.count == 5)
      #expect(document.diary.count == 98)
      #expect(document.weighIns.count == 23 + 1)
      #expect(document.bodyProfile != nil)
      #expect(document.targets != nil)
      #expect(document.photos.count == 1)
      #expect(result.photoCount == 1)
      #expect(result.skipped == 0)
      #expect(document.formatVersion == 1)
      #expect(document.app == ExportedApp(name: "Cauldron", version: "1.2.3"))
      #expect(document.exportedAt == now)

      // The store itself agrees on the rows that have no duplicates.
      let store = fixture.context
      #expect(
        try store.fetchCount(FetchDescriptor<PlanEntryRecord>()) == document.planEntries.count)
      #expect(try store.fetchCount(FetchDescriptor<DiaryEntryRecord>()) == document.diary.count)
    }

    @Test func recipesKeepEveryStructuredField() throws {
      let fixture = try fixture()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let document = try read(try export(fixture.container, into: folder))
      let shakshuka = try #require(document.recipes.first { $0.id == fixture.cooked.id })
      #expect(shakshuka.servings == 4)
      #expect(shakshuka.prepMinutes == 10)
      #expect(shakshuka.cookMinutes == 25)
      #expect(shakshuka.ingredients.count == 12)
      #expect(shakshuka.ingredients[0].original == "2 tbsp olive oil")
      #expect(shakshuka.ingredients[0].quantity == ExportedQuantity(min: 2))
      #expect(shakshuka.ingredients[0].unit == "tbsp")
      #expect(
        shakshuka.ingredients[7].alt
          == ExportedAltMeasure(quantity: ExportedQuantity(min: 28), unit: "oz"))
      #expect(shakshuka.steps.map(\.timerSeconds) == [480, 60, 600, 360, nil])
      #expect(shakshuka.macros.calories != nil)
      #expect(shakshuka.macrosSource == "manual")
    }

    @Test func aPhotoIsInTheZipUnderTheNameTheJSONGives() throws {
      let fixture = try fixture()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let result = try export(fixture.container, into: folder)
      let document = try read(result)
      let entry = try #require(document.photos.first)
      #expect(entry.id == fixture.photo.id)
      #expect(entry.recipeId == fixture.cooked.id)
      #expect(entry.width == 1600)
      #expect(entry.height == 1200)
      #expect(entry.file == "photos/\(fixture.photo.id.uuidString).jpg")

      let zip = try zipEntries(try #require(result.photosURL))
      #expect(Array(zip.keys) == [try #require(entry.file)])
      #expect(zip[try #require(entry.file)] == jpeg)
      #expect(result.urls == [result.jsonURL, try #require(result.photosURL)])
    }

    @Test func theFilesAreNamedForTheDay() throws {
      let fixture = try fixture()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let result = try export(fixture.container, into: folder)
      #expect(result.jsonURL.lastPathComponent == "cauldron-export-2026-10-11.json")
      #expect(result.photosURL?.lastPathComponent == "cauldron-photos-2026-10-11.zip")
    }

    @Test func theFileReadsBackAndWritesBackTheSameBytes() throws {
      let fixture = try fixture()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let result = try export(fixture.container, into: folder)
      let bytes = try Data(contentsOf: result.jsonURL)
      #expect(try CauldronExport.decode(bytes).encoded() == bytes)
    }

    @Test func twoExportsOfOneStoreAreTheSameBytes() throws {
      let fixture = try fixture()
      let first = folder()
      let second = folder()
      defer {
        try? FileManager.default.removeItem(at: first)
        try? FileManager.default.removeItem(at: second)
      }
      let a = try export(fixture.container, into: first)
      let b = try export(fixture.container, into: second)
      #expect(try Data(contentsOf: a.jsonURL) == Data(contentsOf: b.jsonURL))
      #expect(
        try Data(contentsOf: try #require(a.photosURL))
          == Data(contentsOf: try #require(b.photosURL)))
    }

    // MARK: What the store holds beyond the ticket's list

    @Test func aBanishedRecipeIsInTheFileAndFlagged() throws {
      let fixture = try fixture()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let document = try read(try export(fixture.container, into: folder))
      let stew = try #require(document.recipes.first { $0.id == fixture.banished.id })
      #expect(stew.deletedAt == now)
      #expect(stew.ingredients.map(\.item) == ["stock"])
      #expect(document.recipes.filter { $0.deletedAt != nil }.count == 1)
    }

    @Test func tagsCooksPantryFavouritesAndPreferencesAreIn() throws {
      let fixture = try fixture()
      let context = fixture.context
      let cooked = fixture.cooked
      let cook = CookRecord(cookedOn: today)
      context.insert(cook)
      cook.recipe = cooked
      context.insert(PantryItemRecord(itemKey: "olive oil"))
      let favourite = FavouriteRecord(key: "apple", name: "Apple", source: .manual)
      favourite.calories = 95
      context.insert(favourite)
      let preferences = PreferencesRecord()
      preferences.weekStartsOn = .sunday
      preferences.unitSystem = .metric
      context.insert(preferences)
      try context.save()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let document = try read(try export(fixture.container, into: folder))
      #expect(document.cooks.map(\.recipeId) == [cooked.id])
      #expect(document.cooks.map(\.cookedOn) == [today])
      #expect(document.pantry.map(\.itemKey) == ["olive oil"])
      #expect(document.favourites.map(\.key) == ["apple"])
      #expect(document.favourites.first?.macros.calories == 95)
      #expect(document.preferences?.weekStartsOn == 0)
      #expect(document.preferences?.unitSystem == "metric")
      #expect(document.tags.isEmpty == false)
    }

    @Test func gatherItemsKeepTheirSources() throws {
      let fixture = try fixture()
      let context = fixture.context
      let monday = today.startOfWeek(startingOn: .monday)
      let item = GatherItemRecord(weekStart: monday, item: "tomatoes", itemKey: "tomato")
      item.quantity = Quantity(min: 2, max: 3)
      item.unit = .can
      item.aisle = .pantry
      item.checked = true
      context.insert(item)
      let source = GatherSourceRecord(quantity: Quantity(min: 2, max: 3), unit: .can)
      context.insert(source)
      source.item = item
      source.recipe = fixture.cooked
      try context.save()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let document = try read(try export(fixture.container, into: folder))
      let exported = try #require(document.gatherItems.first)
      #expect(exported.weekStart == monday)
      #expect(exported.quantity == ExportedQuantity(min: 2, max: 3))
      #expect(exported.unit == "can")
      #expect(exported.aisle == "pantry")
      #expect(exported.checked)
      #expect(exported.sources.map(\.recipeId) == [fixture.cooked.id])
      #expect(exported.sources.first?.quantity == ExportedQuantity(min: 2, max: 3))
    }

    @Test func aiJobsAreLeftOut() throws {
      let fixture = try fixture()
      fixture.context.insert(AIJobRecord(kind: .mealEstimate, input: "two eggs"))
      try fixture.context.save()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let result = try export(fixture.container, into: folder)
      let json = try String(contentsOf: result.jsonURL, encoding: .utf8)
      #expect(!json.contains("two eggs"))
      #expect(!json.lowercased().contains("aijob"))
    }

    // MARK: Duplicates

    @Test func aDuplicateWeighInExportsOnlyTheWinner() throws {
      let fixture = try fixture()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let document = try read(try export(fixture.container, into: folder))
      let todays = document.weighIns.filter { $0.day == today }
      #expect(todays.map(\.weightKg) == [79.5])
    }

    @Test func aDuplicateTagIsMergedOntoTheWinnerAndItsRecipesFollow() throws {
      let fixture = try fixture()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let document = try read(try export(fixture.container, into: folder))
      let dinners = document.tags.filter { $0.name.lowercased() == "dinner" }
      #expect(dinners.map(\.name) == ["Dinner"])
      let winner = try #require(dinners.first)
      let shakshuka = try #require(document.recipes.first { $0.id == fixture.cooked.id })
      #expect(shakshuka.tagIds.filter { $0 == winner.id }.count == 1)
      let known = Set(document.tags.map(\.id))
      #expect(document.recipes.allSatisfy { Set($0.tagIds).isSubset(of: known) })
    }

    @Test func aDuplicateTargetsRowExportsOnlyTheWinner() throws {
      let fixture = try fixture()
      let stale = TargetsRecord(calories: 1, protein: 1, carbs: 1, fat: 1)
      stale.updatedAt = Date(timeIntervalSince1970: 0)
      fixture.context.insert(stale)
      try fixture.context.save()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let document = try read(try export(fixture.container, into: folder))
      #expect(document.targets?.id != stale.id)
      #expect(document.targets?.calories != 1)
    }

    // MARK: Edges

    @Test func anEmptyStoreExportsAValidFile() throws {
      let container = try CauldronStore.container(.inMemory)
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let result = try export(container, into: folder)
      let document = try read(result)
      #expect(document.recipes.isEmpty)
      #expect(document.photos.isEmpty)
      #expect(document.planEntries.isEmpty)
      #expect(document.diary.isEmpty)
      #expect(document.bodyProfile == nil)
      #expect(document.targets == nil)
      #expect(result.photosURL == nil)
      #expect(result.recipeCount == 0)
      #expect(result.photoCount == 0)
      let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path())
      #expect(contents == ["cauldron-export-2026-10-11.json"])
    }

    @Test func aPhotoWithoutImageDataIsListedWithoutAFile() throws {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      let recipe = RecipeRecord(title: "Toast")
      context.insert(recipe)
      let photo = PhotoRecord(imageData: nil, width: 10, height: 10)
      context.insert(photo)
      photo.recipe = recipe
      try context.save()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let result = try export(container, into: folder)
      let document = try read(result)
      #expect(document.photos.count == 1)
      #expect(document.photos.first?.file == nil)
      #expect(result.photoCount == 0)
      #expect(result.photosURL == nil)
    }

    @Test func aUnitFromANewerBuildSurvivesTheExport() throws {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      let recipe = RecipeRecord(title: "Future stew")
      recipe.ingredientsData = Data(
        #"[{"item":"barley","itemKey":"barley","optional":false,"original":"2 bushels barley","quantity":{"min":2},"unit":"bushel"}]"#
          .utf8)
      context.insert(recipe)
      try context.save()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let document = try read(try export(container, into: folder))
      let line = try #require(document.recipes.first?.ingredients.first)
      #expect(line.unit == "bushel")
      #expect(line.original == "2 bushels barley")
    }

    @Test func aRowWithoutAReadableDayIsCountedNotHidden() throws {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      let entry = PlanEntryRecord(day: today, slot: .dinner, title: "Ghost")
      entry.dayKey = "not a day"
      context.insert(entry)
      context.insert(PlanEntryRecord(day: today, slot: .lunch, title: "Soup"))
      try context.save()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }

      let result = try export(container, into: folder)
      #expect(result.skipped == 1)
      #expect(try read(result).planEntries.map(\.title) == ["Soup"])
    }

    @Test func failsWhenTheFolderCantBeMade() throws {
      let fixture = try fixture()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }
      // A file where the folder should go, so the export can't write beside it.
      try Data().write(to: folder)

      #expect(throws: (any Error).self) { try export(fixture.container, into: folder) }
    }

    @Test func progressRunsFromStartToFinishWithoutGoingBack() throws {
      let fixture = try fixture()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }
      let seen = Locked<[ExportProgress]>([])

      _ = try export(fixture.container, into: folder) { progress in
        seen.withLock { $0.append(progress) }
      }
      let steps = seen.withLock { $0 }
      #expect(steps.map(\.completed) == steps.map(\.completed).sorted())
      let last = try #require(steps.last)
      #expect(last.completed == last.total)
      #expect(last.fraction == 1)
      // One photo: read, the photo, then write.
      #expect(last.total == 3)
    }

    @Test func exportingDoesNotChangeTheStore() throws {
      let fixture = try fixture()
      let folder = folder()
      defer { try? FileManager.default.removeItem(at: folder) }
      let before = try fixture.context.fetchCount(FetchDescriptor<RecipeRecord>())

      _ = try export(fixture.container, into: folder)
      #expect(fixture.context.hasChanges == false)
      #expect(try fixture.context.fetchCount(FetchDescriptor<RecipeRecord>()) == before)
    }

    @Test func theSectionsControllerEndsReadyWithFilesToShare() async throws {
      let fixture = try fixture()
      let controller = ExportController()
      #expect(controller.isWorking == false)

      await controller.start(fixture.container)
      guard case .ready(let result) = controller.phase else {
        Issue.record("expected a finished export, got \(controller.phase)")
        return
      }
      defer { try? FileManager.default.removeItem(at: result.jsonURL.deletingLastPathComponent()) }
      #expect(result.recipeCount == 5)
      #expect(result.photoCount == 1)
      #expect(result.urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path()) })
      #expect(controller.isWorking == false)
    }
  }

  /// A value shared with a `@Sendable` callback.
  private final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
      lock.lock()
      defer { lock.unlock() }
      return body(&value)
    }
  }
#endif
