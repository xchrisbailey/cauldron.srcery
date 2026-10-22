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
  let onCommit: ((EntryChange) throws -> Void)?
  let limits: PlannedEntryLimits?
  let onEditBatch: (() -> Void)?
  /// Moves it one place up (-1) or down (1) in its meal.
  let onShift: (Int) -> Void
  let onRemove: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var draft: PlannedMealDraft
  @State private var problem: String?

  init(
    meal: PlanEntry, days: [LocalDate], slotSize: Int, onSave: @escaping (EntryChange) -> Void,
    onShift: @escaping (Int) -> Void, onRemove: @escaping () -> Void,
    limits: PlannedEntryLimits? = nil, onEditBatch: (() -> Void)? = nil,
    onCommit: ((EntryChange) throws -> Void)? = nil
  ) {
    self.meal = meal
    self.days = days
    self.slotSize = slotSize
    self.onSave = onSave
    self.onCommit = onCommit
    self.limits = limits
    self.onEditBatch = onEditBatch
    self.onShift = onShift
    self.onRemove = onRemove
    _draft = State(initialValue: PlannedMealDraft(meal, allowsBatchServingEdits: limits != nil))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          if draft.canRename {
            TextField(text: $draft.title) { Text(verbatim: Copy.week.meal.text) }
          }
          if draft.canEditServings {
            Picker(selection: $draft.servings) {
              if limits == nil {
                Text(verbatim: Copy.week.sameServings(meal.recipe?.servings).text)
                  .tag(Int?.none)
              } else if draft.servings == nil {
                Text(verbatim: Copy.week.invalidAssignment.text).tag(Int?.none)
              }
              ForEach(servingChoices, id: \.self) { n in
                Text(verbatim: String(n)).brandText(.quantity).tag(Int?.some(n))
              }
            } label: {
              Text(verbatim: Copy.week.servings.text)
            }
          }
          if let onEditBatch {
            Button(action: onEditBatch) {
              Text(verbatim: Copy.week.spread.total.text)
            }
          }
        }
        Section {
          Picker(selection: $draft.day) {
            ForEach(availableDays, id: \.self) { day in
              Text(verbatim: WeekDates.label(day, long: true)).brandText(.quantity).tag(day)
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
        if let problem {
          Section { Text(verbatim: problem).foregroundStyle(Brand.Colors.subtext) }
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
            guard let change = draft.change else { dismiss(); return }
            do {
              if let onCommit { try onCommit(change) } else { onSave(change) }
              dismiss()
            } catch {
              problem = WeekPlan.message(for: error).text
            }
          } label: {
            Text(verbatim: Copy.week.save.text)
          }
          .disabled(!isDraftValid)
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 400, minHeight: 440)
    #endif
  }

  private var availableDays: [LocalDate] {
    guard let limits else { return days }
    return limits.days.contains(draft.day) ? limits.days : [draft.day] + limits.days
  }

  private var servingChoices: [Int] {
    guard let limits else { return Array(1...WeekLimits.servings) }
    return Set(
      (limits.maxServings > 0 ? Array(1...limits.maxServings) : [])
        + [draft.servings].compactMap { $0 }
    )
    .sorted()
  }

  private var isDraftValid: Bool {
    guard draft.isValid else { return false }
    return limits?.allows(day: draft.day, servings: draft.servings) ?? true
  }
}
