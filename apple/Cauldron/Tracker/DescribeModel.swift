import CauldronKit
import Foundation
import Observation
import SwiftData

/// What "Describe it" does, without any view (#179): the typed meal, the ask, the review of the
/// foods it found, and the two ways it ends. Ported from `DescribeIt.tsx` and the describe route
/// of `Tracker.ts`.
///
/// - Online, the foods come back to be checked and adjusted, and logging writes one entry per
///   food that is kept.
/// - When the AI can't be reached (no key, a refused key, a spent quota, an unknown model, no
///   connection), the description is saved as one waiting entry named with the cook's words, and
///   the queue fills it in when the AI is back. It is never estimated on the device.
/// - A bad answer, or one with no food in it, is a failure: the text stays, nothing is saved,
///   and the cook can ask again or use quick add.
/// - Asking again, or closing the sheet, cancels a request in flight and logs nothing.
@MainActor
@Observable
final class DescribeModel {
  enum Phase: Equatable {
    /// Typing. A failure, if there was one, shows here with the text kept.
    case writing
    case asking
    /// The foods the model found, to check before logging.
    case reviewing
    /// Saved as a waiting entry.
    case waiting
  }

  /// One food in the review. The draft keeps what is typed as text until it is logged.
  struct Row: Identifiable, Equatable {
    let id: Int
    var draft: EntryDraft

    init(id: Int, item: DescribedItem, slot: MealSlot) {
      self.id = id
      var draft = EntryDraft(slot: slot)
      draft.name = item.name
      draft.amount = item.amount ?? ""
      draft.calories = item.macros.calories.map { showNumber($0, digits: 0) } ?? ""
      draft.protein = item.macros.protein.map { showNumber($0) } ?? ""
      draft.carbs = item.macros.carbs.map { showNumber($0) } ?? ""
      draft.fat = item.macros.fat.map { showNumber($0) } ?? ""
      self.draft = draft
    }

    /// Something that isn't food comes back with no numbers; the web shows it with a note and
    /// leaves it to the cook to remove or fill in.
    var hasNoNumbers: Bool {
      draft.calories.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && draft.protein.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  /// The longest description that is sent (`MEAL_DESCRIPTION_MAX` in the reference).
  static let maxLength = 1000

  var text = ""
  private(set) var phase = Phase.writing
  /// Why the last ask or log didn't go through. Cleared by the next one.
  private(set) var failure: CopyString?
  var rows: [Row] = []
  /// True once the cook has tried to log, so errors in the rows show.
  private(set) var attempted = false

  let day: LocalDate
  let slot: MealSlot

  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var nextID = 0

  init(day: LocalDate, slot: MealSlot) {
    self.day = day
    self.slot = slot
  }

  isolated deinit {
    // The sheet went away: nobody wants the answer.
    task?.cancel()
  }

  // MARK: Writing

  var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// Shown while typing once the text is past the limit.
  var lengthError: CopyString? {
    trimmed.count > Self.maxLength ? Copy.validation.tooLong(Self.maxLength) : nil
  }

  // MARK: Asking

  /// Asks the AI what was eaten. Returns the work so a caller can wait for it; nil when nothing
  /// was asked (blank or over-long text, or a request already running). Nothing is sent for text
  /// the reference would refuse.
  @discardableResult
  func startDivining(using ai: RecipeAIService, in context: ModelContext) -> Task<Void, Never>? {
    guard phase == .writing else { return nil }
    failure = nil
    let meal = trimmed
    if meal.isEmpty {
      failure = Copy.validation.required
      return nil
    }
    if let lengthError {
      failure = lengthError
      return nil
    }
    phase = .asking
    let estimator = ai.estimator
    // Holds the model weakly, so closing the sheet (which drops it) can cancel the request.
    let work = Task { @MainActor [weak self] in
      let result = await Self.ask(estimator, about: meal)
      self?.finish(result, meal: meal, in: context)
    }
    task = work
    return work
  }

  /// Stops a request in flight and goes back to typing. Logs nothing.
  func cancel() {
    task?.cancel()
    task = nil
    if phase == .asking { phase = .writing }
  }

  private static func ask(
    _ estimator: any RecipeAI, about meal: String
  ) async -> Result<[DescribedItem], RecipeAIError> {
    do throws(RecipeAIError) {
      return .success(try await estimator.estimateMeal(meal))
    } catch {
      return .failure(error)
    }
  }

  private func finish(
    _ result: Result<[DescribedItem], RecipeAIError>, meal: String, in context: ModelContext
  ) {
    // Cancelled, or asked again since: this answer isn't wanted.
    guard !Task.isCancelled, phase == .asking else { return }
    task = nil
    switch result {
    case .success(let items):
      guard !items.isEmpty else {
        phase = .writing
        failure = Copy.tracker.describe.unreadable
        return
      }
      rows = items.map { item in
        defer { nextID += 1 }
        return Row(id: nextID, item: item, slot: slot)
      }
      attempted = false
      phase = .reviewing
    case .failure(.cancelled):
      phase = .writing
    case .failure(let error) where error.isUnavailable:
      saveWaiting(meal, in: context)
    case .failure:
      phase = .writing
      failure = Copy.tracker.describe.failed
    }
  }

  // MARK: Waiting

  /// The description as an entry's name: the cook's words on one line, short enough to store.
  /// The full text goes to the job.
  static func waitingName(_ meal: String) -> String {
    let oneLine = meal.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return String(oneLine.prefix(TrackerLimits.name)).trimmingCharacters(in: .whitespaces)
  }

  /// One entry named with the cook's words, marked as waiting, and a job to fill it in.
  private func saveWaiting(_ meal: String, in context: ModelContext) {
    do {
      let entry = NewEntry(
        name: Self.waitingName(meal), macros: .none, source: .described, macrosPending: true)
      let added = try DiaryEditor(context: context).add([entry], on: day, slot: slot)
      for record in added { AIJobQueue.enqueueMeal(meal, for: record, in: context) }
      try? context.save()
      phase = .waiting
    } catch {
      phase = .writing
      failure = AddContext.message(for: error)
    }
  }

  // MARK: Reviewing

  /// What the rows add up to, with numbers that can't be read left out.
  var totals: MacroTotals {
    rows.reduce(MacroTotals.zero) { sum, row in
      guard let valid = row.draft.valid(requireCalories: false) else { return sum }
      let add = entryTotals(macros: valid.macros, servings: 1)
      var next = sum
      for key in MacroKey.allCases { next[key] += add[key] }
      return next
    }
  }

  /// What is wrong with a row, once the cook has tried to log.
  func errors(for row: Row) -> [EntryDraft.Field: CopyString] {
    attempted ? row.draft.errors(requireCalories: false) : [:]
  }

  func remove(_ row: Row) {
    rows.removeAll { $0.id == row.id }
  }

  /// Back to typing, with the text kept.
  func startOver() {
    rows = []
    attempted = false
    failure = nil
    phase = .writing
  }

  /// Logs one entry per food kept, as a described entry, through the sheet. Nothing is logged
  /// while any row is wrong. A refusal (a full day) leaves the review as it was.
  func log(through context: AddContext) {
    attempted = true
    failure = nil
    guard !rows.isEmpty else { return }
    var entries: [NewEntry] = []
    for row in rows {
      guard let valid = row.draft.valid(requireCalories: false) else { return }
      entries.append(NewEntry(valid, source: .described))
    }
    failure = context.log(entries)
  }
}
