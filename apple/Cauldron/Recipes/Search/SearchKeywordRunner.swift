import CauldronKit
import Foundation
import Observation
import SwiftData
import Synchronization

/// Writes search keywords for saved recipes, one recipe at a time, and never inside a save: a
/// save returns first, then `enqueue` runs the writer in a task of its own. `drain` does the
/// same for every recipe that is missing keywords or has stale ones, such as those saved before
/// keywords existed.
///
/// Keywords are current while the recipe's stored fingerprint equals the fingerprint of its
/// inputs, so a recipe saved without a change to them costs nothing, and keywords another
/// device wrote and synced are not written again. State is the stored fingerprint, so a fresh
/// launch picks up exactly where the last one stopped. The only state kept here is in memory:
/// how many bad answers a recipe has had, and whether the model was unavailable last time.
///
/// It is on-device only and never waits on the network or a key.
///
/// A recipe is never written twice at once.
@Observable
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
    /// The attempt limit was reached. The current fingerprint is stored with no keywords, so the
    /// recipe counts as current and is asked for again only when its inputs change.
    case gaveUp
  }

  /// How many times a turn goes round for a recipe that was edited while it was being written.
  private static let rounds = 3

  /// The recipes that lack current keywords, the one being read included. Every recipe is
  /// looked at when `drain` starts (and when `refreshPending` is asked to); after that a recipe
  /// is added or taken off one at a time, as `drain` finishes it or a save job does. Empty until
  /// the first look.
  private var waiting: Set<UUID> = []
  /// How many recipes still lack current keywords.
  var pending: Int { waiting.count }
  /// How many times every recipe has been looked at to find the pending ones.
  @ObservationIgnored private(set) var scans = 0
  /// Why the model couldn't run the last time it was asked; nil once it has written something.
  /// While it is set the job is paused, and `drain` tries again the next time it is called.
  private(set) var unavailability: SearchKeywordUnavailability?

  /// The number for the library's "still reading" line: how many recipes are waiting, while
  /// the job can run. Nil when none are waiting, or when the model is unavailable.
  var stillReading: Int? { pending > 0 && unavailability == nil ? pending : nil }

  @ObservationIgnored private let writer: any SearchKeywordWriting
  @ObservationIgnored private let timeout: Duration
  @ObservationIgnored private let save: (ModelContext) throws -> Void
  @ObservationIgnored private var running: Set<UUID> = []
  @ObservationIgnored private var jobs: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var draining = false
  /// Bad answers so far for the inputs a recipe has now. Not stored: a relaunch starts again,
  /// and a recipe whose inputs change starts again.
  @ObservationIgnored private var attempts: [UUID: (fingerprint: String, count: Int)] = [:]

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
      // Only this recipe's part of the count changes, before and after its turn.
      settle(id, in: context)
      _ = await process(id, in: context)
      jobs[id] = nil
      settle(id, in: context)
    }
    jobs[id] = job
    return job
  }

  // MARK: The backfill

  /// The recipes that lack current keywords, newest first: not banished, readable by this
  /// build, and with no fingerprint or a different one from their inputs'.
  static func pendingIDs(in context: ModelContext) -> [UUID] {
    let recipes =
      (try? context.fetch(
        FetchDescriptor<RecipeRecord>(
          predicate: #Predicate { $0.deletedAt == nil },
          sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    return recipes.filter(isPending).map(\.id)
  }

  /// How many recipes still lack current keywords.
  static func pendingCount(in context: ModelContext) -> Int { pendingIDs(in: context).count }

  private static func isPending(_ recipe: RecipeRecord) -> Bool {
    guard !recipe.isBanished, let inputs = recipe.readableSearchKeywordInputs else { return false }
    return recipe.searchKeywordsFingerprint != inputs.fingerprint
  }

  private static func isPending(_ id: UUID, in context: ModelContext) -> Bool {
    find(id, in: context).map(isPending) ?? false
  }

  /// Puts the recipe on or off the waiting list as its stored fingerprint says.
  private func settle(_ id: UUID, in context: ModelContext) {
    if Self.isPending(id, in: context) {
      waiting.insert(id)
    } else {
      waiting.remove(id)
    }
  }

  /// Looks at every recipe for the ones that lack current keywords.
  private func scan(in context: ModelContext) -> [UUID] {
    scans += 1
    return Self.pendingIDs(in: context)
  }

  /// Counts the recipes that lack current keywords. The model's own word on whether it can run
  /// comes first, so the count never shows as "still reading" for a model that can't.
  func refreshPending(in context: ModelContext) {
    if let reason = writer.availability { unavailability = reason }
    waiting = Set(scan(in: context))
  }

  /// Writes keywords for every recipe that lacks current ones, one at a time, until none are
  /// left or the task is cancelled. Call it when the app comes forward.
  ///
  /// It asks the model whether it can run before it reads a recipe, and if it can't it stops
  /// at once with everything as it was: no attempt is spent, and the next call tries again. A
  /// bad answer spends an attempt, and the recipe goes to the back of the line; after
  /// `AIJobRules.maxAttempts` it is given up on. A call that arrives while one is running
  /// returns at once.
  func drain(in context: ModelContext) async {
    guard !draining else { return }
    draining = true
    defer { draining = false }
    var line = scan(in: context)
    waiting = Set(line)
    unavailability = writer.availability
    guard unavailability == nil else { return }
    while !line.isEmpty, !Task.isCancelled {
      let id = line.removeFirst()
      switch await process(id, in: context) {
      case .unavailable:
        return
      case .failed:
        line.append(id)
      case .written, .upToDate, .gone, .unreadable, .gaveUp:
        waiting.remove(id)
      case .busy:
        // Another job has the recipe and takes it off the list when it finishes.
        break
      }
    }
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
      guard let inputs = recipe.readableSearchKeywordInputs else { return .unreadable }
      let fingerprint = inputs.fingerprint
      if recipe.searchKeywordsFingerprint == fingerprint { return .upToDate }
      // Ask the model about itself first: a model that can't run is not given the recipe.
      if let reason = writer.availability {
        unavailability = reason
        return .unavailable(reason)
      }
      let keywords: String
      switch await write(inputs) {
      case .unavailable(let reason):
        unavailability = reason
        return .unavailable(reason)
      case .failed:
        return failed(id, fingerprint, in: context)
      case .written(let text):
        keywords = text
      }
      // An answer with no words is no answer: storing it would count the recipe as done.
      guard keywords.contains(where: \.isLetter) || keywords.contains(where: \.isNumber)
      else { return failed(id, fingerprint, in: context) }
      // The cook may have saved again while the model worked. Nothing suspends between this
      // look and the write, so what is stored is what was written for.
      guard let current = Self.find(id, in: context), !current.isBanished else { return .gone }
      guard let now = current.readableSearchKeywordInputs else { return .unreadable }
      guard now.fingerprint == fingerprint else { continue }
      guard store(keywords, fingerprint, in: current, context: context) else {
        return failed(id, fingerprint, in: context)
      }
      unavailability = nil
      attempts[id] = nil
      return .written
    }
    return .failed
  }

  /// Counts a bad answer against the recipe's current inputs. At the limit the current
  /// fingerprint is stored with no keywords, so the recipe counts as done until it is edited.
  private func failed(_ id: UUID, _ fingerprint: String, in context: ModelContext) -> Result {
    let before = attempts[id]?.fingerprint == fingerprint ? (attempts[id]?.count ?? 0) : 0
    let count = before + 1
    guard count >= AIJobRules.maxAttempts else {
      attempts[id] = (fingerprint, count)
      return .failed
    }
    attempts[id] = nil
    guard let recipe = Self.find(id, in: context), !recipe.isBanished,
      store(nil, fingerprint, in: recipe, context: context)
    else { return .failed }
    return .gaveUp
  }

  /// Stores the keywords and the fingerprint they were written from. If the store refuses, only
  /// this recipe's two fields are put back: the context is shared, and a rollback would throw
  /// away what other screens have changed and not saved yet.
  private func store(
    _ keywords: String?, _ fingerprint: String, in recipe: RecipeRecord, context: ModelContext
  ) -> Bool {
    let previous = (recipe.searchKeywords, recipe.searchKeywordsFingerprint)
    recipe.searchKeywords = keywords
    recipe.searchKeywordsFingerprint = fingerprint
    do {
      try save(context)
      return true
    } catch {
      (recipe.searchKeywords, recipe.searchKeywordsFingerprint) = previous
      return false
    }
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
  /// What the keywords are written from, or nil when a line of the ingredients is one this
  /// build can't read.
  var readableSearchKeywordInputs: SearchKeywordInputs? {
    let lines = StoredJSON.decodeList(Ingredient.self, from: ingredientsData)
    guard lines.complete else { return nil }
    return SearchKeywordInputs(
      title: title, ingredients: lines.values.map(\.item), tags: (tags ?? []).map(\.name),
      description: summary)
  }

  /// What the keywords are written from.
  var searchKeywordInputs: SearchKeywordInputs {
    SearchKeywordInputs(
      title: title, ingredients: ingredients.map(\.item), tags: (tags ?? []).map(\.name),
      description: summary)
  }
}
