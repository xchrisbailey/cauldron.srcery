import CauldronImports
import CauldronKit
import Foundation
import SwiftData
import Synchronization
import Testing

@testable import Cauldron

/// A writer that answers one way and keeps what it was asked. Never the real model.
@MainActor
final class StubSearchKeywordWriter: SearchKeywordWriting {
  var outcome: SearchKeywordOutcome
  var inputs: [SearchKeywordInputs] = []
  /// Runs in the middle of a write, with the number of the call.
  var onWrite: ((Int) -> Void)?
  /// What the writer says about itself before it is asked to write; nil means it can run.
  var availability: SearchKeywordUnavailability?
  /// The write waits this long before it answers, as a stalled model would.
  var stall: Duration?

  init(_ outcome: SearchKeywordOutcome = .written("leftover rice, korean")) {
    self.outcome = outcome
  }

  func write(_ inputs: SearchKeywordInputs) async -> SearchKeywordOutcome {
    self.inputs.append(inputs)
    onWrite?(self.inputs.count)
    if let stall { try? await Task.sleep(for: stall) }
    return outcome
  }
}

/// A cloud AI that counts every call it gets.
final class CountingCloudAI: RecipeAI {
  private let calls = Mutex(0)
  var count: Int { calls.withLock { $0 } }

  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    calls.withLock { $0 += 1 }
    throw .unreachable
  }

  func estimateMacros(_ input: MacroEstimateInput) async throws(RecipeAIError) -> Macros {
    calls.withLock { $0 += 1 }
    throw .unreachable
  }

  func estimateMeal(_ text: String) async throws(RecipeAIError) -> [DescribedItem] {
    calls.withLock { $0 += 1 }
    throw .unreachable
  }
}

@MainActor
@Suite("Search keywords")
struct SearchKeywordTests {
  private let context: ModelContext
  private let writer = StubSearchKeywordWriter()
  private let runner: SearchKeywordRunner

  init() throws {
    context = ModelContext(try CauldronStore.container(.inMemory))
    runner = SearchKeywordRunner(writer: writer)
  }

  private func draft(title: String = "Kimchi fried rice", rice: String = "2 cups day-old rice")
    -> RecipeDraft
  {
    var draft = RecipeDraft()
    draft.title = title
    draft.summary = "Uses up leftover rice."
    draft.setIngredientText(draft.ingredients[0].id, rice)
    draft.addIngredient(after: draft.ingredients[0].id)
    draft.setIngredientText(draft.ingredients[1].id, "1 cup kimchi")
    draft.setStepText(draft.steps[0].id, "Fry it.")
    draft.addTag("Dinner")
    return draft
  }

  private func save(_ draft: RecipeDraft, into recipe: RecipeRecord? = nil) throws -> RecipeRecord {
    try RecipeSaver.save(draft, into: recipe, context: context)
  }

  // MARK: Writing

  @Test func aSavedRecipeGetsKeywordsAndTheirFingerprint() async throws {
    let recipe = try save(draft())
    #expect(recipe.searchKeywords == nil)
    #expect(await runner.process(recipe.id, in: context) == .written)
    #expect(recipe.searchKeywords == "leftover rice, korean")
    #expect(recipe.searchKeywordsFingerprint == recipe.searchKeywordInputs?.fingerprint)
    let asked = writer.inputs
    #expect(asked.count == 1)
    #expect(asked.first?.title == "Kimchi fried rice")
    #expect(asked.first?.ingredients == ["day-old rice", "kimchi"])
    #expect(asked.first?.tags == ["Dinner"])
    #expect(asked.first?.description == "Uses up leftover rice.")
  }

  @Test func enqueuingRunsTheJobAfterTheSave() async throws {
    let recipe = try save(draft())
    #expect(writer.inputs.isEmpty)
    await runner.enqueue(recipe.id, in: context).value
    #expect(recipe.searchKeywords == "leftover rice, korean")
  }

  @Test func savingUnchangedDoesNotAskTheWriterAgain() async throws {
    let recipe = try save(draft())
    await runner.enqueue(recipe.id, in: context).value
    var same = RecipeDraft(recipe)
    same.notes = "Serve hot."
    let again = try save(same, into: recipe)
    #expect(await runner.process(again.id, in: context) == .upToDate)
    #expect(writer.inputs.count == 1)
  }

  @Test func editingAnIngredientWritesTheKeywordsAgain() async throws {
    let recipe = try save(draft())
    await runner.enqueue(recipe.id, in: context).value
    let before = recipe.searchKeywordsFingerprint
    writer.outcome = .written("fried rice, spicy")
    var edited = RecipeDraft(recipe)
    edited.setIngredientText(edited.ingredients[0].id, "2 cups brown rice")
    let again = try save(edited, into: recipe)
    #expect(await runner.process(again.id, in: context) == .written)
    #expect(writer.inputs.count == 2)
    #expect(recipe.searchKeywords == "fried rice, spicy")
    #expect(recipe.searchKeywordsFingerprint != before)
    #expect(recipe.searchKeywordsFingerprint == recipe.searchKeywordInputs?.fingerprint)
  }

  @Test func theCloudAIIsNeverCalled() async throws {
    let cloud = CountingCloudAI()
    let device = CountingCloudAI()
    let service = RecipeAIService(
      keys: MemoryKeyStore("a-key"), client: cloud, onDevice: device)
    let recipe = try save(draft())
    #expect(await runner.process(recipe.id, in: context) == .written)
    writer.outcome = .unavailable(.unavailable)
    var edited = RecipeDraft(recipe)
    edited.title = "Kimchi rice"
    let again = try save(edited, into: recipe)
    #expect(await runner.process(again.id, in: context) == .unavailable(.unavailable))
    #expect(cloud.count == 0 && device.count == 0)
    #expect(service.status == .ready)
  }

  @Test(arguments: [
    SearchKeywordUnavailability.unavailable, .notEligible, .downloading,
  ])
  func anUnavailableWriterLeavesTheRecipeWithoutKeywords(
    _ reason: SearchKeywordUnavailability
  ) async throws {
    writer.outcome = .unavailable(reason)
    let recipe = try save(draft())
    #expect(await runner.process(recipe.id, in: context) == .unavailable(reason))
    #expect(recipe.searchKeywords == nil)
    #expect(recipe.searchKeywordsFingerprint == nil)
    #expect(try context.fetchCount(FetchDescriptor<RecipeRecord>()) == 1)
    // Once the model is back the same recipe is written.
    writer.outcome = .written("rice")
    #expect(await runner.process(recipe.id, in: context) == .written)
    #expect(recipe.searchKeywords == "rice")
  }

  @Test func aBadAnswerLeavesTheRecipeAlone() async throws {
    writer.outcome = .failed
    let recipe = try save(draft())
    #expect(await runner.process(recipe.id, in: context) == .failed)
    #expect(recipe.searchKeywords == nil && recipe.searchKeywordsFingerprint == nil)
  }

  @Test func aRecipeThatIsGoneOrBanishedIsNotWritten() async throws {
    #expect(await runner.process(UUID(), in: context) == .gone)
    let recipe = try save(draft())
    RecipeLibrary.banish(recipe)
    #expect(await runner.process(recipe.id, in: context) == .gone)
    #expect(writer.inputs.isEmpty)
  }

  // MARK: One at a time

  @Test func aSecondRequestWhileOneIsRunningDoesNotWriteTwice() async throws {
    let recipe = try save(draft())
    let id = recipe.id
    let context = context
    let runner = runner
    var second: Task<Void, Never>?
    writer.onWrite = { _ in
      // Asked again while the model is working on the same recipe.
      second = runner.enqueue(id, in: context)
    }
    await runner.enqueue(id, in: context).value
    await second?.value
    #expect(second != nil)
    #expect(writer.inputs.count == 1)
    #expect(recipe.searchKeywords == "leftover rice, korean")
  }

  @Test func aRecipeEditedWhileItsKeywordsAreWrittenIsWrittenAgain() async throws {
    let recipe = try save(draft())
    let context = context
    writer.onWrite = { call in
      guard call == 1 else { return }
      // The cook saves a change while the model is working.
      var edited = RecipeDraft(recipe)
      edited.title = "Kimchi rice bowl"
      _ = try? RecipeSaver.save(edited, into: recipe, context: context)
    }
    #expect(await runner.process(recipe.id, in: context) == .written)
    #expect(writer.inputs.count == 2)
    #expect(writer.inputs.last?.title == "Kimchi rice bowl")
    #expect(recipe.searchKeywordsFingerprint == recipe.searchKeywordInputs?.fingerprint)
  }

  // MARK: Recipes it must not write for

  @Test func aRecipeWithALineThisBuildCantReadIsNotWritten() async throws {
    let recipe = try save(draft())
    var lines = try #require(
      JSONSerialization.jsonObject(with: recipe.ingredientsData) as? [[String: Any]])
    lines[1]["unit"] = "unit-from-the-future"
    recipe.ingredientsData = try JSONSerialization.data(withJSONObject: lines)
    #expect(!recipe.canRewriteIngredients)
    #expect(await runner.process(recipe.id, in: context) == .unreadable)
    #expect(writer.inputs.isEmpty)
    #expect(recipe.searchKeywords == nil && recipe.searchKeywordsFingerprint == nil)
  }

  @Test(arguments: ["", "  \n ", " , "])
  func anEmptyAnswerIsNotStoredAsCurrent(_ text: String) async throws {
    writer.outcome = .written(text)
    let recipe = try save(draft())
    #expect(await runner.process(recipe.id, in: context) == .failed)
    #expect(recipe.searchKeywords == nil && recipe.searchKeywordsFingerprint == nil)
  }

  // MARK: Failing

  @Test func aStalledModelIsGivenUpOnAndTheJobClears() async throws {
    writer.stall = .seconds(3_600)
    let quick = SearchKeywordRunner(writer: writer, timeout: .milliseconds(50))
    let recipe = try save(draft())
    let job = quick.enqueue(recipe.id, in: context)
    await job.value
    await quick.settled()
    #expect(recipe.searchKeywords == nil && recipe.searchKeywordsFingerprint == nil)
    // The recipe can be asked for again, and a model that has recovered is used.
    writer.stall = nil
    #expect(await quick.process(recipe.id, in: context) == .written)
  }

  @Test func aStalledModelReportsAFailure() async throws {
    writer.stall = .seconds(3_600)
    let quick = SearchKeywordRunner(writer: writer, timeout: .milliseconds(50))
    let recipe = try save(draft())
    #expect(await quick.process(recipe.id, in: context) == .timedOut)
  }

  @Test func aSaveThatFailsRestoresTheRecipeAndKeepsOtherPendingChanges() async throws {
    struct Refused: Error {}
    let failing = SearchKeywordRunner(writer: writer, save: { _ in throw Refused() })
    let recipe = try save(draft())
    recipe.searchKeywords = "old words"
    recipe.searchKeywordsFingerprint = "oldfingerprint"
    try context.save()
    let other = try save(draft(title: "Toast"))
    // A change another screen has made and not saved yet.
    other.notes = "Pending change"
    #expect(await failing.process(recipe.id, in: context) == .failed)
    #expect(recipe.searchKeywords == "old words")
    #expect(recipe.searchKeywordsFingerprint == "oldfingerprint")
    #expect(other.notes == "Pending change")
  }

  // MARK: Search

  @Test func searchFindsARecipeThroughItsKeywords() async throws {
    let kimchi = try save(draft())
    let toast = try save(draft(title: "Toast", rice: "1 slice bread"))
    #expect(
      RecipeLibrary.visible([kimchi, toast], matching: "korean", tag: nil, sort: .recent).isEmpty)
    _ = await runner.process(kimchi.id, in: context)
    let found = RecipeLibrary.visible(
      [kimchi, toast], matching: "korean leftover", tag: nil, sort: .recent)
    #expect(found.map(\.title) == ["Kimchi fried rice"])
  }
}
