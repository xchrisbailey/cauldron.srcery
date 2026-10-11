import CauldronKit
import Testing

@Suite("Export copy")
struct ExportCopyTests {
  @Test func everyStringIsPlain() {
    let copy = Copy.export
    let strings = [
      copy.title, copy.explanation, copy.action, copy.working, copy.share, copy.failed,
      copy.ready(recipes: 2, photos: 1), copy.skipped(1), copy.skipped(3),
    ]
    #expect(strings.allSatisfy { $0.tone == .plain && !$0.text.isEmpty })
  }

  @Test func countsFollowTheNumber() {
    #expect(Copy.export.ready(recipes: 1, photos: 1).text == "Exported 1 recipe and 1 photo.")
    #expect(Copy.export.ready(recipes: 0, photos: 12).text == "Exported 0 recipes and 12 photos.")
    #expect(Copy.export.skipped(1).text == "1 entry couldn't be read, so it was left out.")
    #expect(Copy.export.skipped(2).text == "2 entries couldn't be read, so they were left out.")
  }
}
