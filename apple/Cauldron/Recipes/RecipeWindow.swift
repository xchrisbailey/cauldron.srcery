import CauldronKit
import SwiftData
import SwiftUI

/// What opens a recipe window on the Mac: the recipe. A plain value, so a window can be opened
/// with it and restored by it, and opening the same recipe again brings its window forward.
struct RecipeWindowRequest: Codable, Hashable {
  var recipeID: UUID
}

/// What a recipe's window has to show.
enum RecipeWindowState {
  /// The recipe, ready to read.
  case open(RecipeRecord)
  /// Banished since the window opened (here or in another window); it can still be restored.
  case banished(RecipeRecord)
  /// No such recipe: purged, or it never synced to this device.
  case missing

  static func resolve(_ id: UUID, in recipes: [RecipeRecord]) -> RecipeWindowState {
    guard let recipe = recipes.first(where: { $0.id == id }) else { return .missing }
    return recipe.isBanished ? .banished(recipe) : .open(recipe)
  }
}

/// One recipe in a window of its own, so it can sit beside the week or the diary while you
/// cook or plan. It reads its recipe live, so a recipe banished or deleted while the window is
/// open turns the window into a short message instead of leaving it showing what is gone.
struct RecipeWindow: View {
  let request: RecipeWindowRequest

  @Query private var matches: [RecipeRecord]
  @State private var banishing = false

  init(request: RecipeWindowRequest) {
    self.request = request
    let id = request.recipeID
    _matches = Query(filter: #Predicate<RecipeRecord> { $0.id == id })
  }

  var body: some View {
    Group {
      switch RecipeWindowState.resolve(request.recipeID, in: matches) {
      case .open(let recipe):
        RecipeDetailView(recipe: recipe, inOwnWindow: true) { banishing = true }
          .navigationTitle(recipe.title)
          .confirmationDialog(
            Text(verbatim: Copy.recipes.banishConfirm(recipe.title).verb.text),
            isPresented: $banishing, titleVisibility: .visible
          ) {
            Button(role: .destructive) {
              RecipeLibrary.banish(recipe)
              banishing = false
            } label: {
              Text(verbatim: Copy.recipes.banishConfirm(recipe.title).verb.text)
            }
            Button(role: .cancel) {
            } label: {
              Text(verbatim: Copy.recipeView.cancel.text)
            }
          } message: {
            Text(verbatim: Copy.recipes.banishConfirm(recipe.title).confirm.text)
          }
      case .banished(let recipe):
        gone(Copy.recipeView.banished(recipe.title).text) {
          Button {
            RecipeLibrary.restore(recipe)
          } label: {
            Text(verbatim: Copy.recipeView.undo.text)
          }
        }
        .navigationTitle(recipe.title)
      case .missing:
        gone(Copy.recipeView.notFound.text) { EmptyView() }
          .navigationTitle(Copy.pageTitles.recipe.text)
      }
    }
    .foregroundStyle(Brand.Colors.ink)
    .background(Brand.Colors.base)
    #if os(macOS)
      .frame(minWidth: 520, minHeight: 480)
    #endif
  }

  private func gone(_ message: String, @ViewBuilder action: () -> some View) -> some View {
    VStack(spacing: 12) {
      Image(systemName: AppDestination.recipes.systemImage)
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(Brand.Colors.magic)
        .accessibilityHidden(true)
      Text(verbatim: message)
        .brandText(.body)
        .foregroundStyle(Brand.Colors.subtext)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
      action()
        .brandText(.control)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
