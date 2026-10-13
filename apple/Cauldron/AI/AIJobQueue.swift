import CauldronKit
import Foundation
import SwiftData

/// The estimates waiting for Gemini. A job waits for as long as Gemini can't be reached and
/// runs when it can; an estimate is never guessed. Only a bad answer uses up attempts.
@MainActor
enum AIJobQueue {
  /// Queues a macro estimate for `recipe`, unless one is already waiting.
  static func enqueueMacros(for recipe: RecipeRecord, in context: ModelContext) {
    recipe.macrosPending = true
    let waiting = (recipe.aiJobs ?? []).contains {
      $0.kind == .recipeMacros && $0.status != .failed
    }
    guard !waiting else { return }
    let job = AIJobRecord(kind: .recipeMacros)
    context.insert(job)
    job.recipe = recipe
  }

  /// Queues an estimate of the meal described in `text`, to fill in `entry`.
  static func enqueueMeal(_ text: String, for entry: DiaryEntryRecord, in context: ModelContext) {
    entry.macrosPending = true
    let job = AIJobRecord(kind: .mealEstimate, input: text)
    context.insert(job)
    job.diaryEntry = entry
  }

  /// How many estimates are waiting, for the line in Settings.
  static func waitingCount(in context: ModelContext) -> Int {
    let failed = AIJobStatus.failed.rawValue
    let waiting = FetchDescriptor<AIJobRecord>(predicate: #Predicate { $0.statusRaw != failed })
    return (try? context.fetchCount(waiting)) ?? 0
  }

  /// Runs every waiting job, oldest first. It stops at the first one Gemini can't be reached
  /// for, since the rest would only fail the same way. Returns how many finished.
  @discardableResult
  static func drain(in context: ModelContext, using ai: any RecipeAI) async -> Int {
    let failed = AIJobStatus.failed.rawValue
    let descriptor = FetchDescriptor<AIJobRecord>(
      predicate: #Predicate { $0.statusRaw != failed }, sortBy: [SortDescriptor(\.createdAt)])
    guard let jobs = try? context.fetch(descriptor) else { return 0 }
    var finished = 0
    for job in jobs {
      // A job left `running` was cut off by the app closing, and runs again.
      job.status = .running
      do {
        try await run(job, in: context, using: ai)
        finished += 1
      } catch {
        switch AIJobRules.decide(after: error, attempts: job.attempts) {
        case .wait:
          job.status = .waiting
          try? context.save()
          return finished
        case .retry:
          job.attempts += 1
          job.status = .waiting
          job.lastError = String(describing: error)
        case .fail:
          job.attempts += 1
          job.status = .failed
          job.lastError = String(describing: error)
          // Nothing is waiting any more, so what it was for stops saying so.
          job.recipe?.macrosPending = false
          job.diaryEntry?.macrosPending = false
        }
      }
    }
    try? context.save()
    return finished
  }

  /// Runs one job and writes its result. A job whose recipe or entry has gone is dropped.
  private static func run(
    _ job: AIJobRecord, in context: ModelContext, using ai: any RecipeAI
  ) async throws(RecipeAIError) {
    switch job.kind {
    case .recipeMacros:
      guard let recipe = job.recipe, !recipe.isBanished else {
        job.recipe?.macrosPending = false
        context.delete(job)
        return
      }
      let lines = recipe.ingredients.map(\.original).filter { !$0.isEmpty }
      guard !lines.isEmpty else {
        recipe.macrosPending = false
        context.delete(job)
        return
      }
      let macros = try await ai.estimateMacros(
        MacroEstimateInput(title: recipe.title, servings: recipe.servings, ingredients: lines))
      // The cook may have typed their own while this waited. Theirs stand. An estimate with
      // nothing in it (the lines weren't food) leaves the recipe as it was.
      let typedIn = recipe.macrosSource == .manual && recipe.macros != .none
      if !typedIn, macros != .none {
        recipe.macros = macros
        recipe.macrosSource = .estimated
      }
      recipe.macrosPending = false
      context.delete(job)
    case .mealEstimate:
      guard let entry = job.diaryEntry, let text = job.input, !text.isEmpty else {
        job.diaryEntry?.macrosPending = false
        context.delete(job)
        return
      }
      let items = try await ai.estimateMeal(text)
      fill(entry, with: items, in: context)
      context.delete(job)
    }
  }

  /// The waiting entry becomes the first food; any others follow it in the same meal.
  private static func fill(
    _ entry: DiaryEntryRecord, with items: [DescribedItem], in context: ModelContext
  ) {
    entry.macrosPending = false
    guard let first = items.first else { return }
    entry.name = first.name
    entry.amount = first.amount
    entry.macros = first.macros
    guard let day = entry.day else { return }
    for (offset, item) in items.dropFirst().enumerated() {
      let extra = DiaryEntryRecord(day: day, slot: entry.slot, name: item.name, source: .described)
      extra.amount = item.amount
      extra.macros = item.macros
      extra.position = entry.position + offset + 1
      context.insert(extra)
    }
  }
}
