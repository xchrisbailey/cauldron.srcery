import CauldronKit
import SwiftUI

/// "Stir into the week" on a recipe's page: opens the week's sheet to pick a day and a meal,
/// planning the servings the cook scaled the recipe to. A banished recipe can't be added.
/// Afterwards the button says where it went, for a moment.
struct RecipeAddToWeekAction: View {
  let recipe: RecipeRecord
  let scale: Scale
  /// Where the page keeps whether the sheet is open, so the Recipe menu can open it too.
  var isChoosing: Binding<Bool>?

  @State private var ownChoosing = false
  @State private var confirmation: String?
  @State private var confirmationCount = 0

  private var choosing: Binding<Bool> { isChoosing ?? $ownChoosing }

  var body: some View {
    Button {
      choosing.wrappedValue = true
    } label: {
      Text(verbatim: confirmation ?? Copy.week.stirIntoWeek.text)
    }
    .buttonStyle(RecipeActionButtonStyle())
    .disabled(recipe.isBanished)
    .sheet(isPresented: choosing) {
      StirRecipeSheet(recipe: recipe, scale: scale, today: WeekDates.today()) { text in
        choosing.wrappedValue = false
        confirmation = text
        confirmationCount += 1
        AccessibilityNotification.Announcement(text).post()
      }
    }
    .task(id: confirmationCount) {
      guard confirmation != nil else { return }
      try? await Task.sleep(for: .seconds(4))
      if !Task.isCancelled { confirmation = nil }
    }
  }
}
