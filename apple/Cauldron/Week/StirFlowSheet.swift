import CauldronKit
import SwiftData
import SwiftUI

/// Stirring something into one meal: pick a recipe from the box (then choose the days it
/// feeds), or write a meal that isn't a recipe.
struct StirFlowSheet: View {
  let target: MealTarget
  /// The week being planned.
  let days: [LocalDate]
  let today: LocalDate
  /// Done: the sheet closes and the week says what happened.
  let onFinish: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Query(filter: #Predicate<RecipeRecord> { $0.deletedAt == nil })
  private var recipes: [RecipeRecord]
  @State private var search = ""
  @State private var searchCache = RecipeSearchCache()
  @State private var meal = ""
  @State private var problem: String?
  @State private var path: [UUID] = []

  /// The recipes the picker lists: the last cooked first until the cook searches.
  private var results: [RecipeRecord] {
    Self.matches(recipes, search: search, index: searchCache.index(for: recipes))
  }

  /// How many recipes the picker lists.
  static let limit = 30

  static func matches(
    _ recipes: [RecipeRecord], search: String, index: RecipeSearchIndex? = nil
  ) -> [RecipeRecord] {
    let words = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return Array(
      RecipeLibrary.visible(
        recipes, matching: words, sort: words.isEmpty ? .lastCooked : .recent, index: index
      ).prefix(limit))
  }

  var body: some View {
    NavigationStack(path: $path) {
      List {
        Section {
          TextField(text: $search) { Text(verbatim: Copy.week.searchRecipes.text) }
            .brandText(.body)
          if results.isEmpty {
            Text(verbatim: Copy.week.noMatches.text)
              .brandText(.body)
              .foregroundStyle(Brand.Colors.subtext)
          }
          ForEach(results) { recipe in
            NavigationLink(value: recipe.id) { row(recipe) }
          }
        }
        Section {
          HStack {
            TextField(text: $meal, prompt: Text(verbatim: Copy.week.writePlaceholder.text)) {
              Text(verbatim: Copy.week.orWrite.text)
            }
            .brandText(.body)
            .onSubmit(writeMeal)
            Button(action: writeMeal) { Text(verbatim: Copy.week.add.text) }
              .disabled(meal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        } header: {
          Text(verbatim: Copy.week.orWrite.text)
        }
        if let problem {
          Section { Text(verbatim: problem).foregroundStyle(Brand.Colors.heat) }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Brand.Colors.base)
      .navigationTitle(
        Text(
          verbatim: Copy.week.stirInto(
            WeekDates.label(target.day, long: true), Copy.week.slots[target.slot].text
          ).text)
      )
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
      .navigationDestination(for: UUID.self) { id in
        if let recipe = recipes.first(where: { $0.id == id }) {
          SpreadView(recipe: recipe, target: target, days: days, today: today) {
            onFinish($0)
          }
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 440, minHeight: 520)
    #endif
  }

  private func row(_ recipe: RecipeRecord) -> some View {
    HStack {
      Text(verbatim: recipe.title).brandText(.body).lineLimit(2)
      Spacer(minLength: 8)
      if let time = RecipeTimes.label(
        recipeMinutes(
          totalMinutes: recipe.totalMinutes, prepMinutes: recipe.prepMinutes,
          cookMinutes: recipe.cookMinutes))
      {
        Text(verbatim: time).brandText(.quantity).foregroundStyle(Brand.Colors.subtext)
      }
    }
  }

  private func writeMeal() {
    guard !meal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    do {
      try WeekPlan.commit(in: context) { try WeekPlan.stirText(meal, at: target, into: context) }
      onFinish(Copy.week.stirred(WeekDates.label(target.day, long: true)).text)
    } catch {
      problem = WeekPlan.message(for: error).text
    }
  }
}

/// A recipe dropped on a meal of the week: the same days step the picker leads to, opened
/// straight on the recipe, set to the dropped day and meal. `position` is where in the meal it
/// was dropped (nil for the end), and it holds while the meal is the one dropped on.
struct DroppedRecipeSheet: View {
  let recipe: RecipeRecord
  let target: MealTarget
  let position: Int?
  let days: [LocalDate]
  let today: LocalDate
  let onFinish: (String) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      SpreadView(
        recipe: recipe, target: target, days: days, today: today, position: position,
        onFinish: onFinish
      )
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
      .frame(minWidth: 440, minHeight: 520)
    #endif
  }
}

/// Choosing the days a recipe's servings feed, and how many go to each.
struct SpreadView: View {
  let recipe: RecipeRecord
  let target: MealTarget
  let today: LocalDate
  let position: Int?
  let onFinish: (String) -> Void

  @Environment(\.modelContext) private var context
  @State private var plan: SpreadPlan
  @State private var problem: String?

  init(
    recipe: RecipeRecord, target: MealTarget, days: [LocalDate], today: LocalDate,
    position: Int? = nil, onFinish: @escaping (String) -> Void
  ) {
    self.recipe = recipe
    self.target = target
    self.today = today
    self.position = position
    self.onFinish = onFinish
    _plan = State(
      initialValue: SpreadPlan(
        days: days, anchor: target.day, slot: target.slot, recipeServings: recipe.servings))
  }

  var body: some View {
    List {
      Section {
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
    .scrollContentBackground(.hidden)
    .background(Brand.Colors.base)
    .navigationTitle(Text(verbatim: recipe.title))
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
  }

  private func stir() {
    do {
      let placed = position.map {
        Placement(day: target.day, slot: target.slot, position: $0)
      }
      onFinish(try WeekPlan.stir(recipe, spread: plan, placed: placed, into: context))
    } catch {
      problem = WeekPlan.message(for: error).text
    }
  }
}
