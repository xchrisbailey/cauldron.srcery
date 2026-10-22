import CauldronKit
import SwiftData
import SwiftUI

struct BatchAssignmentEditor: View {
  let entry: PlanEntryRecord
  let batch: PlannedBatchRecord

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @State private var day: LocalDate?
  @State private var slot: MealSlot
  @State private var servings: Int
  @State private var problem: String?

  init(entry: PlanEntryRecord, batch: PlannedBatchRecord) {
    self.entry = entry
    self.batch = batch
    _day = State(initialValue: entry.day ?? batch.weekStart?.weekDays().first)
    _slot = State(initialValue: entry.slot)
    let current = entry.servings
    _servings = State(
      initialValue: current.flatMap { (1...WeekLimits.servings).contains($0) ? $0 : nil } ?? 1)
  }

  private var days: [LocalDate] { batch.weekStart?.weekDays() ?? [] }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker(selection: $day) {
            ForEach(days, id: \.self) { value in
              Text(verbatim: WeekDates.label(value, long: true))
                .brandText(.quantity).tag(LocalDate?.some(value))
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
            ForEach(1...WeekLimits.servings, id: \.self) { value in
              Text(verbatim: String(value)).brandText(.quantity).tag(value)
            }
          } label: {
            Text(verbatim: Copy.week.servings.text)
          }
        } header: {
          Text(verbatim: Copy.week.invalidAssignment.text)
        }
        if let problem {
          Text(verbatim: problem).foregroundStyle(Brand.Colors.heat)
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
            .disabled(day == nil || days.isEmpty)
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 420, minHeight: 420)
    #endif
  }

  private func save() {
    guard let day else { return }
    do {
      try WeekPlan.commit(in: context) {
        var change = EntryChange()
        change.day = day
        change.slot = slot
        change.servings = .some(servings)
        try WeekPlan.apply(change, to: entry, in: context)
      }
      dismiss()
    } catch {
      problem = WeekPlan.message(for: error).text
    }
  }
}
