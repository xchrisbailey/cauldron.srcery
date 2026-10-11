import CauldronKit
import SwiftData
import SwiftUI

/// "Stir into the week" from a recipe's page: a day in the next two weeks, and a meal.
struct StirRecipeSheet: View {
  let recipe: RecipeRecord
  /// The scale the cook chose on the recipe's page.
  let scale: Scale
  let today: LocalDate
  /// Done: the sheet closes, and this is what to tell the cook.
  let onStirred: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @State private var day: LocalDate
  @State private var slot = MealSlot.dinner
  @State private var problem: String?

  init(
    recipe: RecipeRecord, scale: Scale, today: LocalDate, onStirred: @escaping (String) -> Void
  ) {
    self.recipe = recipe
    self.scale = scale
    self.today = today
    self.onStirred = onStirred
    _day = State(initialValue: today)
  }

  var body: some View {
    NavigationStack {
      Form {
        Picker(selection: $day) {
          ForEach(WeekPlan.upcoming(from: today), id: \.self) { day in
            Text(verbatim: dayName(day)).tag(day)
          }
        } label: {
          Text(verbatim: Copy.week.day.text)
        }
        Picker(selection: $slot) {
          ForEach(MealSlot.allCases, id: \.self) { slot in
            Text(verbatim: Copy.week.slots[slot].text).tag(slot)
          }
        } label: {
          Text(verbatim: Copy.week.slot.text)
        }
        if let problem {
          Text(verbatim: problem).foregroundStyle(Brand.Colors.heat)
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(Brand.Colors.base)
      .navigationTitle(Text(verbatim: Copy.week.stirIntoWeek.text))
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
          Button(action: stir) {
            Text(
              verbatim: Copy.week.stirInto(
                WeekDates.label(day, long: false), Copy.week.slots[slot].text
              ).text)
          }
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 400, minHeight: 240)
    #endif
  }

  private func dayName(_ day: LocalDate) -> String {
    let label = WeekDates.label(day, long: true)
    return day == today ? "\(label) (\(Copy.week.today.text))" : label
  }

  private func stir() {
    let servings = WeekPlan.servings(for: scale, recipeServings: recipe.servings)
    do {
      try WeekPlan.commit(in: context) {
        try WeekPlan.stir(
          recipe, at: MealTarget(day: day, slot: slot), servings: servings, into: context)
      }
      dismiss()
      onStirred(Copy.week.stirred(WeekDates.label(day, long: true)).text)
    } catch {
      problem = WeekPlan.message(for: error).text
    }
  }
}
