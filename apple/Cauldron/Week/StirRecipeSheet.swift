import CauldronKit
import SwiftData
import SwiftUI

/// "Stir into the week" from a recipe's page: the day to start on and the meal, then the days
/// the batch feeds. A recipe that makes several servings starts out spread one a day from the
/// starting day, as meal prep, and the cook changes the days and servings from there.
struct StirRecipeSheet: View {
  let recipe: RecipeRecord
  /// The scale the cook chose on the recipe's page.
  let scale: Scale
  let today: LocalDate
  /// Done: the sheet closes, and this is what to tell the cook.
  let onStirred: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @State private var plan: SpreadPlan
  @State private var problem: String?

  init(
    recipe: RecipeRecord, scale: Scale, today: LocalDate, onStirred: @escaping (String) -> Void
  ) {
    self.recipe = recipe
    self.scale = scale
    self.today = today
    self.onStirred = onStirred
    _plan = State(initialValue: Self.startingPlan(recipe: recipe, scale: scale, today: today))
  }

  /// Where the sheet opens: today, in the default meal, with the scaled servings spread.
  static func startingPlan(recipe: RecipeRecord, scale: Scale, today: LocalDate) -> SpreadPlan {
    .batch(
      anchor: today, slot: WeekPlan.defaultSlot,
      servings: WeekPlan.batchServings(for: scale, recipeServings: recipe.servings))
  }

  /// Picking another starting day moves the spread with it.
  private var startingDay: Binding<LocalDate> {
    Binding(get: { plan.anchor }, set: { plan = plan.started(on: $0) })
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker(selection: startingDay) {
            ForEach(WeekPlan.upcoming(from: today), id: \.self) { day in
              Text(verbatim: dayName(day)).tag(day)
            }
          } label: {
            Text(verbatim: Copy.week.day.text)
          }
          Picker(selection: $plan.slot) {
            ForEach(MealSlot.allCases, id: \.self) { slot in
              Text(verbatim: Copy.week.slots[slot].text).tag(slot)
            }
          } label: {
            Text(verbatim: Copy.week.slot.text)
          }
        }
        SpreadSections(plan: $plan, today: today, problem: problem, onStir: stir)
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
      }
    }
    #if os(macOS)
      .frame(minWidth: 440, minHeight: 640)
    #endif
  }

  private func dayName(_ day: LocalDate) -> String {
    let label = WeekDates.label(day, long: true)
    return day == today ? "\(label) (\(Copy.week.today.text))" : label
  }

  private func stir() {
    do {
      let message = try WeekPlan.stir(recipe, spread: plan, into: context)
      dismiss()
      onStirred(message)
    } catch {
      problem = WeekPlan.message(for: error).text
    }
  }
}
