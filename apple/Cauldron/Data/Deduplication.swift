import CauldronKit
import Foundation
import SwiftData

/// A record that can be picked between when two devices each made one.
protocol Deduplicated: PersistentModel {
  var id: UUID { get }
  /// When the row last changed (or was made, for rows that never change).
  var lastChanged: Date { get }
}

extension BodyProfileRecord: Deduplicated { var lastChanged: Date { updatedAt } }
extension TargetsRecord: Deduplicated { var lastChanged: Date { updatedAt } }
extension PreferencesRecord: Deduplicated { var lastChanged: Date { updatedAt } }
extension WeighInRecord: Deduplicated { var lastChanged: Date { updatedAt } }
extension FavouriteRecord: Deduplicated { var lastChanged: Date { updatedAt } }
extension TagRecord: Deduplicated { var lastChanged: Date { updatedAt } }
extension PantryItemRecord: Deduplicated { var lastChanged: Date { createdAt } }
extension GatherItemRecord: Deduplicated { var lastChanged: Date { updatedAt } }
extension CookRecord: Deduplicated { var lastChanged: Date { createdAt } }

/// CloudKit can't enforce uniqueness, so two devices that both set targets, or both weigh in
/// on the same day, before they sync leave two rows. The rule everywhere: the row changed
/// most recently is the truth. Reads apply it through `current(_:)` and `weighIn(on:)`, and
/// `tidy` removes the losers once they have been left alone for a while.
enum Deduplication {
  /// How long a duplicate must go unchanged before `tidy` deletes it. A delete syncs and
  /// beats any later edit of the same row, so a row another device may still be editing, or
  /// whose relationships may still be arriving, has to be left in place. Reads already
  /// ignore it.
  static let grace: TimeInterval = 7 * 24 * 60 * 60

  /// The row to keep: the most recently changed, with the id breaking a tie so every device
  /// picks the same one.
  static func keeper<Row: Deduplicated>(of rows: [Row]) -> Row? {
    rows.max { a, b in
      (a.lastChanged, b.id.uuidString) < (b.lastChanged, a.id.uuidString)
    }
  }

  /// Deletes every duplicate that has gone unchanged for `grace`, and returns how many rows
  /// went. Newer duplicates stay until a later run.
  @discardableResult
  static func tidy(_ context: ModelContext, now: Date = .now) throws -> Int {
    let settled = now.addingTimeInterval(-grace)
    func prune<Row: Deduplicated>(
      _ type: Row.Type, in context: ModelContext, key: (Row) -> String?,
      absorb: (_ keeper: Row, _ extra: Row) -> Void = { _, _ in }
    ) throws -> Int {
      try Deduplication.prune(type, in: context, settled: settled, key: key, absorb: absorb)
    }
    var removed = 0
    removed += try prune(BodyProfileRecord.self, in: context) { _ in "" }
    removed += try prune(TargetsRecord.self, in: context) { _ in "" }
    removed += try prune(PreferencesRecord.self, in: context) { _ in "" }
    removed += try prune(WeighInRecord.self, in: context) { $0.dayKey }
    removed += try prune(FavouriteRecord.self, in: context) { $0.key }
    removed += try prune(PantryItemRecord.self, in: context) { $0.itemKey }
    // A gathered line is one per week and merge key; lines added by hand are each their own.
    removed += try prune(
      GatherItemRecord.self, in: context,
      key: { item in
        item.manual
          ? nil : "\(item.weekStartKey)|\(mergeKeyOf(item.itemKey, item.quantity, item.unit))"
      }
    ) { keeper, extra in
      // A tick belongs to the line, so it outlives the row that held it.
      if extra.checked { keeper.checked = true }
    }
    removed += try prune(CookRecord.self, in: context) { cook in
      cook.recipe.map { "\($0.id.uuidString)|\(cook.cookedOnKey)" }
    }
    removed += try prune(TagRecord.self, in: context, key: { $0.name.lowercased() }) {
      keeper, extra in
      // Recipes tagged with the duplicate keep their tag.
      for recipe in extra.recipes ?? []
      where !(recipe.tags ?? []).contains(where: { $0 === keeper }) {
        recipe.tags = (recipe.tags ?? []) + [keeper]
      }
    }
    return removed
  }

  /// Groups rows by `key` (nil leaves a row alone) and deletes the rows of each group that
  /// are not its keeper and last changed before `settled`, after `absorb` has moved anything
  /// worth keeping onto the keeper.
  private static func prune<Row: Deduplicated>(
    _ type: Row.Type, in context: ModelContext, settled: Date, key: (Row) -> String?,
    absorb: (_ keeper: Row, _ extra: Row) -> Void
  ) throws -> Int {
    var groups: [String: [Row]] = [:]
    for row in try context.fetch(FetchDescriptor<Row>()) {
      guard let key = key(row) else { continue }
      groups[key, default: []].append(row)
    }
    var removed = 0
    for rows in groups.values where rows.count > 1 {
      guard let keeper = keeper(of: rows) else { continue }
      for extra in rows where extra !== keeper && extra.lastChanged < settled {
        absorb(keeper, extra)
        context.delete(extra)
        removed += 1
      }
    }
    return removed
  }
}

extension ModelContext {
  /// The one row of a kind there should only be one of (targets, body profile, preferences),
  /// or nil when none has been made yet.
  func current<Row: Deduplicated>(_ type: Row.Type) throws -> Row? {
    Deduplication.keeper(of: try fetch(FetchDescriptor<Row>()))
  }

  /// The weigh-in that counts for a day.
  func weighIn(on day: LocalDate) throws -> WeighInRecord? {
    let key = day.description
    return Deduplication.keeper(
      of: try fetch(FetchDescriptor<WeighInRecord>(predicate: #Predicate { $0.dayKey == key })))
  }
}
