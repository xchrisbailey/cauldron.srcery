import CauldronKit
import SwiftData
import SwiftUI

struct PlannedBatchSheet: View {
  let batch: PlannedBatchRecord
  let onRemoved: () -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @State private var total: Int
  @State private var day: LocalDate?
  @State private var slot = WeekPlan.defaultSlot
  @State private var servings = 1
  @State private var problem: String?
  @State private var confirmingRemoval = false

  init(batch: PlannedBatchRecord, onRemoved: @escaping () -> Void) {
    self.batch = batch
    self.onRemoved = onRemoved
    let week = batch.weekStart?.weekDays() ?? []
    _total = State(initialValue: batch.totalServings)
    _day = State(initialValue: week.first)
  }

  private var week: [LocalDate] { batch.weekStart?.weekDays() ?? [] }
  private var allocation: WeekPlan.Allocation { WeekPlan.allocation(batch) }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker(selection: $total) {
            ForEach(1...WeekLimits.servings, id: \.self) { value in
              Text(verbatim: String(value)).tag(value)
            }
          } label: {
            Text(verbatim: Copy.week.spread.total.text)
          }
          Text(
            verbatim: allocation.isOverAssigned || allocation.hasInvalidEntries
              ? Copy.week.allocationConflict.text
              : Copy.week.spread.allocationStatus(
                remaining: max(0, total - allocation.assigned)
              ).text
          )
          .brandText(.quantity)
          .foregroundStyle(
            allocation.isOverAssigned || allocation.hasInvalidEntries
              ? Brand.Colors.heat : Brand.Colors.subtext)
        }
        Section {
          ForEach((batch.entries ?? []).sorted(by: entryOrder), id: \.id) { entry in
            assignmentRow(entry)
          }
        } header: {
          Text(verbatim: Copy.week.spread.days.text)
        }
        Section {
          Picker(selection: $day) {
            ForEach(week, id: \.self) { value in
              Text(verbatim: WeekDates.label(value, long: true)).tag(LocalDate?.some(value))
            }
          } label: {
            Text(verbatim: Copy.week.day.text)
          }
          Picker(selection: $slot) {
            ForEach(MealSlot.allCases, id: \.self) { value in
              Text(verbatim: Copy.week.slots[value].text).tag(value)
            }
          } label: {
            Text(verbatim: Copy.week.slot.text)
          }
          Picker(selection: $servings) {
            ForEach(
              1...max(1, min(WeekLimits.servings, max(1, total - allocation.assigned))), id: \.self
            ) { value in
              Text(verbatim: String(value)).tag(value)
            }
          } label: {
            Text(verbatim: Copy.week.servings.text)
          }
          Button(action: assign) {
            Text(verbatim: Copy.week.addAssignment.text)
          }
          .disabled(week.isEmpty || allocation.unassigned <= 0)
        } header: {
          Text(verbatim: Copy.week.addAssignment.text)
        }
        if let problem {
          Text(verbatim: problem).foregroundStyle(Brand.Colors.heat)
        }
        Section {
          Button(role: .destructive) {
            confirmingRemoval = true
          } label: {
            Text(verbatim: Copy.week.removeBatch.text)
          }
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(Brand.Colors.base)
      .navigationTitle(Text(verbatim: batch.title))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Text(verbatim: Copy.week.cancel.text)
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(action: save) { Text(verbatim: Copy.week.save.text) }
            .disabled(total < allocation.assigned)
        }
      }
      .confirmationDialog(
        Text(verbatim: Copy.week.removeBatchConfirm.text), isPresented: $confirmingRemoval,
        titleVisibility: .visible
      ) {
        Button(role: .destructive, action: removeBatch) {
          Text(verbatim: Copy.week.removeBatch.text)
        }
        Button(role: .cancel) {
        } label: {
          Text(verbatim: Copy.week.cancel.text)
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 440, minHeight: 600)
    #endif
  }

  private func assignmentRow(_ entry: PlanEntryRecord) -> some View {
    HStack {
      VStack(alignment: .leading) {
        Text(
          verbatim: entry.day.map { WeekDates.label($0, long: true) }
            ?? Copy.week.invalidAssignment.text)
        Text(verbatim: Copy.week.slots[entry.slot].text).brandText(.control)
      }
      Spacer()
      Text(
        verbatim: entry.servings.map { Copy.week.spread.servingsOn($0).text }
          ?? Copy.week.invalidAssignment.text
      )
      .brandText(.quantity)
      Button(role: .destructive) {
        unassign(entry)
      } label: {
        Text(verbatim: Copy.week.unassign.text)
      }
      .buttonStyle(.borderless)
    }
  }

  private func entryOrder(_ lhs: PlanEntryRecord, _ rhs: PlanEntryRecord) -> Bool {
    if lhs.dayKey != rhs.dayKey { return lhs.dayKey < rhs.dayKey }
    if lhs.slot != rhs.slot {
      return (MealSlot.allCases.firstIndex(of: lhs.slot) ?? 0)
        < (MealSlot.allCases.firstIndex(of: rhs.slot) ?? 0)
    }
    return lhs.position < rhs.position
  }

  private func save() {
    do {
      try WeekPlan.commit(in: context) { try WeekPlan.editTotal(batch, to: total) }
      dismiss()
    } catch {
      problem = WeekPlan.message(for: error).text
    }
  }

  private func unassign(_ entry: PlanEntryRecord) {
    do {
      try WeekPlan.commit(in: context) { _ = try WeekPlan.remove(entry, in: context) }
    } catch {
      problem = WeekPlan.message(for: error).text
    }
  }

  private func assign() {
    guard let day else { return }
    do {
      try WeekPlan.commit(in: context) {
        _ = try WeekPlan.assign(servings, on: day, slot: slot, to: batch, in: context)
      }
      problem = nil
    } catch {
      problem = WeekPlan.message(for: error).text
    }
  }

  private func removeBatch() {
    do {
      try WeekPlan.commit(in: context) { WeekPlan.removeBatch(batch, in: context) }
      onRemoved()
      dismiss()
    } catch {
      problem = WeekPlan.message(for: error).text
    }
  }
}
