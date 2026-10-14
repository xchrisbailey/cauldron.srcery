import CauldronKit
import Foundation
import SwiftData

/// Where the app starts the queue. It runs `AIJobQueue` and, when that finished a job, tells
/// Health what a diary change tells it: a described meal that has just got its numbers needs
/// its nutrition sent, and the queue itself knows nothing of Health. Does nothing more than
/// `AIJobQueue.drain` until Health is connected.
@MainActor
enum AIQueueRunner {
  @discardableResult
  static func drain(
    in context: ModelContext, using ai: any RecipeAI, health: HealthSync = .shared
  ) async -> Int {
    let finished = await AIJobQueue.drain(in: context, using: ai)
    if finished > 0 { health.diaryChanged(saved: [], removed: [], in: context) }
    return finished
  }

  /// Switches the AI to `provider` at once, then runs the queue: estimates that waited on the
  /// last provider's key or quota may be able to run on this one. Returns the drain, for a
  /// caller that wants to wait for it.
  @discardableResult
  static func switchProvider(
    to provider: AIProvider, in context: ModelContext, ai: RecipeAIService,
    health: HealthSync = .shared
  ) -> Task<Int, Never> {
    ai.select(provider)
    let estimator = ai.estimator
    return Task { await drain(in: context, using: estimator, health: health) }
  }
}
