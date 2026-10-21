import CauldronImports
import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("Shared import recovery")
struct SharedImportRecoveryTests {
  @Test func failedShareSurvivesReceiptAndRestartAsTheOriginalSource() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let item = SharedItem(text: "Grandma’s soup from her notebook.")
    let sheet = ShareSheetModel(
      item: item, importer: ImportModel(fetcher: ScriptedFetcher(), extractor: nil),
      finishedFolder: folder.appending(path: "finished"),
      inboxFolder: folder.appending(path: "legacy"),
      closeDelay: .milliseconds(1), keyMissing: { true }, retainedFolder: folder, close: { _ in })
    sheet.start()
    await sheet.finished()
    guard case .failed = sheet.phase else {
      Issue.record("The original source must need a model before continuation")
      return
    }
    sheet.sendToCauldron()
    await sheet.closed()
    let queue = SharedImportQueue(
      folder: folder.appending(path: "legacy"), finishedFolder: folder.appending(path: "finished"),
      retainedFolder: folder, enabled: true)
    let editor = UUID()
    queue.editorOpened(editor)
    queue.request(item.id)
    queue.request(item.id)
    #expect(queue.waiting == 1)
    #expect(queue.nextSession() == nil)
    queue.editorClosed(editor)
    let session = try #require(queue.nextSession())
    #expect(session.retained.item == item)
    #expect(session.retained.recipeDraft == nil)
    queue.closedSession(item.id)
    let restarted = SharedImportQueue(
      folder: folder.appending(path: "legacy"), finishedFolder: folder.appending(path: "finished"),
      retainedFolder: folder, enabled: true)
    restarted.pickUp()
    #expect(restarted.nextSession()?.retained.item == item)
    let container = try CauldronStore.container(.inMemory)
    #expect(try ModelContext(container).fetchCount(FetchDescriptor<RecipeRecord>()) == 0)
  }
  @Test func successfulRetryIsDurableBeforeReadyAndRestartSkipsExtraction() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let item = SharedItem(url: ImportFixtures.tacosLink)
    let store = RetainedSharedDraftStore(folder: folder)
    try store.write(RetainedSharedDraft(item: item))
    let session = try SharedDraftSession(id: item.id, store: store)
    let fetcher = ScriptedFetcher([
      ImportFixtures.tacosLink: ImportFixtures.tacos(nutrition: true, image: false)
    ])
    let importer = ImportModel(fetcher: fetcher, extractor: nil, options: ImportFixtures.quick)
    session.retry(using: importer)
    await importer.finished()
    guard case .ready = importer.phase else { Issue.record("Retry must reach the editor"); return }
    let resumed = try SharedDraftSession(id: item.id, store: store)
    #expect(resumed.isParsed)
    #expect(resumed.draft.title == "Smoky black bean tacos")
    #expect(resumed.draft.pageMacros?.calories == 350)
    #expect(resumed.draft.imported?.author == "Ada Cook")
    #expect(resumed.retained.item == item)
    let unused = ImportModel(fetcher: fetcher, extractor: nil)
    resumed.retry(using: unused)
    #expect(fetcher.requests.count == 1)
    #expect(unused.phase == .editing)
  }

  @Test func rawWriteFailureLeavesContinuationRetryAndCancellationAvailable() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    var closed = false
    let item = SharedItem(url: "https://down.example/soup", text: "Original source text")
    let sheet = ShareSheetModel(
      item: item,
      importer: ImportModel(
        fetcher: ScriptedFetcher(), extractor: nil, options: ImportFixtures.quick),
      finishedFolder: nil, inboxFolder: nil, retainedFolder: file, close: { _ in closed = true })
    sheet.start()
    await sheet.finished()
    sheet.sendToCauldron()
    guard case .failed(let notice) = sheet.phase else {
      Issue.record("Must keep the sheet open"); return
    }
    #expect(notice.canSend)
    #expect(sheet.retainedFailure != nil)
    #expect(sheet.retainedDraftID == nil)
    #expect(!closed)
    sheet.sendToCauldron()
    #expect(!closed)
    sheet.cancel()
    #expect(closed)
  }

  @Test func retryFailureAndClosingLeaveTheOriginalSourceForTheNextActivation() async throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let item = SharedItem(url: ImportFixtures.tacosLink, text: "Original caption")
    let store = RetainedSharedDraftStore(folder: folder)
    try store.write(RetainedSharedDraft(item: item))
    let importer = ImportModel(
      fetcher: ScriptedFetcher(), extractor: nil, options: ImportFixtures.quick)
    try SharedDraftSession(id: item.id, store: store).retry(using: importer)
    await importer.finished()
    guard case .failed = importer.phase else { Issue.record("Expected a failed retry"); return }
    importer.discard()
    let resumed = try SharedDraftSession(id: item.id, store: store)
    #expect(!resumed.isParsed)
    #expect(resumed.retained.item == item)
    #expect(resumed.retained.status == .editing)
    try resumed.discard()
    let delayed = ImportModel(fetcher: ScriptedFetcher(), extractor: nil)
    resumed.retry(using: delayed)
    #expect(delayed.phase == .editing)
    let queue = SharedImportQueue(
      folder: folder.appending(path: "legacy"), retainedFolder: folder, enabled: true)
    queue.request(item.id)
    #expect(queue.nextSession() == nil)
  }

  @Test func failedPromotionRetriesPersistenceWithoutReadingTheSourceAgain() async throws {
    let folder = try scratch()
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: folder.path())
      try? FileManager.default.removeItem(at: folder)
    }
    let item = SharedItem(url: ImportFixtures.tacosLink)
    let store = RetainedSharedDraftStore(folder: folder)
    try store.write(RetainedSharedDraft(item: item))
    let session = try SharedDraftSession(id: item.id, store: store)
    let fetcher = ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)])
    let importer = ImportModel(fetcher: fetcher, extractor: nil, options: ImportFixtures.quick)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path())
    session.retry(using: importer)
    await importer.finished()
    guard case .failed(let notice) = importer.phase else {
      Issue.record("An unkept result must not open an editor"); return
    }
    #expect(notice.canRetry)
    #expect(store.read(item.id)?.recipeDraft == nil)
    #expect(!session.isParsed)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path())
    importer.retry()
    guard case .ready = importer.phase else {
      Issue.record("Persistence retry should open the editor"); return
    }
    #expect(fetcher.requests.count == 1)
    #expect(store.read(item.id)?.recipeDraft?.title == "Smoky black bean tacos")
  }

  @Test(arguments: ["envelope", "parsed", "draft", "damaged"])
  func unsupportedAndDamagedParsedDraftsRecoverTheirSourceAndKeepEvidence(payload: String)
    async throws
  {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let item = SharedItem(url: ImportFixtures.tacosLink, text: "Original text")
    var object = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(RetainedSharedDraft(item: item, draft: RecipeDraft())))
        as? [String: Any])
    switch payload {
    case "envelope": object["version"] = 900
    case "parsed":
      var parsed = try #require(object["parsed"] as? [String: Any])
      parsed["version"] = 900
      object["parsed"] = parsed
    case "draft":
      var parsed = try #require(object["parsed"] as? [String: Any])
      var draft = try #require(parsed["draft"] as? [String: Any])
      draft["version"] = 900
      parsed["draft"] = draft
      object["parsed"] = parsed
    default: object["parsed"] = "damaged recipe data"
    }
    let evidence = try JSONSerialization.data(withJSONObject: object)
    let file = folder.appending(path: "\(item.id.uuidString).json")
    try evidence.write(to: file)
    let queue = SharedImportQueue(
      folder: folder.appending(path: "legacy"), retainedFolder: folder, enabled: true)
    queue.request(item.id)
    let session = try #require(queue.nextSession())
    #expect(!session.isParsed)
    #expect(session.retained.item == item)
    #expect(session.retained.recoveryEvidence == evidence)
    #expect(try Data(contentsOf: file) == evidence)
    let importer = ImportModel(
      fetcher: ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)]),
      extractor: nil, options: ImportFixtures.quick)
    session.retry(using: importer)
    await importer.finished()
    let resumed = try SharedDraftSession(id: item.id, store: session.store)
    #expect(resumed.draft.title == "Smoky black bean tacos")
    #expect(resumed.retained.recoveryEvidence == evidence)
  }

  @Test(arguments: [RetainedSharedDraft.Status.saved, .discarded])
  func unsupportedNestedPayloadsKeepTerminalKnowledge(status: RetainedSharedDraft.Status) throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = RetainedSharedDraftStore(folder: folder)
    for nestedDraft in [false, true] {
      let item = SharedItem(url: ImportFixtures.tacosLink, text: "Original text")
      var retained = RetainedSharedDraft(item: item, draft: RecipeDraft())
      retained.status = status
      if nestedDraft {
        retained.parsed?.draft.version = KeptDraft.currentVersion + 1
      } else {
        retained.parsed?.version = FinishedRecipe.currentVersion + 1
      }
      let evidence = try JSONEncoder().encode(retained)
      let file = folder.appending(path: "\(item.id.uuidString).json")
      try evidence.write(to: file)
      let queue = SharedImportQueue(
        folder: folder.appending(path: "legacy"), retainedFolder: folder, enabled: true)
      queue.request(item.id)
      queue.pickUp()
      #expect(queue.nextSession() == nil)
      let recovered = try #require(store.read(item.id))
      #expect(recovered.status == status)
      #expect(recovered.item == item)
      #expect(recovered.recoveryEvidence == evidence)
      #expect(try Data(contentsOf: file) == evidence)
    }
  }

  @Test func unreadableEvidenceOpensAnExplanationAndIsNeverConsumed() throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let id = UUID()
    let evidence = Data("interrupted or unreadable draft".utf8)
    let file = folder.appending(path: "\(id.uuidString).json")
    try evidence.write(to: file)
    let queue = SharedImportQueue(
      folder: folder.appending(path: "legacy"), retainedFolder: folder, enabled: true)
    queue.request(id)
    let session = try #require(queue.nextSession())
    let importer = ImportModel(fetcher: ScriptedFetcher(), extractor: nil)
    session.retry(using: importer)
    guard case .failed(let notice) = importer.phase else {
      Issue.record("Unreadable data needs an explanation"); return
    }
    #expect(notice.message == Copy.sharedRetry.unreadable)
    #expect(try Data(contentsOf: file) == evidence)
    try session.discard()
    #expect(session.store.read(id)?.status == .discarded)
    #expect(session.store.read(id)?.recoveryEvidence == evidence)
  }

  private func scratch() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

}
