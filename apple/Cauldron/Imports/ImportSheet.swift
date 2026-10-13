import CauldronKit
import SwiftUI

/// Distill: a link or pasted text in, and the draft opens in the editor to review. One sheet
/// holds all of it, so the editor replaces the form in the same sheet; Cancel in the editor
/// closes the lot and nothing has been stored.
struct ImportSheet: View {
  let model: ImportModel
  /// Called with the saved recipe, just before the sheet closes.
  var onSaved: (RecipeRecord) -> Void = { _ in }
  /// Opens the recipe the draft duplicates; the sheet is closed by the caller.
  var onOpenDuplicate: (UUID) -> Void = { _ in }

  var body: some View {
    Group {
      if case .ready(let review) = model.phase {
        RecipeEditorSheet(
          recipe: nil, importing: review, onSaved: onSaved, onOpenDuplicate: onOpenDuplicate)
      } else {
        ImportStartSheet(model: model)
      }
    }
    // Closed any way at all, such as by a swipe: stop what is running.
    .onDisappear { model.discard() }
  }
}

/// The form, the wait and the failure: everything before there is a draft.
struct ImportStartSheet: View {
  @Bindable var model: ImportModel
  @Environment(\.dismiss) private var dismiss
  @Environment(RecipeAIService.self) private var ai: RecipeAIService?
  @FocusState private var focus: Field?

  private enum Field { case link, paste }

  var body: some View {
    // Modifiers that run work hang off the stack, not its content: inside it they crash an
    // `ImageRenderer` on iOS when the render is torn down, which is how the tests draw this.
    NavigationStack {
      content
        .navigationTitle(Copy.imports.title.text)
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button {
              model.discard()
              dismiss()
            } label: {
              Text(verbatim: Copy.recipeView.cancel.text)
            }
          }
        }
    }
    #if os(macOS)
      .frame(minWidth: 480, idealWidth: 540, minHeight: 520, idealHeight: 620)
    #endif
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .editing, .ready: form
    case .working: working
    case .failed(let notice): failed(notice)
    }
  }

  // MARK: The form

  private var form: some View {
    List {
      if let ai, ai.status.needsAttention {
        Section {
          AIStatusLine(status: ai.status)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
        }
        .listRowBackground(Brand.Colors.mantle)
      }

      Section {
        if let kept = model.pastingFor {
          Text(verbatim: Copy.importNative.pastingFor(kept).text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
            .fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: Copy.imports.link.text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
          TextField(
            "", text: $model.link, prompt: Text(verbatim: Copy.imports.linkPlaceholder.text)
          )
          .textFieldStyle(.plain)
          .brandText(.body)
          .focused($focus, equals: .link)
          .autocorrectionDisabled()
          #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
          #endif
          .onSubmit { model.start() }
          .accessibilityLabel(Text(verbatim: Copy.imports.link.text))
          if let error = model.linkError {
            Text(verbatim: error.text).brandText(.control).foregroundStyle(Brand.Colors.heat)
          }
        }
      } footer: {
        Text(verbatim: Copy.imports.linkHint.text)
      }
      .listRowBackground(Brand.Colors.mantle)

      Section {
        ZStack(alignment: .topLeading) {
          TextEditor(text: $model.text)
            .scrollContentBackground(.hidden)
            .brandText(.body)
            .focused($focus, equals: .paste)
            .frame(minHeight: 180)
            .disabled(model.pasteIsOff)
            .accessibilityLabel(Text(verbatim: Copy.imports.orPaste.text))
          if model.text.isEmpty {
            Text(verbatim: Copy.imports.pastePlaceholder.text)
              .brandText(.body)
              .foregroundStyle(Brand.Colors.overlay1)
              .padding(.top, 8)
              .padding(.leading, 5)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .opacity(model.pasteIsOff ? 0.4 : 1)
      } header: {
        Text(verbatim: Copy.imports.orPaste.text)
      } footer: {
        Text(verbatim: Copy.imports.pasteHint.text)
      }
      .listRowBackground(Brand.Colors.mantle)

      Section {
        if model.stopped {
          Text(verbatim: Copy.imports.stopped.text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
        }
        Button {
          model.start()
        } label: {
          Text(verbatim: Copy.imports.distill.text)
        }
        .buttonStyle(RecipeActionButtonStyle(.primary))
        .disabled(!model.canStart)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
      }
      .listRowBackground(Brand.Colors.mantle)

      #if DEBUG
        ImportLiveChecksSection(model: model)
      #endif
    }
    #if os(iOS)
      .listStyle(.insetGrouped)
    #else
      .listStyle(.inset)
    #endif
    .scrollContentBackground(.hidden)
    .background(Brand.Colors.base)
    .foregroundStyle(Brand.Colors.ink)
    .defaultFocus($focus, model.pastingFor == nil ? .link : .paste)
  }

  // MARK: Working and failed

  private var working: some View {
    VStack(spacing: 20) {
      ProgressView()
      Text(verbatim: Copy.imports.distilling.text)
        .brandText(.body)
        .foregroundStyle(Brand.Colors.subtext)
      Button {
        model.stop()
      } label: {
        Text(verbatim: Copy.imports.stop.text)
      }
      .buttonStyle(RecipeActionButtonStyle())
      .frame(maxWidth: 240)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Brand.Colors.base)
    .accessibilityElement(children: .contain)
  }

  private func failed(_ notice: ImportFailureNotice) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      if let ai, ai.status.needsAttention {
        AIStatusLine(status: ai.status)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
      }
      Text(verbatim: notice.message.text)
        .brandText(.body)
        .foregroundStyle(Brand.Colors.heat)
        .fixedSize(horizontal: false, vertical: true)
      VStack(spacing: 10) {
        if notice.canRetry {
          Button {
            model.retry()
          } label: {
            Text(verbatim: Copy.imports.tryAgain.text)
          }
          .buttonStyle(RecipeActionButtonStyle(notice.canPaste ? .secondary : .primary))
        }
        if notice.canPaste {
          Button {
            model.pasteInstead()
          } label: {
            Text(verbatim: Copy.imports.pasteInstead.text)
          }
          .buttonStyle(RecipeActionButtonStyle(.primary))
        }
        Button {
          model.another()
        } label: {
          Text(verbatim: Copy.imports.another.text)
        }
        .buttonStyle(RecipeActionButtonStyle())
      }
      .frame(maxWidth: 320)
      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Brand.Colors.base)
  }
}
