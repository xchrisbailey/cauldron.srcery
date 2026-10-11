import SwiftUI

/// The add sheet's "Recipe" way in (#180): log a recipe by servings.
///
/// Fill in `body`, and set `isAvailable` to true so the sheet shows the tab. Nothing else
/// needs to change: log with `context.log([NewEntry(...)])`, which closes the sheet when it
/// works and returns the message to show when it doesn't.
struct AddRecipeTab: View {
  /// False until the tab is built; the sheet hides it.
  static let isAvailable = false

  let context: AddContext

  var body: some View {
    EmptyView()
  }
}
