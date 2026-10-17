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

  /// Copies a day, or one meal of it, onto the end of `target`. Entries still waiting for an
  /// estimate wait there too, each with a job of its own.
  @discardableResult
  func copy(from source: LocalDate, to target: LocalDate, slot: MealSlot? = nil) throws
    -> [DiaryEntryRecord]
  {
    let copies = try DiaryWrites.copy(from: source, to: target, slot: slot, in: context)
    guard !copies.isEmpty else { return [] }
    for record in copies where record.macrosPending {
      AIJobQueue.enqueueMeal(record.name, for: record, in: context)
    }
    if copies.contains(where: \.macrosPending) { try? context.save() }
    health.diaryChanged(saved: copies.compactMap(HealthEntry.init), removed: [], in: context)
    widget.publish(from: context)
    return copies
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
