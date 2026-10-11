import CauldronKit
import SwiftData
import SwiftUI

/// Log a recipe from outside the diary: a recipe's page, or a planned meal in the week. It asks
/// for the servings, the meal and the day, starting from the ones it is given, and logs through
/// the diary's editor so Health follows.
///
/// To place it: `RecipeLogSheet(recipe:, servings:, day:, slot:, onClose:)`, presented as a sheet.
/// `slot` and `day` default to the meal the hour suggests today.
struct RecipeLogSheet: View {
  let recipe: RecipeRecord
  let servings: Double
  let day: LocalDate?
  let slot: MealSlot?
  let onClose: () -> Void

  @Environment(\.modelContext) private var context

  init(
    recipe: RecipeRecord, servings: Double = 1, day: LocalDate? = nil, slot: MealSlot? = nil,
    onClose: @escaping () -> Void
  ) {
    self.recipe = recipe
    self.servings = servings
    self.day = day
    self.slot = slot
    self.onClose = onClose
  }

  var body: some View {
    NavigationStack {
      Group {
        if let start = day ?? TargetsForm.today() {
          RecipeLogForm(
            recipe: recipe,
            draft: RecipeLogDraft(
              slot: slot ?? suggestedSlot(hour: Calendar.current.component(.hour, from: .now)),
              day: start, servings: servings),
            chooseSlot: true, chooseDay: true, onLog: log)
        } else {
          Text(verbatim: Copy.tracker.diary.couldntLoad.text)
        }
      }
      .navigationTitle(Copy.tracker.logRecipe.title.text)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(Copy.tracker.entry.cancel.text, action: onClose)
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 420, minHeight: 520)
    #endif
  }

  private func log(_ draft: RecipeLogDraft) -> CopyString? {
    guard let new = draft.entry(for: recipe) else { return Copy.tracker.targets.fixThese }
    do {
      try DiaryEditor(context: context).add([new], on: draft.day, slot: draft.slot)
      onClose()
      return nil
    } catch DiaryWrites.Failure.dayFull {
      return Copy.tracker.dayFull
    } catch DiaryWrites.Failure.invalid {
      return Copy.tracker.targets.fixThese
    } catch {
      return Copy.tracker.diary.couldntSave
    }
  }
}
