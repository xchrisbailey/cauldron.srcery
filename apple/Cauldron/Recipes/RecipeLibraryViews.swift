import CauldronKit
import SwiftUI

/// What the library says when a search or a tag matches no recipe, with the way back.
struct NoMatchesView: View {
  let onClear: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(Brand.Colors.magic)
        .accessibilityHidden(true)
      Text(verbatim: Copy.library.noMatches.text)
        .brandText(.body)
        .foregroundStyle(Brand.Colors.subtext)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
      Button(action: onClear) {
        Text(verbatim: Copy.library.clearFilters.text)
      }
      .buttonStyle(.brandProminent)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Brand.Colors.base)
  }
}

/// A tag's new name. It stays open with what is wrong with the name until the name is good.
struct TagRenameSheet: View {
  /// The tag's name now.
  let name: String
  /// Renames the tag; what went wrong, or nil when it worked.
  let onRename: (String) -> RecipeTagRename.Failure?
  @State private var text = ""
  @State private var failure: RecipeTagRename.Failure?
  @FocusState private var focused: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(verbatim: Copy.libraryNative.renameTagTitle(name).text)
        .brandText(.section)
      TextField(Copy.libraryNative.renameTagField.text, text: $text)
        .brandText(.body)
        .textFieldStyle(.plain)
        .padding(12)
        .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(failure == nil ? Brand.Colors.surface0 : Brand.Colors.heat, lineWidth: 1)
        )
        .focused($focused)
        .autocorrectionDisabled()
        .onSubmit(save)
        .onChange(of: text) { failure = nil }
      if let failure {
        Text(verbatim: failure.message.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.heat)
      }
      HStack {
        Spacer()
        Button(role: .cancel) {
          dismiss()
        } label: {
          Text(verbatim: Copy.recipeView.cancel.text)
        }
        .keyboardShortcut(.cancelAction)
        Button(action: save) {
          Text(verbatim: Copy.libraryNative.renameTagSave.text)
        }
        .buttonStyle(.brandProminent)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .background(Brand.Colors.base)
    #if os(macOS)
      .frame(minWidth: 380)
    #else
      .presentationDetents([.height(240)])
    #endif
    .onAppear {
      text = name
      focused = true
    }
  }

  private func save() {
    if let failure = onRename(text) {
      self.failure = failure
    } else {
      dismiss()
    }
  }
}
