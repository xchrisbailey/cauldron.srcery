import CauldronKit
import SwiftData
import SwiftUI

/// "Brewed it today" on a recipe's page: marks the recipe cooked today, with the same write
/// brew mode makes at its last step. Afterwards the button says so, for a moment.
struct RecipeMarkBrewedAction: View {
  let recipe: RecipeRecord

  @Environment(\.modelContext) private var context
  @State private var confirmation: String?
  @State private var confirmationCount = 0

  var body: some View {
    Button(action: markBrewed) {
      Text(verbatim: confirmation ?? Copy.recipeView.markBrewed.text)
    }
    .buttonStyle(RecipeActionButtonStyle())
    .disabled(recipe.isBanished)
    .task(id: confirmationCount) {
      guard confirmation != nil else { return }
      try? await Task.sleep(for: .seconds(4))
      if !Task.isCancelled { confirmation = nil }
    }
  }

  private func markBrewed() {
    do {
      guard let today = RecipeCooking.today() else { throw RecipeCooking.NoDay() }
      try RecipeCooking.markCooked(recipe, on: today, context: context)
      say(Copy.recipeView.brewedToday.text)
    } catch {
      say(Copy.errors.internal.text)
    }
  }

  private func say(_ text: String) {
    confirmation = text
    confirmationCount += 1
    AccessibilityNotification.Announcement(text).post()
  }
}
