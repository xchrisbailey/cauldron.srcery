import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

/// Health, in memory. Saving a sample replaces the one with its sync id when the version is
/// higher, as Health does; anything else stays. Each nutrient can be refused, and a save or a
/// delete that includes a refused one fails as a whole, as it does in Health.
actor FakeHealthStore: HealthStore {
  nonisolated let availability: HealthAvailability
  private(set) var samples: [String: (sample: NutritionSample, version: Int)] = [:]
  private(set) var authorizationRequests = 0
  private(set) var readRequests = 0
  private(set) var nutritionReadRequests = 0
  private(set) var saveRequests = 0
  private(set) var deleteRequests = 0
  var weights: [HealthWeightSample] = []
  var authorizationFails = false
  var writesFail = false
  var denied: Set<Nutrient> = []
  private var holdReads = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  init(availability: HealthAvailability = .supported) {
    self.availability = availability
  }

  func setWeights(_ new: [HealthWeightSample]) { weights = new }
  func setAuthorizationFails(_ fails: Bool) { authorizationFails = fails }
  func setWritesFail(_ fails: Bool) { writesFail = fails }
  func setDenied(_ nutrients: Set<Nutrient>) { denied = nutrients }

  /// Reads of body mass wait until `releaseReads`.
  func holdReadsOfBodyMass() { holdReads = true }

  func releaseReads() {
    holdReads = false
    for waiter in waiting { waiter.resume() }
    waiting = []
  }

  /// Puts a sample in Health as though another device (or an earlier run) had.
  func plant(_ sample: NutritionSample, version: Int) {
    samples[sample.syncID] = (sample, version)
  }

  func requestAuthorization() async throws {
    authorizationRequests += 1
    if authorizationFails { throw HealthFailure("denied") }
  }

  func writableNutrients() async -> Set<Nutrient> {
    Set(Nutrient.allCases).subtracting(denied)
  }

  func nutritionSamples(since date: Date) async throws -> [HeldNutrition] {
    nutritionReadRequests += 1
    return samples.values.filter { $0.sample.date >= date }.map {
      HeldNutrition(
        syncID: $0.sample.syncID, value: $0.sample.value, date: $0.sample.date,
        name: $0.sample.name, version: $0.version)
    }
  }

  func bodyMass(since date: Date) async throws -> [HealthWeightSample] {
    readRequests += 1
    if holdReads { await withCheckedContinuation { waiting.append($0) } }
    return weights.filter { $0.date >= date }.sorted { $0.date > $1.date }
  }

  func save(_ new: [NutritionSample], version: Int) async throws {
    saveRequests += 1
    if writesFail || new.contains(where: { denied.contains($0.nutrient) }) {
      throw HealthFailure("write")
    }
    for sample in new where (samples[sample.syncID]?.version ?? 0) < version {
      samples[sample.syncID] = (sample, version)
    }
  }

  func deleteNutrition(syncIDs: [String]) async throws {
    deleteRequests += 1
    if writesFail
      || syncIDs.contains(where: { HealthNutrition.nutrient(of: $0).map(denied.contains) ?? false })
    {
      throw HealthFailure("write")
    }
    for id in syncIDs { samples[id] = nil }
  }

  /// What Health holds now, by sync id.
  var held: [String: NutritionSample] { samples.mapValues(\.sample) }
}

private func noon(_ day: LocalDate) -> Date {
  calendar.date(
    from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? .now
}

private let calendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
  return calendar
}()

@Suite("Health setup")
struct HealthSetupTests {
  @Test func aBuildIsReadyOnlyWithBothUsageDescriptions() {
    let both: [String: Any] = [
      HealthSetup.shareKey: "Reads weight.", HealthSetup.updateKey: "Saves meals.",
    ]
    #expect(HealthSetup(info: both).isConfigured)
    #expect(!HealthSetup(info: [HealthSetup.shareKey: "Reads weight."]).isConfigured)
    #expect(!HealthSetup(info: [HealthSetup.updateKey: "Saves meals."]).isConfigured)
    #expect(
      !HealthSetup(info: [HealthSetup.shareKey: "  ", HealthSetup.updateKey: ""]).isConfigured)
    #expect(!HealthSetup(info: nil).isConfigured)
  }

  @Test func thisBuildExplainsHealthInTheCopyModulesWords() {
    // The usage descriptions arrived with the HealthKit entitlement (#162), copied into
    // project.yml from the copy module.
    #expect(HealthSetup.thisBuild.isConfigured)
    let info = Bundle.main.infoDictionary
    #expect(info?[HealthSetup.shareKey] as? String == Copy.settings.health.shareUsage.text)
    #expect(info?[HealthSetup.updateKey] as? String == Copy.settings.health.updateUsage.text)
  }

  @Test func theUsageDescriptionsAreInTheCopyModule() {
    #expect(Copy.settings.health.shareUsage.text.contains("weight"))
    #expect(Copy.settings.health.updateUsage.text.contains("protein"))
    #expect(!Copy.settings.health.shareUsage.text.lowercased().contains("active energy"))
  }
}

@Suite("Entries to Health")
struct HealthNutritionTests {
  private let day = LocalDate(year: 2026, month: 10, day: 10)!
  private let id = UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000001")!

  private func entry(
    servings: Double = 1, macros: Macros, pending: Bool = false, slot: MealSlot = .lunch
  ) -> HealthEntry {
    HealthEntry(
      id: id, day: day, slot: slot, name: "Eggs", servings: servings, macros: macros,
      pending: pending)
  }

  @Test func everyKnownNumberIsWrittenTimesTheServings() {
    let plan = HealthNutrition.plan(
      for: entry(servings: 2, macros: Macros(calories: 143, protein: 12.5, carbs: 1, fat: 9.5)),
      calendar: calendar)
    #expect(plan.save.map(\.nutrient) == [.energy, .protein, .carbs, .fat])
    #expect(plan.save.map(\.value) == [286, 25, 2, 19])
    #expect(plan.delete.isEmpty)
    #expect(plan.save.allSatisfy { $0.name == "Eggs" })
  }

  @Test func samplesAreNamedByTheEntryAndTheNutrient() {
    let plan = HealthNutrition.plan(
      for: entry(macros: Macros(calories: 100, protein: 1, carbs: 2, fat: 3)), calendar: calendar)
    #expect(
      plan.save.map(\.syncID) == [
        "cauldron.entry.0a1b2c3d-0000-4000-8000-000000000001.energy",
        "cauldron.entry.0a1b2c3d-0000-4000-8000-000000000001.protein",
        "cauldron.entry.0a1b2c3d-0000-4000-8000-000000000001.carbs",
        "cauldron.entry.0a1b2c3d-0000-4000-8000-000000000001.fat",
      ])
  }

  @Test func anUnknownNumberIsNotWrittenAndIsDeleted() {
    let plan = HealthNutrition.plan(
      for: entry(macros: Macros(calories: 100, protein: nil, carbs: 5, fat: nil)),
      calendar: calendar)
    #expect(plan.save.map(\.nutrient) == [.energy, .carbs])
    #expect(
      plan.delete
        == HealthNutrition.syncIDs(entry: id).filter {
          $0.hasSuffix("protein") || $0.hasSuffix("fat")
        })
  }

  @Test func aMealStillWaitingForItsNumbersWritesNothing() {
    let plan = HealthNutrition.plan(
      for: entry(macros: Macros(calories: 100), pending: true), calendar: calendar)
    #expect(plan.save.isEmpty)
    #expect(plan.delete.count == 4)
  }

  @Test func numbersThatAreNotUsableAreLeftOut() {
    #expect(
      HealthNutrition.plan(
        for: entry(servings: .nan, macros: Macros(calories: 1)), calendar: calendar
      ).save.isEmpty)
    #expect(
      HealthNutrition.plan(for: entry(servings: 0, macros: Macros(calories: 1)), calendar: calendar)
        .save.isEmpty)
    #expect(
      HealthNutrition.plan(for: entry(macros: Macros(calories: -5)), calendar: calendar).save
        .isEmpty)
    #expect(
      HealthNutrition.plan(for: entry(macros: Macros(calories: .infinity)), calendar: calendar).save
        .isEmpty)
    // Zero is a number.
    #expect(
      HealthNutrition.plan(for: entry(macros: Macros(fat: 0)), calendar: calendar).save.map(\.value)
        == [0])
  }

  @Test func aMealIsDatedOnItsDayAtAUsualHour() {
    func parts(_ slot: MealSlot) -> [Int] {
      let plan = HealthNutrition.plan(
        for: entry(macros: Macros(calories: 1), slot: slot), calendar: calendar)
      let c = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute], from: plan.save[0].date)
      return [c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0]
    }
    #expect(parts(.breakfast) == [2026, 10, 10, 8, 0])
    #expect(parts(.lunch) == [2026, 10, 10, 12, 30])
    #expect(parts(.dinner) == [2026, 10, 10, 19, 0])
    #expect(parts(.snack) == [2026, 10, 10, 15, 30])
  }

  @Test func removingAnEntryNamesAllFourSamples() {
    let plan = HealthNutrition.removal(of: id)
    #expect(plan.save.isEmpty && plan.delete.count == 4)
    #expect(Set(plan.delete).count == 4)
  }
}

@Suite("Making Health match the diary")
struct HealthReconcileTests {
  private let day = LocalDate(year: 2026, month: 10, day: 10)!
  private let id = UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000001")!
  private let other = UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000002")!

  private func entry(
    _ id: UUID? = nil, servings: Double = 2, name: String = "Eggs",
    macros: Macros = Macros(calories: 143, protein: 12.5, carbs: 1, fat: 9.5),
    pending: Bool = false, slot: MealSlot = .lunch
  ) -> HealthEntry {
    HealthEntry(
      id: id ?? self.id, day: day, slot: slot, name: name, servings: servings, macros: macros,
      pending: pending)
  }

  /// What Health would hold after `entry` was written.
  private func held(_ entry: HealthEntry, version: Int = 5) -> [HeldNutrition] {
    HealthNutrition.plan(for: entry, calendar: calendar).save.map {
      HeldNutrition(
        syncID: $0.syncID, value: $0.value, date: $0.date, name: $0.name, version: version)
    }
  }

  private func plan(
    _ entries: [HealthEntry], _ held: [HeldNutrition],
    writable: Set<Nutrient> = Set(Nutrient.allCases)
  ) -> NutritionPlan {
    HealthReconcile.plan(entries: entries, held: held, writable: writable, calendar: calendar)
  }

  @Test func whenHealthAlreadyMatchesThereIsNothingToDo() {
    let e = entry()
    #expect(plan([e], held(e)) == NutritionPlan(save: [], delete: []))
    #expect(plan([], []) == NutritionPlan(save: [], delete: []))
  }

  @Test func anEntryWithNoSamplesIsWritten() {
    let e = entry()
    let result = plan([e], [])
    #expect(result.save.map(\.nutrient) == [.energy, .protein, .carbs, .fat])
    #expect(result.save.map(\.value) == [286, 25, 2, 19])
    #expect(result.delete.isEmpty)
  }

  @Test func samplesWhoseEntryIsGoneAreDeleted() {
    let gone = entry(other)
    let result = plan([entry()], held(entry()) + held(gone))
    #expect(result.save.isEmpty)
    #expect(result.delete == HealthNutrition.syncIDs(entry: other).sorted())
  }

  @Test func samplesThatDifferAreWrittenAgain() {
    let changed = entry(servings: 3)
    let result = plan([changed], held(entry()))
    #expect(result.save.map(\.value) == [429, 37.5, 3, 28.5])
    // A different meal moves the time; a different name changes the label.
    #expect(plan([entry(slot: .dinner)], held(entry())).save.count == 4)
    #expect(plan([entry(name: "Omelette")], held(entry())).save.count == 4)
  }

  @Test func onlyTheSamplesThatDifferAreRewritten() {
    let have = held(entry()).map { sample -> HeldNutrition in
      var sample = sample
      if sample.syncID.hasSuffix("fat") { sample.value = 1 }
      return sample
    }
    #expect(plan([entry()], have).save.map(\.nutrient) == [.fat])
  }

  @Test func aNumberThatBecameUnknownIsDeletedAndOthersStay() {
    let before = entry()
    let after = entry(macros: Macros(calories: 143, protein: nil, carbs: 1, fat: nil))
    let result = plan([after], held(before))
    #expect(result.save.isEmpty)
    #expect(
      result.delete
        == HealthNutrition.syncIDs(entry: id).filter {
          $0.hasSuffix("protein") || $0.hasSuffix("fat")
        }.sorted())
  }

  @Test func aMealWaitingForNumbersWritesNothingAndLosesItsSamples() {
    let waiting = entry(pending: true)
    #expect(plan([waiting], []) == NutritionPlan(save: [], delete: []))
    #expect(plan([waiting], held(entry())).delete.count == 4)
  }

  @Test func nutrientsHealthWontTakeAreLeftAlone() {
    let e = entry()
    let writable: Set<Nutrient> = [.energy, .carbs]
    let result = plan([e], [], writable: writable)
    #expect(result.save.map(\.nutrient) == [.energy, .carbs])
    // Nothing is deleted for a nutrient that can't be written either.
    let stale = held(entry(other))
    #expect(plan([], stale, writable: writable).delete.count == 2)
  }

  @Test func samplesThatAreNotCauldronsAreIgnored() {
    let foreign = HeldNutrition(
      syncID: "other.app.protein", value: 9, date: .now, name: "", version: 1)
    let alsoForeign = HeldNutrition(
      syncID: "cauldron.entry.x.sodium", value: 9, date: .now, name: "", version: 1)
    #expect(plan([], [foreign, alsoForeign]) == NutritionPlan(save: [], delete: []))
  }

  @Test func doingItAgainOnTheResultChangesNothing() {
    let entries = [
      entry(), entry(other, servings: 1, name: "Toast", macros: Macros(calories: 100)),
    ]
    var have =
      held(entry(UUID(), name: "Stale"))
      + held(entries[0], version: 3).map {
        var sample = $0
        sample.value += 1
        return sample
      }
    let first = plan(entries, have)
    #expect(!first.save.isEmpty && !first.delete.isEmpty)
    // Apply it the way Health would.
    have.removeAll { first.delete.contains($0.syncID) }
    for sample in first.save {
      have.removeAll { $0.syncID == sample.syncID }
      have.append(
        HeldNutrition(
          syncID: sample.syncID, value: sample.value, date: sample.date, name: sample.name,
          version: 9))
    }
    #expect(plan(entries, have) == NutritionPlan(save: [], delete: []))
  }

  @Test func theSampleIdsAreReadBack() {
    #expect(
      HealthNutrition.nutrient(of: HealthNutrition.syncID(entry: id, nutrient: .carbs)) == .carbs)
    #expect(HealthNutrition.nutrient(of: "cauldron.entry.abc.energy") == .energy)
    #expect(HealthNutrition.nutrient(of: "cauldron.entry.abc.sodium") == nil)
    #expect(HealthNutrition.nutrient(of: "nope.protein") == nil)
  }
}

@Suite("Weights from Health")
struct HealthWeightImportTests {
  private let today = LocalDate(year: 2026, month: 10, day: 10)!
  private var window: ClosedRange<LocalDate> { today.adding(days: -365)...today }

  private func at(_ day: LocalDate, hour: Int = 8, minute: Int = 0) -> Date {
    calendar.date(
      from: DateComponents(
        year: day.year, month: day.month, day: day.day, hour: hour, minute: minute))
      ?? .now
  }

  private func sample(_ id: String, _ day: LocalDate, _ kg: Double, hour: Int = 8)
    -> HealthWeightSample
  {
    HealthWeightSample(id: id, date: at(day, hour: hour), kg: kg)
  }

  private func plan(
    _ samples: [HealthWeightSample], existing: [ExistingWeighIn] = [], dismissed: Set<String> = []
  ) -> WeightImportPlan {
    HealthWeightImport.plan(
      samples: samples, existing: existing, dismissed: dismissed, window: window,
      calendar: calendar)
  }

  @Test func aDayWithNoWeighInGetsItsLatestReading() {
    let result = plan([
      sample("morning", today, 74.2, hour: 7), sample("evening", today, 73.8, hour: 21),
      sample("old", today.adding(days: -3), 75),
    ])
    #expect(
      result.insert == [
        .init(day: today.adding(days: -3), kg: 75, sampleID: "old"),
        .init(day: today, kg: 73.8, sampleID: "evening"),
      ])
    #expect(result.update.isEmpty && result.remove.isEmpty)
  }

  @Test func readingsAreGroupedByTheLocalDay() {
    // 23:30 in Los Angeles is already the next day in UTC.
    let late = HealthWeightSample(id: "late", date: at(today, hour: 23, minute: 30), kg: 70)
    #expect(plan([late]).insert.map(\.day) == [today])
  }

  @Test func aWeighInTypedInCauldronIsNeverTouched() {
    let typed = ExistingWeighIn(day: today, kg: 74.0, healthSampleID: nil)
    let result = plan([sample("s", today, 73.1)], existing: [typed])
    #expect(result.isEmpty)
  }

  @Test func anImportedWeighInFollowsANewerOrCorrectedReading() {
    let held = ExistingWeighIn(day: today, kg: 74.2, healthSampleID: "s1")
    #expect(plan([sample("s1", today, 74.2)], existing: [held]).isEmpty)
    #expect(
      plan([sample("s1", today, 73.9)], existing: [held]).update
        == [.init(day: today, kg: 73.9, sampleID: "s1")])
    #expect(
      plan([sample("s2", today, 73.5, hour: 20)], existing: [held]).update
        == [.init(day: today, kg: 73.5, sampleID: "s2")])
  }

  @Test func anImportedWeighInGoneFromHealthIsRemoved() {
    let gone = ExistingWeighIn(day: today.adding(days: -2), kg: 74, healthSampleID: "x")
    let typed = ExistingWeighIn(day: today.adding(days: -4), kg: 75, healthSampleID: nil)
    #expect(plan([], existing: [gone, typed]).remove == [today.adding(days: -2)])
  }

  @Test func daysOutsideTheWindowAreNotLookedAt() {
    let old = today.adding(days: -400)
    let held = ExistingWeighIn(day: old, kg: 80, healthSampleID: "old")
    let result = plan(
      [sample("old", old, 80), sample("older", old.adding(days: -1), 81)], existing: [held])
    #expect(result.isEmpty)
  }

  @Test func aWeightRemovedFromCauldronStaysRemoved() {
    #expect(plan([sample("s", today, 74)], dismissed: ["s"]).isEmpty)
    let held = ExistingWeighIn(day: today, kg: 74.2, healthSampleID: "s1")
    #expect(plan([sample("s2", today, 73)], existing: [held], dismissed: ["s2"]).isEmpty)
  }

  @Test func readingsThatCouldNotBeAWeightAreIgnored() {
    let result = plan([
      sample("a", today, 0), sample("b", today, -4), sample("c", today, .nan),
      sample("d", today, 19.9), sample("e", today, 400.1), sample("f", today, .infinity),
    ])
    #expect(result.isEmpty)
    #expect(plan([sample("lo", today, 20)]).insert.count == 1)
  }

  @Test func weightsAreKeptToTwoDecimalsAndTinyDifferencesAreNotChanges() {
    #expect(plan([sample("s", today, 74.2349)]).insert.map(\.kg) == [74.23])
    let held = ExistingWeighIn(day: today, kg: 74.23, healthSampleID: "s")
    #expect(plan([sample("s", today, 74.2349)], existing: [held]).isEmpty)
  }
}

@MainActor
@Suite("Health sync")
struct HealthSyncTests {
  private let today = LocalDate(year: 2026, month: 10, day: 10)!
  private let container: ModelContainer
  private let context: ModelContext
  private let defaults: UserDefaults

  init() throws {
    container = try CauldronStore.container(.inMemory)
    context = ModelContext(container)
    let suite = "health-tests-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
  }

  private func sync(
    _ store: FakeHealthStore, configured: Bool = true, connected: Bool = true
  ) async -> HealthSync {
    let sync = HealthSync(
      store: store, setup: HealthSetup(isConfigured: configured), defaults: defaults,
      calendar: calendar, now: { [today = self.today] in noon(today) })
    if connected { await sync.connect() }
    return sync
  }

  private func editor(_ sync: HealthSync) -> DiaryEditor {
    DiaryEditor(context: context, health: sync)
  }

  private func food(
    _ name: String = "Eggs", servings: Double = 2,
    macros: Macros = Macros(calories: 143, protein: 12.5, carbs: 1, fat: 9.5)
  ) -> NewEntry {
    NewEntry(name: name, servings: servings, macros: macros, source: .manual)
  }

  // MARK: Status and connecting

  @Test func statusSaysWhyHealthIsNotInUse() async {
    let store = FakeHealthStore()
    #expect(await sync(store, configured: false, connected: false).status == .notSetUp)
    #expect(
      await sync(FakeHealthStore(availability: .unsupported), connected: false).status
        == .unavailable)
    let off = await sync(store, connected: false)
    #expect(off.status == .off)
    await off.connect()
    #expect(off.status == .on)
  }

  @Test func healthIsNeverAskedForOnABuildThatIsNotSetUp() async {
    let store = FakeHealthStore()
    let sync = await sync(store, configured: false)
    #expect(sync.status == .notSetUp)
    #expect(await store.authorizationRequests == 0)
  }

  @Test func trackerActivationInMemoryCannotReadOrDeleteHealthForAnEmptyDiary() async throws {
    let suite = "health-ui-isolation-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    defaults.set(true, forKey: HealthSync.enabledKey)
    let store = FakeHealthStore()
    let held = NutritionSample(
      syncID: "com.srcery.cauldron.nutrition.old-entry.energy", nutrient: .energy,
      value: 350, date: noon(today), name: "Existing Health meal")
    await store.plant(held, version: 1)
    let health = HealthSync.disabled(store: store, defaults: defaults)
    let context = ModelContext(try CauldronStore.container(.inMemory))

    await TrackerRoot.checkHealth(health: health, in: context)

    #expect(health.status == .notSetUp)
    #expect(await store.readRequests == 0)
    #expect(await store.nutritionReadRequests == 0)
    #expect(await store.saveRequests == 0)
    #expect(await store.deleteRequests == 0)
    #expect(await store.held[held.syncID] != nil)
    #expect(defaults.bool(forKey: HealthSync.enabledKey))
  }

  @Test func aDeviceWithoutHealthIsNeverAsked() async {
    let store = FakeHealthStore(availability: .unsupported)
    let sync = await sync(store)
    #expect(sync.status == .unavailable)
    #expect(await store.authorizationRequests == 0)
  }

  @Test func connectingAsksOnceAndRemembersTheChoice() async {
    let store = FakeHealthStore()
    let first = await sync(store)
    #expect(first.status == .on && first.failure == nil)
    #expect(await store.authorizationRequests == 1)
    // A new run of the app on the same device is still connected, without asking again.
    let second = await sync(store, connected: false)
    #expect(second.status == .on)
    #expect(await store.authorizationRequests == 1)
    second.disconnect()
    #expect(second.status == .off)
    #expect(await sync(store, connected: false).status == .off)
  }

  @Test func aRefusedPromptLeavesHealthOffWithAMessage() async {
    let store = FakeHealthStore()
    await store.setAuthorizationFails(true)
    let sync = await sync(store)
    #expect(sync.status == .off)
    #expect(sync.failure == Copy.settings.health.couldntConnect)
  }

  // MARK: Meals out

  @Test func aLoggedMealAppearsInHealth() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    let added = try editor(sync).add([food()], on: today, slot: .breakfast)
    await sync.settle()
    let held = await store.held
    let id = added[0].id
    #expect(held.count == 4)
    #expect(held[HealthNutrition.syncID(entry: id, nutrient: .energy)]?.value == 286)
    #expect(held[HealthNutrition.syncID(entry: id, nutrient: .protein)]?.value == 25)
    #expect(held[HealthNutrition.syncID(entry: id, nutrient: .carbs)]?.value == 2)
    #expect(held[HealthNutrition.syncID(entry: id, nutrient: .fat)]?.value == 19)
  }

  @Test func editingAnEntryUpdatesItsSamplesInPlace() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    let eggs = try editor(sync).add([food()], on: today, slot: .breakfast)[0]
    await sync.settle()

    var draft = EntryDraft(eggs)
    draft.servings = "3"
    draft.fat = ""
    let valid = try #require(draft.valid(requireCalories: false))
    try editor(sync).update(eggs, with: valid)
    await sync.settle()

    let held = await store.held
    // Still one sample for each nutrient, the fat one gone, the others updated.
    #expect(held.count == 3)
    #expect(held[HealthNutrition.syncID(entry: eggs.id, nutrient: .energy)]?.value == 429)
    #expect(held[HealthNutrition.syncID(entry: eggs.id, nutrient: .fat)] == nil)
  }

  @Test func movingAnEntryMovesItsSamplesToTheNewDay() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    let eggs = try editor(sync).add([food()], on: today, slot: .breakfast)[0]
    await sync.settle()
    var draft = EntryDraft(eggs)
    draft.day = today.adding(days: 1)
    draft.slot = .dinner
    try editor(sync).update(eggs, with: try #require(draft.valid(requireCalories: false)))
    await sync.settle()
    let sample = await store.held[HealthNutrition.syncID(entry: eggs.id, nutrient: .energy)]
    let parts = calendar.dateComponents(
      [.day, .hour], from: try #require(sample).date)
    #expect(parts.day == 11 && parts.hour == 19)
    #expect(await store.held.count == 4)
  }

  @Test func deletingAnEntryTakesItsSamplesOut() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    let eggs = try editor(sync).add([food()], on: today, slot: .breakfast)[0]
    let toast = try editor(sync).add([food("Toast", servings: 1)], on: today, slot: .breakfast)[0]
    await sync.settle()
    #expect(await store.held.count == 8)
    try editor(sync).remove(eggs)
    await sync.settle()
    let held = await store.held
    #expect(held.count == 4)
    #expect(held.keys.allSatisfy { $0.contains(toast.id.uuidString.lowercased()) })
  }

  @Test func undoingADeleteWritesTheSamplesAgain() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    let eggs = try editor(sync).add([food()], on: today, slot: .breakfast)[0]
    let removed = try editor(sync).remove(eggs)
    await sync.settle()
    #expect(await store.held.isEmpty)
    try editor(sync).restore(removed)
    await sync.settle()
    #expect(await store.held.count == 4)
  }

  @Test func aSaveRightBeforeADeleteEndsWithNothingInHealth() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    let eggs = try editor(sync).add([food()], on: today, slot: .breakfast)[0]
    try editor(sync).remove(eggs)
    await sync.settle()
    #expect(await store.held.isEmpty)
  }

  @Test func aMealWaitingForItsNumbersWritesNothingUntilItHasThem() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    var pending = food()
    pending.macrosPending = true
    let record = try editor(sync).add([pending], on: today, slot: .lunch)[0]
    await sync.settle()
    #expect(await store.held.isEmpty)
    record.macrosPending = false
    sync.entriesSaved([try #require(HealthEntry(record))])
    await sync.settle()
    #expect(await store.held.count == 4)
  }

  @Test func nothingIsWrittenWhileHealthIsOffOrUnavailable() async throws {
    for store in [FakeHealthStore(), FakeHealthStore(availability: .unsupported)] {
      let sync = await sync(store, connected: false)
      let added = try editor(sync).add([food()], on: today, slot: .breakfast)
      try editor(sync).remove(added[0])
      await sync.settle()
      #expect(await store.held.isEmpty)
    }
  }

  @Test func aFailedWriteNeverStopsTheDiary() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    await store.setWritesFail(true)
    let added = try editor(sync).add([food()], on: today, slot: .breakfast)
    await sync.settle()
    #expect(sync.failure == Copy.settings.health.couldntUpdate)
    #expect(try DiaryWrites.count(on: today, in: context) == 1)
    #expect(added.count == 1)
    // The next change that goes through clears the message.
    await store.setWritesFail(false)
    try editor(sync).add([food("Toast", servings: 1)], on: today, slot: .breakfast)
    await sync.settle()
    #expect(sync.failure == nil)
  }

  @Test func aRefusedChangeNeverReachesHealth() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    try DiaryWrites.add(
      (0..<TrackerLimits.perDay).map {
        NewEntry(name: "F\($0)", macros: Macros(), source: .manual)
      },
      on: today, slot: .snack, in: context)
    #expect(throws: DiaryWrites.Failure.dayFull) {
      try self.editor(sync).add([self.food()], on: self.today, slot: .lunch)
    }
    #expect(throws: DiaryWrites.Failure.invalid) {
      try self.editor(sync).add(
        [self.food(servings: .nan)], on: self.today.adding(days: 1), slot: .lunch)
    }
    await sync.settle()
    #expect(await store.held.isEmpty)
  }

  // MARK: Weights in

  private func reading(_ id: String, _ day: LocalDate, _ kg: Double) -> HealthWeightSample {
    HealthWeightSample(
      id: id,
      date: calendar.date(
        from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 8)) ?? .now,
      kg: kg)
  }

  private func weighIns() throws -> [WeighInRecord] {
    try context.fetch(FetchDescriptor<WeighInRecord>()).sorted { $0.dayKey < $1.dayKey }
  }

  @Test func aWeightFromHealthAppearsAsAWeighIn() async throws {
    let store = FakeHealthStore()
    await store.setWeights([
      reading("s1", today, 73.4), reading("s0", today.adding(days: -1), 73.9),
    ])
    let sync = await sync(store)
    #expect(await sync.importWeights(into: context) == 2)
    let rows = try weighIns()
    #expect(rows.map(\.dayKey) == ["2026-10-09", "2026-10-10"])
    #expect(rows.map(\.weightKg) == [73.9, 73.4])
    #expect(rows.map(\.healthSampleID) == ["s0", "s1"])
  }

  @Test func checkingAgainChangesNothingAndNeverDuplicates() async throws {
    let store = FakeHealthStore()
    await store.setWeights([reading("s1", today, 73.4)])
    let sync = await sync(store)
    await sync.importWeights(into: context)
    #expect(await sync.importWeights(into: context) == 0)
    #expect(try weighIns().count == 1)
  }

  @Test func aWeightTypedInCauldronBeatsHealthForThatDay() async throws {
    context.insert(WeighInRecord(day: today, weightKg: 74.0))
    try context.save()
    let store = FakeHealthStore()
    await store.setWeights([reading("s1", today, 73.4)])
    let sync = await sync(store)
    #expect(await sync.importWeights(into: context) == 0)
    let rows = try weighIns()
    #expect(rows.count == 1 && rows[0].weightKg == 74.0 && rows[0].healthSampleID == nil)
  }

  @Test func aReadingCorrectedOrDeletedInHealthIsFollowed() async throws {
    let store = FakeHealthStore()
    await store.setWeights([reading("s1", today, 73.4)])
    let sync = await sync(store)
    await sync.importWeights(into: context)
    await store.setWeights([reading("s1", today, 73.0)])
    await sync.importWeights(into: context)
    #expect(try weighIns().map(\.weightKg) == [73.0])
    await store.setWeights([])
    await sync.importWeights(into: context)
    #expect(try weighIns().isEmpty)
  }

  @Test func aWeightRemovedFromCauldronStaysRemovedOnEveryDevice() async throws {
    let store = FakeHealthStore()
    await store.setWeights([reading("s1", today, 73.4)])
    let sync = await sync(store)
    await sync.importWeights(into: context)
    try WeightWrites.remove(day: today, in: context)
    #expect(try context.fetch(FetchDescriptor<HealthDismissalRecord>()).map(\.sampleID) == ["s1"])
    #expect(await sync.importWeights(into: context) == 0)
    #expect(try weighIns().isEmpty)
    // Another run of the app, or another device reading the same store, sees the choice too.
    let next = await self.sync(store, connected: false)
    #expect(await next.importWeights(into: context) == 0)
  }

  @Test func aWeightRemovedOnTheMacIsNotImportedOnThePhone() async throws {
    // The Mac removed the weigh-in and its dismissal synced here.
    context.insert(HealthDismissalRecord(sampleID: "s1"))
    try context.save()
    let store = FakeHealthStore()
    await store.setWeights([
      reading("s1", today, 73.4), reading("s2", today.adding(days: -1), 73.9),
    ])
    let sync = await sync(store)
    await sync.importWeights(into: context)
    #expect(try weighIns().map(\.healthSampleID) == ["s2"])
  }

  @Test func editingAHealthWeighInAndRemovingItDoesNotBringTheReadingBack() async throws {
    let store = FakeHealthStore()
    await store.setWeights([reading("s1", today, 73.4)])
    let sync = await sync(store)
    await sync.importWeights(into: context)
    try WeightWrites.save(kg: 74, on: today, today: today, in: context)
    try WeightWrites.remove(day: today, in: context)
    #expect(await sync.importWeights(into: context) == 0)
    #expect(try weighIns().isEmpty)
  }

  @Test func overlappingChecksShareOneRunAndNeverDuplicate() async throws {
    let store = FakeHealthStore()
    await store.setWeights([
      reading("s1", today, 73.4), reading("s0", today.adding(days: -1), 73.9),
    ])
    await store.holdReadsOfBodyMass()
    let sync = await sync(store)
    let first = Task { await sync.importWeights(into: context) }
    let second = Task { await sync.importWeights(into: context) }
    for _ in 0..<200 where await store.readRequests == 0 { await Task.yield() }
    await Task.yield()
    await store.releaseReads()
    let counts = await [first.value, second.value]
    #expect(counts == [2, 2])
    #expect(await store.readRequests == 1)
    #expect(try weighIns().map(\.dayKey) == ["2026-10-09", "2026-10-10"])
  }

  @Test func twoSyncsRacingOnOneStoreStillLeaveOneWeighInADay() async throws {
    let store = FakeHealthStore()
    await store.setWeights([reading("s1", today, 73.4)])
    await store.holdReadsOfBodyMass()
    let a = await sync(store)
    let b = await sync(store, connected: false)
    let first = Task { await a.importWeights(into: context) }
    let second = Task { await b.importWeights(into: context) }
    for _ in 0..<200 where await store.readRequests < 2 { await Task.yield() }
    await store.releaseReads()
    _ = await [first.value, second.value]
    #expect(try weighIns().count == 1)
  }

  @Test func healthIsNotReadWhileOffOrNotSetUp() async throws {
    let store = FakeHealthStore()
    await store.setWeights([reading("s1", today, 73.4)])
    #expect(await sync(store, connected: false).importWeights(into: context) == 0)
    #expect(await sync(store, configured: false).importWeights(into: context) == 0)
    #expect(await store.readRequests == 0)
    #expect(try weighIns().isEmpty)
  }

  @Test func theTargetsFormStartsFromAHealthWeight() async throws {
    let store = FakeHealthStore()
    await store.setWeights([reading("s1", today.adding(days: -2), 71.4)])
    let sync = await sync(store)
    await sync.importWeights(into: context)
    let form = try TargetsForm.load(from: context, today: today)
    #expect(form.weight == "71.4")
  }

  @Test func aWeightTypedInTheTargetsFormIsTheCooksOwn() async throws {
    let store = FakeHealthStore()
    await store.setWeights([reading("s1", today, 73.4)])
    let sync = await sync(store)
    await sync.importWeights(into: context)
    var form = try TargetsForm.load(from: context, today: today)
    form.sex = .female
    form.birthDate = LocalDate(year: 1990, month: 5, day: 14)
    form.cm = "168"
    form.weight = "72.6"
    try form.save(in: context)
    #expect(try weighIns().map(\.healthSampleID) == [nil])
    await store.setWeights([reading("s1", today, 73.0)])
    #expect(await sync.importWeights(into: context) == 0)
    #expect(try weighIns().map(\.weightKg) == [72.6])
  }

  // MARK: Reconciling

  /// A diary entry the way another device would have synced it: written to the store without
  /// going through `DiaryEditor`.
  @discardableResult
  private func synced(
    _ name: String, on day: LocalDate? = nil, servings: Double = 1,
    macros: Macros = Macros(calories: 100, protein: 5, carbs: 10, fat: 2)
  ) throws -> DiaryEntryRecord {
    let record = DiaryEntryRecord(
      day: day ?? today, slot: .lunch, name: name, servings: servings, source: .manual)
    record.macros = macros
    context.insert(record)
    try context.save()
    return record
  }

  @Test func anEntryLoggedBeforeHealthWasConnectedIsWrittenWhenItIs() async throws {
    let before = try synced("Soup")
    let store = FakeHealthStore()
    let sync = await sync(store)
    #expect(await store.held.isEmpty)
    await sync.reconcile(in: context)
    #expect(
      await store.held.keys.sorted() == HealthNutrition.syncIDs(entry: before.id).sorted())
  }

  @Test func onlyTheLastThirtyDaysAreBackfilled() async throws {
    try synced("Today")
    try synced("A month ago", on: today.adding(days: -29))
    try synced("Too old", on: today.adding(days: -30))
    let store = FakeHealthStore()
    let sync = await sync(store)
    await sync.reconcile(in: context)
    let names = Set(await store.held.values.map(\.name))
    #expect(names == ["Today", "A month ago"])
  }

  @Test func anEntryDeletedOnAnotherDeviceLosesItsSamples() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    let soup = try editor(sync).add([food("Soup")], on: today, slot: .lunch)[0]
    await sync.settle()
    #expect(await store.held.count == 4)
    // The Mac deleted it; the delete synced here without touching the editor.
    context.delete(soup)
    try context.save()
    await sync.appDidBecomeActive(in: context)
    #expect(await store.held.isEmpty)
  }

  @Test func disconnectedDeletedAndReconnectedEndsClean() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    let soup = try editor(sync).add([food("Soup")], on: today, slot: .lunch)[0]
    await sync.settle()
    sync.disconnect()
    try editor(sync).remove(soup)
    await sync.settle()
    #expect(await store.held.count == 4)
    await sync.connect()
    await sync.reconcile(in: context)
    #expect(await store.held.isEmpty)
  }

  @Test func aWriteThatFailedIsMadeGoodLater() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    await store.setWritesFail(true)
    try editor(sync).add([food("Soup")], on: today, slot: .lunch)
    await sync.settle()
    #expect(await store.held.isEmpty)
    await store.setWritesFail(false)
    await sync.appDidBecomeActive(in: context)
    #expect(await store.held.count == 4)
    #expect(sync.failure == nil)
  }

  @Test func aDescribedMealGetsItsSamplesWhenItsNumbersArrive() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    var pending = food("Described")
    pending.macros = Macros()
    pending.macrosPending = true
    let record = try editor(sync).add([pending], on: today, slot: .lunch)[0]
    await sync.settle()
    #expect(await store.held.isEmpty)
    // The estimate comes back later and is written to the entry directly.
    record.macros = Macros(calories: 300, protein: 20, carbs: 30, fat: 10)
    record.macrosPending = false
    try context.save()
    await sync.reconcile(in: context)
    #expect(await store.held.count == 4)
  }

  @Test func aStaleSampleIsFixedByTheNextDiaryChange() async throws {
    let store = FakeHealthStore()
    let sync = await sync(store)
    let soup = try editor(sync).add([food("Soup", servings: 1)], on: today, slot: .lunch)[0]
    await sync.settle()
    // Something else changed the entry (another device) and Health wasn't told.
    soup.servings = 2
    try context.save()
    try editor(sync).add([food("Toast", servings: 1)], on: today, slot: .lunch)
    await sync.settle()
    let energy = await store.held[HealthNutrition.syncID(entry: soup.id, nutrient: .energy)]
    #expect(energy?.value == 286)
  }

  @Test func reconcilingTwiceWritesNothingTheSecondTime() async throws {
    try synced("Soup")
    let store = FakeHealthStore()
    let sync = await sync(store)
    await sync.reconcile(in: context)
    let saves = await store.saveRequests
    await sync.reconcile(in: context)
    await sync.appDidBecomeActive(in: context)
    #expect(await store.saveRequests == saves)
  }

  @Test func aVersionHigherThanOursStillGetsReplaced() async throws {
    let soup = try synced("Soup")
    let store = FakeHealthStore()
    let sync = await sync(store)
    // Another device with a fast clock wrote this, with a version from the future.
    let stale = NutritionSample(
      syncID: HealthNutrition.syncID(entry: soup.id, nutrient: .energy), nutrient: .energy,
      value: 999, date: noon(today), name: "Soup")
    await store.plant(stale, version: Int.max / 2)
    await sync.reconcile(in: context)
    #expect(await store.held[stale.syncID]?.value == 100)
  }

  @Test func thePhoneNeverReadsOrWritesAnythingWhileOff() async throws {
    try synced("Soup")
    let store = FakeHealthStore()
    let off = await sync(store, connected: false)
    await off.appDidBecomeActive(in: context)
    #expect(await store.held.isEmpty)
    #expect(await store.readRequests == 0)
  }

  @Test func comingForwardChecksWeightsAndTheDiary() async throws {
    try synced("Soup")
    let store = FakeHealthStore()
    await store.setWeights([reading("s1", today, 73.4)])
    let sync = await sync(store)
    await sync.appDidBecomeActive(in: context)
    #expect(try weighIns().count == 1)
    #expect(await store.held.count == 4)
  }

  // MARK: Nutrients Health won't take

  @Test func aNutrientTheCookRefusedIsLeftOutAndTheRestAreWritten() async throws {
    let store = FakeHealthStore()
    await store.setDenied([.protein])
    let sync = await sync(store)
    let soup = try editor(sync).add([food("Soup", servings: 1)], on: today, slot: .lunch)[0]
    await sync.settle()
    let held = await store.held
    #expect(
      Set(held.keys)
        == Set(HealthNutrition.syncIDs(entry: soup.id).filter { !$0.hasSuffix("protein") }))
    #expect(sync.deniedNutrients == [.protein])
    #expect(sync.failure == nil)
  }

  @Test func refusingSeveralNutrientsStillWritesWhatIsAllowed() async throws {
    let store = FakeHealthStore()
    await store.setDenied([.energy, .fat])
    let sync = await sync(store)
    try editor(sync).add([food("Soup", servings: 1)], on: today, slot: .lunch)
    await sync.settle()
    #expect(Set(await store.held.values.map(\.nutrient)) == [.protein, .carbs])
    #expect(sync.deniedNutrients == [.energy, .fat])
  }

  @Test func deletingAndReconcilingWorkWhileANutrientIsRefused() async throws {
    let store = FakeHealthStore()
    await store.setDenied([.carbs])
    let sync = await sync(store)
    let soup = try editor(sync).add([food("Soup")], on: today, slot: .lunch)[0]
    await sync.settle()
    try editor(sync).remove(soup)
    await sync.reconcile(in: context)
    #expect(await store.held.isEmpty)
    #expect(sync.failure == nil)
  }

  @Test func theCookAllowingItLaterGetsTheMissingSamplesBackfilled() async throws {
    let store = FakeHealthStore()
    await store.setDenied([.protein])
    let sync = await sync(store)
    try editor(sync).add([food("Soup", servings: 1)], on: today, slot: .lunch)
    await sync.settle()
    #expect(await store.held.count == 3)
    await store.setDenied([])
    await sync.appDidBecomeActive(in: context)
    #expect(await store.held.count == 4)
    #expect(sync.deniedNutrients.isEmpty)
  }

  @Test func connectingReportsWhichNutrientsAreOff() async throws {
    let store = FakeHealthStore()
    await store.setDenied([.fat])
    let sync = await sync(store)
    #expect(sync.deniedNutrients == [.fat])
    sync.disconnect()
    #expect(sync.deniedNutrients.isEmpty)
  }

  // MARK: Weights typed in the targets form

  @Test func aHealthWeightLeftAsShownIsNotClaimedByTheTargetsForm() async throws {
    // The form opens before the weight is imported, so it doesn't know the day has one.
    var form = try TargetsForm.load(from: context, today: today)
    let store = FakeHealthStore()
    await store.setWeights([reading("s1", today, 73.44)])
    let sync = await sync(store)
    await sync.importWeights(into: context)
    form.sex = .female
    form.birthDate = LocalDate(year: 1990, month: 5, day: 14)
    form.cm = "168"
    form.weight = "73.4"
    try form.save(in: context)
    let rows = try weighIns()
    #expect(rows.map(\.healthSampleID) == ["s1"])
    #expect(rows.map(\.weightKg) == [73.44])
    #expect(try context.fetch(FetchDescriptor<HealthDismissalRecord>()).isEmpty)
  }
}
