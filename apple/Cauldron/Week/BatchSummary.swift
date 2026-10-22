import CauldronKit
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
            .brandText(.control)
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
