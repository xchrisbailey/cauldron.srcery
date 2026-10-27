import CauldronImports
import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("Search keyword backfill")
struct SearchKeywordBackfillTests {
  private let context: ModelContext
  private let writer = StubSearchKeywordWriter(.written("korean"))
  private let runner: SearchKeywordRunner

  init() throws {
    context = ModelContext(try CauldronStore.container(.inMemory))
    runner = SearchKeywordRunner(writer: writer)
  }

  /// A recipe as an older build saved it: no keywords, no fingerprint.
  @discardableResult
  private func legacy(_ title: String) throws -> RecipeRecord {
    var draft = RecipeDraft()
    draft.title = title
    draft.setIngredientText(draft.ingredients[0].id, "1 cup rice")
    draft.setStepText(draft.steps[0].id, "Cook it.")
    return try RecipeSaver.save(draft, into: nil, context: context)
  }

  private func asked() -> [String] { writer.inputs.map(\.title) }

  // MARK: What it picks

  @Test func onlyMissingOrStaleRecipesAreProcessed() async throws {
    let current = try legacy("Current")
    #expect(await runner.process(current.id, in: context) == .written)
    let stale = try legacy("Stale")
    stale.searchKeywords = "old"
    stale.searchKeywordsFingerprint = "00000000deadbeef"
    try legacy("Missing")
    writer.inputs.removeAll()
    #expect(SearchKeywordRunner.pendingCount(in: context) == 2)
    await runner.drain(in: context)
    #expect(Set(asked()) == ["Stale", "Missing"])
    #expect(asked().count == 2)
    #expect(stale.searchKeywords == "korean")
    #expect(SearchKeywordRunner.pendingCount(in: context) == 0)
    #expect(runner.pending == 0)
  }

  @Test func keywordsAnotherDeviceWroteAreSkipped() async throws {
    let synced = try legacy("Synced")
    synced.searchKeywords = "from the other device"
    synced.searchKeywordsFingerprint = synced.searchKeywordInputs.fingerprint
    await runner.drain(in: context)
    #expect(writer.inputs.isEmpty)
    #expect(synced.searchKeywords == "from the other device")
  }

  @Test func aFreshRunPicksUpWhereTheLastOneStopped() async throws {
    for title in ["One", "Two", "Three"] { try legacy(title) }
    writer.onWrite = { [writer] call in
      if call == 2 { writer.outcome = .unavailable(.unavailable) }
    }
    await runner.drain(in: context)
    // Two were asked: the second found the model gone, so one was written.
    #expect(SearchKeywordRunner.pendingCount(in: context) == 2)
    // A new launch: a new runner, with only the stored fingerprints to go on.
    let later = StubSearchKeywordWriter(.written("rice"))
    let fresh = SearchKeywordRunner(writer: later)
    await fresh.drain(in: context)
    #expect(later.inputs.count == 2)
    #expect(SearchKeywordRunner.pendingCount(in: context) == 0)
  }

  @Test func staleFingerprintsFromATagRenameOrACopyAreCaughtByTheScan() async throws {
    let recipe = try legacy("Rice")
    await runner.drain(in: context)
    #expect(writer.inputs.count == 1)
    let tag = TagRecord(name: "Dinner")
    context.insert(tag)
    recipe.tags = [tag]
    tag.name = "Supper"
    try context.save()
    #expect(SearchKeywordRunner.pendingCount(in: context) == 1)
    await runner.drain(in: context)
    #expect(writer.inputs.count == 2)
    #expect(writer.inputs.last?.tags == ["Supper"])
  }

  @Test func banishedAndUnreadableRecipesAreSkippedAndNotCounted() async throws {
    let banished = try legacy("Banished")
    RecipeLibrary.banish(banished)
    let unreadable = try legacy("Unreadable")
    var lines = try #require(
      JSONSerialization.jsonObject(with: unreadable.ingredientsData) as? [[String: Any]])
    lines[0]["unit"] = "unit-from-the-future"
    unreadable.ingredientsData = try JSONSerialization.data(withJSONObject: lines)
    try legacy("Fine")
    #expect(SearchKeywordRunner.pendingCount(in: context) == 1)
    await runner.drain(in: context)
    #expect(asked() == ["Fine"])
    #expect(banished.searchKeywordsFingerprint == nil)
    #expect(unreadable.searchKeywordsFingerprint == nil)
    #expect(runner.pending == 0)
  }

  // MARK: Pausing

  @Test(arguments: [SearchKeywordUnavailability.unavailable, .notEligible, .downloading])
  func anUnavailableModelPausesTheJobKeepsTheCountAndSpendsNothing(
    _ reason: SearchKeywordUnavailability
  ) async throws {
    for title in ["One", "Two", "Three"] { try legacy(title) }
    writer.outcome = .unavailable(reason)
    for _ in 0..<5 { await runner.drain(in: context) }
    // Each pass stopped at the first recipe, since the rest would find the same.
    #expect(writer.inputs.count == 5)
    #expect(SearchKeywordRunner.pendingCount(in: context) == 3)
    #expect(runner.pending == 3)
    #expect(runner.unavailability == reason)
    #expect(runner.stillReading == nil)
    // The model comes back: nothing was given up on, so all three are written.
    writer.outcome = .written("rice")
    await runner.drain(in: context)
    #expect(SearchKeywordRunner.pendingCount(in: context) == 0)
    #expect(runner.unavailability == nil)
    #expect(writer.inputs.count == 8)
  }

  // MARK: Giving up

  @Test func aRecipeIsGivenUpOnAfterTheAttemptLimitAndRetriedOnlyWhenEdited() async throws {
    let recipe = try legacy("Stubborn")
    writer.outcome = .failed
    await runner.drain(in: context)
    #expect(writer.inputs.count == AIJobRules.maxAttempts)
    // Current with no words: out of the count, and not asked again.
    #expect(recipe.searchKeywords == nil)
    #expect(recipe.searchKeywordsFingerprint == recipe.searchKeywordInputs.fingerprint)
    #expect(SearchKeywordRunner.pendingCount(in: context) == 0)
    await runner.drain(in: context)
    #expect(writer.inputs.count == AIJobRules.maxAttempts)
    // An edit makes it stale, and it gets a fresh set of attempts.
    recipe.title = "Less stubborn"
    writer.outcome = .written("rice")
    await runner.drain(in: context)
    #expect(writer.inputs.count == AIJobRules.maxAttempts + 1)
    #expect(recipe.searchKeywords == "rice")
  }

  @Test func attemptsAreCountedForEachRecipe() async throws {
    try legacy("One")
    try legacy("Two")
    writer.outcome = .failed
    await runner.drain(in: context)
    #expect(writer.inputs.count == 2 * AIJobRules.maxAttempts)
    #expect(runner.pending == 0)
  }

  @Test func attemptsAreSpentAgainOnAnEditedRecipe() async throws {
    let recipe = try legacy("Rice")
    writer.outcome = .failed
    #expect(await runner.process(recipe.id, in: context) == .failed)
    #expect(await runner.process(recipe.id, in: context) == .failed)
    recipe.title = "Rice bowl"
    #expect(await runner.process(recipe.id, in: context) == .failed)
    #expect(await runner.process(recipe.id, in: context) == .failed)
    // Four failures in all, but two of them were for other words: not yet at the limit.
    #expect(recipe.searchKeywordsFingerprint == nil)
    #expect(await runner.process(recipe.id, in: context) == .gaveUp)
    #expect(recipe.searchKeywordsFingerprint == recipe.searchKeywordInputs.fingerprint)
  }

  // MARK: The cloud AI

  @Test func theCloudAIIsNeverCalledByTheBackfill() async throws {
    let cloud = CountingCloudAI()
    let device = CountingCloudAI()
    _ = RecipeAIService(keys: MemoryKeyStore("a-key"), client: cloud, onDevice: device)
    try legacy("One")
    try legacy("Two")
    await runner.drain(in: context)
    writer.outcome = .unavailable(.unavailable)
    try legacy("Three")
    await runner.drain(in: context)
    writer.outcome = .failed
    await runner.drain(in: context)
    #expect(cloud.count == 0 && device.count == 0)
  }

  // MARK: Reading along

  @Test func theRunnerShowsTheCountOnlyWhileItCanRun() async throws {
    #expect(runner.stillReading == nil)
    try legacy("One")
    try legacy("Two")
    writer.outcome = .unavailable(.downloading)
    runner.refreshPending(in: context)
    #expect(runner.pending == 2)
    #expect(runner.stillReading == 2)
    await runner.drain(in: context)
    #expect(runner.stillReading == nil)
    writer.outcome = .written("rice")
    await runner.drain(in: context)
    #expect(runner.stillReading == nil)
  }

  @Test func theCountFallsAsRecipesAreWritten() async throws {
    for title in ["One", "Two", "Three"] { try legacy(title) }
    var seen: [Int] = []
    let runner = runner
    writer.onWrite = { _ in seen.append(runner.pending) }
    await runner.drain(in: context)
    #expect(seen == [2, 1, 0])
  }

  // MARK: The index

  @Test func eachWriteChangesOneSearchEntrySoTheIndexRebuildsOncePerRecipe() async throws {
    for title in ["One", "Two", "Three"] { try legacy(title) }
    let cache = RecipeSearchCache()
    func recipes() throws -> [RecipeRecord] {
      try context.fetch(FetchDescriptor<RecipeRecord>(sortBy: [SortDescriptor(\.title)]))
    }
    var before = cache.index(for: try recipes()).entries
    var changes = 0
    writer.onWrite = { _ in }
    for recipe in try recipes() {
      #expect(await runner.process(recipe.id, in: context) == .written)
      let after = cache.index(for: try recipes()).entries
      changes += zip(before, after).filter { $0 != $1 }.count
      #expect(zip(before, after).filter { $0 != $1 }.count == 1)
      before = after
    }
    #expect(changes == 3)
    // Nothing changes while nothing is written.
    #expect(cache.index(for: try recipes()).entries == before)
  }
}
