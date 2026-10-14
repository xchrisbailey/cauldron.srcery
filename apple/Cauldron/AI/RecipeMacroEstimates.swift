import CauldronKit
import Foundation
import SwiftData

/// Divining a recipe's macros from its ingredients: when it can be asked for, asking, and what
/// each screen shows meanwhile. Estimates for saved recipes go through `AIJobQueue`, so the
/// button, an import and a late answer all take one path. They are never filled from the
/// on-device model: `RecipeAIService.estimator` is Gemini alone.
@MainActor
enum RecipeMacroEstimates {
  /// What a recipe's page shows of the estimate.
  enum State: Equatable {
    /// Nothing to offer: it is banished, has no ingredients, has its macros, or the cook's own
    /// numbers would be kept over an estimate.
    case hidden
    /// Can be asked for now.
    case idle
    /// Asked for and not answered yet (Gemini out of reach, or the answer on its way).
    case waiting
    /// The last try gave up after bad answers. Asking again starts a fresh one.
    case failed
  }

  /// Whether `recipe` has an ingredient to estimate from and isn't banished.
  nonisolated static func canDivine(_ recipe: RecipeRecord) -> Bool {
    !recipe.isBanished && recipe.ingredients.contains { !$0.original.isEmpty }
  }

  static func state(of recipe: RecipeRecord) -> State {
    if recipe.macrosPending { return .waiting }
    guard canDivine(recipe), hasGaps(recipe.macros) else { return .hidden }
    // The queue keeps numbers the cook typed in, so an estimate would be thrown away.
    if recipe.macrosSource == .manual && recipe.macros != .none { return .hidden }
    let gaveUp = (recipe.aiJobs ?? []).contains { $0.kind == .recipeMacros && $0.status == .failed }
    return gaveUp ? .failed : .idle
  }

  // MARK: Saved recipes

  /// The button: queues an estimate and runs the queue straight away, so the same path serves
  /// whether Gemini answers now or the estimate waits. The cook is looking at the button, so a
  /// bad answer to this ask is shown as a failure at once instead of waiting for the queue's
  /// next attempts (which jobs queued by an import or a save still get).
  static func divine(
    _ recipe: RecipeRecord, in context: ModelContext, using ai: RecipeAIService
  ) async {
    guard canDivine(recipe) else { return }
    AIJobQueue.enqueueMacros(for: recipe, in: context)
    try? context.save()
    await AIQueueRunner.drain(in: context, using: ai.estimator)
    giveUpOnBadAnswer(for: recipe, in: context)
  }

  /// A job left waiting after a bad answer (it has used an attempt and kept the error) is
  /// marked failed, and the recipe stops showing as waiting. One left waiting because Gemini
  /// is out of reach has used no attempt, and keeps waiting.
  private static func giveUpOnBadAnswer(for recipe: RecipeRecord, in context: ModelContext) {
    let bad = (recipe.aiJobs ?? []).filter {
      $0.kind == .recipeMacros && $0.status == .waiting && $0.attempts > 0 && $0.lastError != nil
    }
    guard !bad.isEmpty else { return }
    for job in bad { job.status = .failed }
    recipe.macrosPending = false
    try? context.save()
  }

  /// The entry point for imports: queues an estimate for a saved recipe that has no macros and
  /// at least one ingredient, and does nothing otherwise (including when one is waiting
  /// already). Returns whether it queued one. It doesn't run the queue: the app does when it
  /// comes forward, when the network returns and when a key is saved; the async overload
  /// below also asks at once.
  @discardableResult
  static func requestIfMissing(for recipe: RecipeRecord, in context: ModelContext) -> Bool {
    guard isMissingMacros(recipe) else { return false }
    AIJobQueue.enqueueMacros(for: recipe, in: context)
    try? context.save()
    return true
  }

  /// Whether "estimate missing macros" in Settings would queue `recipe`: the same test as an
  /// import's, so a recipe with numbers, with none to read, banished or already waiting is left.
  static func isMissingMacros(_ recipe: RecipeRecord) -> Bool {
    recipe.macros == .none && canDivine(recipe) && !recipe.macrosPending
  }

  /// Queues an estimate for every recipe `isMissingMacros` picks, and returns how many. The
  /// caller runs the queue.
  @discardableResult
  static func requestAllMissing(in context: ModelContext) -> Int {
    let recipes = (try? context.fetch(FetchDescriptor<RecipeRecord>())) ?? []
    var queued = 0
    for recipe in recipes where isMissingMacros(recipe) {
      AIJobQueue.enqueueMacros(for: recipe, in: context)
      queued += 1
    }
    if queued > 0 { try? context.save() }
    return queued
  }

  /// After the editor saved `recipe` from `draft`: queues the estimate Gemini couldn't give
  /// while the cook was editing, using the ingredients as saved. An imported recipe whose page
  /// gave no nutrition is queued the same way (the pipeline leaves the estimate to the app).
  /// Numbers typed or read from the page stand in for it. Returns whether one was queued, in
  /// which case the caller runs the queue.
  @discardableResult
  static func queueAfterSave(
    of draft: RecipeDraft, saved recipe: RecipeRecord, in context: ModelContext
  ) -> Bool {
    (draft.estimateOnSave || draft.imported != nil) && requestIfMissing(for: recipe, in: context)
  }

  /// `requestIfMissing(for:in:)`, then runs the queue so the numbers appear as soon as Gemini
  /// answers.
  @discardableResult
  static func requestIfMissing(
    for recipe: RecipeRecord, in context: ModelContext, using ai: RecipeAIService
  ) async -> Bool {
    guard requestIfMissing(for: recipe, in: context) else { return false }
    await AIQueueRunner.drain(in: context, using: ai.estimator)
    return true
  }

  // MARK: The editor

  /// What asking from the editor came to.
  enum DraftOutcome: Equatable {
    /// The numbers to put in the draft's fields, to be checked before saving.
    case filled(Macros)
    /// The draft has no ingredient lines.
    case needsIngredients
    /// Gemini can't be reached. Save queues the estimate for the saved recipe.
    case queued
    /// Gemini answered with nothing usable.
    case failed
    /// Asked to stop before an answer came; nothing changes.
    case cancelled
  }

  /// Estimates from `input`, the draft's ingredients as currently typed rather than the saved
  /// ones, straight through Gemini and not the queue. The caller puts the answer in its draft
  /// (`RecipeDraft.apply`). Nothing is written to the store, so closing the editor without
  /// saving leaves no job or pending flag behind.
  static func divine(_ input: MacroEstimateInput?, using ai: RecipeAIService) async -> DraftOutcome
  {
    guard let input else { return .needsIngredients }
    do {
      let macros = try await ai.estimator.estimateMacros(input)
      // The lines weren't food: the draft stays as it was.
      return macros == .none ? .failed : .filled(macros)
    } catch {
      if error == .cancelled { return .cancelled }
      switch AIJobRules.decide(after: error, attempts: 0) {
      case .wait: return .queued
      case .retry, .fail: return .failed
      }
    }
  }
}

extension RecipeDraft {
  /// Takes what an estimate came to: the numbers go into the fields, or Save is told to queue
  /// the estimate. Anything else leaves the draft as it was.
  mutating func apply(_ outcome: RecipeMacroEstimates.DraftOutcome) {
    switch outcome {
    case .filled(let macros): fill(withEstimate: macros)
    case .queued: estimateOnSave = true
    case .needsIngredients, .failed, .cancelled: break
    }
  }
}
