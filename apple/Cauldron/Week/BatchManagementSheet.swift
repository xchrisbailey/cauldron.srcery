import CauldronKit
import SwiftData
import SwiftUI

struct BatchManagementButton: View {
  let batches: [PlannedBatchRecord]
  let action: () -> Void

  private var unassignedServings: Int {
    batches.reduce(0) { total, batch in
      total + WeekPlan.allocation(batch).unassigned
    }
  }

  private var conflictCount: Int {
    batches.filter {
      WeekPlan.allocation($0).isOverAssigned || WeekPlan.allocation($0).hasInvalidEntries
    }.count
  }

  var body: some View {
    Button(action: action) {
      VStack(alignment: .trailing, spacing: 1) {
        HStack(spacing: 6) {
          Text(verbatim: Copy.week.batches.text).brandText(.control)
          Text(verbatim: String(batches.count)).brandText(.quantity)
        }
        if unassignedServings > 0 {
          Text(verbatim: Copy.week.spread.remaining(unassignedServings).text)
            .brandText(.quantity)
            .foregroundStyle(Brand.Colors.heat)
        }
        if conflictCount > 0 {
          Text(verbatim: Copy.week.batchConflicts(conflictCount).text)
            .brandText(.quantity)
            .foregroundStyle(Brand.Colors.heat)
        }
      }
      .frame(minHeight: 44, alignment: .trailing)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("week.batches")
    .accessibilityLabel(
      Text(
        verbatim: Copy.week.batchButtonLabel(
          count: batches.count, unassigned: unassignedServings, conflicts: conflictCount
        ).text)
    )
    .accessibilityHint(Text(verbatim: Copy.week.editBatch.text))
  }
}

struct BatchManagementSheet: View {
  let weekStart: LocalDate
  let today: LocalDate
  @Query private var batches: [PlannedBatchRecord]

  @Environment(\.dismiss) private var dismiss
  @State private var planning = false

  init(weekStart: LocalDate, today: LocalDate) {
    self.weekStart = weekStart
    self.today = today
    let lower = weekStart.description
    let upper = weekStart.adding(days: 6).description
    _batches = Query(
      filter: #Predicate { $0.weekStartKey >= lower && $0.weekStartKey <= upper })
  }

  private var orderedBatches: [PlannedBatchRecord] {
    batches.sorted {
      $0.createdAt == $1.createdAt
        ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
    }
  }

  var body: some View {
    NavigationStack {
      List {
        if orderedBatches.isEmpty {
          ContentUnavailableView {
            Label(Copy.week.batches.text, systemImage: "square.stack.3d.up")
          } description: {
            Text(verbatim: Copy.week.empty.text)
          } actions: {
            Button(action: { planning = true }) {
              Text(verbatim: Copy.week.planRecipe.text)
            }
          }
          .listRowBackground(Color.clear)
        } else {
          ForEach(orderedBatches, id: \.id) { batch in
            NavigationLink(value: batch.id) {
              BatchManagementRow(batch: batch)
            }
            .accessibilityIdentifier("week.batch.\(batch.id.uuidString)")
          }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(Brand.Colors.base)
      .navigationTitle(Text(verbatim: Copy.week.batches.text))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            dismiss()
          } label: {
            Text(verbatim: Copy.week.done.text)
          }
          .accessibilityIdentifier("week.batches.done")
        }
        if !orderedBatches.isEmpty {
          #if os(iOS)
            ToolbarItem(placement: .bottomBar) {
              Button(action: { planning = true }) {
                Label(Copy.week.planRecipe.text, systemImage: "plus")
              }
            }
          #endif
        }
      }
      .navigationDestination(for: UUID.self) { id in
        if let batch = orderedBatches.first(where: { $0.id == id }) {
          PlannedBatchSheet(batch: batch, onRemoved: {})
        }
      }
      .sheet(isPresented: $planning) {
        StirFlowSheet(
          target: MealTarget(day: weekStart, slot: WeekPlan.defaultSlot),
          days: weekStart.weekDays(), today: today
        ) { text in
          planning = false
          AccessibilityNotification.Announcement(text).post()
        }
      }
    }
    .background(Brand.Colors.base)
    .presentationDetents([.large])
  }
}

private struct BatchManagementRow: View {
  let batch: PlannedBatchRecord

  private var allocation: WeekPlan.Allocation { WeekPlan.allocation(batch) }
  private var summary: BatchAllocationSummary {
    BatchAllocationSummary(
      title: batch.title, total: allocation.total, assigned: allocation.assigned,
      hasInvalidEntries: allocation.hasInvalidEntries)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: batch.title)
        .brandText(.body)
        .fixedSize(horizontal: false, vertical: true)
      Text(verbatim: Copy.week.spread.planned(allocation.assigned, allocation.total).text)
        .brandText(.quantity)
      if summary.isConflict || summary.remaining > 0 {
        Text(verbatim: summary.status)
          .brandText(.quantity)
          .foregroundStyle(summary.isConflict ? Brand.Colors.heat : Brand.Colors.subtext)
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
    .accessibilityHint(Text(verbatim: Copy.week.editBatch.text))
  }
}
