import CauldronKit
import Foundation
import SwiftUI
import Testing

@testable import Cauldron
@testable import CauldronImports

/// A new recipe's unfinished draft is kept on this device and offered again, as the web
/// editor's was (`lib/recipe-draft.ts`).
@MainActor
@Suite("Kept draft")
struct KeptDraftTests {
  private func typed() -> RecipeDraft {
    var draft = RecipeDraft()
    draft.title = "Sunday sauce"
    draft.summary = "Slow."
    draft.servings = "6"
    draft.prepMinutes = "15"
    draft.calories = "410"
    draft.protein = "8.5"
    draft.sourceURL = "https://example.com/sauce"
    draft.notes = "Better on day two."
    draft.addTag("Italian")
    let first = draft.ingredients[0].id
    draft.setIngredientText(first, "2 cups tomatoes\n")
    draft.addHeading()
    draft.ingredients[draft.ingredients.count - 1] = .heading("To serve")
    draft.addIngredient()
    draft.setIngredientText(draft.ingredients[draft.ingredients.count - 1].id, "basil")
    draft.setIngredientItem(first, "plum tomatoes")
    let step = draft.steps[0].id
    draft.setStepText(step, "Simmer for 1 hour.")
    draft.setTimer(step, minutes: "90")
    return draft
  }

  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "kept-draft-\(UUID().uuidString)", directoryHint: .isDirectory)
      .appending(path: "ConjureDraft.json")
  }

  // MARK: What is kept

  @Test func aKeptDraftComesBackAsItWas() {
    var draft = typed()
    draft.fill(withEstimate: Macros(calories: 400, protein: 9, carbs: 40, fat: 12))
    draft.photo = .replace(ProcessedPhoto(data: Data([1, 2, 3]), width: 4, height: 3))
    let kept = KeptDraft(draft)
    let back = kept.draft

    #expect(KeptDraft(back) == kept)
    #expect(back.title == "Sunday sauce")
    #expect(back.tags == ["Italian"])
    #expect(back.ingredients.map(\.text) == ["2 cups tomatoes", "", "To serve", "basil"])
    #expect(back.ingredients.map(\.isHeading).contains(true))
    // A fix made by hand is still a fix.
    #expect(back.ingredients[0].parsed?.item == "plum tomatoes")
    #expect(back.ingredients[0].corrected)
    #expect(back.steps[0].timerSeconds == 5400 && back.steps[0].timerSet)
    // An estimate is still marked as one.
    #expect(back.estimatedMacros == back.typedMacros)
    #expect(back.photo == draft.photo)
  }

  @Test func theStoredFormSurvivesBeingWrittenAsJSON() throws {
    let kept = KeptDraft(typed())
    let data = try JSONEncoder().encode(kept)
    #expect(try JSONDecoder().decode(KeptDraft.self, from: data) == kept)
  }

  @Test func nothingTypedIsNothingToKeep() {
    #expect(KeptDraft(RecipeDraft()).isEmpty)
    #expect(RecipeDraft().hasNothingToKeep)
    var draft = RecipeDraft()
    draft.title = "   "
    draft.addIngredient()
    draft.addStep()
    #expect(KeptDraft(draft).isEmpty)
  }

  @Test(arguments: ["title", "tag", "line", "step", "heading", "photo", "number", "notes"])
  func anythingTypedIsWorthKeeping(what: String) {
    var draft = RecipeDraft()
    switch what {
    case "title": draft.title = "Soup"
    case "tag": draft.addTag("quick")
    case "line": draft.setIngredientText(draft.ingredients[0].id, "1 egg")
    case "step": draft.setStepText(draft.steps[0].id, "Whisk.")
    case "heading": draft.ingredients = [.heading("Sauce")]
    case "photo": draft.photo = .replace(ProcessedPhoto(data: Data([1]), width: 1, height: 1))
    case "number": draft.servings = "4"
    default: draft.notes = "Hm"
    }
    #expect(!KeptDraft(draft).isEmpty, "\(what)")
    #expect(!draft.hasNothingToKeep)
  }

  // MARK: Keeping it

  @Test func changesAreKeptAndAnEmptiedDraftIsCleared() {
    let keeper = MemoryDraftKeeper()
    let keep = DraftKeep(keeper: keeper)
    #expect(keep.keep(typed()) == .kept)
    #expect(keeper.kept != nil)
    #expect(keep.restored()?.title == "Sunday sauce")

    // Put back to empty, the draft is dropped rather than kept as a blank form.
    #expect(keep.keep(RecipeDraft()) == .idle)
    #expect(keeper.kept == nil)
    #expect(keep.restored() == nil)
  }

  @Test func aDraftThatCantBeWrittenSaysSoAndTheEditorCarriesOn() {
    let keeper = MemoryDraftKeeper()
    keeper.failsToKeep = true
    #expect(DraftKeep(keeper: keeper).keep(typed()) == .failed)
  }

  @Test func savingOrStartingOverDropsIt() {
    let keeper = MemoryDraftKeeper()
    let keep = DraftKeep(keeper: keeper)
    keep.keep(typed())
    keep.clear()
    #expect(keeper.kept == nil)
    #expect(keep.restored() == nil)
  }

  @Test func aDraftFromAnotherVersionIsDroppedNotRestored() {
    var kept = KeptDraft(typed())
    kept.version = KeptDraft.currentVersion + 1
    let keeper = MemoryDraftKeeper(kept)
    #expect(DraftKeep(keeper: keeper).restored() == nil)
    #expect(keeper.kept == nil)
  }

  // MARK: In a file

  @Test func aDraftIsKeptInAFileAndReadBackByANewKeeper() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let kept = KeptDraft(typed())
    #expect(FileDraftKeeper(url: url).keep(kept))
    #expect(FileDraftKeeper(url: url).load() == kept)
    // Keeping again replaces it.
    var changed = kept
    changed.title = "Sunday gravy"
    #expect(FileDraftKeeper(url: url).keep(changed))
    #expect(FileDraftKeeper(url: url).load()?.title == "Sunday gravy")

    FileDraftKeeper(url: url).clear()
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(FileDraftKeeper(url: url).load() == nil)
  }

  @Test func aFileThatCantBeUsedIsRemovedAndReadsAsNoDraft() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

    try Data("not json".utf8).write(to: url)
    #expect(FileDraftKeeper(url: url).load() == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))

    var other = KeptDraft(typed())
    other.version = 0
    try JSONEncoder().encode(other).write(to: url)
    #expect(FileDraftKeeper(url: url).load() == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test func clearingWhenNothingIsKeptIsFine() {
    let url = temporaryFile()
    FileDraftKeeper(url: url).clear()
    #expect(FileDraftKeeper(url: url).load() == nil)
  }

  @Test func aFileThatCantBeWrittenIsReportedNotThrown() {
    // The parent is a file, so the folder can't be made.
    let blocker = FileManager.default.temporaryDirectory.appending(path: "blocker-\(UUID())")
    FileManager.default.createFile(atPath: blocker.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: blocker) }
    let keeper = FileDraftKeeper(url: blocker.appending(path: "ConjureDraft.json"))
    #expect(!keeper.keep(KeptDraft(typed())))
  }

  // MARK: The editor

  private func renders(_ view: some View) -> Bool {
    ImageRenderer(content: view.frame(width: 600, height: 900)).cgImage != nil
  }

  @Test func theEditorRendersOverAKeptDraftInBothAppearances() throws {
    let container = try CauldronStore.container(.inMemory)
    let keeper = MemoryDraftKeeper(KeptDraft(typed()))
    for scheme in [ColorScheme.light, .dark] {
      let view = RecipeEditorSheet(recipe: nil)
        .modelContainer(container)
        .environment(\.draftKeeper, keeper)
        .environment(\.colorScheme, scheme)
      #expect(renders(view), "\(scheme)")
    }
    // An editor that isn't for a new recipe leaves what is kept alone.
    #expect(keeper.kept != nil)
  }

  @Test func theFormShowsWhenADraftIsKept() throws {
    let container = try CauldronStore.container(.inMemory)
    let form = RecipeEditorForm(
      draft: .constant(typed()), recipe: nil, errors: nil, showsSummary: false, couldntSave: false,
      keptNote: Copy.editor.draftKept, onStartOver: {}
    ).modelContainer(container)
    #expect(renders(form))
  }
}
