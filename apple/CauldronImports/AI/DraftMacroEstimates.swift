import CauldronKit
import Foundation

/// Divining a recipe's macros from its ingredients. This half is for a draft: asking straight
/// through the AI and putting the answer in the draft. The half for saved recipes, which goes
/// through `AIJobQueue`, is in the app. Neither ever fills an estimate from the on-device model:
/// `RecipeAIService.estimator` is the cloud provider alone.
@MainActor
public enum RecipeMacroEstimates {
  /// What asking from the editor came to.
  public enum DraftOutcome: Equatable, Sendable {
    /// The numbers to put in the draft's fields, to be checked before saving.
    case filled(Macros)
    /// The draft has no ingredient lines.
    case needsIngredients
    /// The AI can't be reached. Save queues the estimate for the saved recipe.
    case queued
    /// The AI answered with nothing usable.
    case failed
    /// Asked to stop before an answer came; nothing changes.
    case cancelled
  }

  /// Estimates from `input`, the draft's ingredients as currently typed rather than the saved
  /// ones, straight through the AI and not the queue. The caller puts the answer in its draft
  /// (`RecipeDraft.apply`). Nothing is written to the store, so closing the editor without
  /// saving leaves no job or pending flag behind.
  public static func divine(_ input: MacroEstimateInput?, using ai: RecipeAIService) async
    -> DraftOutcome
  {
    await divine(input, using: ai.estimator)
  }

  /// `divine(_:using:)` for any estimator. With a `limit`, an answer that hasn't come by then
  /// counts as the AI being out of reach: the estimate is left for after Save, as for an import
  /// (`MACRO_TIMEOUT` in the reference).
  public static func divine(
    _ input: MacroEstimateInput?, using estimator: any RecipeAI, within limit: Duration? = nil
  ) async -> DraftOutcome {
    guard let input else { return .needsIngredients }
    do {
      let macros = try await ask(estimator, input, within: limit)
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

extension RecipeMacroEstimates {
  /// One estimate, given up on as unreachable if it takes longer than `limit`.
  fileprivate static func ask(
    _ estimator: any RecipeAI, _ input: MacroEstimateInput, within limit: Duration?
  ) async throws(RecipeAIError) -> Macros {
    guard let limit else { return try await estimator.estimateMacros(input) }
    let result = await withTaskGroup(of: Result<Macros, RecipeAIError>.self) { group in
      group.addTask {
        do throws(RecipeAIError) {
          return .success(try await estimator.estimateMacros(input))
        } catch {
          return .failure(error)
        }
      }
      group.addTask {
        do {
          try await Task.sleep(for: limit)
          return .failure(.unreachable)
        } catch {
          return .failure(.cancelled)
        }
      }
      let first = await group.next()
      group.cancelAll()
      return first ?? .failure(.cancelled)
    }
    return try result.get()
  }
}

extension RecipeDraft {
  /// Takes what an estimate came to: the numbers go into the fields, or Save is told to queue
  /// the estimate. Anything else leaves the draft as it was.
  public mutating func apply(_ outcome: RecipeMacroEstimates.DraftOutcome) {
    switch outcome {
    case .filled(let macros): fill(withEstimate: macros)
    case .queued: estimateOnSave = true
    case .needsIngredients, .failed, .cancelled: break
    }
  }
}
