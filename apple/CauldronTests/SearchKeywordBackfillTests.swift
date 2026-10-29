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
    synced.searchKeywordsFingerprint = synced.searchKeywordInputs?.fingerprint
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
    #expect(recipe.searchKeywordsFingerprint == recipe.searchKeywordInputs?.fingerprint)
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
    #expect(recipe.searchKeywordsFingerprint == recipe.searchKeywordInputs?.fingerprint)
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
    #expect(seen == [3, 2, 1])
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

  // MARK: Asking before reading

  @Test(arguments: [SearchKeywordUnavailability.unavailable, .notEligible, .downloading])
  func aWriterThatReportsItselfUnavailableIsNeverAskedAndTheFooterNeverShows(
    _ reason: SearchKeywordUnavailability
  ) async throws {
    writer.availability = reason
    try legacy("One")
    try legacy("Two")
    #expect(runner.stillReading == nil)
    // Counting alone must not make the line show.
    runner.refreshPending(in: context)
    #expect(runner.pending == 2)
    #expect(runner.stillReading == nil)
    await runner.drain(in: context)
    #expect(writer.inputs.isEmpty)
    #expect(runner.pending == 2)
    #expect(runner.unavailability == reason)
    #expect(runner.stillReading == nil)
    // A save-time job is turned away the same way.
    let id = try #require(try context.fetch(FetchDescriptor<RecipeRecord>()).first?.id)
    #expect(await runner.process(id, in: context) == .unavailable(reason))
    #expect(writer.inputs.isEmpty)
  }

  @Test func theJobRunsAgainOnceTheModelReportsItselfAvailable() async throws {
    writer.availability = .downloading
    try legacy("One")
    await runner.drain(in: context)
    #expect(runner.stillReading == nil)
    writer.availability = nil
    await runner.drain(in: context)
    #expect(writer.inputs.count == 1)
    #expect(runner.unavailability == nil)
    #expect(runner.pending == 0)
  }

  // MARK: Counting

  /// Recipes straight into the store: a thousand through the saver would take a while.
  private func fill(_ count: Int) throws {
    for number in 1...count {
      let recipe = RecipeRecord(title: "Recipe \(number)")
      context.insert(recipe)
      recipe.ingredients = [
        Ingredient(
          section: nil, quantity: nil, unit: nil, item: "rice \(number)", note: nil,
          optional: false, alt: nil, original: "rice \(number)", itemKey: "rice")
      ]
    }
    try context.save()
  }

  @Test func aThousandRecipesAreCountedOncePerDrainNotOncePerJob() async throws {
    try fill(1_000)
    let clock = ContinuousClock()
    let counted = clock.measure { runner.refreshPending(in: context) }
    // Not an assertion on speed, but a note: this is what the start of a drain costs.
    print("Counting 1,000 recipes took \(counted)")
    #expect(runner.pending == 1_000)
    #expect(runner.scans == 1)
    var low = 1_000
    writer.onWrite = { [runner] _ in low = min(low, runner.pending) }
    await runner.drain(in: context)
    #expect(writer.inputs.count == 1_000)
    #expect(runner.pending == 0)
    #expect(low == 1)
    // One count before the drain, one at its start; none for any of the thousand jobs.
    #expect(runner.scans == 2)
    #expect(SearchKeywordRunner.pendingCount(in: context) == 0)
  }

  @Test func aSaveJobAdjustsTheCountForItsRecipeAloneWithoutAScan() async throws {
    try legacy("Old")
    runner.refreshPending(in: context)
    #expect(runner.pending == 1 && runner.scans == 1)
    // A new recipe is saved and written: it was never counted, and is not afterwards.
    let fresh = try legacy("Fresh")
    await runner.enqueue(fresh.id, in: context).value
    #expect(runner.pending == 1)
    // A recipe that was counted and is written by its save job comes off the count.
    let old = try #require(
      try context.fetch(FetchDescriptor<RecipeRecord>()).first { $0.title == "Old" })
    await runner.enqueue(old.id, in: context).value
    #expect(runner.pending == 0)
    // A job that gives up leaves the count, too.
    writer.outcome = .failed
    let stubborn = try legacy("Stubborn")
    for _ in 0..<AIJobRules.maxAttempts { _ = await runner.process(stubborn.id, in: context) }
    #expect(runner.pending == 0)
    #expect(runner.scans == 1)
  }

  // MARK: Giving up keeps what is there

  @Test func aGiveUpLeavesKeywordsThatSyncedInDuringTheLastCall() async throws {
    let recipe = try legacy("Rice")
    writer.outcome = .failed
    writer.onWrite = { [recipe] call in
      guard call == AIJobRules.maxAttempts else { return }
      // The other device's keywords arrive while the third attempt is running.
      recipe.searchKeywords = "good"
      recipe.searchKeywordsFingerprint = recipe.searchKeywordInputs?.fingerprint
    }
    await runner.drain(in: context)
    #expect(recipe.searchKeywords == "good")
    #expect(recipe.searchKeywordsFingerprint == recipe.searchKeywordInputs?.fingerprint)
    #expect(runner.pending == 0)
  }

  @Test func aGiveUpKeepsOldKeywordsUnderTheNewFingerprint() async throws {
    let recipe = try legacy("Rice")
    #expect(await runner.process(recipe.id, in: context) == .written)
    let written = recipe.searchKeywordsFingerprint
    recipe.title = "Rice bowl"
    writer.outcome = .failed
    await runner.drain(in: context)
    #expect(recipe.searchKeywords == "korean")
    #expect(recipe.searchKeywordsFingerprint == recipe.searchKeywordInputs?.fingerprint)
    #expect(recipe.searchKeywordsFingerprint != written)
    #expect(SearchKeywordRunner.pendingCount(in: context) == 0)
  }

  @Test func aGiveUpForInputsThatChangedMeanwhileStoresNothing() async throws {
    let recipe = try legacy("Rice")
    writer.outcome = .failed
    writer.onWrite = { [recipe] call in
      if call == AIJobRules.maxAttempts { recipe.title = "Edited meanwhile" }
    }
    for _ in 0..<AIJobRules.maxAttempts {
      #expect(await runner.process(recipe.id, in: context) == .failed)
    }
    // The failures were for other words, so the edited recipe is still waiting.
    #expect(recipe.searchKeywordsFingerprint == nil)
    #expect(SearchKeywordRunner.pendingCount(in: context) == 1)
  }

  @Test func aGiveUpThatCannotBeStoredStillSticksForTheSession() async throws {
    struct Refused: Error {}
    let failing = SearchKeywordRunner(writer: writer, save: { _ in throw Refused() })
    let recipe = try legacy("Stubborn")
    writer.outcome = .failed
    await failing.drain(in: context)
    // Three attempts, then it is let go: the model is not called for ever.
    #expect(writer.inputs.count == AIJobRules.maxAttempts)
    #expect(failing.pending == 0)
    await failing.drain(in: context)
    #expect(writer.inputs.count == AIJobRules.maxAttempts)
    #expect(failing.stillReading == nil)
    // Nothing reached the store, so after a relaunch it would be tried afresh.
    #expect(recipe.searchKeywordsFingerprint == nil)
    // Edited, it is a different recipe to the runner and gets its attempts again.
    recipe.title = "Less stubborn"
    await failing.drain(in: context)
    #expect(writer.inputs.count == 2 * AIJobRules.maxAttempts)
  }

  // MARK: A stalled model

  @Test func aTimeoutPausesTheDrainAfterOneRecipeAndSpendsNoAttempt() async throws {
    try legacy("One")
    try legacy("Two")
    writer.stall = .seconds(3_600)
    let slow = SearchKeywordRunner(writer: writer, timeout: .milliseconds(50))
    await slow.drain(in: context)
    #expect(writer.inputs.count == 1)
    #expect(slow.pending == 2)
    #expect(slow.stillReading == nil)
    // Next foreground: the model answers, and both are written.
    writer.stall = nil
    await slow.drain(in: context)
    #expect(writer.inputs.count == 3)
    #expect(slow.pending == 0)
  }

  @Test func aTimeoutIsNotAnAttempt() async throws {
    let recipe = try legacy("Rice")
    writer.stall = .seconds(3_600)
    let slow = SearchKeywordRunner(writer: writer, timeout: .milliseconds(50))
    for _ in 0..<5 { await slow.drain(in: context) }
    #expect(writer.inputs.count == 5)
    #expect(recipe.searchKeywordsFingerprint == nil)
    // All three attempts are still there to spend.
    writer.stall = nil
    writer.outcome = .failed
    await slow.drain(in: context)
    #expect(writer.inputs.count == 5 + AIJobRules.maxAttempts)
    #expect(recipe.searchKeywordsFingerprint == recipe.searchKeywordInputs?.fingerprint)
  }

  // MARK: Owning the drain

  @Test func aStopAndAStartMidRecipeStillFinishesEveryPendingRecipe() async throws {
    for title in ["One", "Two", "Three"] { try legacy(title) }
    let runner = runner
    let context = context
    writer.onWrite = { call in
      guard call == 1 else { return }
      // Backgrounded and brought forward again while the first is being written.
      runner.stopDraining()
      runner.startDraining(in: context)
    }
    runner.startDraining(in: context)
    await runner.settled()
    #expect(writer.inputs.count == 3)
    #expect(runner.pending == 0)
  }

  @Test func aStopWithoutAStartEndsTheDrainAfterTheRecipeInHand() async throws {
    for title in ["One", "Two", "Three"] { try legacy(title) }
    let runner = runner
    writer.onWrite = { call in
      if call == 1 { runner.stopDraining() }
    }
    runner.startDraining(in: context)
    await runner.settled()
    #expect(writer.inputs.count == 1)
    #expect(runner.pending == 2)
    // The next foreground starts it again.
    writer.onWrite = nil
    runner.startDraining(in: context)
    await runner.settled()
    #expect(writer.inputs.count == 3)
  }

  @Test func startingWhileADrainIsRunningDoesNotStartASecond() async throws {
    for title in ["One", "Two"] { try legacy(title) }
    runner.startDraining(in: context)
    runner.startDraining(in: context)
    await runner.settled()
    #expect(writer.inputs.count == 2)
  }

  // MARK: The footer follows the model

  @Test func aBadAnswerDoesNotHideTheFooterWhileTheModelIsAvailable() async throws {
    for title in ["One", "Two", "Three"] { try legacy(title) }
    writer.outcome = .failed
    var shown: [Int?] = []
    let runner = runner
    writer.onWrite = { _ in shown.append(runner.stillReading) }
    await runner.drain(in: context)
    #expect(!shown.isEmpty)
    #expect(shown.allSatisfy { $0 != nil })
  }

  @Test func theFooterFollowsTheModelsOwnCheckAfterEveryRecipe() async throws {
    let recipe = try legacy("Rice")
    writer.outcome = .unavailable(.downloading)
    #expect(await runner.process(recipe.id, in: context) == .unavailable(.downloading))
    #expect(runner.unavailability == .downloading)
    // The model is back, and the next turn is a bad answer: the line comes back all the same.
    writer.outcome = .failed
    #expect(await runner.process(recipe.id, in: context) == .failed)
    #expect(runner.unavailability == nil)
    runner.refreshPending(in: context)
    #expect(runner.stillReading == 1)
    // And it goes when the model says it can't run.
    writer.availability = .notEligible
    #expect(await runner.process(recipe.id, in: context) == .unavailable(.notEligible))
    #expect(runner.stillReading == nil)
  }
}
