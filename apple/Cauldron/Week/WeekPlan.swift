import CauldronKit
import Foundation
import SwiftData

// The week's planning rules, apart from any view so they can be tested: which entries a day
// and meal hold, where a move lands, what adding, moving and removing do to the positions
// around them. Ported from `apps/web/src/lib/plan.ts` and `apps/api/src/Plan.ts`.

/// The limits the week keeps (`PLAN_LIMITS` in the reference).
enum WeekLimits {
  /// Entries in one meal slot on one day.
  static let perSlot = 20
  static let servings = RecipeLimits.servings
  static let title = RecipeLimits.title
}

/// Why the week refused a change.
enum WeekPlanError: Error, Equatable {
  case slotFull
  case recipeBanished
  case recipeMissing
  case emptyTitle
  case invalidServings
  case noDays

  var message: CopyString {
    switch self {
    case .slotFull: Copy.week.slotFull
    case .recipeBanished, .recipeMissing, .emptyTitle, .invalidServings, .noDays:
      Copy.week.couldntSave
    }
  }
}

/// One meal of one day.
struct MealTarget: Hashable {
  var day: LocalDate
  var slot: MealSlot
}

/// A change to one entry. A nil field is left as it is; `servings` is `.some(nil)` to follow
/// the recipe's own servings again.
struct EntryChange: Equatable {
  var day: LocalDate?
  var slot: MealSlot?
  var servings: Int??
  var title: String?
  var position: Int?

  var isEmpty: Bool {
    day == nil && slot == nil && servings == nil && title == nil && position == nil
  }
}

/// What a removed entry needs to be put back: undo restores it where it was.
struct RemovedMeal {
  let target: MealTarget
  let title: String
  let servings: Int?
  let position: Int
  let recipe: RecipeRecord?
}

enum WeekPlan {
  // MARK: Reading

  /// Day, then meal, then position: the order the week shows. Entries on the same spot sort
  /// by when they were made, then id, so every device agrees (two devices can add at once).
  static func ordered(_ entries: [PlanEntryRecord]) -> [PlanEntryRecord] {
    entries.sorted { a, b in
      if a.dayKey != b.dayKey { return a.dayKey < b.dayKey }
      if a.slot != b.slot { return slotIndex(a.slot) < slotIndex(b.slot) }
      return precedes(a, b)
    }
  }

  /// The entries of one meal of one day, in order.
  static func inSlot(_ entries: [PlanEntryRecord], _ target: MealTarget) -> [PlanEntryRecord] {
    let key = target.day.description
    return entries.filter { $0.dayKey == key && $0.slot == target.slot }.sorted(by: precedes)
  }

  private static func precedes(_ a: PlanEntryRecord, _ b: PlanEntryRecord) -> Bool {
    if a.position != b.position { return a.position < b.position }
    if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
    return a.id.uuidString < b.id.uuidString
  }

  private static func slotIndex(_ slot: MealSlot) -> Int {
    MealSlot.allCases.firstIndex(of: slot) ?? 0
  }

  /// The entry as the tally and the cards read it. Nil when its day can't be read. A banished
  /// recipe reads as gone: the entry keeps its stored title and counts as a meal with nothing
  /// to count, as in the web app.
  static func meal(_ record: PlanEntryRecord) -> PlanEntry? {
    guard let day = record.day else { return nil }
    let live = record.recipe.flatMap { $0.isBanished ? nil : $0 }
    return PlanEntry(
      id: record.id, date: day, slot: record.slot, title: record.title,
      recipe: live.map(planRecipe), servings: record.servings, position: record.position,
      brewed: live?.cooks?.contains { $0.cookedOnKey == record.dayKey } ?? false)
  }

  static func planRecipe(_ recipe: RecipeRecord) -> PlanRecipe {
    PlanRecipe(
      id: recipe.id, title: recipe.title, servings: recipe.servings,
      totalMinutes: recipeMinutes(
        totalMinutes: recipe.totalMinutes, prepMinutes: recipe.prepMinutes,
        cookMinutes: recipe.cookMinutes),
      photoKey: nil, macros: recipe.macros)
  }

  // MARK: Fetching

  /// Entries from `from` through `through`; day keys sort as dates.
  static func predicate(from: LocalDate, through: LocalDate) -> Predicate<PlanEntryRecord> {
    let lower = from.description
    let upper = through.description
    return #Predicate { $0.dayKey >= lower && $0.dayKey <= upper }
  }

  static func fetch(
    from: LocalDate, through: LocalDate, in context: ModelContext
  ) throws -> [PlanEntryRecord] {
    ordered(
      try context.fetch(FetchDescriptor(predicate: predicate(from: from, through: through))))
  }

  private static func fetchSlot(
    _ target: MealTarget, in context: ModelContext
  ) throws -> [PlanEntryRecord] {
    let key = target.day.description
    let raw = target.slot.rawValue
    let found = try context.fetch(
      FetchDescriptor<PlanEntryRecord>(
        predicate: #Predicate { $0.dayKey == key && $0.slotRaw == raw }))
    return found.sorted(by: precedes)
  }

  // MARK: Adding

  /// Stirs a recipe into the week: one entry for each day, each with its own servings. All of
  /// them land or none do.
  @discardableResult
  static func stir(
    _ recipe: RecipeRecord, days: [DayServings], slot: MealSlot, into context: ModelContext
  ) throws -> [PlanEntryRecord] {
    guard !recipe.isBanished else { throw WeekPlanError.recipeBanished }
    guard !days.isEmpty else { throw WeekPlanError.noDays }
    guard days.allSatisfy({ (1...WeekLimits.servings).contains($0.servings) }) else {
      throw WeekPlanError.invalidServings
    }
    var counts: [LocalDate: Int] = [:]
    for day in days {
      let held =
        try counts[day.date] ?? fetchSlot(MealTarget(day: day.date, slot: slot), in: context).count
      guard held < WeekLimits.perSlot else { throw WeekPlanError.slotFull }
      counts[day.date] = held + 1
    }
    return try days.map {
      try insert(
        title: recipe.title, recipe: recipe, servings: $0.servings,
        at: MealTarget(day: $0.date, slot: slot), position: nil, in: context)
    }
  }

  /// Stirs a recipe into one meal. Nil `servings` follows the recipe's own.
  @discardableResult
  static func stir(
    _ recipe: RecipeRecord, at target: MealTarget, servings: Int?, into context: ModelContext
  ) throws -> PlanEntryRecord {
    guard !recipe.isBanished else { throw WeekPlanError.recipeBanished }
    if let servings, !(1...WeekLimits.servings).contains(servings) {
      throw WeekPlanError.invalidServings
    }
    return try insert(
      title: recipe.title, recipe: recipe, servings: servings, at: target, position: nil,
      in: context)
  }

  /// The meal a recipe goes into when the cook hasn't chosen one: dinner, as on the recipe's page.
  static let defaultSlot = MealSlot.dinner

  /// Where Add Meal starts: the day the cook has chosen, else today when the week holds it, else
  /// the week's first day, in the default meal.
  static func newMeal(chosen: LocalDate?, week: [LocalDate], today: LocalDate) -> MealTarget {
    let day =
      chosen.flatMap { week.contains($0) ? $0 : nil }
      ?? (week.contains(today) ? today : week.first ?? today)
    return MealTarget(day: day, slot: defaultSlot)
  }

  /// Stirs a recipe that was dragged onto a day, found by its id, with its own servings. It goes
  /// the way "Stir into the week" does, so a banished recipe is refused and a full meal is too.
  @discardableResult
  static func stir(
    recipeID: UUID, at target: MealTarget, into context: ModelContext
  ) throws -> PlanEntryRecord {
    let found = try context.fetch(
      FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == recipeID }))
    guard let recipe = found.first else { throw WeekPlanError.recipeMissing }
    return try stir(recipe, at: target, servings: nil, into: context)
  }

  /// Stirs a meal that isn't a recipe into the week ("Leftovers").
  @discardableResult
  static func stirText(
    _ text: String, at target: MealTarget, into context: ModelContext
  ) throws -> PlanEntryRecord {
    let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title.count <= WeekLimits.title else { throw WeekPlanError.emptyTitle }
    return try insert(
      title: title, recipe: nil, servings: nil, at: target, position: nil, in: context)
  }

  private static func insert(
    title: String, recipe: RecipeRecord?, servings: Int?, at target: MealTarget, position: Int?,
    in context: ModelContext
  ) throws -> PlanEntryRecord {
    let siblings = try fetchSlot(target, in: context)
    guard siblings.count < WeekLimits.perSlot else { throw WeekPlanError.slotFull }
    let record = PlanEntryRecord(
      day: target.day, slot: target.slot, title: title, servings: servings,
      position: siblings.count)
    context.insert(record)
    record.recipe = recipe
    if let position, position < siblings.count {
      renumber(siblings.toSpliced(at: max(0, position), with: record))
    }
    return record
  }

  // MARK: Changing

  /// Applies `change` to `entry`: its servings or title, and where it sits. A move lands at
  /// `position`, or at the end of a different meal, and both meals are renumbered.
  static func apply(
    _ change: EntryChange, to entry: PlanEntryRecord, in context: ModelContext
  ) throws {
    if let servings = change.servings {
      if let servings, !(1...WeekLimits.servings).contains(servings) {
        throw WeekPlanError.invalidServings
      }
      if entry.servings != servings { entry.servings = servings }
    }
    if let text = change.title, isFreeText(entry) {
      let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty, title.count <= WeekLimits.title else {
        throw WeekPlanError.emptyTitle
      }
      if entry.title != title { entry.title = title }
    }
    guard change.day != nil || change.slot != nil || change.position != nil else { return }
    guard let day = entry.day else { return }
    let from = MealTarget(day: day, slot: entry.slot)
    let to = MealTarget(day: change.day ?? from.day, slot: change.slot ?? from.slot)
    let moved = from != to
    let siblings = try fetchSlot(to, in: context).filter { $0.id != entry.id }
    if moved && siblings.count >= WeekLimits.perSlot { throw WeekPlanError.slotFull }
    let current =
      moved
      ? siblings.count : try fetchSlot(from, in: context).firstIndex { $0.id == entry.id } ?? 0
    let position = min(max(0, change.position ?? current), siblings.count)
    if moved {
      entry.day = to.day
      entry.slot = to.slot
    }
    renumber(siblings.toSpliced(at: position, with: entry))
    if moved { renumber(try fetchSlot(from, in: context).filter { $0.id != entry.id }) }
  }

  /// Text a cook wrote, or the name of a recipe that has since been banished: the entries
  /// whose title is theirs to change.
  static func isFreeText(_ entry: PlanEntryRecord) -> Bool {
    guard let recipe = entry.recipe else { return true }
    return recipe.isBanished
  }

  /// Takes the entry off the week and closes the gap it left.
  static func remove(_ entry: PlanEntryRecord, in context: ModelContext) throws -> RemovedMeal {
    guard let day = entry.day else { throw WeekPlanError.noDays }
    let target = MealTarget(day: day, slot: entry.slot)
    let removed = RemovedMeal(
      target: target, title: entry.title, servings: entry.servings, position: entry.position,
      recipe: entry.recipe)
    context.delete(entry)
    renumber(try fetchSlot(target, in: context).filter { $0.id != entry.id })
    return removed
  }

  /// Puts a removed entry back where it was. A recipe banished in the meantime comes back
  /// as its title alone.
  @discardableResult
  static func restore(
    _ removed: RemovedMeal, in context: ModelContext
  ) throws -> PlanEntryRecord {
    let recipe = removed.recipe.flatMap { $0.isBanished ? nil : $0 }
    return try insert(
      title: removed.title, recipe: recipe, servings: removed.servings, at: removed.target,
      position: removed.position, in: context)
  }

  // MARK: The whole week

  /// Copies the week before `start` into the week from `start`, after whatever is already
  /// there, up to the limit of each meal. Returns how many entries it added.
  @discardableResult
  static func copyLastWeek(into start: LocalDate, in context: ModelContext) throws -> Int {
    let source = try fetch(
      from: start.adding(days: -7), through: start.adding(days: -1), in: context)
    var next: [MealTarget: Int] = [:]
    var added = 0
    for entry in source {
      guard let day = entry.day else { continue }
      let target = MealTarget(day: day.adding(days: 7), slot: entry.slot)
      let held = try next[target] ?? fetchSlot(target, in: context).count
      guard held < WeekLimits.perSlot else { continue }
      next[target] = held + 1
      let copy = PlanEntryRecord(
        day: target.day, slot: target.slot, title: entry.title, servings: entry.servings,
        position: held)
      context.insert(copy)
      copy.recipe = entry.recipe
      added += 1
    }
    return added
  }

  /// Removes every entry in the week from `start`. Returns how many went.
  @discardableResult
  static func clear(week start: LocalDate, in context: ModelContext) throws -> Int {
    let entries = try fetch(from: start, through: start.adding(days: 6), in: context)
    for entry in entries { context.delete(entry) }
    return entries.count
  }

  // MARK: Dragging

  /// Where a meal dragged onto a meal lands: before `before` when it was dropped on another
  /// entry, otherwise at the end. Nil when nothing would change, such as an entry dropped on
  /// itself or back where it was.
  static func dropMove(
    _ entries: [PlanEntryRecord], moving id: UUID, to target: MealTarget,
    before: UUID?
  ) -> EntryChange? {
    guard let moving = entries.first(where: { $0.id == id }), before != id else { return nil }
    let here = inSlot(entries, target)
    let siblings = here.filter { $0.id != id }
    let index = before.flatMap { before in siblings.firstIndex { $0.id == before } }
    let position = index ?? siblings.count
    let stays = moving.dayKey == target.day.description && moving.slot == target.slot
    if stays && position == here.firstIndex(where: { $0.id == id }) { return nil }
    return EntryChange(day: target.day, slot: target.slot, position: position)
  }

  // MARK: Recipe page

  /// The days the recipe page offers: today and the thirteen after it.
  static func upcoming(from today: LocalDate) -> [LocalDate] {
    (0..<14).map { today.adding(days: $0) }
  }

  /// The servings an entry plans for a recipe at the scale the cook chose: nil when it is the
  /// recipe's own, so the entry keeps following the recipe.
  static func servings(for scale: Scale, recipeServings: Int?) -> Int? {
    guard case .servings(let wanted) = scale, wanted != recipeServings,
      (1...WeekLimits.servings).contains(wanted)
    else { return nil }
    return wanted
  }

  // MARK: Saving

  /// Runs a change and saves it. A change that fails is rolled back, so the screens never show
  /// what isn't stored.
  static func commit(in context: ModelContext, _ change: () throws -> Void) throws {
    do {
      try change()
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }

  /// What to tell the cook when a change failed.
  static func message(for error: any Error) -> CopyString {
    (error as? WeekPlanError)?.message ?? Copy.week.couldntSave
  }

  // MARK: Helpers

  /// Writes positions 0..n in the given order, touching only the entries that change.
  private static func renumber(_ ordered: [PlanEntryRecord]) {
    for (position, entry) in ordered.enumerated() where entry.position != position {
      entry.position = position
    }
  }
}

extension Array {
  /// A copy with `element` inserted at `index`.
  fileprivate func toSpliced(at index: Int, with element: Element) -> [Element] {
    var copy = self
    copy.insert(element, at: Swift.min(Swift.max(0, index), count))
    return copy
  }
}
