import CauldronKit
import Foundation
import SwiftData

/// Something to log: what the add sheet's ways in (typing, describing, a recipe, a recent food)
/// all hand to `DiaryWrites.add`. Macros are per serving and snapshot at the time of logging.
struct NewEntry {
  var name: String
  var amount: String?
  var servings: Double = 1
  var macros: Macros
  var source: DiarySource
  var recipe: RecipeRecord?
  /// True while a described meal waits for the model.
  var macrosPending = false

  init(
    name: String, amount: String? = nil, servings: Double = 1, macros: Macros,
    source: DiarySource, recipe: RecipeRecord? = nil, macrosPending: Bool = false
  ) {
    self.name = name
    self.amount = amount
    self.servings = servings
    self.macros = macros
    self.source = source
    self.recipe = recipe
    self.macrosPending = macrosPending
  }

  init(_ valid: EntryDraft.Valid, source: DiarySource) {
    self.init(
      name: valid.name, amount: valid.amount, servings: valid.servings, macros: valid.macros,
      source: source)
  }

  /// Whether every number is one the store accepts: servings above 0 up to the limit,
  /// calories whole and in range, grams in range, nothing infinite or not a number.
  var isStorable: Bool {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= TrackerLimits.name,
      (amount ?? "").count <= TrackerLimits.amount,
      servings.isFinite, servings > 0, servings <= Double(TrackerLimits.servings)
    else { return false }
    return MacroKey.allCases.allSatisfy { key in
      guard let value = macros[key] else { return true }
      let limit = Double(key == .calories ? RecipeLimits.calories : RecipeLimits.grams)
      return value.isFinite && (0...limit).contains(value)
    }
  }
}

/// Changes to the diary. They save as they go, and a change that is refused leaves the store as
/// it was. Positions run from 0 in a meal and a new entry goes last; deleting leaves a gap, which
/// costs nothing (the order is what matters) and keeps the other entries from being rewritten.
enum DiaryWrites {
  enum Failure: Error {
    /// The day already holds as many entries as it may.
    case dayFull
    /// A number or text outside what the store accepts.
    case invalid
  }

  /// Logs `entries` at the end of `slot` on `day`, all or none.
  @discardableResult
  static func add(
    _ entries: [NewEntry], on day: LocalDate, slot: MealSlot, in context: ModelContext
  ) throws -> [DiaryEntryRecord] {
    guard entries.allSatisfy(\.isStorable) else { throw Failure.invalid }
    guard try count(on: day, in: context) + entries.count <= TrackerLimits.perDay else {
      throw Failure.dayFull
    }
    var position = try nextPosition(on: day, slot: slot, in: context)
    var added: [DiaryEntryRecord] = []
    for new in entries {
      let record = DiaryEntryRecord(
        day: day, slot: slot, name: new.name.trimmingCharacters(in: .whitespacesAndNewlines),
        servings: new.servings, source: new.source)
      record.amount = new.amount
      record.macros = new.macros
      record.recipe = new.recipe
      record.macrosPending = new.macrosPending
      record.position = position
      position += 1
      context.insert(record)
      added.append(record)
    }
    try commit(context)
    return added
  }

  /// Changes an entry's name, amount, servings, numbers, meal and day. Typing numbers into an
  /// entry that waits for them ends the wait. Moving it to another meal
  /// or day puts it last there; a day that is already full refuses.
  static func update(
    _ record: DiaryEntryRecord, with valid: EntryDraft.Valid, in context: ModelContext
  ) throws {
    let new = NewEntry(valid, source: record.source)
    guard new.isStorable, let currentDay = record.day else { throw Failure.invalid }
    let day = valid.day ?? currentDay
    let moved = valid.slot != record.slot || day != currentDay
    if day != currentDay, try count(on: day, in: context) >= TrackerLimits.perDay {
      throw Failure.dayFull
    }
    // Placed before the fields change, while the entry still counts in its old meal.
    let position =
      moved ? try nextPosition(on: day, slot: valid.slot, in: context) : record.position
    record.name = valid.name
    record.amount = valid.amount
    record.servings = valid.servings
    record.macros = valid.macros
    // Numbers typed in for a meal that was waiting for the model are the cook's: they stand, and
    // the queue drops the job without writing over them. An edit that leaves it with no numbers
    // (a new name, another meal) leaves it waiting.
    if record.macrosPending, valid.macros != .none { record.macrosPending = false }
    record.slot = valid.slot
    record.day = day
    record.position = position
    try commit(context)
  }

  /// What an entry was, kept so a delete can be taken back: the same id, day, meal, position and
  /// numbers.
  struct Removed: Equatable {
    var id: UUID
    var day: LocalDate
    var slot: MealSlot
    var position: Int
    var name: String
    var amount: String?
    var servings: Double
    var macros: Macros
    var source: DiarySource
    var macrosPending: Bool
    var createdAt: Date
    var recipeID: UUID?
  }

  /// Deletes the entry for good, and returns what it was for `restore`.
  @discardableResult
  static func remove(_ record: DiaryEntryRecord, in context: ModelContext) throws -> Removed {
    guard let day = record.day else { throw Failure.invalid }
    let removed = Removed(
      id: record.id, day: day,
      slot: record.slot, position: record.position, name: record.name, amount: record.amount,
      servings: record.servings, macros: record.macros, source: record.source,
      macrosPending: record.macrosPending, createdAt: record.createdAt, recipeID: record.recipe?.id)
    context.delete(record)
    try commit(context)
    return removed
  }

  /// Puts a removed entry back as it was. Doing it twice, or after the entry came back some
  /// other way, changes nothing. A day that filled up in the meantime refuses; a recipe that is
  /// gone is let go (the entry keeps its own numbers).
  @discardableResult
  static func restore(_ removed: Removed, in context: ModelContext) throws -> DiaryEntryRecord {
    let id = removed.id
    if let already = try context.fetch(
      FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.id == id })
    ).first {
      return already
    }
    guard try count(on: removed.day, in: context) < TrackerLimits.perDay else {
      throw Failure.dayFull
    }
    let record = DiaryEntryRecord(
      day: removed.day, slot: removed.slot, name: removed.name, servings: removed.servings,
      source: removed.source)
    record.id = removed.id
    record.amount = removed.amount
    record.macros = removed.macros
    record.macrosPending = removed.macrosPending
    record.position = removed.position
    record.createdAt = removed.createdAt
    if let recipeID = removed.recipeID {
      record.recipe = try context.fetch(
        FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == recipeID })
      ).first
    }
    context.insert(record)
    try commit(context)
    return record
  }

  /// Saves, and puts the context back as it was if that fails.
  private static func commit(_ context: ModelContext) throws {
    do {
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }

  static func count(on day: LocalDate, in context: ModelContext) throws -> Int {
    let key = day.description
    return try context.fetchCount(
      FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.dayKey == key }))
  }

  private static func nextPosition(
    on day: LocalDate, slot: MealSlot, in context: ModelContext
  ) throws -> Int {
    let key = day.description
    let raw = slot.rawValue
    let inSlot = try context.fetch(
      FetchDescriptor<DiaryEntryRecord>(
        predicate: #Predicate { $0.dayKey == key && $0.slotRaw == raw }))
    return (inSlot.map(\.position).max() ?? -1) + 1
  }
}
