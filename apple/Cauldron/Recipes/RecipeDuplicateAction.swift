import CauldronKit
import SwiftUI

/// The editor on a fresh copy of a recipe, with a short line saying a copy was made, as the
/// web opens the copy's edit page and says so. The copy is already saved: Cancel keeps it.
struct RecipeCopySheet: View {
  let copy: RecipeRecord

  @State private var saying = true

  var body: some View {
    RecipeEditorSheet(recipe: copy)
      .safeAreaInset(edge: .bottom) {
        if saying {
          RecipeNoticeBanner(notice: .duplicated, onUndo: {})
            .padding(.bottom, 12)
            .transition(.opacity)
        }
      }
      .task {
        AccessibilityNotification.Announcement(RecipeNotice.duplicated.text).post()
        try? await Task.sleep(for: .seconds(4))
        if !Task.isCancelled { withAnimation { saying = false } }
      }
  }
}
