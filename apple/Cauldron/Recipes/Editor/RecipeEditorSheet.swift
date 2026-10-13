import CauldronKit
import SwiftData
import SwiftUI

/// The editor in its own window: a new recipe, or the one given. It changes a `RecipeDraft`,
/// so Cancel changes nothing and Save writes the whole of it at once.
struct RecipeEditorSheet: View {
  let recipe: RecipeRecord?
  /// For a draft from Distill: what was read, and the recipe already saved from the same link.
  /// Nothing is stored until the cook saves it, and leaving asks first.
  let importing: ImportReview?
  /// Called with the saved recipe, just before the sheet closes.
  var onSaved: (RecipeRecord) -> Void = { _ in }
  /// Opens the recipe already saved from the same link, instead of saving a second copy.
  var onOpenDuplicate: (UUID) -> Void = { _ in }

  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @Environment(RecipeAIService.self) private var ai: RecipeAIService?
  @State private var draft: RecipeDraft
  private let initial: RecipeDraft
  /// Problems show once Save has been tried, and then follow the cook's fixes.
  @State private var triedToSave = false
  @State private var couldntSave = false
  @State private var saveLatch = SaveLatch()
  @State private var confirmingLeave = false
  @State private var divining = false
  @State private var divineMessage: CopyString?

  init(
    recipe: RecipeRecord?, importing: ImportReview? = nil,
    onSaved: @escaping (RecipeRecord) -> Void = { _ in },
    onOpenDuplicate: @escaping (UUID) -> Void = { _ in }
  ) {
    self.recipe = recipe
    self.importing = importing
    self.onSaved = onSaved
    self.onOpenDuplicate = onOpenDuplicate
    let start = importing?.draft ?? recipe.map(RecipeDraft.init) ?? RecipeDraft()
    // An import was never saved, so leaving it always asks first.
    initial = importing == nil ? start : RecipeDraft()
    _draft = State(initialValue: start)
  }

  private var isDirty: Bool { draft != initial }

  var body: some View {
    NavigationStack {
      RecipeEditorForm(
        draft: $draft, recipe: recipe, errors: triedToSave ? draft.validate() : nil,
        couldntSave: couldntSave, divining: divining, divineMessage: divineMessage,
        onDivine: divine, duplicate: importing?.duplicate,
        onOpenDuplicate: {
          if let id = importing?.duplicate?.id { onOpenDuplicate(id) }
        }
      )
      .navigationTitle(
        importing != nil
          ? Copy.imports.title.text
          : recipe == nil ? Copy.editor.newTitle.text : Copy.editor.editTitle.text
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
          .disabled(saveLatch.isSaving)
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
    // A second tap or click before the sheet has gone would save the recipe again.
    guard saveLatch.begin() else { return }
    couldntSave = false
    do {
      let saved = try RecipeSaver.save(draft, into: recipe, context: context)
      // An estimate that couldn't be had while editing is asked for now, with the saved
      // ingredients; if Gemini is still out of reach it waits in the queue.
      if RecipeMacroEstimates.queueAfterSave(of: draft, saved: saved, in: context), let ai {
        let context = context
        Task { await AIQueueRunner.drain(in: context, using: ai.estimator) }
      }
      onSaved(saved)
      dismiss()
    } catch RecipeSaver.Failure.invalid {
      triedToSave = true
      saveLatch.reopen()
    } catch {
      triedToSave = true
      couldntSave = true
      saveLatch.reopen()
    }
  }
}

/// Lets one save through at a time. It closes when a save starts and stays closed once the
/// recipe is saved (the sheet is on its way out); a save that fails opens it again so the cook
/// can fix the problem and try again.
struct SaveLatch {
  private(set) var isSaving = false

  /// True for the first call, false for every call after it until `reopen()`.
  mutating func begin() -> Bool {
    guard !isSaving else { return false }
    isSaving = true
    return true
  }

  mutating func reopen() {
    isSaving = false
  }
}
