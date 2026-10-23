import CauldronImports
import CauldronKit
import SwiftUI

/// Visible corrections share the model's draft with Save and continuation; no local text copy.
struct ShareSheetFields: View {
  let model: ShareSheetModel
  let focus: FocusState<RecipeDraft.Field?>.Binding
  let accessibilityFocus: AccessibilityFocusState<RecipeDraft.Field?>.Binding
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric private var bodySize = 15

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      field(.title, Copy.editor.title, \.title)
      field(.servings, Copy.editor.servings, \.servings)
      timeLayout { times }
    }
    #if os(iOS)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Button(Copy.shareSheetFields.next.text) { advance() }
          .disabled(focus.wrappedValue == .cookMinutes)
          Spacer()
          Button(Copy.editor.done.text) { focus.wrappedValue = nil }
        }
      }
    #endif
  }

  private var timeLayout: AnyLayout {
    typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
  }

  private var times: some View {
    Group {
      field(.prepMinutes, Copy.editor.prepMinutes, \.prepMinutes)
      field(.cookMinutes, Copy.editor.cookMinutes, \.cookMinutes)
    }
  }

  private func binding(_ keyPath: WritableKeyPath<RecipeDraft, String>) -> Binding<String> {
    Binding(
      get: { model.currentDraft?[keyPath: keyPath] ?? "" },
      set: { value in
        guard var draft = model.currentDraft else { return }
        draft[keyPath: keyPath] = value
        model.currentDraft = draft
      })
  }

  private func field(
    _ field: RecipeDraft.Field, _ label: CopyString,
    _ keyPath: WritableKeyPath<RecipeDraft, String>
  ) -> some View {
    let error = model.error(for: field)
    return VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: label.text)
        .font(ShareFonts.font(size: bodySize - 2, weight: 500))
        .foregroundStyle(Brand.Colors.subtext)
      entry(field, keyPath)
        .textFieldStyle(.plain)
        .font(
          field == .title
            ? ShareFonts.font(size: bodySize + 3, weight: 600) : ShareFonts.mono(size: bodySize)
        )
        .foregroundStyle(Brand.Colors.ink)
        .padding(10)
        .frame(minHeight: 44)
        .background(Brand.Colors.mantle, in: .rect(cornerRadius: 8))
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(error == nil ? Brand.Colors.surface0 : Brand.Colors.heat, lineWidth: 1)
        }
        .focused(focus, equals: field)
        .accessibilityFocused(accessibilityFocus, equals: field)
        .accessibilityLabel(Text(verbatim: label.text))
        .accessibilityHint(
          // copylint:ignore -- empty hint when there is no field error
          Text(verbatim: error?.text ?? "")
        )
        .submitLabel(field == .cookMinutes ? .done : .next)
        .onSubmit { advance() }
      if let error {
        Text(verbatim: error.text)
          .font(ShareFonts.font(size: bodySize - 2, weight: 400))
          .foregroundStyle(Brand.Colors.heat)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .id(field)
  }

  @ViewBuilder private func entry(
    _ field: RecipeDraft.Field, _ keyPath: WritableKeyPath<RecipeDraft, String>
  ) -> some View {
    if field == .title {
      TextField("", text: binding(keyPath), axis: .vertical).lineLimit(1...5)
    } else {
      TextField("", text: binding(keyPath), prompt: Text(verbatim: Copy.editor.optional.text))
        .autocorrectionDisabled()
        #if os(iOS)
          .keyboardType(.numberPad)
        #endif
    }
  }

  private func advance() {
    guard let field = focus.wrappedValue,
      let index = ShareSheetModel.editableFields.firstIndex(of: field)
    else { return }
    let next = index + 1
    focus.wrappedValue =
      next < ShareSheetModel.editableFields.count
      ? ShareSheetModel.editableFields[next] : nil
  }
}
