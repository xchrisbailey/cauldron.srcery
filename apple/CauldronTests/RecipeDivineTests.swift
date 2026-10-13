import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

private let estimate = Macros(calories: 310, protein: 17, carbs: 18, fat: 19)
private let emptyJSON = #"{"servings":null,"calories":null,"protein":null,"carbs":null,"fat":null}"#
private let badAnswer = ScriptedTransport.Reply.status(200, answer(#"{"nope":1}"#))
private let goodAnswer = ScriptedTransport.Reply.status(200, answer(macrosJSON))

private func body(_ request: URLRequest?) -> String {
  String(decoding: request?.httpBody ?? Data(), as: UTF8.self)
}

@MainActor
@Suite("Divine macros")
struct DivineMacrosTests {
  private let container: ModelContainer
  private var context: ModelContext { container.mainContext }

  init() throws {
    container = try CauldronStore.container(.inMemory)
  }

  private func recipe(_ title: String = "Shakshuka", lines: [String] = ["6 large eggs"])
    -> RecipeRecord
  {
    let recipe = RecipeRecord(title: title)
    recipe.servings = 4
    recipe.ingredients = lines.map {
      Ingredient(
        section: nil, quantity: nil, unit: nil, item: $0, note: nil, optional: false,
        alt: nil, original: $0, itemKey: $0)
    }
    context.insert(recipe)
    return recipe
  }

  private func jobs() throws -> [AIJobRecord] {
    try context.fetch(FetchDescriptor<AIJobRecord>())
  }

  // MARK: The button

  @Test func theButtonFillsTheMacrosAndMarksThemAsAnEstimate() async throws {
    let recipe = recipe()
    #expect(RecipeMacroEstimates.state(of: recipe) == .idle)
    let (ai, transport, _) = service([goodAnswer])
    await RecipeMacroEstimates.divine(recipe, in: context, using: ai)
    #expect(recipe.macros == estimate)
    #expect(recipe.macrosSource == .estimated)
    #expect(!recipe.macrosPending)
    #expect(try jobs().isEmpty)
    #expect(RecipeMacroEstimates.state(of: recipe) == .hidden)
    #expect(transport.requests.count == 1)
  }

  @Test func withGeminiOutOfReachTheEstimateWaitsAndThenFillsIn() async throws {
    let recipe = recipe()
    let (ai, _, _) = service([.offline, goodAnswer])
    await RecipeMacroEstimates.divine(recipe, in: context, using: ai)
    #expect(RecipeMacroEstimates.state(of: recipe) == .waiting)
    #expect(recipe.macrosPending && recipe.macros == .none)
    #expect(try jobs().count == 1)

    // The app's next drain (coming forward, the network returning).
    await AIJobQueue.drain(in: context, using: ai.estimator)
    #expect(recipe.macros == estimate)
    #expect(recipe.macrosSource == .estimated)
    #expect(!recipe.macrosPending)
    #expect(try jobs().isEmpty)
  }

  @Test func theOnDeviceModelIsNeverUsedForAnEstimate() async throws {
    let recipe = recipe()
    let (ai, _, _) = service([.offline], onDevice: true)
    await RecipeMacroEstimates.divine(recipe, in: context, using: ai)
    #expect(recipe.macros == .none && recipe.macrosPending)
  }

  @Test func withoutAKeyItWaitsAndTheStatusSaysWhy() async throws {
    let recipe = recipe()
    let (ai, transport, _) = service(key: nil, [])
    await RecipeMacroEstimates.divine(recipe, in: context, using: ai)
    #expect(RecipeMacroEstimates.state(of: recipe) == .waiting)
    #expect(ai.status == .missingKey && ai.status.needsAttention)
    #expect(transport.requests.isEmpty)
  }

  @Test func numbersTheCookTypedInWhileItWaitedAreKept() async throws {
    let recipe = recipe()
    let (ai, _, _) = service([.offline, goodAnswer])
    await RecipeMacroEstimates.divine(recipe, in: context, using: ai)
    recipe.macros = Macros(calories: 500, protein: 1, carbs: 2, fat: 3)
    recipe.macrosSource = .manual
    await AIJobQueue.drain(in: context, using: ai.estimator)
    #expect(recipe.macros.calories == 500)
    #expect(recipe.macrosSource == .manual)
    #expect(!recipe.macrosPending)
  }

  @Test func theButtonIsNotOfferedWhereTheCooksOwnNumbersWouldBeKept() {
    let recipe = recipe()
    recipe.macros = Macros(calories: 500)
    recipe.macrosSource = .manual
    #expect(RecipeMacroEstimates.state(of: recipe) == .hidden)
    // Numbers from an import with gaps can still be completed.
    recipe.macrosSource = .page
    #expect(RecipeMacroEstimates.state(of: recipe) == .idle)
    // A complete set has nothing to divine.
    recipe.macros = estimate
    #expect(RecipeMacroEstimates.state(of: recipe) == .hidden)
  }

  @Test func anEstimateWithNothingInItLeavesTheRecipeAsItWas() async throws {
    let recipe = recipe(lines: ["a walk in the park"])
    let (ai, _, _) = service([.status(200, answer(emptyJSON))])
    await RecipeMacroEstimates.divine(recipe, in: context, using: ai)
    #expect(recipe.macros == .none)
    #expect(recipe.macrosSource == nil)
    #expect(!recipe.macrosPending)
    #expect(try jobs().isEmpty)
  }

  @Test func aRecipeWithNoIngredientsCantBeDivined() async throws {
    let empty = recipe("Nothing", lines: [])
    let banished = recipe("Gone")
    banished.deletedAt = .now
    let (ai, transport, _) = service([goodAnswer])
    for recipe in [empty, banished] {
      #expect(!RecipeMacroEstimates.canDivine(recipe))
      #expect(RecipeMacroEstimates.state(of: recipe) == .hidden)
      await RecipeMacroEstimates.divine(recipe, in: context, using: ai)
      #expect(!recipe.macrosPending)
    }
    #expect(try jobs().isEmpty)
    #expect(transport.requests.isEmpty)
  }

  @Test func aFailedEstimateIsShownAndAskingAgainStartsAFreshOne() async throws {
    let recipe = recipe()
    let (ai, _, _) = service([badAnswer, badAnswer, badAnswer, goodAnswer])
    await RecipeMacroEstimates.divine(recipe, in: context, using: ai)
    await AIJobQueue.drain(in: context, using: ai.estimator)
    await AIJobQueue.drain(in: context, using: ai.estimator)
    #expect(try jobs().map(\.status) == [.failed])
    #expect(!recipe.macrosPending)
    #expect(RecipeMacroEstimates.state(of: recipe) == .failed)

    await RecipeMacroEstimates.divine(recipe, in: context, using: ai)
    #expect(recipe.macros == estimate)
    #expect(recipe.macrosSource == .estimated)
    // The failed job was replaced, not left beside the new one.
    #expect(try jobs().isEmpty)
  }

  @Test func askingAgainAfterAFailureDoesNotPileUpFailedRows() async throws {
    let recipe = recipe()
    AIJobQueue.enqueueMacros(for: recipe, in: context)
    try #require(try jobs().first).status = .failed
    recipe.macrosPending = false
    AIJobQueue.enqueueMacros(for: recipe, in: context)
    try context.save()
    let all = try jobs()
    #expect(all.count == 1 && all[0].status == .waiting && all[0].attempts == 0)
    #expect(recipe.macrosPending)
  }

  // MARK: Imports

  @Test func anImportedRecipeWithoutMacrosIsQueued() async throws {
    let recipe = recipe()
    #expect(RecipeMacroEstimates.requestIfMissing(for: recipe, in: context))
    #expect(recipe.macrosPending)
    #expect(try jobs().count == 1)
    // Asking twice queues once.
    #expect(!RecipeMacroEstimates.requestIfMissing(for: recipe, in: context))
    #expect(try jobs().count == 1)
  }

  @Test func requestIfMissingDoesNothingWhenThereIsNothingToDo() throws {
    let withMacros = recipe("Has macros")
    withMacros.macros = Macros(calories: 400)
    withMacros.macrosSource = .page
    let noIngredients = recipe("Bare", lines: [])
    let banished = recipe("Gone")
    banished.deletedAt = .now
    for recipe in [withMacros, noIngredients, banished] {
      #expect(!RecipeMacroEstimates.requestIfMissing(for: recipe, in: context))
      #expect(!recipe.macrosPending)
    }
    #expect(try jobs().isEmpty)
  }

  @Test func theImportEntryPointCanRunTheQueueToo() async throws {
    let recipe = recipe()
    let (ai, _, _) = service([goodAnswer])
    #expect(await RecipeMacroEstimates.requestIfMissing(for: recipe, in: context, using: ai))
    #expect(recipe.macros == estimate && recipe.macrosSource == .estimated)
  }

  @Test func anImportWaitsForGeminiToo() async throws {
    let recipe = recipe()
    let (ai, _, _) = service([.offline, goodAnswer])
    #expect(await RecipeMacroEstimates.requestIfMissing(for: recipe, in: context, using: ai))
    #expect(recipe.macrosPending && recipe.macros == .none)
    await AIJobQueue.drain(in: context, using: ai.estimator)
    #expect(recipe.macros == estimate)
  }

  // MARK: The editor

  private func draft(lines: [String]) -> RecipeDraft {
    var draft = RecipeDraft()
    draft.title = "Shakshuka"
    draft.servings = "4"
    draft.ingredients = lines.map { .line($0) }
    return draft
  }

  @Test func theEditorEstimatesFromTheIngredientsAsEditedAndSavesThemAsAnEstimate() async throws {
    let saved = recipe(lines: ["6 large eggs"])
    var draft = RecipeDraft(saved)
    draft.ingredients = [.line("2 cups lentils"), .heading("Sauce"), .line("1 can tomatoes")]
    let (ai, transport, _) = service([goodAnswer])

    let outcome = await RecipeMacroEstimates.divine(draft.estimateInput, using: ai)
    draft.apply(outcome)
    #expect(outcome == .filled(estimate))
    let sent = body(transport.requests.last)
    #expect(sent.contains("- 2 cups lentils\\n- 1 can tomatoes"))
    #expect(!sent.contains("6 large eggs") && !sent.contains("Sauce"))
    #expect(draft.calories == "310" && draft.protein == "17")
    // Nothing is stored until Save.
    #expect(saved.macros == .none && !saved.macrosPending)
    #expect(try jobs().isEmpty)

    try RecipeSaver.save(draft, into: saved, context: context)
    #expect(saved.macros == estimate)
    #expect(saved.macrosSource == .estimated)
    #expect(try jobs().isEmpty)
  }

  @Test func changingAnEstimatedNumberByHandMakesTheNumbersManual() async throws {
    var draft = draft(lines: ["6 large eggs"])
    let (ai, _, _) = service([goodAnswer])
    draft.apply(await RecipeMacroEstimates.divine(draft.estimateInput, using: ai))
    draft.protein = "25"
    let saved = try RecipeSaver.save(draft, into: nil, context: context)
    #expect(saved.macros.protein == 25)
    #expect(saved.macrosSource == .manual)
  }

  @Test func closingTheEditorWithoutSavingLeavesNothingBehind() async throws {
    let saved = recipe()
    var draft = RecipeDraft(saved)
    let (offline, _, _) = service([.offline])
    draft.apply(await RecipeMacroEstimates.divine(draft.estimateInput, using: offline))
    #expect(draft.estimateOnSave)
    // The draft is dropped: no job, no pending flag, no macros.
    #expect(try jobs().isEmpty)
    #expect(!saved.macrosPending && saved.macros == .none)
  }

  @Test func withGeminiOutOfReachSavingQueuesTheEstimateForTheSavedIngredients() async throws {
    var draft = draft(lines: ["3 eggs", "1 tbsp butter"])
    let (ai, transport, _) = service([.offline, goodAnswer])
    let outcome = await RecipeMacroEstimates.divine(draft.estimateInput, using: ai)
    draft.apply(outcome)
    #expect(outcome == .queued)

    let saved = try RecipeSaver.save(draft, into: nil, context: context)
    #expect(try jobs().isEmpty)
    #expect(RecipeMacroEstimates.queueAfterSave(of: draft, saved: saved, in: context))
    #expect(saved.macrosPending && saved.macros == .none)
    #expect(try jobs().count == 1)

    await AIJobQueue.drain(in: context, using: ai.estimator)
    #expect(saved.macros == estimate && saved.macrosSource == .estimated)
    #expect(body(transport.requests.last).contains("- 3 eggs\\n- 1 tbsp butter"))
  }

  @Test func numbersTypedAfterAQueuedAskStandInForTheEstimate() async throws {
    var draft = draft(lines: ["3 eggs"])
    let (ai, _, _) = service([.offline])
    draft.apply(await RecipeMacroEstimates.divine(draft.estimateInput, using: ai))
    draft.calories = "400"
    let saved = try RecipeSaver.save(draft, into: nil, context: context)
    #expect(!RecipeMacroEstimates.queueAfterSave(of: draft, saved: saved, in: context))
    #expect(!saved.macrosPending)
    #expect(saved.macrosSource == .manual)
    #expect(try jobs().isEmpty)
  }

  @Test func theEditorNeedsAnIngredientToEstimateFrom() async throws {
    var draft = draft(lines: [])
    draft.ingredients = [.heading("Sauce"), .line("   ")]
    #expect(draft.estimateInput == nil)
    let (ai, transport, _) = service([goodAnswer])
    #expect(await RecipeMacroEstimates.divine(draft.estimateInput, using: ai) == .needsIngredients)
    #expect(transport.requests.isEmpty)
  }

  @Test func aBadAnswerOrAnEmptyOneLeavesTheDraftAsItWas() async throws {
    var draft = draft(lines: ["3 eggs"])
    draft.calories = "123"
    let before = draft
    let (ai, _, _) = service([badAnswer, .status(200, answer(emptyJSON))])
    for _ in 0..<2 {
      let outcome = await RecipeMacroEstimates.divine(draft.estimateInput, using: ai)
      #expect(outcome == .failed)
      draft.apply(outcome)
    }
    #expect(draft == before)
  }
}

@MainActor
@Suite("Divine views")
struct DivineViewsTests {
  private func render(_ recipe: RecipeRecord, _ ai: RecipeAIService, container: ModelContainer)
    -> Bool
  {
    for scheme in [ColorScheme.light, .dark] {
      let view = RecipeDetailView(recipe: recipe) {}
        .environment(ai)
        .modelContainer(container)
        .environment(\.colorScheme, scheme)
        .frame(width: 390, height: 900)
      guard ImageRenderer(content: view).cgImage != nil else { return false }
    }
    return true
  }

  private func recipe(in container: ModelContainer) -> RecipeRecord {
    let recipe = RecipeRecord(title: "Shakshuka")
    recipe.ingredients = [
      Ingredient(
        section: nil, quantity: nil, unit: nil, item: "eggs", note: nil, optional: false,
        alt: nil, original: "6 large eggs", itemKey: "egg")
    ]
    container.mainContext.insert(recipe)
    return recipe
  }

  @Test func theDetailRendersIdleWaitingEstimatedAndNeedingAttention() throws {
    let container = try CauldronStore.container(.inMemory)
    let ready = RecipeAIService.offline(key: "abc")
    let noKey = RecipeAIService.offline()

    let idle = recipe(in: container)
    #expect(RecipeMacroEstimates.state(of: idle) == .idle)
    #expect(render(idle, ready, container: container))
    #expect(render(idle, noKey, container: container))

    let waiting = recipe(in: container)
    AIJobQueue.enqueueMacros(for: waiting, in: container.mainContext)
    #expect(RecipeMacroEstimates.state(of: waiting) == .waiting)
    #expect(render(waiting, ready, container: container))
    #expect(render(waiting, noKey, container: container))

    let estimated = recipe(in: container)
    estimated.macros = Macros(calories: 310, protein: 17, carbs: 18, fat: 19)
    estimated.macrosSource = .estimated
    #expect(RecipeMacroEstimates.state(of: estimated) == .hidden)
    #expect(render(estimated, ready, container: container))

    let failed = recipe(in: container)
    AIJobQueue.enqueueMacros(for: failed, in: container.mainContext)
    failed.aiJobs?.first?.status = .failed
    failed.macrosPending = false
    #expect(RecipeMacroEstimates.state(of: failed) == .failed)
    #expect(render(failed, noKey, container: container))
  }

  @Test func theDetailRendersWithoutAnAIService() throws {
    let container = try CauldronStore.container(.inMemory)
    let view = RecipeDetailView(recipe: recipe(in: container)) {}
      .modelContainer(container)
      .frame(width: 390, height: 900)
    #expect(ImageRenderer(content: view).cgImage != nil)
  }

  @Test func theEditorRendersItsDivineStatesInBothAppearances() throws {
    let container = try CauldronStore.container(.inMemory)
    var queued = RecipeDraft()
    queued.estimateOnSave = true
    var estimated = RecipeDraft()
    estimated.fill(withEstimate: Macros(calories: 310, protein: 17, carbs: 18, fat: 19))
    let cases: [(RecipeDraft, Bool, CopyString?)] = [
      (RecipeDraft(), false, nil), (RecipeDraft(), true, nil), (queued, false, nil),
      (estimated, false, nil), (RecipeDraft(), false, Copy.editor.divineFailed),
    ]
    for service in [RecipeAIService.offline(key: "abc"), .offline()] {
      for (draft, divining, message) in cases {
        for scheme in [ColorScheme.light, .dark] {
          let view = RecipeEditorForm(
            draft: .constant(draft), recipe: nil, errors: nil, couldntSave: false,
            divining: divining, divineMessage: message
          )
          .environment(service)
          .modelContainer(container)
          .environment(\.colorScheme, scheme)
          .frame(width: 390, height: 900)
          #expect(ImageRenderer(content: view).cgImage != nil)
        }
      }
    }
  }
}
