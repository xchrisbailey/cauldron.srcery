import CauldronImports
import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("Retained shared drafts")
struct RetainedSharedDraftTests {
  @Test func closingAndRestartingResumesEditedDraftAndSaveIsIdempotent() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = RetainedSharedDraftStore(folder: folder)
    var draft = RecipeDraft()
    draft.title = "Soup"
    draft.ingredients = [.line("2 carrots")]
    draft.setStepText(draft.steps[0].id, "Boil.")
    draft.fill(withPage: Macros(calories: 200))
    draft.imported = ImportedFrom(
      platform: .web, author: "Ada", siteName: "Soup site",
      fetchedAt: Date(timeIntervalSince1970: 100), rough: true)
    draft.review = [.title, .macros]
    draft.photo = .replace(ProcessedPhoto(data: Data([1, 2, 3]), width: 10, height: 20))
    let shared = RetainedSharedDraft(item: SharedItem(text: "Original soup"), draft: draft)
    try store.write(shared)
    let session = try SharedDraftSession(id: shared.id, store: store)
    draft.title = "Corrected soup"
    draft.notes = "Keep all editor changes"
    try session.checkpoint(draft)
    let resumed = try SharedDraftSession(id: shared.id, store: store)
    #expect(resumed.draft.title == "Corrected soup")
    #expect(resumed.draft.notes == "Keep all editor changes")
    #expect(resumed.draft.pageMacros?.calories == 200)
    #expect(resumed.draft.imported?.author == "Ada")
    #expect(resumed.draft.imported?.rough == true)
    #expect(resumed.draft.review == [.macros])
    #expect(
      resumed.draft.photo == .replace(ProcessedPhoto(data: Data([1, 2, 3]), width: 10, height: 20)))
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let saved = try resumed.save(draft, in: context, index: SavedLinksIndex(folder: nil))
    let again = try resumed.save(draft, in: context, index: SavedLinksIndex(folder: nil))
    #expect(saved.id == shared.id && again.id == shared.id)
    #expect(try context.fetchCount(FetchDescriptor<RecipeRecord>()) == 1)
    #expect(store.read(shared.id)?.status == .saved)
  }
  @Test func exactRequestsWaitForCurrentWorkAndClosedDraftRecoversOnActivation() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = RetainedSharedDraftStore(folder: folder)
    var draft = RecipeDraft()
    draft.title = "First"
    let first = RetainedSharedDraft(
      item: SharedItem(text: "first", sharedAt: Date(timeIntervalSince1970: 1)), draft: draft)
    draft.title = "Second"
    let second = RetainedSharedDraft(
      item: SharedItem(text: "second", sharedAt: Date(timeIntervalSince1970: 2)), draft: draft)
    try store.write(first)
    try store.write(second)
    let inbox = folder.appending(path: "legacy")
    let queue = SharedImportQueue(folder: inbox, retainedFolder: folder, enabled: true)
    let editor = UUID()
    queue.editorOpened(editor)
    queue.pickUp()
    queue.request(second.id)
    queue.request(second.id)
    #expect(queue.waiting == 2)
    #expect(queue.nextSession() == nil)
    queue.editorClosed(editor)
    let requested = try #require(queue.nextSession())
    #expect(requested.id == second.id)
    #expect(requested.draft.title == "Second")
    queue.request(second.id)
    #expect(queue.waiting == 1)
    queue.closedSession(second.id)
    let older = try #require(queue.nextSession())
    #expect(older.id == first.id)
    queue.closedSession(first.id)
    #expect(!queue.readyToOpen)
    queue.pickUp()
    #expect(queue.waiting == 2)
    #expect(queue.nextSession()?.id == first.id)
    // Merely receiving or presenting never consumes a handoff.
    #expect(store.read(first.id)?.recipeDraft?.title == "First")
    #expect(store.read(second.id)?.recipeDraft?.title == "Second")
  }

  @Test func aSharedDraftWaitsUntilBothWindowsCloseTheirOrdinaryImports() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = RetainedSharedDraftStore(folder: folder)
    var draft = RecipeDraft()
    draft.title = "Soup"
    let item = RetainedSharedDraft(item: SharedItem(text: "Soup"), draft: draft)
    try store.write(item)
    let queue = SharedImportQueue(
      folder: folder.appending(path: "legacy"), retainedFolder: folder, enabled: true)
    let first = UUID()
    let second = UUID()
    queue.importOpened(first)
    queue.importOpened(second)
    queue.request(item.id)
    queue.importClosed(first)
    queue.importClosed(first)
    queue.importClosed(UUID())
    #expect(!queue.readyToOpen)
    #expect(queue.nextSession() == nil)
    queue.importClosed(second)
    let session = try #require(queue.nextSession())
    #expect(session.id == item.id)
    queue.closedSession(item.id)
    // A delayed close for an earlier shared presentation cannot release a new ordinary import.
    queue.importOpened(UUID())
    queue.request(item.id)
    queue.closedSession(item.id)
    #expect(queue.nextSession() == nil)
  }

  @Test func discardedAndAlreadySavedDraftsDoNotResurrectAfterDelayedRoutes() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = RetainedSharedDraftStore(folder: folder)
    var draft = RecipeDraft()
    draft.title = "Soup"
    draft.ingredients = [.line("2 carrots")]
    draft.setStepText(draft.steps[0].id, "Boil.")
    let discarded = RetainedSharedDraft(item: SharedItem(text: "discard me"), draft: draft)
    try store.write(discarded)
    try SharedDraftSession(id: discarded.id, store: store).discard()
    let saved = RetainedSharedDraft(item: SharedItem(text: "save me"), draft: draft)
    try store.write(saved)
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    // Simulate a crash after the recipe save, before the handoff tombstone was written.
    try RecipeSaver.save(
      draft, into: nil, context: context, id: saved.id, index: SavedLinksIndex(folder: nil))
    let queue = SharedImportQueue(
      folder: folder.appending(path: "legacy"), finishedFolder: folder.appending(path: "finished"),
      retainedFolder: folder, enabled: true)
    queue.request(discarded.id, in: context)
    queue.request(saved.id, in: context)
    queue.pickUp(in: context)
    #expect(!queue.readyToOpen)
    #expect(queue.waiting == 0)
    #expect(store.read(saved.id)?.status == .saved)
    #expect(try context.fetchCount(FetchDescriptor<RecipeRecord>()) == 1)
  }

  @Test func shareSheetContinuationPreservesParsedDataWithoutAnotherImport() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let fetcher = ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)])
    let item = SharedItem(url: ImportFixtures.tacosLink)
    var closings = 0
    let sheet = ShareSheetModel(
      item: item,
      importer: ImportModel(fetcher: fetcher, extractor: nil, options: ImportFixtures.quick),
      finishedFolder: nil, inboxFolder: nil, closeDelay: .milliseconds(1),
      retainedFolder: folder, close: { _ in closings += 1 })
    sheet.start()
    await sheet.finished()
    sheet.sendToCauldron()
    sheet.sendToCauldron()
    await sheet.closed()
    #expect(closings == 1)
    let queue = SharedImportQueue(
      folder: folder.appending(path: "legacy"), finishedFolder: folder.appending(path: "finished"),
      retainedFolder: folder, enabled: true)
    queue.request(item.id)
    let session = try #require(queue.nextSession())
    #expect(session.draft.title == "Smoky black bean tacos")
    #expect(session.draft.sourceURL == ImportFixtures.tacosLink)
    #expect(!session.draft.ingredients.isEmpty)
    #expect(fetcher.requests.count == 1)
    #expect(sheet.retainedStore.read(item.id) != nil)
  }

  @Test func anUnwritableHandoffKeepsTheCurrentDraftAndDoesNotClose() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    var closed = false
    let sheet = ShareSheetModel(
      item: SharedItem(url: ImportFixtures.tacosLink),
      importer: ImportModel(
        fetcher: ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)]),
        extractor: nil, options: ImportFixtures.quick),
      finishedFolder: nil, inboxFolder: nil, retainedFolder: file, close: { _ in closed = true })
    sheet.start()
    await sheet.finished()
    sheet.currentDraft?.title = "My corrected title"
    sheet.sendToCauldron()
    #expect(sheet.retainedFailure != nil)
    #expect(sheet.currentDraft?.title == "My corrected title")
    #expect(!closed)
    sheet.cancel()
    #expect(closed)
  }

  @Test func sharedDraftLinksCarryOnlyAValidIdentityAndTrackerLinksStillWork() throws {
    let id = UUID()
    #expect(AppLink(url: AppLink.sharedDraft(id).url) == .sharedDraft(id))
    #expect(AppLink(url: AppLink.todayDiary.url) == .todayDiary)
    for value in [
      "cauldron://shared-draft", "cauldron://shared-draft/no",
      "cauldron://shared-draft/\(id)/extra", "cauldron://shared-draft/\(id)?title=bad",
    ] {
      #expect(AppLink(url: try #require(URL(string: value))) == nil)
    }
  }

  @Test func uncertainStepsSurviveContinuationAndAnEditedStepStaysCorrected() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = RetainedSharedDraftStore(folder: folder)
    var draft = RecipeDraft()
    draft.title = "Soup"
    draft.steps = [
      .imported("Simmer for 10 minutes.", section: "Sauce", flagged: true),
      .imported("Serve it.", section: nil, flagged: true),
    ]
    draft.setTimer(draft.steps[0].id, minutes: "3")
    let item = RetainedSharedDraft(item: SharedItem(text: "Soup"), draft: draft)
    try store.write(item)
    let session = try SharedDraftSession(id: item.id, store: store)
    #expect(session.draft.steps[0].flagged)
    #expect(session.draft.steps[0].timerSeconds == 180)
    #expect(session.draft.steps[0].timerSet)
    var edited = session.draft
    edited.setStepText(edited.steps[0].id, "Simmer gently.")
    try session.checkpoint(edited)
    let restored = try SharedDraftSession(id: item.id, store: store)
    #expect(!restored.draft.steps[0].flagged)
    #expect(restored.draft.steps[1].flagged)
    #expect(restored.draft.steps[0].timerSeconds == 180)
  }

  @Test func aSavedRetainedRecipeGetsItsCoverWithoutReimporting() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = RetainedSharedDraftStore(folder: folder)
    var draft = RecipeDraft()
    draft.title = "Soup"
    draft.ingredients = [.line("2 carrots")]
    draft.setStepText(draft.steps[0].id, "Boil.")
    let link = "https://cook.example/soup.png"
    let item = RetainedSharedDraft(
      item: SharedItem(url: "https://cook.example/soup"), draft: draft, coverLink: link)
    try store.write(item)
    let session = try SharedDraftSession(id: item.id, store: store)
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let saved = try session.save(draft, in: context, index: SavedLinksIndex(folder: nil))
    let attachedAt = Date(timeIntervalSince1970: 1234)
    let queue = SharedImportQueue(
      folder: folder.appending(path: "legacy"), finishedFolder: folder.appending(path: "finished"),
      retainedFolder: folder, enabled: true, now: { attachedAt })
    let fetcher = ScriptedFetcher([link: .hold])
    let cancelled = Task { await queue.fetchCovers(into: context, using: fetcher) }
    while fetcher.startedCount == 0 { await Task.yield() }
    cancelled.cancel()
    await cancelled.value
    #expect(store.read(item.id)?.parsed?.coverLink == link)
    #expect(saved.photo == nil)
    fetcher.set(link, .image(ImportFixtures.imageData(100, 50)))
    await queue.fetchCovers(into: context, using: fetcher)
    #expect(saved.photo?.width == 100)
    #expect(saved.photo?.height == 50)
    #expect(saved.updatedAt == attachedAt)
    #expect(fetcher.requests.count == 2)
    #expect(fetcher.requests.last?.url == link)
    await queue.fetchCovers(into: context, using: fetcher)
    #expect(fetcher.requests.count == 2)
    #expect(store.read(item.id)?.status == .saved)
  }

  @Test(arguments: [false, true])
  func removingAPhotoWhileItsCoverIsFetchingWins(finishedPayload: Bool) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    var draft = RecipeDraft()
    draft.title = "Soup"
    draft.ingredients = [.line("2 carrots")]
    draft.setStepText(draft.steps[0].id, "Boil.")
    let link = "https://cook.example/soup.png"
    let item = RetainedSharedDraft(item: SharedItem(text: "Soup"), draft: draft, coverLink: link)
    let store = RetainedSharedDraftStore(folder: folder)
    let queue = SharedImportQueue(
      folder: folder.appending(path: "legacy"), finishedFolder: folder,
      retainedFolder: finishedPayload ? folder.appending(path: "retained") : folder, enabled: true)
    let saved: RecipeRecord
    if finishedPayload {
      try FinishedInbox.add(FinishedRecipe(draft: draft, id: item.id, coverLink: link), in: folder)
      #expect(queue.pickUp(in: context) == 1)
      saved = try #require(context.fetch(FetchDescriptor<RecipeRecord>()).first)
    } else {
      try store.write(item)
      saved = try SharedDraftSession(id: item.id, store: store).save(
        draft, in: context, index: SavedLinksIndex(folder: nil))
    }
    let fetcher = EditingCoverFetcher(
      editing: {
        var edited = RecipeDraft(saved)
        edited.photo = .remove
        do {
          try RecipeSaver.save(
            edited, into: saved, context: context, index: SavedLinksIndex(folder: nil))
        } catch { Issue.record(error) }
      }, bytes: ImportFixtures.imageData(100, 50))
    await queue.fetchCovers(into: context, using: fetcher)
    #expect(saved.photo == nil)
    let restarted = ModelContext(container)
    #expect(try restarted.fetch(FetchDescriptor<RecipeRecord>()).first?.photo == nil)
  }

  @Test(arguments: [false, true])
  func explicitPhotoChoicesSurviveRestartWithoutADeferredCover(replace: Bool) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = RetainedSharedDraftStore(folder: folder)
    var draft = RecipeDraft()
    draft.title = "Soup"
    draft.ingredients = [.line("2 carrots")]
    draft.setStepText(draft.steps[0].id, "Boil.")
    let link = "https://cook.example/soup.png"
    let item = RetainedSharedDraft(item: SharedItem(text: "Soup"), draft: draft, coverLink: link)
    try store.write(item)
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let saved = try SharedDraftSession(id: item.id, store: store).save(
      draft, in: context, index: SavedLinksIndex(folder: nil))
    // An invalid ordinary-editor save does not cancel the still-pending imported cover.
    var invalid = draft
    invalid.title = ""
    invalid.photo = .remove
    do {
      try RecipeSaver.save(
        invalid, into: saved, context: context, index: SavedLinksIndex(folder: nil))
      Issue.record("An invalid draft must not save")
    } catch RecipeSaver.Failure.invalid {}
    #expect(store.read(item.id)?.parsed?.coverLink == link)
    // Commit the photo choice while retained metadata cannot be updated, then restart before
    // repairing metadata. The recipe save must contain the durable choice itself.
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path())
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: folder.path())
    }
    draft.photo =
      replace ? .replace(ProcessedPhoto(data: Data([4, 5, 6]), width: 2, height: 3)) : .remove
    try RecipeSaver.save(draft, into: saved, context: context, index: SavedLinksIndex(folder: nil))
    let restartedContext = ModelContext(container)
    let restarted = try #require(
      restartedContext.fetch(FetchDescriptor<RecipeRecord>()).first)
    let recovered = SharedImportQueue(
      folder: folder.appending(path: "legacy"), finishedFolder: folder.appending(path: "finished"),
      retainedFolder: folder, enabled: true)
    let fetcher = ScriptedFetcher([link: .image(ImportFixtures.imageData(100, 50))])
    await recovered.fetchCovers(into: restartedContext, using: fetcher)
    #expect(fetcher.requests.isEmpty)
    #expect(restarted.photo?.width == (replace ? 2 : nil))
    #expect(store.read(item.id)?.status == .saved)
  }

}
