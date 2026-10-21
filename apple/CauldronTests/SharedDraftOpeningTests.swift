import CauldronImports
import CauldronKit
import Foundation
import Testing

@testable import Cauldron

@MainActor
@Suite("Shared draft opening")
struct SharedDraftOpeningTests {
  @Test func openingWaitsForRetentionAndCompletionWaitsForOpening() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let item = SharedItem(url: ImportFixtures.tacosLink)
    let opener = ControlledDraftOpener(store: RetainedSharedDraftStore(folder: folder))
    var closings: [ShareSheetModel.Closing] = []
    let fetcher = ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)])
    let sheet = ShareSheetModel(
      item: item,
      importer: ImportModel(fetcher: fetcher, extractor: nil, options: ImportFixtures.quick),
      finishedFolder: nil, inboxFolder: nil, closeDelay: .zero,
      retainedFolder: folder, opener: opener, close: { closings.append($0) })
    sheet.start()
    await sheet.finished()
    sheet.currentDraft?.title = "Corrected tacos"
    sheet.sendToCauldron()
    sheet.sendToCauldron()
    await opener.requested()
    #expect(opener.identities == [item.id])
    #expect(opener.retainedTitles == ["Corrected tacos"])
    #expect(closings.isEmpty)
    #expect(sheet.isOpening)
    opener.complete(.opened)
    await sheet.closed()
    #expect(closings == [.done])
    #expect(!sheet.isOpening)
    #expect(sheet.openingResult == .opened)
    // URL delivery before activation and repeated delivery still use the existing gate.
    let queue = SharedImportQueue(
      folder: folder.appending(path: "legacy"), finishedFolder: folder.appending(path: "finished"),
      retainedFolder: folder, enabled: true)
    let editor = UUID()
    queue.editorOpened(editor)
    queue.request(item.id)
    queue.pickUp()
    queue.request(item.id)
    #expect(queue.waiting == 1)
    #expect(queue.nextSession() == nil)
    queue.editorClosed(editor)
    let session = try #require(queue.nextSession())
    #expect(session.id == item.id)
    #expect(session.draft.title == "Corrected tacos")
    #expect(fetcher.requests.count == 1)
    #expect(opener.store.read(item.id)?.status == .editing)
  }

  @Test(arguments: [true, false])
  func cancellationPreventsDispatchBeforeTheOpeningTaskStarts(cancelFirst: Bool) async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let opener = ControlledDraftOpener(
      store: RetainedSharedDraftStore(folder: folder), result: .opened)
    var closings: [ShareSheetModel.Closing] = []
    let sheet = makeSheet(folder: folder, opener: opener) { closings.append($0) }
    sheet.start()
    await sheet.finished()
    if cancelFirst {
      sheet.cancel()
      sheet.sendToCauldron()
    } else {
      sheet.sendToCauldron()
      sheet.cancel()
    }
    await sheet.closed()
    #expect(opener.identities.isEmpty)
    #expect(closings == [.cancelled])
    #expect(sheet.openingResult == nil)
    #expect(!sheet.isOpening)
  }

  @Test(arguments: [SharedDraftOpeningResult.failed, .unsupported])
  func unsuccessfulOpeningKeepsTheDraftAndExplainsManualContinuation(
    result: SharedDraftOpeningResult
  ) async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let opener = ControlledDraftOpener(store: RetainedSharedDraftStore(folder: folder))
    var closings: [ShareSheetModel.Closing] = []
    let sheet = makeSheet(folder: folder, opener: opener) { closings.append($0) }
    sheet.start()
    await sheet.finished()
    sheet.currentDraft?.title = "Kept despite opening failure"
    sheet.sendToCauldron()
    await opener.requested()
    opener.complete(result)
    await sheet.closed()
    let id = try #require(sheet.retainedDraftID)
    #expect(opener.store.read(id)?.recipeDraft?.title == "Kept despite opening failure")
    #expect(sheet.openingResult == result)
    #expect(!sheet.isOpening)
    if result == .failed {
      #expect(closings.isEmpty)
      #expect(sheet.continuationDetail == Copy.sharedOpening.couldntOpen)
      sheet.finishManualContinuation()
      sheet.finishManualContinuation()
    } else {
      #expect(sheet.continuationDetail == Copy.sharedDrafts.openToFinish)
    }
    #expect(closings == [.done])
    // Activation before explicit URL delivery also opens the exact retained draft once.
    let queue = SharedImportQueue(
      folder: folder.appending(path: "legacy"), finishedFolder: folder.appending(path: "finished"),
      retainedFolder: folder, enabled: true)
    queue.pickUp()
    queue.request(id)
    let session = try #require(queue.nextSession())
    #expect(session.id == id)
    #expect(session.draft.title == "Kept despite opening failure")
    try session.discard()
    queue.closedSession(id)
    queue.request(id)
    queue.pickUp()
    #expect(queue.nextSession() == nil)
  }

  @Test func persistenceFailurePreventsOpeningAndPreservesCorrections() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let opener = ControlledDraftOpener(
      store: RetainedSharedDraftStore(folder: file), result: .opened)
    var closed = false
    let sheet = makeSheet(folder: file, opener: opener) { _ in closed = true }
    sheet.start()
    await sheet.finished()
    sheet.currentDraft?.title = "Still here"
    sheet.sendToCauldron()
    await sheet.closed()
    #expect(sheet.retainedFailure != nil)
    #expect(sheet.currentDraft?.title == "Still here")
    #expect(sheet.retainedDraftID == nil)
    #expect(opener.identities.isEmpty)
    #expect(!closed)
  }

  @Test func ordinarySaveNeverRequestsOpening() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let opener = ControlledDraftOpener(
      store: RetainedSharedDraftStore(folder: folder), result: .opened)
    var closings: [ShareSheetModel.Closing] = []
    let sheet = makeSheet(folder: folder, opener: opener) { closings.append($0) }
    sheet.start()
    await sheet.finished()
    sheet.save()
    await sheet.closed()
    #expect(sheet.phase == .saved)
    #expect(closings == [.done])
    #expect(opener.identities.isEmpty)
    #expect(sheet.retainedDraftID == nil)
    #expect(FinishedInbox.pending(from: folder).count == 1)
  }

  @Test func lateOpeningResultAfterCancellationDoesNotCompleteAgain() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let opener = ControlledDraftOpener(store: RetainedSharedDraftStore(folder: folder))
    var closings: [ShareSheetModel.Closing] = []
    let sheet = makeSheet(folder: folder, opener: opener) { closings.append($0) }
    sheet.start()
    await sheet.finished()
    sheet.sendToCauldron()
    await opener.requested()
    sheet.cancel()
    opener.complete(.opened)
    await sheet.closed()
    sheet.sendToCauldron()
    #expect(closings == [.cancelled])
    #expect(sheet.openingResult == nil)
    #expect(opener.identities.count == 1)
    #expect(opener.store.read(try #require(sheet.retainedDraftID))?.status == .editing)
  }

  private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  private func makeSheet(
    folder: URL, opener: ControlledDraftOpener,
    close: @escaping @MainActor (ShareSheetModel.Closing) -> Void
  ) -> ShareSheetModel {
    ShareSheetModel(
      item: SharedItem(url: ImportFixtures.tacosLink),
      importer: ImportModel(
        fetcher: ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)]),
        extractor: nil, options: ImportFixtures.quick),
      finishedFolder: folder, inboxFolder: nil, closeDelay: .zero,
      retainedFolder: folder, opener: opener, close: close)
  }

}

@MainActor
private final class ControlledDraftOpener: SharedDraftOpening {
  let store: RetainedSharedDraftStore
  private(set) var identities: [UUID] = []
  private(set) var retainedTitles: [String?] = []
  private var pending: CheckedContinuation<SharedDraftOpeningResult, Never>?
  private let result: SharedDraftOpeningResult?
  private var onRequest: CheckedContinuation<Void, Never>?

  init(store: RetainedSharedDraftStore, result: SharedDraftOpeningResult? = nil) {
    self.store = store
    self.result = result
  }

  func open(_ id: UUID) async -> SharedDraftOpeningResult {
    identities.append(id)
    retainedTitles.append(store.read(id)?.recipeDraft?.title)
    if let result { return result }
    return await withCheckedContinuation { continuation in
      pending = continuation
      onRequest?.resume()
      onRequest = nil
    }
  }

  func requested() async {
    if !identities.isEmpty { return }
    await withCheckedContinuation { onRequest = $0 }
  }

  func complete(_ result: SharedDraftOpeningResult) {
    pending?.resume(returning: result)
    pending = nil
  }
}
