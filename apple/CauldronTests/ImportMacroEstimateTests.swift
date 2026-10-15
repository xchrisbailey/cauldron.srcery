import CauldronKit
import Foundation
import SwiftData
import Synchronization
import Testing

@testable import Cauldron

/// An estimator that answers one way and keeps what it was asked. Never the real provider.
final class ScriptedEstimator: RecipeAI {
  enum Reply: Sendable {
    case macros(Macros)
    case fail(RecipeAIError)
    /// Never answers, until it is cancelled.
    case hang
  }

  private let reply: Reply
  private let seen = Mutex<[MacroEstimateInput]>([])

  init(_ reply: Reply) { self.reply = reply }

  var inputs: [MacroEstimateInput] { seen.withLock { $0 } }

  func estimateMacros(_ input: MacroEstimateInput) async throws(RecipeAIError) -> Macros {
    seen.withLock { $0.append(input) }
    switch reply {
    case .macros(let macros): return macros
    case .fail(let error): throw error
    case .hang:
      do { try await Task.sleep(for: .seconds(60)) } catch { throw .cancelled }
      throw .unreachable
    }
  }

  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    throw .unreachable
  }

  func estimateMeal(_ text: String) async throws(RecipeAIError) -> [DescribedItem] {
    throw .unreachable
  }
}

/// An import estimates its macros while it reads, as the web app's import did
/// (`withMacros` in `apps/api/src/imports/distill.ts`): the numbers land in the draft flagged
/// for the cook to check, and an estimate that couldn't be had is queued by Save instead.
@MainActor
@Suite("Import macro estimates")
struct ImportMacroEstimateTests {
  private let estimate = Macros(calories: 310, protein: 17, carbs: 18, fat: 19)
  private let container: ModelContainer
  private var context: ModelContext { container.mainContext }

  init() throws {
    container = try CauldronStore.container(.inMemory)
  }

  private func fetcher(nutrition: Bool = false) -> ScriptedFetcher {
    ScriptedFetcher([
      ImportFixtures.tacosLink: ImportFixtures.tacos(nutrition: nutrition, image: false)
    ])
  }

  private func flow(
    _ estimator: (any RecipeAI)?, nutrition: Bool = false, wait: Duration = .seconds(30)
  ) -> ImportModel {
    var options = ImportFixtures.quick
    options.macroTimeout = wait
    return ImportModel(
      fetcher: fetcher(nutrition: nutrition), extractor: nil, estimator: estimator,
      options: options)
  }

  private func draft(from model: ImportModel) async throws -> RecipeDraft {
    model.link = ImportFixtures.tacosLink
    model.start()
    await model.finished()
    guard case .ready(let review) = model.phase else {
      throw Failure("not ready: \(model.phase)")
    }
    return review.draft
  }

  private struct Failure: Error { let message: String; init(_ m: String) { message = m } }

  @Test func theEstimateIsPutInTheDraftFlaggedForTheCookToCheck() async throws {
    let estimator = ScriptedEstimator(.macros(estimate))
    let draft = try await draft(from: flow(estimator))

    #expect(draft.typedMacros == estimate)
    #expect(draft.calories == "310" && draft.protein == "17")
    #expect(draft.estimatedMacros == estimate)
    #expect(draft.review.contains(.macros))
    #expect(draft.needsReview)
    #expect(draft.pageMacros == nil)
    // It was had, so Save has nothing to queue.
    #expect(!draft.estimateOnSave)
    // The ask is the recipe's own lines and yield.
    #expect(estimator.inputs.count == 1)
    #expect(estimator.inputs.first?.title == "Smoky black bean tacos")
    #expect(estimator.inputs.first?.servings == 4)
    #expect(
      estimator.inputs.first?.ingredients == [
        "2 cans black beans, drained", "1 tsp smoked paprika", "8 corn tortillas",
      ])
  }

  @Test func theCookChangingAnEstimatedNumberMakesItTheirsAndClearsTheFlag() async throws {
    var draft = try await draft(from: flow(ScriptedEstimator(.macros(estimate))))
    draft.calories = "280"
    #expect(!draft.review.contains(.macros))
    let recipe = try RecipeSaver.save(draft, into: nil, context: context)
    #expect(recipe.macrosSource == .manual)
  }

  @Test func savingKeepsTheEstimateMarkedAsOneAndQueuesNothing() async throws {
    let draft = try await draft(from: flow(ScriptedEstimator(.macros(estimate))))
    let recipe = try RecipeSaver.save(draft, into: nil, context: context)
    #expect(recipe.macros == estimate)
    #expect(recipe.macrosSource == .estimated)
    #expect(!RecipeMacroEstimates.queueAfterSave(of: draft, saved: recipe, in: context))
    #expect(!recipe.macrosPending)
    #expect((recipe.aiJobs ?? []).isEmpty)
  }

  @Test func numbersTheCookClearsAreNotAskedForAgain() async throws {
    var draft = try await draft(from: flow(ScriptedEstimator(.macros(estimate))))
    draft.calories = ""
    draft.protein = ""
    draft.carbs = ""
    draft.fat = ""
    let recipe = try RecipeSaver.save(draft, into: nil, context: context)
    #expect(!RecipeMacroEstimates.queueAfterSave(of: draft, saved: recipe, in: context))
  }

  @Test func nutritionThePagePublishedWinsAndNothingIsAsked() async throws {
    let estimator = ScriptedEstimator(.macros(estimate))
    let draft = try await draft(from: flow(estimator, nutrition: true))
    #expect(estimator.inputs.isEmpty)
    #expect(draft.calories == "350")
    #expect(draft.pageMacros == draft.typedMacros)
    #expect(draft.estimatedMacros == nil)
    #expect(!draft.estimateOnSave)
    #expect(!draft.review.contains(.macros))
    let recipe = try RecipeSaver.save(draft, into: nil, context: context)
    #expect(recipe.macrosSource == .page)
  }

  @Test(
    arguments: [
      RecipeAIError.missingKey, .invalidKey, .rateLimited, .noCredit, .invalidModel, .unreachable,
    ])
  func anEstimateThatCantBeHadIsLeftEmptyAndQueuedBySave(error: RecipeAIError) async throws {
    let draft = try await draft(from: flow(ScriptedEstimator(.fail(error))))
    #expect(draft.typedMacros == .none)
    #expect(draft.estimatedMacros == nil)
    #expect(!draft.review.contains(.macros))
    #expect(draft.estimateOnSave)

    let recipe = try RecipeSaver.save(draft, into: nil, context: context)
    #expect(recipe.macros == .none)
    #expect(RecipeMacroEstimates.queueAfterSave(of: draft, saved: recipe, in: context))
    #expect(recipe.macrosPending)
  }

  @Test func anEstimateThatTakesTooLongIsLeftForAfterSave() async throws {
    let estimator = ScriptedEstimator(.hang)
    let started = ContinuousClock.now
    let draft = try await draft(from: flow(estimator, wait: .milliseconds(50)))
    #expect(ContinuousClock.now - started < .seconds(10))
    #expect(estimator.inputs.count == 1)
    #expect(draft.typedMacros == .none)
    #expect(draft.estimateOnSave)
    #expect(!draft.review.contains(.macros))
  }

  @Test func aBadOrEmptyAnswerIsNeverGuessedAtAndStaysQueued() async throws {
    for reply in [ScriptedEstimator.Reply.fail(.failed(detail: "nope")), .macros(Macros())] {
      let draft = try await draft(from: flow(ScriptedEstimator(reply)))
      #expect(draft.typedMacros == .none)
      #expect(draft.estimateOnSave)
    }
  }

  @Test func withNoAIServiceTheEstimateWaitsForSave() async throws {
    let draft = try await draft(from: flow(nil))
    #expect(draft.typedMacros == .none)
    #expect(draft.estimateOnSave)
  }

  @Test func pastedTextIsEstimatedToo() async throws {
    let estimator = ScriptedEstimator(.macros(estimate))
    let model = ImportModel(
      fetcher: ScriptedFetcher(), extractor: nil, estimator: estimator,
      options: ImportFixtures.quick)
    model.text = ImportFixtures.soupPage
    model.start()
    await model.finished()
    guard case .ready(let review) = model.phase else {
      throw Failure("not ready: \(model.phase)")
    }
    #expect(review.draft.typedMacros == estimate)
    #expect(estimator.inputs.first?.ingredients == ["2 onions", "400 g tomatoes"])
  }

  @Test func theLimitIsThirtySecondsLikeTheReference() {
    #expect(DistillOptions().macroTimeout == .seconds(30))
  }
}
