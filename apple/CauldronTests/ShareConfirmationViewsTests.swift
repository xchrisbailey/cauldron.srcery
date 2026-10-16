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
