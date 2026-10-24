import CauldronKit
import SwiftData
import SwiftUI

struct PlannedBatchSheet: View {
  let batch: PlannedBatchRecord
  let onRemoved: () -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @State private var draft: PlannedBatchEditDraft
  @State private var day: LocalDate?
  @State private var slot = WeekPlan.defaultSlot
  @State private var servings = 1
  @State private var problem: String?
  @State private var confirmingRemoval = false
  @State private var editingEntry: PlanEntryRecord?

  init(batch: PlannedBatchRecord, onRemoved: @escaping () -> Void) {
    self.batch = batch
    self.onRemoved = onRemoved
    let week = batch.weekStart?.weekDays() ?? []
    _draft = State(initialValue: PlannedBatchEditDraft(openedTotal: batch.totalServings))
    _day = State(initialValue: week.first)
  }

  private var week: [LocalDate] { batch.weekStart?.weekDays() ?? [] }
  private var allocation: WeekPlan.Allocation { WeekPlan.allocation(batch) }
  private var draftSummary: BatchAllocationSummary {
    BatchAllocationSummary(
      title: batch.title, total: displayedTotal, assigned: allocation.assigned,
      hasInvalidEntries: allocation.hasInvalidEntries)
  }
  private var displayedTotal: Int { draft.hasExplicitChange ? draft.total : batch.totalServings }
  private var totalSelection: Binding<Int> {
    Binding(get: { displayedTotal }, set: { draft.setTotal($0) })
  }

  var body: some View {
    Form {
      Section {
        Picker(selection: totalSelection) {
          ForEach(1...WeekLimits.servings, id: \.self) { value in
            Text(verbatim: String(value)).brandText(.quantity).tag(value)
              .accessibilityIdentifier("week.batchEditor.totalOption.\(value)")
          }
        } label: {
          Text(verbatim: Copy.week.spread.total.text)
        }
        .accessibilityIdentifier("week.batchEditor.total")
        Text(verbatim: draftSummary.status)
          .brandText(.quantity)
          .foregroundStyle(
            draftSummary.isConflict ? Brand.Colors.heat : Brand.Colors.subtext)
      }
      Section {
        ForEach((batch.entries ?? []).sorted(by: entryOrder), id: \.persistentModelID) { entry in
          assignmentRow(entry)
        }
      } header: {
        Text(verbatim: Copy.week.spread.days.text)
      }
      Section {
        Picker(selection: $day) {
          ForEach(week, id: \.self) { value in
            Text(verbatim: WeekDates.label(value, long: true))
              .brandText(.quantity).tag(LocalDate?.some(value))
              .accessibilityIdentifier("week.batchEditor.dayOption.\(value.description)")
          }
        } label: {
          Text(verbatim: Copy.week.day.text)
        }
        .accessibilityIdentifier("week.batchEditor.day")
        Picker(selection: $slot) {
          ForEach(MealSlot.allCases, id: \.self) { value in
            Text(verbatim: Copy.week.slots[value].text)
              .tag(value)
              .accessibilityIdentifier("week.batchEditor.slotOption.\(value.rawValue)")
          }
        } label: {
          Text(verbatim: Copy.week.slot.text)
        }
        .accessibilityIdentifier("week.batchEditor.slot")
        Picker(selection: $servings) {
          ForEach(
            1...max(
              1,
              min(
                WeekLimits.servings,
                max(
                  1,
                  draft.availableServings(
                    currentTotal: batch.totalServings, assigned: allocation.assigned)))),
            id: \.self
          ) { value in
            Text(verbatim: String(value)).brandText(.quantity).tag(value)
              .accessibilityIdentifier("week.batchEditor.servingsOption.\(value)")
          }
        } label: {
          Text(verbatim: Copy.week.servings.text)
        }
        .accessibilityIdentifier("week.batchEditor.servings")
        Button(action: assign) {
          Text(verbatim: Copy.week.addAssignment.text)
        }
        .accessibilityIdentifier("week.batchEditor.assign")
        .disabled(week.isEmpty || draftSummary.assignable < servings)
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
        .accessibilityIdentifier("week.batchEditor.remove")
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
        .accessibilityIdentifier("week.batchEditor.cancel")
      }
      ToolbarItem(placement: .confirmationAction) {
        Button(action: save) { Text(verbatim: Copy.week.save.text) }
          .disabled(draft.total < allocation.assigned)
          .accessibilityIdentifier("week.batchEditor.save")
      }
    }
    .sheet(item: $editingEntry) { entry in
      BatchAssignmentEditor(entry: entry, batch: batch)
    }
    .confirmationDialog(
      Text(verbatim: Copy.week.removeBatchConfirm.text), isPresented: $confirmingRemoval,
      titleVisibility: .visible
    ) {
      Button(role: .destructive, action: removeBatch) {
        Text(verbatim: Copy.week.removeBatch.text)
      }
      .accessibilityIdentifier("week.batchEditor.confirmRemove")
      Button(role: .cancel) {
      } label: {
        Text(verbatim: Copy.week.cancel.text)
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
            ?? Copy.week.invalidAssignment.text
        )
        .brandText(.quantity)
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
      .accessibilityLabel(
        Text(
          verbatim: Copy.week.unassignEntry(
            day: entry.day.map { WeekDates.label($0, long: true) }
              ?? Copy.week.invalidAssignment.text,
            slot: Copy.week.slots[entry.slot].text,
            title: batch.title
          ).text))
      Button {
        editingEntry = entry
      } label: {
        Text(verbatim: Copy.week.editAssignment.text)
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
      try draft.save(to: batch, in: context)
      dismiss()
    } catch {
      problem =
        error is PlannedBatchDraftError
        ? Copy.week.batchChanged.text : WeekPlan.message(for: error).text
    }
  }

  private func unassign(_ entry: PlanEntryRecord) {
    do {
      try WeekPlan.commit(in: context) {
        if entry.day == nil {
          try WeekPlan.removeInvalid(entry, in: context)
        } else {
          _ = try WeekPlan.remove(entry, in: context)
        }
      }
    } catch {
      problem = WeekPlan.message(for: error).text
    }
  }

  private func assign() {
    guard let day else { return }
    do {
      try draft.assign(servings, on: day, slot: slot, to: batch, in: context)
      problem = nil
    } catch {
      problem =
        error is PlannedBatchDraftError
        ? Copy.week.batchChanged.text : WeekPlan.message(for: error).text
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
