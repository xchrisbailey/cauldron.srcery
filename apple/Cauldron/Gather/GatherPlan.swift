import CauldronKit
import Foundation
import SwiftData

// The Gather list's rules, apart from any view so they can be tested: building a week's rows
// from its plan, keeping them in step when the plan changes, and what checking, adding,
// removing and marking "in the pantry" do. Ported from `apps/api/src/Gather.ts`; the merging,
// the aisles and the reconcile step are CauldronKit's.

/// The limits the list keeps (`GatherItemInput` in the reference).
enum GatherLimits {
  /// An item added by hand is written like an ingredient line.
  static let line = RecipeLimits.line
}

/// Why the list refused a change.
enum GatherError: Error, Equatable {
  case blank
  case tooLong
  /// The item is gone, such as one another device removed.
  case missing
  /// Only items added by hand can be removed; the rest come from the week.
  case notManual

  var message: CopyString {
    switch self {
    case .blank: Copy.validation.required
    case .tooLong: Copy.validation.tooLong(GatherLimits.line)
    case .missing, .notManual: Copy.gather.couldntSave
    }
  }
}

/// A week's planned recipes as the list reads them: each entry with its servings and the
/// recipe's ingredients, and the recipe records behind them.
struct PlannedWeek {
  var entries: [PlannedEntry]
  var recipes: [RecipeId: RecipeRecord]

  /// Recipes the list is gathered from, each counted once.
  var recipeCount: Int { recipes.count }
}

enum GatherPlan {
  // MARK: Reading the plan

  /// The amount as a stored column holds it: four decimal places, capped (`quantity.round` in
  /// the reference). The reference compares and merges amounts as it stored them, so this
  /// does too and the two lists agree to the last digit.
  static func stored(_ amount: Double) -> Double {
    min(99_999_999, (amount * 10_000).rounded() / 10_000)
  }

  private static func stored(_ quantity: Quantity?) -> Quantity? {
    quantity.map { Quantity(min: stored($0.min), max: $0.max.map(stored)) }
  }

  /// The week's planned recipes. An entry that isn't a recipe, or whose recipe is banished or
  /// gone, adds nothing: banished recipes drop out of the list along with the week.
  static func planned(week start: LocalDate, in context: ModelContext) throws -> PlannedWeek {
    var week = PlannedWeek(entries: [], recipes: [:])
    for record in try WeekPlan.fetch(from: start, through: start.adding(days: 6), in: context) {
      guard let recipe = record.recipe, !recipe.isBanished else { continue }
      week.recipes[recipe.id] = recipe
      week.entries.append(
        PlannedEntry(
          recipeId: recipe.id, recipeServings: recipe.servings, servings: record.servings,
          ingredients: recipe.ingredients.map {
            PlannedIngredient(
              item: $0.item, itemKey: $0.itemKey, quantity: stored($0.quantity), unit: $0.unit)
          }))
    }
    return week
  }

  // MARK: Duplicates

  /// What two lines must share to be one: the week and, for a gathered line, its merge key.
  /// Nil for a line added by hand, which is always its own.
  static func mergeKey(of row: GatherItemRecord) -> String? {
    row.manual ? nil : mergeKeyOf(row.itemKey, row.quantity, row.unit)
  }

  /// The lines of a week a reader shows, oldest first. CloudKit can't keep two devices from
  /// each building the same line, so a merge key can have several rows; the one changed most
  /// recently counts (see `Deduplication`) and the others are left alone, neither shown nor
  /// edited, until `Deduplication.tidy` removes them.
  static func shown(_ rows: [GatherItemRecord], week start: LocalDate) -> [GatherItemRecord] {
    let key = start.description
    var groups: [String: [GatherItemRecord]] = [:]
    var shown: [GatherItemRecord] = []
    for row in rows where row.weekStartKey == key {
      if let merge = mergeKey(of: row) {
        groups[merge, default: []].append(row)
      } else {
        shown.append(row)
      }
    }
    shown += groups.values.compactMap { Deduplication.keeper(of: $0) }
    return shown.sorted { a, b in
      (a.createdAt, a.id.uuidString) < (b.createdAt, b.id.uuidString)
    }
  }

  private static func fetchRows(
    week start: LocalDate, in context: ModelContext
  ) throws -> [GatherItemRecord] {
    let key = start.description
    return try context.fetch(
      FetchDescriptor<GatherItemRecord>(predicate: #Predicate { $0.weekStartKey == key }))
  }

  // MARK: Rebuilding

  /// Brings the week's gathered lines in line with its plan, and returns what it changed.
  /// A line still needed keeps its check (unless the week now needs more of it); new ones are
  /// added; lines no longer needed go. Lines added by hand are never touched.
  ///
  /// Where a merge key has several rows, the one a reader shows is the one that is kept up to
  /// date. The others are left as they are, so nothing is deleted that another device might
  /// still be editing, unless the item has left the week altogether: then the whole group goes,
  /// since an edit to an item nobody needs is moot.
  @discardableResult
  static func rebuild(week start: LocalDate, in context: ModelContext) throws -> Reconciled {
    let planned = try planned(week: start, in: context)
    let all = try fetchRows(week: start, in: context)
    let current = shown(all, week: start).filter { !$0.manual }
    let existing = current.map { row in
      ExistingGatherRow(
        id: row.id, item: row.item, itemKey: row.itemKey, quantity: row.quantity,
        unit: row.unit, aisle: row.aisle, checked: row.checked,
        sources: (row.sources ?? []).compactMap { source in
          source.recipe.map {
            GatherContribution(recipeId: $0.id, quantity: source.quantity, unit: source.unit)
          }
        })
    }
    let result = reconcile(
      existing: existing, wanted: gatherWeek(planned.entries), round: stored)

    let byId = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
    for row in result.inserts {
      let record = GatherItemRecord(weekStart: start, item: row.item, itemKey: row.itemKey)
      record.quantity = row.quantity
      record.unit = row.unit
      record.aisle = row.aisle
      context.insert(record)
      writeSources(row.sources, to: record, planned: planned, in: context)
    }
    for update in result.updates {
      guard let record = byId[update.id] else { continue }
      if update.changed || update.uncheck {
        record.item = update.row.item
        record.quantity = update.row.quantity
        record.unit = update.row.unit
        record.aisle = update.row.aisle
        if update.uncheck { record.checked = false }
      }
      if update.sources {
        for source in record.sources ?? [] { context.delete(source) }
        writeSources(update.row.sources, to: record, planned: planned, in: context)
      }
    }
    let gone = Set(result.removals.compactMap { byId[$0] }.compactMap(mergeKey(of:)))
    for row in all where mergeKey(of: row).map(gone.contains) ?? false {
      context.delete(row)
    }
    return result
  }

  private static func writeSources(
    _ sources: [GatherContribution], to record: GatherItemRecord, planned: PlannedWeek,
    in context: ModelContext
  ) {
    for contribution in sources {
      let source = GatherSourceRecord(quantity: contribution.quantity, unit: contribution.unit)
      context.insert(source)
      source.item = record
      source.recipe = planned.recipes[contribution.recipeId]
    }
  }

  // MARK: Changing

  /// Adds an item by hand, written like an ingredient line: "2 lemons", "oat milk". A line the
  /// parser can't read is kept whole as the item.
  @discardableResult
  static func add(
    _ text: String, week start: LocalDate, in context: ModelContext
  ) throws -> GatherItemRecord {
    let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { throw GatherError.blank }
    guard line.count <= GatherLimits.line else { throw GatherError.tooLong }
    let parsed = parseIngredientLine(line)
    let item =
      parsed.item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? line : parsed.item
    let key = ingredientKey(item)
    let record = GatherItemRecord(weekStart: start, item: item, itemKey: key)
    record.quantity = stored(parsed.quantity)
    record.unit = parsed.unit
    record.aisle = aisleFor(key)
    record.manual = true
    context.insert(record)
    return record
  }

  private static func row(
    _ id: GatherItemId, in context: ModelContext
  ) throws -> GatherItemRecord {
    let found = try context.fetch(
      FetchDescriptor<GatherItemRecord>(predicate: #Predicate { $0.id == id }))
    guard let row = found.first else { throw GatherError.missing }
    return row
  }

  /// Ticks an item off, or puts it back. It is stored on the item, so it follows the item to
  /// every device.
  static func setChecked(
    _ id: GatherItemId, _ checked: Bool, in context: ModelContext
  ) throws {
    let item = try row(id, in: context)
    if item.checked != checked { item.checked = checked }
  }

  /// Removes an item added by hand.
  static func remove(_ id: GatherItemId, in context: ModelContext) throws {
    let item = try row(id, in: context)
    guard item.manual else { throw GatherError.notManual }
    context.delete(item)
  }

  /// Marks an item as already at home, or not. The mark is on the item's key, so it holds for
  /// every line of that item in every week. Unmarking removes every row for the key,
  /// duplicates included, or the item would still read as in the pantry.
  static func setPantry(
    itemKey key: String, _ inPantry: Bool, in context: ModelContext
  ) throws {
    let held = try context.fetch(
      FetchDescriptor<PantryItemRecord>(predicate: #Predicate { $0.itemKey == key }))
    if inPantry {
      if held.isEmpty { context.insert(PantryItemRecord(itemKey: key)) }
    } else {
      for mark in held { context.delete(mark) }
    }
  }

  // MARK: Saving

  /// Runs a change and saves it. A change that fails is rolled back, so the screen never
  /// shows what isn't stored.
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
    (error as? GatherError)?.message ?? Copy.gather.couldntSave
  }
}
