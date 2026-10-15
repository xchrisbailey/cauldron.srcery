import CauldronKit
import Foundation
import SwiftData

/// The estimates waiting for the AI. A job waits for as long as the AI can't be reached and
/// runs when it can; an estimate is never guessed. Only a bad answer uses up attempts.
///
/// Jobs sync, so the same one can run on two devices. Everything a job writes is therefore
/// something that reads the same however often it is written: a recipe's macros, or one diary
/// entry's. A job never inserts rows.
@MainActor
enum AIJobQueue {
  /// How long a job is kept while the recipe or entry it is for can't be found. Its record may
  /// still be on its way from another device.
  static let orphanGrace: TimeInterval = 7 * 24 * 60 * 60

  private static var draining = false
  private static var drainAgain = false

  /// Queues a macro estimate for `recipe`, unless one is already waiting. A job that gave up
  /// is replaced by the new one, so asking again after a failure doesn't pile up failed rows.
  static func enqueueMacros(for recipe: RecipeRecord, in context: ModelContext) {
    recipe.macrosPending = true
    let jobs = (recipe.aiJobs ?? []).filter { $0.kind == .recipeMacros }
    guard !jobs.contains(where: { $0.status != .failed }) else { return }
    for failed in jobs { context.delete(failed) }
    let job = AIJobRecord(kind: .recipeMacros)
    context.insert(job)
    job.recipe = recipe
  }

  /// Queues an estimate of the meal described in `text`, to fill in `entry`, unless one is
  /// already waiting.
  static func enqueueMeal(_ text: String, for entry: DiaryEntryRecord, in context: ModelContext) {
    entry.macrosPending = true
    let waiting = (entry.aiJobs ?? []).contains {
      $0.kind == .mealEstimate && $0.status != .failed
    }
    guard !waiting else { return }
    let job = AIJobRecord(kind: .mealEstimate, input: text)
    context.insert(job)
    job.diaryEntry = entry
  }

  /// How many estimates are waiting, for the line in Settings.
  static func waitingCount(in context: ModelContext) -> Int {
    (try? context.fetchCount(waitingJobs())) ?? 0
  }

  private static func waitingJobs() -> FetchDescriptor<AIJobRecord> {
    let failed = AIJobStatus.failed.rawValue
    return FetchDescriptor<AIJobRecord>(
      predicate: #Predicate { $0.statusRaw != failed }, sortBy: [SortDescriptor(\.createdAt)])
  }

  /// Runs every waiting job, oldest first. It stops at the first one the AI can't be reached
  /// for, since the rest would only fail the same way. Returns how many finished.
  ///
  /// Only one drain runs at a time. A call that arrives while one is running asks it to go
  /// round again when it finishes, and returns at once.
  @discardableResult
  static func drain(
    in context: ModelContext, using ai: any RecipeAI, now: Date = .now
  ) async -> Int {
    guard !draining else {
      drainAgain = true
      return 0
    }
    draining = true
    defer { draining = false }
    var finished = 0
    repeat {
      drainAgain = false
      finished += await pass(in: context, using: ai, now: now)
    } while drainAgain
    return finished
  }

  private static func pass(in context: ModelContext, using ai: any RecipeAI, now: Date) async -> Int
  {
    requeueOrphans(in: context)
    guard let jobs = try? context.fetch(waitingJobs()) else { return 0 }
    var finished = 0
    for job in jobs {
      // A job left `running` was cut off by the app closing, and runs again.
      job.status = .running
      do {
        if try await run(job, in: context, using: ai, now: now) { finished += 1 }
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

  /// Something marked as waiting with no job behind it would wait for ever. That happens when
  /// a removed entry is put back, or a job was deleted on another device. It gets a new job.
  private static func requeueOrphans(in context: ModelContext) {
    let recipes =
      (try? context.fetch(FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.macrosPending })))
      ?? []
    for recipe in recipes where (recipe.aiJobs ?? []).isEmpty {
      enqueueMacros(for: recipe, in: context)
    }
    let entries =
      (try? context.fetch(
        FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.macrosPending })))
      ?? []
    // A described entry is named with what the cook wrote until it is estimated.
    for entry in entries where (entry.aiJobs ?? []).isEmpty {
      enqueueMeal(entry.name, for: entry, in: context)
    }
  }

  /// Runs one job and writes its result. False when the job could only be left to wait.
  private static func run(
    _ job: AIJobRecord, in context: ModelContext, using ai: any RecipeAI, now: Date
  ) async throws(RecipeAIError) -> Bool {
    switch job.kind {
    case .recipeMacros:
      guard let recipe = job.recipe else {
        dropIfLongOrphaned(job, in: context, now: now)
        return false
      }
      // Held to the limits the web editor holds an ask to, so a long recipe isn't refused.
      let input = MacroEstimateInput.limited(
        title: recipe.title, servings: recipe.servings,
        lines: recipe.ingredients.map(\.original))
      guard !recipe.isBanished, let input else {
        recipe.macrosPending = false
        context.delete(job)
        return true
      }
      let macros = try await ai.estimateMacros(input)
      // The cook may have typed their own while this waited. Theirs stand. An estimate with
      // nothing in it (the lines weren't food) leaves the recipe as it was.
      let typedIn = recipe.macrosSource == .manual && recipe.macros != .none
      if !typedIn, macros != .none {
        recipe.macros = macros
        recipe.macrosSource = .estimated
      }
      recipe.macrosPending = false
      context.delete(job)
      return true
    case .mealEstimate:
      guard let entry = job.diaryEntry else {
        dropIfLongOrphaned(job, in: context, now: now)
        return false
      }
      // Nothing is waiting any more (the cook typed the numbers in), so there is nothing to ask.
      guard entry.macrosPending, let text = job.input, !text.isEmpty else {
        entry.macrosPending = false
        context.delete(job)
        return true
      }
      let items = try await ai.estimateMeal(text)
      // Another drain, here or on another device, may have filled it while this one asked.
      if entry.macrosPending { entry.macros = total(of: items) }
      entry.macrosPending = false
      context.delete(job)
      return true
    }
  }

  /// A job whose recipe or entry can't be found is left to wait: over sync the job can arrive
  /// before what it is for. After a week it is taken to be gone for good.
  private static func dropIfLongOrphaned(_ job: AIJobRecord, in context: ModelContext, now: Date) {
    job.status = .waiting
    if now.timeIntervalSince(job.createdAt) > orphanGrace { context.delete(job) }
  }

  /// The meal's numbers: its foods added up. A number none of the foods has stays unknown.
  /// The entry keeps the cook's own words as its name.
  static func total(of items: [DescribedItem]) -> Macros {
    func sum(_ key: MacroKey) -> Double? {
      let values = items.compactMap { $0.macros[key] }
      return values.isEmpty ? nil : values.reduce(0, +)
    }
    return Macros(
      calories: sum(.calories), protein: sum(.protein), carbs: sum(.carbs), fat: sum(.fat))
  }
}
