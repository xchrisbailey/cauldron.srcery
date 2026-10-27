import CauldronKit
import Foundation
import SwiftData
import Synchronization

/// Writes search keywords for saved recipes, one recipe at a time, and never inside a save: a
/// save returns first, then `enqueue` runs the writer in a task of its own.
///
/// Keywords are current while the recipe's stored fingerprint equals the fingerprint of its
/// inputs, so a recipe saved without a change to them costs nothing, and keywords another
/// device wrote and synced are not written again. State is the stored fingerprint, so nothing
/// here needs to survive a relaunch.
///
/// A recipe is never written twice at once. `process` is also the seam for a scan of every
/// recipe that is missing keywords (#255): it takes one id, and reports `.unavailable` so the
/// scan can pause without spending an attempt on a recipe.
@MainActor
final class SearchKeywordRunner {
  /// How one recipe's turn came out.
  enum Result: Equatable {
    /// New keywords were stored.
    case written
    /// The stored fingerprint already matches; the writer wasn't asked.
    case upToDate
    /// The model can't run now. Nothing was stored and nothing counts against the recipe.
    case unavailable(SearchKeywordUnavailability)
    /// The model answered with nothing usable, or the store refused. Nothing was stored.
    case failed
    /// Another turn for the same recipe is running. It looks at the recipe again when it
    /// finishes, so this request is not lost.
    case busy
    /// The recipe is purged or banished.
    case gone
    /// The recipe holds ingredient lines this build can't read, so the fingerprint it computes
    /// would differ from the one a newer build computes. Nothing is written, and nothing counts
    /// against the recipe.
    case unreadable
  }

  /// How many times a turn goes round for a recipe that was edited while it was being written.
  private static let rounds = 3

  private let writer: any SearchKeywordWriting
  private let timeout: Duration
  private let save: (ModelContext) throws -> Void
  private var running: Set<UUID> = []
  private var jobs: [UUID: Task<Void, Never>] = [:]

  init(
    writer: any SearchKeywordWriting, timeout: Duration = .seconds(30),
    save: @escaping (ModelContext) throws -> Void = { try $0.save() }
  ) {
    self.writer = writer
    self.timeout = timeout
    self.save = save
  }

  /// Writes the recipe's keywords in the background. Call it after the save has returned. A
  /// recipe that already has a job waiting or running shares it. The task is returned for a
  /// caller that wants to wait.
  @discardableResult
  func enqueue(_ id: UUID, in context: ModelContext) -> Task<Void, Never> {
    if let job = jobs[id] { return job }
    let job = Task {
      _ = await process(id, in: context)
      jobs[id] = nil
    }
    jobs[id] = job
    return job
  }

  /// Returns when every job queued so far has finished.
  func settled() async {
    for job in Array(jobs.values) { await job.value }
  }

  /// Writes keywords for one recipe if its stored ones aren't current.
  func process(_ id: UUID, in context: ModelContext) async -> Result {
    guard running.insert(id).inserted else { return .busy }
    defer { running.remove(id) }
    for _ in 0..<Self.rounds {
      guard let recipe = Self.find(id, in: context), !recipe.isBanished else { return .gone }
      // A line this build can't read is left out of the inputs, so the fingerprint here would
      // differ from the one a build that can read it computes, and the two would keep writing
      // over each other.
      guard recipe.canRewriteIngredients else { return .unreadable }
      let inputs = recipe.searchKeywordInputs
      let fingerprint = inputs.fingerprint
      if recipe.searchKeywordsFingerprint == fingerprint { return .upToDate }
      let keywords: String
      switch await write(inputs) {
      case .unavailable(let reason): return .unavailable(reason)
      case .failed: return .failed
      case .written(let text): keywords = text
      }
      // An answer with no words is no answer: storing it would count the recipe as done.
      guard keywords.contains(where: \.isLetter) || keywords.contains(where: \.isNumber)
      else { return .failed }
      // The cook may have saved again while the model worked. Nothing suspends between this
      // look and the write, so what is stored is what was written for.
      guard let current = Self.find(id, in: context), !current.isBanished else { return .gone }
      guard current.canRewriteIngredients else { return .unreadable }
      guard current.searchKeywordInputs.fingerprint == fingerprint else { continue }
      let previous = (current.searchKeywords, current.searchKeywordsFingerprint)
      current.searchKeywords = keywords
      current.searchKeywordsFingerprint = fingerprint
      do {
        try save(context)
      } catch {
        // Put back only this recipe's two fields: the context is shared, and a rollback would
        // throw away what other screens have changed and not saved yet.
        (current.searchKeywords, current.searchKeywordsFingerprint) = previous
        return .failed
      }
      return .written
    }
    return .failed
  }

  /// Asks the writer, giving up with `.failed` after `timeout`. The answer of a writer that
  /// comes back late, or never, is dropped, so a stalled model can't hold a job for ever.
  private func write(_ inputs: SearchKeywordInputs) async -> SearchKeywordOutcome {
    let writer = writer
    let timeout = timeout
    return await withCheckedContinuation { continuation in
      let race = Race(continuation)
      let work = Task { race.finish(await writer.write(inputs)) }
      let timer = Task {
        try? await Task.sleep(for: timeout)
        race.finish(.failed)
      }
      race.attach([work, timer])
    }
  }

  /// Resumes with whichever outcome comes first, once, and cancels the other.
  private final class Race: Sendable {
    private struct State {
      var continuation: CheckedContinuation<SearchKeywordOutcome, Never>?
      var tasks: [Task<Void, Never>] = []
      var finished = false
    }

    private let state: Mutex<State>

    init(_ continuation: CheckedContinuation<SearchKeywordOutcome, Never>) {
      state = Mutex(State(continuation: continuation))
    }

    func attach(_ tasks: [Task<Void, Never>]) {
      let finished = state.withLock { state in
        state.tasks = tasks
        return state.finished
      }
      if finished { tasks.forEach { $0.cancel() } }
    }

    func finish(_ outcome: SearchKeywordOutcome) {
      let (continuation, tasks) = state.withLock { state in
        defer {
          state.continuation = nil
          state.finished = true
        }
        return (state.continuation, state.tasks)
      }
      guard let continuation else { return }
      tasks.forEach { $0.cancel() }
      continuation.resume(returning: outcome)
    }
  }

  private static func find(_ id: UUID, in context: ModelContext) -> RecipeRecord? {
    try? context.fetch(FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })).first
  }
}

extension RecipeRecord {
  /// What the keywords are written from.
  var searchKeywordInputs: SearchKeywordInputs {
    SearchKeywordInputs(
      title: title, ingredients: ingredients.map(\.item), tags: (tags ?? []).map(\.name),
      description: summary)
  }
}
