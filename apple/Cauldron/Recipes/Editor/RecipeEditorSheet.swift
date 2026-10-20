import CauldronImports
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
  let shared: SharedDraftSession?
  /// Called with the saved recipe, just before the sheet closes.
  var onSaved: (RecipeRecord) -> Void = { _ in }
  /// Opens the recipe already saved from the same link, instead of saving a second copy.
  var onOpenDuplicate: (UUID) -> Void = { _ in }

  @Environment(\.modelContext) private var context
  @Environment(\.pageFetcher) private var fetcher
  @Environment(\.dismiss) private var dismiss
  @Environment(RecipeAIService.self) private var ai: RecipeAIService?
  @Environment(SharedImportQueue.self) private var sharing: SharedImportQueue?
  @Environment(\.draftKeeper) private var draftKeeper
  @Environment(\.scenePhase) private var scenePhase
  /// Tells the shared-import queue this editor is open, so nothing shared replaces it.
  @State private var openToken = UUID()
  @State private var draft: RecipeDraft
  private let initial: RecipeDraft
  /// Problems show once Save has been tried, and then follow the cook's fixes.
  @State private var triedToSave = false
  @State private var couldntSave = false
  @State private var saveLatch = SaveLatch()
  @State private var confirmingLeave = false
  @State private var confirmingStartOver = false
  /// The fields the cook has been to and left: a problem with one shows at once, the rest only
  /// once Save has been tried.
  @State private var touched: Set<RecipeDraft.Field> = []
  @FocusState private var focus: RecipeDraft.Field?
  /// A new recipe's draft is kept on this device as it changes; this is how that stands.
  @State private var keptStatus = DraftKeepStatus.idle
  /// The draft was restored (or there was none), so what is kept may be changed.
  @State private var restored = false
  /// The recipe is saved, so nothing more is kept.
  @State private var finished = false
  @State private var divining = false
  @State private var divineMessage: CopyString?

  init(
    recipe: RecipeRecord?, importing: ImportReview? = nil, shared: SharedDraftSession? = nil,
    onSaved: @escaping (RecipeRecord) -> Void = { _ in },
    onOpenDuplicate: @escaping (UUID) -> Void = { _ in }
  ) {
    self.recipe = recipe
    self.importing = importing
    self.shared = shared
    self.onSaved = onSaved
    self.onOpenDuplicate = onOpenDuplicate
    let start = shared?.draft ?? importing?.draft ?? recipe.map(RecipeDraft.init) ?? RecipeDraft()
    // An import was never saved, so leaving it always asks first.
    initial = importing == nil ? start : RecipeDraft()
    _draft = State(initialValue: start)
  }

  /// Only a new recipe typed from scratch is kept as a draft: an edit is saved or left, and an
  /// import is the sheet's own until it is saved.
  private var keepsDraft: Bool { recipe == nil && importing == nil && shared == nil }

  /// Leaving would lose something: an edit or an import not yet saved, or a new recipe that
  /// couldn't be kept.
  private var isDirty: Bool {
    shared != nil ? keptStatus == .failed : keepsDraft ? keptStatus == .failed : draft != initial
  }

  private var keep: DraftKeep { DraftKeep(keeper: draftKeeper ?? DraftKeepers.shared) }

  /// The problems to show: all of them once Save has been tried, before that those of fields
  /// the cook has been to and left (`errorFor` in the web editor).
  private var shownErrors: RecipeDraft.Errors? {
    triedToSave ? draft.validate() : draft.validate().showing(touched)
  }

  var body: some View {
    NavigationStack {
      RecipeEditorForm(
        draft: $draft, recipe: recipe, errors: shownErrors, showsSummary: triedToSave,
        couldntSave: couldntSave, divining: divining, divineMessage: divineMessage,
        onDivine: divine, focus: $focus,
        keptNote: shared != nil
          ? (keptStatus == .failed ? Copy.sharedDrafts.couldntKeep : Copy.sharedDrafts.kept)
          : keepsDraft && keptStatus == .kept ? Copy.editor.draftKept : nil,
        onStartOver: keepsDraft && (keptStatus == .kept || !draft.hasNothingToKeep)
          ? { confirmingStartOver = true } : nil,
        duplicate: importing?.duplicate,
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
            // A kept draft is on this device already; one that couldn't be kept asks first.
            if keepsDraft || shared != nil { keepDraft() }
            if isDirty { confirmingLeave = true } else { dismiss() }
          } label: {
            Text(verbatim: Copy.recipeView.cancel.text)
          }
        }
        ToolbarItem(placement: .automatic) {
          if shared != nil {
            Button(role: .destructive) {
              confirmingStartOver = true
            } label: {
              Text(verbatim: Copy.sharedDrafts.discard.text)
            }
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
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let sharing, sharing.waiting > 0 { SharedWaitingBadge(count: sharing.waiting) }
    }
    .interactiveDismissDisabled(isDirty)
    .onAppear {
      sharing?.editorOpened(openToken)
      restoreKeptDraft()
    }
    .onDisappear {
      sharing?.editorClosed(openToken)
      keepDraft()
    }
    // Kept a moment after the cook stops changing something, and as soon as the app leaves the
    // screen or the editor closes, so the last change isn't lost (`wait: 800` in the web editor).
    .task(id: draft) {
      guard (keepsDraft && restored) || shared != nil, !finished else { return }
      guard shared == nil else { return }
      try? await Task.sleep(for: .milliseconds(800))
      guard !Task.isCancelled else { return }
      keepDraft()
    }
    .onChange(of: draft) { _, _ in
      if shared != nil { keepDraft() }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { keepDraft() }
    }
    .onChange(of: focus) { old, _ in
      if let old { touched.insert(old) }
    }
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
    .confirmationDialog(
      Text(verbatim: shared != nil ? Copy.sharedDrafts.discard.text : Copy.editor.startOver.text),
      isPresented: $confirmingStartOver,
      titleVisibility: .visible
    ) {
      Button(role: .destructive) {
        startOver()
      } label: {
        Text(verbatim: shared != nil ? Copy.sharedDrafts.discard.text : Copy.editor.startOver.text)
      }
      Button(role: .cancel) {
      } label: {
        Text(verbatim: Copy.editor.stay.text)
      }
    } message: {
      Text(
        verbatim: shared != nil
          ? Copy.sharedDrafts.discardConfirm.text : Copy.editor.startOverConfirm.text)
    }
    #if os(macOS)
      .frame(minWidth: 560, idealWidth: 640, minHeight: 640, idealHeight: 760)
    #endif
  }

  /// A new recipe opens on the draft kept last time, if there is one.
  private func restoreKeptDraft() {
    guard keepsDraft, !restored else { return }
    restored = true
    if let kept = keep.restored() {
      draft = kept
      keptStatus = .kept
    }
  }

  /// Writes the draft down now, or clears it when it is empty again.
  private func keepDraft() {
    guard (keepsDraft && restored) || shared != nil, !finished else { return }
    if let shared {
      do { try shared.checkpoint(draft); keptStatus = .kept } catch { keptStatus = .failed }
    } else {
      keptStatus = keep.keep(draft)
    }
  }

  /// Drops the kept draft and the form with it.
  private func startOver() {
    if let shared {
      do { try shared.discard(); finished = true; dismiss() } catch { keptStatus = .failed }
      return
    }
    keep.clear()
    keptStatus = .idle
    touched = []
    triedToSave = false
    draft = RecipeDraft()
  }

  /// Estimates the macros from the ingredients as they are now, into the draft. Nothing is
  /// stored until Save, so Cancel leaves nothing behind. If the AI can't be reached, Save
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
      let saved: RecipeRecord
      if let shared {
        saved = try shared.save(draft, in: context); finished = true
      } else {
        saved = try RecipeSaver.save(draft, into: recipe, context: context)
      }
      // Saved, so the draft is not needed, and the editor's last write must not bring it back.
      if keepsDraft {
        finished = true
        keep.clear()
      }
      // An estimate that couldn't be had while editing is asked for now, with the saved
      // ingredients; if the AI is still out of reach it waits in the queue.
      if RecipeMacroEstimates.queueAfterSave(of: draft, saved: saved, in: context), let ai {
        let context = context
        Task { await AIQueueRunner.drain(in: context, using: ai.estimator) }
      }
      if shared != nil, let sharing {
        let context = context
        let fetcher = fetcher
        Task { await sharing.fetchCovers(into: context, using: fetcher) }
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
