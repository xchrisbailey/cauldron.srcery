import CauldronKit
import Foundation
import SwiftData

/// The diary's changes, with Health kept in step: each one is made in the store (`DiaryWrites`)
/// and then handed to `HealthSync`, which does nothing unless Health is connected. A change that
/// is refused reaches neither.
@MainActor
struct DiaryEditor {
  let context: ModelContext
  var health: HealthSync = .shared

  @discardableResult
  func add(_ entries: [NewEntry], on day: LocalDate, slot: MealSlot) throws -> [DiaryEntryRecord] {
    let added = try DiaryWrites.add(entries, on: day, slot: slot, in: context)
    health.entriesSaved(added.compactMap(HealthEntry.init))
    return added
  }

  func update(_ record: DiaryEntryRecord, with valid: EntryDraft.Valid) throws {
    try DiaryWrites.update(record, with: valid, in: context)
    health.entriesSaved([HealthEntry(record)].compactMap { $0 })
  }

  @discardableResult
  func remove(_ record: DiaryEntryRecord) throws -> DiaryWrites.Removed {
    let removed = try DiaryWrites.remove(record, in: context)
    health.entriesRemoved([removed.id])
    return removed
  }

  @discardableResult
  func restore(_ removed: DiaryWrites.Removed) throws -> DiaryEntryRecord {
    let record = try DiaryWrites.restore(removed, in: context)
    health.entriesSaved([HealthEntry(record)].compactMap { $0 })
    return record
  }
}
