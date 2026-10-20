import CauldronKit
import Foundation
import Testing

@testable import Cauldron
@testable import CauldronImports

@MainActor
@Suite("Share sheet corrections")
struct ShareSheetCorrectionTests {
  @Test func missingTitleIsPromptedImmediatelyAndOtherErrorsWaitForBlurOrSave() async throws {
    let sheet = ShareSheetModel(
      item: SharedItem(url: ImportFixtures.tacosLink),
      importer: ImportModel(
        fetcher: ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)]),
        extractor: nil, options: ImportFixtures.quick),
      finishedFolder: nil, inboxFolder: nil, close: { _ in })
    sheet.start()
    await sheet.finished()
    var draft = try #require(sheet.currentDraft)
    draft.title = " "
    draft.servings = "0"
    sheet.currentDraft = draft
    #expect(sheet.error(for: .title) == Copy.validation.required)
    #expect(sheet.error(for: .servings) == nil)
    sheet.blurred(.servings)
    #expect(sheet.error(for: .servings) == Copy.validation.wholeNumber(1, 1000))
    sheet.save()
    #expect(sheet.firstInvalidField == .title)
    guard case .ready = sheet.phase else {
      Issue.record("Invalid Save must keep corrections open")
      return
    }
  }

  @Test(arguments: ["", "0", "1", "1000", "1001", "-1", "2.5", "many"])
  func servingsKeepTypedInputAndUseCanonicalLimits(_ input: String) async throws {
    let sheet = await readySheet()
    var draft = try #require(sheet.currentDraft)
    draft.servings = input
    sheet.currentDraft = draft
    sheet.blurred(.servings)
    let valid = ["", "1", "1000"].contains(input)
    #expect((sheet.error(for: .servings) == nil) == valid)
    #expect(sheet.currentDraft?.servings == input)
    guard case .ready(let review) = sheet.phase else { return }
    #expect(review.canSave == valid)
  }

  @Test(arguments: ["", "0", "20160", "20161", "-1", "1.5", "later"])
  func timesKeepTypedInputAndUseCanonicalLimits(_ input: String) async throws {
    let sheet = await readySheet()
    var draft = try #require(sheet.currentDraft)
    draft.prepMinutes = input
    draft.cookMinutes = input
    sheet.currentDraft = draft
    sheet.blurred(.prepMinutes)
    sheet.blurred(.cookMinutes)
    let valid = ["", "0", "20160"].contains(input)
    #expect((sheet.error(for: .prepMinutes) == nil) == valid)
    #expect((sheet.error(for: .cookMinutes) == nil) == valid)
    #expect(sheet.currentDraft?.prepMinutes == input)
    #expect(sheet.currentDraft?.cookMinutes == input)
  }

  @Test(arguments: [200, 201])
  func longTitleWaitsForBlurAndRespectsTheFullEditorLimit(_ count: Int) async throws {
    let sheet = await readySheet()
    var draft = try #require(sheet.currentDraft)
    draft.title = String(repeating: "a", count: count)
    sheet.currentDraft = draft
    #expect(sheet.error(for: .title) == nil)
    sheet.blurred(.title)
    #expect((sheet.error(for: .title) == nil) == (count == 200))
  }

  @Test func fixingMissingTitleMakesTheLatestDraftSavable() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sheet = await readySheet(folder: folder)
    var draft = try #require(sheet.currentDraft)
    draft.title = ""
    sheet.currentDraft = draft
    sheet.save()
    #expect(FinishedInbox.pending(from: folder).isEmpty)
    draft.title = "Corrected tacos"
    sheet.currentDraft = draft
    sheet.save()
    #expect(sheet.phase == .saved)
    #expect(
      FinishedInbox.pending(from: folder).first?.recipe.recipeDraft.title == "Corrected tacos")
  }

  @Test(arguments: [false, true])
  func saveAndContinuationUseLatestCorrectionsAndPreserveUnrelatedData(_ continuing: Bool)
    async throws
  {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let item = SharedItem(url: ImportFixtures.tacosLink)
    let sheet = await readySheet(item: item, folder: folder, withCover: true)
    let original = try #require(sheet.currentDraft)
    var draft = original
    draft.title = "First correction"
    sheet.currentDraft = draft
    draft.title = "Latest correction"
    draft.servings = "8"
    draft.prepMinutes = "0"
    draft.cookMinutes = "20160"
    sheet.currentDraft = draft
    let received: RecipeDraft
    if continuing {
      sheet.sendToCauldron()
      let queue = SharedImportQueue(
        folder: folder.appending(path: "legacy"),
        finishedFolder: folder.appending(path: "finished"),
        retainedFolder: sheet.retainedStore.folder, enabled: true)
      queue.pickUp()
      received = try #require(queue.nextSession()).draft
      #expect(sheet.retainedStore.read(item.id)?.item == item)
      #expect(sheet.retainedStore.read(item.id)?.parsed?.coverLink == ImportFixtures.tacosImage)
      #expect(FinishedInbox.pending(from: folder).isEmpty)
    } else {
      sheet.save()
      let saved = try #require(FinishedInbox.pending(from: folder).first?.recipe)
      #expect(saved.coverLink == ImportFixtures.tacosImage)
      received = saved.recipeDraft
    }
    #expect(received.title == "Latest correction")
    #expect(received.servings == "8")
    #expect(received.prepMinutes == "0")
    #expect(received.cookMinutes == "20160")
    #expect(received.totalMinutes == original.totalMinutes)
    #expect(received.ingredients.compactMap(\.parsed) == original.ingredients.compactMap(\.parsed))
    #expect(received.steps.map(\.text) == original.steps.map(\.text))
    #expect(received.sourceURL == original.sourceURL)
    #expect(received.imported == original.imported)
    #expect(received.typedMacros == original.typedMacros)
    #expect(received.pageMacros == original.pageMacros)
    #expect(received.estimateOnSave == original.estimateOnSave)
  }

  @Test func readOnlyErrorsBlockSaveButIncompleteCorrectionsStillReachTheEditor() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sheet = await readySheet(folder: folder)
    var draft = try #require(sheet.currentDraft)
    draft.notes = String(repeating: "n", count: RecipeLimits.notes + 1)
    sheet.currentDraft = draft
    #expect(sheet.hasReadOnlyErrors)
    #expect(sheet.firstInvalidField == nil)
    sheet.save()
    #expect(FinishedInbox.pending(from: folder).isEmpty)
    draft.title = ""
    draft.servings = "invalid paste"
    sheet.currentDraft = draft
    sheet.sendToCauldron()
    let queue = SharedImportQueue(
      folder: folder.appending(path: "legacy"), finishedFolder: folder.appending(path: "finished"),
      retainedFolder: sheet.retainedStore.folder, enabled: true)
    queue.pickUp()
    let received = try #require(queue.nextSession()).draft
    #expect(received.title.isEmpty)
    #expect(received.servings == "invalid paste")
    #expect(received.notes == draft.notes)
  }

  private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  private func readySheet(item: SharedItem? = nil, folder: URL? = nil, withCover: Bool = false)
    async -> ShareSheetModel
  {
    let sheet = ShareSheetModel(
      item: item ?? SharedItem(url: ImportFixtures.tacosLink),
      importer: ImportModel(
        fetcher: ScriptedFetcher([
          ImportFixtures.tacosLink: ImportFixtures.tacos(nutrition: true, image: withCover),
          ImportFixtures.tacosImage: .image(ImportFixtures.imageData(64, 48)),
        ]), extractor: nil, options: ImportFixtures.quick, cover: .sheetThumbnail),
      finishedFolder: folder, inboxFolder: folder, closeDelay: .milliseconds(1), close: { _ in })
    sheet.start()
    await sheet.finished()
    return sheet
  }

}
