import CauldronKit
import SwiftData
import SwiftUI

/// The editor's fields, over a draft binding.
struct RecipeEditorForm: View {
  @Binding var draft: RecipeDraft
  let recipe: RecipeRecord?
  /// What's wrong, once the cook has tried to save; nil before.
  let errors: RecipeDraft.Errors?
  let couldntSave: Bool
  /// Whether an estimate is being asked for, and what the last ask came to if it needs saying.
  var divining = false
  var divineMessage: CopyString?
  var onDivine: () -> Void = {}

  @Environment(RecipeAIService.self) private var ai: RecipeAIService?

  var body: some View {
    List {
      if let errors, !errors.isEmpty {
        Section {
          Text(verbatim: Copy.editor.fixErrors.text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.heat)
        }
        .listRowBackground(Brand.Colors.mantle)
      }
      if couldntSave {
        Section {
          Text(verbatim: Copy.editor.couldntSave.text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.heat)
        }
        .listRowBackground(Brand.Colors.mantle)
      }

      RecipePhotoSection(draft: $draft, recipe: recipe)

      Section {
        EditorField(
          label: Copy.editor.title, text: $draft.title, error: errors?[.title], axis: .vertical,
          optional: false)
        EditorField(
          label: Copy.editor.description, text: $draft.summary, error: errors?[.summary],
          axis: .vertical)
      }
      .listRowBackground(Brand.Colors.mantle)

      Section {
        EditorField(
          label: Copy.editor.servings, text: $draft.servings, error: errors?[.servings],
          mono: true, numeric: true)
        EditorField(
          label: Copy.editor.prepMinutes, text: $draft.prepMinutes, error: errors?[.prepMinutes],
          mono: true, numeric: true)
        EditorField(
          label: Copy.editor.cookMinutes, text: $draft.cookMinutes, error: errors?[.cookMinutes],
          mono: true, numeric: true)
        EditorField(
          label: Copy.editor.totalMinutes, text: $draft.totalMinutes,
          error: errors?[.totalMinutes], mono: true, numeric: true)
      }
      .listRowBackground(Brand.Colors.mantle)

      Section {
        divineRow
        EditorField(
          label: Copy.editor.macroFields.calories, text: $draft.calories,
          error: errors?[.calories], mono: true, numeric: true)
        EditorField(
          label: Copy.editor.macroFields.protein, text: $draft.protein, error: errors?[.protein],
          mono: true, numeric: true)
        EditorField(
          label: Copy.editor.macroFields.carbs, text: $draft.carbs, error: errors?[.carbs],
          mono: true, numeric: true)
        EditorField(
          label: Copy.editor.macroFields.fat, text: $draft.fat, error: errors?[.fat], mono: true,
          numeric: true)
      } header: {
        Text(verbatim: Copy.editor.macros.text)
      } footer: {
        macrosFooter
      }
      .listRowBackground(Brand.Colors.mantle)

      RecipeTagsSection(draft: $draft, error: errors?[.tags])

      Section {
        EditorField(
          label: Copy.editor.sourceUrl, text: $draft.sourceURL, error: errors?[.sourceURL],
          url: true)
      }
      .listRowBackground(Brand.Colors.mantle)

      RecipeIngredientsSection(draft: $draft, recipe: recipe, errors: errors)
      RecipeStepsSection(draft: $draft, recipe: recipe, errors: errors)

      Section {
        EditorField(
          label: Copy.editor.notes, text: $draft.notes, error: errors?[.notes], axis: .vertical)
      }
      .listRowBackground(Brand.Colors.mantle)
    }
    // A List, not a Form: on a Mac a Form lays a field out as a value to the right of a label.
    #if os(iOS)
      .listStyle(.insetGrouped)
    #else
      .listStyle(.inset)
    #endif
    #if os(iOS)
      // Reorder handles and delete controls on the lists' rows, without an Edit button to find.
      .environment(\.editMode, .constant(.active))
    #endif
    .scrollContentBackground(.hidden)
    .background(Brand.Colors.base)
    .foregroundStyle(Brand.Colors.ink)
  }
}

extension RecipeEditorForm {
  /// "Divine from ingredients", and how the AI stands when it needs attention. Hidden where
  /// there is no AI service.
  @ViewBuilder
  fileprivate var divineRow: some View {
    if let ai {
      VStack(alignment: .leading, spacing: 8) {
        Button(action: onDivine) {
          HStack(spacing: 8) {
            if divining { ProgressView().controlSize(.small) }
            Text(verbatim: (divining ? Copy.editor.divining : Copy.editor.divineMacros).text)
          }
        }
        .buttonStyle(RecipeActionButtonStyle())
        .disabled(divining)
        .frame(maxWidth: 320)
        if ai.status.needsAttention {
          AIStatusLine(status: ai.status)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
        }
      }
    }
  }

  /// Under the macro fields: a problem with the last ask, or that the numbers are an estimate
  /// to check, or that one is waiting for Save, or the usual hint.
  @ViewBuilder
  fileprivate var macrosFooter: some View {
    let typed = draft.typedMacros
    if let divineMessage {
      Text(verbatim: divineMessage.text).foregroundStyle(Brand.Colors.heat)
    } else if draft.estimateOnSave && typed == .none {
      Text(verbatim: Copy.recipeEditor.divineQueued.text)
    } else if typed != .none && typed == draft.estimatedMacros {
      Text(verbatim: Copy.editor.divined.text)
    } else {
      Text(verbatim: Copy.editor.macrosHint.text)
    }
  }
}

/// A labelled text field with its problem, if any, under it. Quantities are set in Geist Mono.
struct EditorField: View {
  let label: CopyString
  @Binding var text: String
  var error: CopyString?
  var axis: Axis = .horizontal
  var mono = false
  var numeric = false
  var url = false
  /// Shows "Optional" in an empty field, for everything but the title.
  var optional = true

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: label.text)
        .brandText(.control)
        .foregroundStyle(Brand.Colors.subtext)
      field
        .textFieldStyle(.plain)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandText(mono ? .quantity : .body)
        #if os(iOS)
          .keyboardType(numeric ? .numberPad : url ? .URL : .default)
          .textInputAutocapitalization(url ? .never : nil)
        #endif
        .autocorrectionDisabled(url || numeric)
        .accessibilityLabel(Text(verbatim: label.text))
      if let error {
        Text(verbatim: error.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.heat)
      }
    }
  }

  private var prompt: Text? {
    optional ? Text(verbatim: Copy.editor.optional.text) : nil
  }

  @ViewBuilder
  private var field: some View {
    if axis == .vertical {
      TextField("", text: $text, prompt: prompt, axis: .vertical).lineLimit(1...8)
    } else {
      TextField("", text: $text, prompt: prompt)
    }
  }
}
