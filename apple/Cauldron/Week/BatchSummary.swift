import CauldronKit
import SwiftData
import SwiftUI

struct BatchAllocationSummary {
  let title: String
  let total: Int
  let assigned: Int
  let hasInvalidEntries: Bool

  var remaining: Int { max(0, total - assigned) }
  var assignable: Int { isConflict ? 0 : remaining }
  var isConflict: Bool { hasInvalidEntries || assigned > total }
  var status: String {
    isConflict
      ? Copy.week.allocationConflict.text
      : Copy.week.spread.allocationStatus(remaining: remaining).text
  }
}

enum PlannedBatchDraftError: Error { case staleTotal }

struct PlannedBatchEditDraft {
  let openedTotal: Int
  var total: Int
  init(openedTotal: Int) { self.openedTotal = openedTotal; total = openedTotal }
  mutating func setTotal(_ value: Int) { total = value }
  var hasExplicitChange: Bool { total != openedTotal }
  func totalToCommit(currentTotal: Int) throws -> Int? {
    guard hasExplicitChange else { return nil }
    guard currentTotal == openedTotal else { throw PlannedBatchDraftError.staleTotal }
    return total
  }
  func availableServings(currentTotal: Int, assigned: Int) -> Int {
    max(0, (hasExplicitChange ? total : currentTotal) - assigned)
  }

  mutating func save(to batch: PlannedBatchRecord, in context: ModelContext) throws {
    guard let value = try totalToCommit(currentTotal: batch.totalServings) else { return }
    let previousTotal = batch.totalServings
    let previousUpdatedAt = batch.updatedAt
    do {
      try WeekPlan.commit(in: context) { try WeekPlan.editTotal(batch, to: value) }
      self = PlannedBatchEditDraft(openedTotal: batch.totalServings)
    } catch {
      batch.totalServings = previousTotal
      batch.updatedAt = previousUpdatedAt
      throw error
    }
  }

  mutating func assign(
    _ servings: Int, on day: LocalDate, slot: MealSlot, to batch: PlannedBatchRecord,
    in context: ModelContext
  ) throws {
    let previousTotal = batch.totalServings
    let previousUpdatedAt = batch.updatedAt
    do {
      let newTotal = try totalToCommit(currentTotal: previousTotal)
      try WeekPlan.commit(in: context) {
        if let newTotal { try WeekPlan.editTotal(batch, to: newTotal) }
        _ = try WeekPlan.assign(servings, on: day, slot: slot, to: batch, in: context)
      }
      self = PlannedBatchEditDraft(openedTotal: batch.totalServings)
    } catch {
      batch.totalServings = previousTotal
      batch.updatedAt = previousUpdatedAt
      throw error
    }
  }
}

struct BatchSummary: View {
  let batch: PlannedBatchRecord
  let onOpen: () -> Void

  private var allocation: WeekPlan.Allocation { WeekPlan.allocation(batch) }
  private var presentation: BatchAllocationSummary {
    BatchAllocationSummary(
      title: batch.title, total: allocation.total, assigned: allocation.assigned,
      hasInvalidEntries: allocation.isOverAssigned || allocation.hasInvalidEntries)
  }

  var body: some View {
    let conflict = presentation.isConflict
    Button(action: onOpen) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: batch.title).brandText(.body)
          Text(verbatim: Copy.week.spread.planned(allocation.assigned, allocation.total).text)
            .brandText(.quantity)
          Text(verbatim: presentation.status)
            .brandText(.quantity)
            .foregroundStyle(conflict ? Brand.Colors.heat : Brand.Colors.subtext)
        }
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(Brand.Colors.overlay1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(12)
    .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 12))
    .accessibilityHint(Text(verbatim: Copy.week.editBatch.text))
  }
}
