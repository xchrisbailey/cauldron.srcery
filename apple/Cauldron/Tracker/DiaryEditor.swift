import CauldronKit
import Foundation
import SwiftData

/// The diary's changes, with Health kept in step: each one is made in the store (`DiaryWrites`)
/// and then handed to `HealthSync`, which does nothing unless Health is connected. A change that
/// is refused reaches neither. The macros widget is told after each change too: this is the one
/// place every diary write goes through.
@MainActor
struct DiaryEditor {
  let context: ModelContext
  var health: HealthSync = .shared
  var widget: TodayMacrosPublisher = .shared

  @discardableResult
  func add(_ entries: [NewEntry], on day: LocalDate, slot: MealSlot) throws -> [DiaryEntryRecord] {
    let added = try DiaryWrites.add(entries, on: day, slot: slot, in: context)
    health.diaryChanged(saved: added.compactMap(HealthEntry.init), removed: [], in: context)
    widget.publish(from: context)
    return added
  }

  func update(_ record: DiaryEntryRecord, with valid: EntryDraft.Valid) throws {
    try DiaryWrites.update(record, with: valid, in: context)
    health.diaryChanged(saved: [HealthEntry(record)].compactMap { $0 }, removed: [], in: context)
    widget.publish(from: context)
  }

  @discardableResult
  func remove(_ record: DiaryEntryRecord) throws -> DiaryWrites.Removed {
    let removed = try DiaryWrites.remove(record, in: context)
    health.diaryChanged(saved: [], removed: [removed.id], in: context)
    widget.publish(from: context)
    return removed
  }

  @discardableResult
  func restore(_ removed: DiaryWrites.Removed) throws -> DiaryEntryRecord {
    let record = try DiaryWrites.restore(removed, in: context)
    health.diaryChanged(saved: [HealthEntry(record)].compactMap { $0 }, removed: [], in: context)
    widget.publish(from: context)
    return record
  }
}
