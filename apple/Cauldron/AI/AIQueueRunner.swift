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
}
