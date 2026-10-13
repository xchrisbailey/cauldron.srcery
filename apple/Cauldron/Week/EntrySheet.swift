import CauldronKit
import SwiftUI

/// Changing one planned meal: its servings (or its name, for a meal that isn't a recipe), the
/// day and meal it sits in, and its place among the others there. The way to move a meal
/// without dragging it.
struct EntrySheet: View {
  let meal: PlanEntry
  /// The days it can move to.
  let days: [LocalDate]
  /// Meals in its slot, for moving it up or down.
  let slotSize: Int
  let onSave: (EntryChange) -> Void
  /// Moves it one place up (-1) or down (1) in its meal.
  let onShift: (Int) -> Void
  let onRemove: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var draft: PlannedMealDraft

  init(
    meal: PlanEntry, days: [LocalDate], slotSize: Int, onSave: @escaping (EntryChange) -> Void,
    onShift: @escaping (Int) -> Void, onRemove: @escaping () -> Void
  ) {
    self.meal = meal
    self.days = days
    self.slotSize = slotSize
    self.onSave = onSave
    self.onShift = onShift
    self.onRemove = onRemove
    _draft = State(initialValue: PlannedMealDraft(meal))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          if draft.canRename {
            TextField(text: $draft.title) { Text(verbatim: Copy.week.meal.text) }
          } else {
            Picker(selection: $draft.servings) {
              Text(verbatim: Copy.week.sameServings(meal.recipe?.servings).text)
                .tag(Int?.none)
              ForEach(1...WeekLimits.servings, id: \.self) { n in
                Text(verbatim: String(n)).tag(Int?.some(n))
              }
            } label: {
              Text(verbatim: Copy.week.servings.text)
            }
          }
        }
        Section {
          Picker(selection: $draft.day) {
            ForEach(days, id: \.self) { day in
              Text(verbatim: WeekDates.label(day, long: true)).tag(day)
            }
          } label: {
            Text(verbatim: Copy.week.day.text)
          }
          Picker(selection: $draft.slot) {
            ForEach(MealSlot.allCases, id: \.self) { slot in
              Text(verbatim: Copy.week.slots[slot].text).tag(slot)
            }
          } label: {
            Text(verbatim: Copy.week.slot.text)
          }
        }
        if slotSize > 1 {
          Section {
            Button {
              onShift(-1)
            } label: {
              Text(verbatim: Copy.week.moveUp.text)
            }
            .disabled(meal.position == 0)
            Button {
              onShift(1)
            } label: {
              Text(verbatim: Copy.week.moveDown.text)
            }
            .disabled(meal.position >= slotSize - 1)
          }
        }
        Section {
          Button(role: .destructive, action: onRemove) {
            Text(verbatim: Copy.week.remove.text)
          }
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(Brand.Colors.base)
      .navigationTitle(Text(verbatim: meal.recipe?.title ?? meal.title))
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
          Button {
            if let change = draft.change { onSave(change) }
            dismiss()
          } label: {
            Text(verbatim: Copy.week.save.text)
          }
          .disabled(!draft.isValid)
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 400, minHeight: 440)
    #endif
  }
}
