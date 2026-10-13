import CauldronKit
import SwiftData
import SwiftUI

/// The editor in its own window: a new recipe, or the one given. It changes a `RecipeDraft`,
/// so Cancel changes nothing and Save writes the whole of it at once.
struct RecipeEditorSheet: View {
  let recipe: RecipeRecord?
  /// Called with the saved recipe, just before the sheet closes.
  var onSaved: (RecipeRecord) -> Void = { _ in }

  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @Environment(RecipeAIService.self) private var ai: RecipeAIService?
  @State private var draft: RecipeDraft
  private let initial: RecipeDraft
  /// Problems show once Save has been tried, and then follow the cook's fixes.
  @State private var triedToSave = false
  @State private var couldntSave = false
  @State private var confirmingLeave = false
  @State private var divining = false
  @State private var divineMessage: CopyString?

  init(recipe: RecipeRecord?, onSaved: @escaping (RecipeRecord) -> Void = { _ in }) {
    self.recipe = recipe
    self.onSaved = onSaved
    let start = recipe.map(RecipeDraft.init) ?? RecipeDraft()
    initial = start
    _draft = State(initialValue: start)
  }

  private var isDirty: Bool { draft != initial }

  var body: some View {
    NavigationStack {
      RecipeEditorForm(
        draft: $draft, recipe: recipe, errors: triedToSave ? draft.validate() : nil,
        couldntSave: couldntSave, divining: divining, divineMessage: divineMessage,
        onDivine: divine
      )
      .navigationTitle(
        recipe == nil ? Copy.editor.newTitle.text : Copy.editor.editTitle.text
      )
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            if isDirty { confirmingLeave = true } else { dismiss() }
          } label: {
            Text(verbatim: Copy.recipeView.cancel.text)
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(action: save) {
            Text(verbatim: Copy.editor.save.text)
          }
        }
      }
    }
    .interactiveDismissDisabled(isDirty)
    .confirmationDialog(
      Text(verbatim: Copy.editor.leaveTitle.text), isPresented: $confirmingLeave,
      titleVisibility: .visible
    ) {
      Button(role: .destructive) {
        dismiss()
      } label: {
        Text(verbatim: Copy.editor.leave.text)
      }
      Button(role: .cancel) {
      } label: {
        Text(verbatim: Copy.editor.stay.text)
      }
    } message: {
      Text(verbatim: Copy.editor.leaveBody.text)
    }
    #if os(macOS)
      .frame(minWidth: 560, idealWidth: 640, minHeight: 640, idealHeight: 760)
    #endif
  }

  /// Estimates the macros from the ingredients as they are now, into the draft. Nothing is
  /// stored until Save, so Cancel leaves nothing behind. If Gemini can't be reached, Save
  /// queues the estimate for the saved recipe instead.
  private func divine() {
    guard let ai, !divining else { return }
    divining = true
    divineMessage = nil
    let input = draft.estimateInput
    Task {
      let outcome = await RecipeMacroEstimates.divine(input, using: ai)
      draft.apply(outcome)
      switch outcome {
      case .needsIngredients: divineMessage = Copy.editor.divineNeedsIngredients
      case .failed: divineMessage = Copy.editor.divineFailed
      case .filled, .queued, .cancelled: break
      }
      divining = false
    }
  }

  private func save() {
    couldntSave = false
    do {
      let saved = try RecipeSaver.save(draft, into: recipe, context: context)
      // An estimate that couldn't be had while editing is asked for now, with the saved
      // ingredients; if Gemini is still out of reach it waits in the queue.
      if RecipeMacroEstimates.queueAfterSave(of: draft, saved: saved, in: context), let ai {
        let context = context
        Task { await AIJobQueue.drain(in: context, using: ai.estimator) }
      }
      onSaved(saved)
      dismiss()
    } catch RecipeSaver.Failure.invalid {
      triedToSave = true
    } catch {
      triedToSave = true
      couldntSave = true
    }
  }
}
