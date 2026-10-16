import CauldronKit
import SwiftUI
import Testing

@testable import Cauldron
@testable import CauldronImports

/// The share extension's confirmation and the "more shared" line, drawn in both appearances.
@MainActor
@Suite("Share views")
struct ShareConfirmationViewsTests {
  private func renders(_ view: some View, width: CGFloat = 380, height: CGFloat = 300) -> Bool {
    ImageRenderer(content: view.frame(width: width, height: height)).cgImage != nil
  }

  @Test func theConfirmationRendersForEachOutcome() {
    let outcomes: [ShareConfirmation.Outcome] = [
      .sent(
        title: Copy.importNative.sentToCauldron.text,
        detail: Copy.importNative.opensAsDraft.text),
      .failed(Copy.importNative.nothingToSend.text),
      .failed(Copy.importNative.couldntSend.text),
    ]
    for outcome in outcomes {
      for scheme in [ColorScheme.light, .dark] {
        #expect(
          renders(ShareConfirmation(outcome: outcome).environment(\.colorScheme, scheme)),
          "\(outcome) in \(scheme)")
      }
    }
  }

  @Test func theShareSheetRendersInEachPhaseInBothAppearances() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "ShareViewsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    func sheet(_ item: SharedItem, _ replies: [String: ScriptedFetcher.Reply]) -> ShareSheetModel {
      ShareSheetModel(
        item: item,
        importer: ImportModel(
          fetcher: ScriptedFetcher(replies), extractor: nil, options: ImportFixtures.quick),
        finishedFolder: folder, inboxFolder: folder, closeDelay: .seconds(60), close: { _ in })
    }
    let reading = sheet(
      SharedItem(url: ImportFixtures.tacosLink), [ImportFixtures.tacosLink: .hold])
    reading.start()
    let ready = sheet(
      SharedItem(url: ImportFixtures.tacosLink),
      [ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)])
    ready.start()
    await ready.finished()
    let saved = sheet(
      SharedItem(url: ImportFixtures.tacosLink),
      [ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)])
    saved.start()
    await saved.finished()
    saved.save()
    let failed = sheet(SharedItem(url: "https://down.example/a"), [:])
    failed.start()
    await failed.finished()
    let sent = sheet(SharedItem(url: "https://down.example/a"), [:])
    sent.sendToCauldron()

    let phases: [(ShareSheetModel, String)] = [
      (reading, "reading"), (ready, "ready"), (saved, "saved"), (failed, "failed"),
      (sent, "sent"),
    ]
    for (model, name) in phases {
      for scheme in [ColorScheme.light, .dark] {
        #expect(
          renders(ShareSheetView(model: model).environment(\.colorScheme, scheme)),
          "\(name) in \(scheme)")
      }
    }
    reading.cancel()
  }

  @Test func theWaitingLineRendersInBothAppearances() {
    for scheme in [ColorScheme.light, .dark] {
      for count in [1, 2, 12] {
        #expect(
          renders(
            SharedWaitingBadge(count: count).environment(\.colorScheme, scheme), height: 60),
          "\(count) in \(scheme)")
      }
    }
  }

  @Test func theWaitingLineIsInTheCopyModule() {
    #expect(Copy.importNative.moreShared(2).text == "2 more shared")
    #expect(Copy.importNative.sentToCauldron.text == "Sent to Cauldron")
  }

  @Test func theSheetShowsTheWaitingLineOverTheFormAndTheEditor() throws {
    let container = try CauldronStore.container(.inMemory)
    let flow = ImportModel(
      fetcher: ScriptedFetcher(), extractor: nil, options: ImportFixtures.quick)
    for scheme in [ColorScheme.light, .dark] {
      #expect(
        renders(
          ImportSheet(model: flow, waiting: 2).modelContainer(container)
            .environment(\.colorScheme, scheme), width: 600, height: 900))
    }
  }
}
