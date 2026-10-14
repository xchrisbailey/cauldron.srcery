import Foundation
import Testing

@testable import Cauldron

@Suite("Share inbox")
struct ShareInboxTests {
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "ShareInboxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func itemsComeOutOldestFirstAndOnlyOnce() throws {
    let inbox = try folder()
    defer { try? FileManager.default.removeItem(at: inbox) }
    let later = SharedItem(url: "https://b.example/soup", sharedAt: .now)
    let earlier = SharedItem(text: "2 eggs. Fry them.", sharedAt: .now.addingTimeInterval(-60))
    try ShareInbox.add(later, in: inbox)
    try ShareInbox.add(earlier, in: inbox)
    #expect(ShareInbox.takeAll(from: inbox) == [earlier, later])
    #expect(ShareInbox.takeAll(from: inbox).isEmpty)
  }

  @Test func longTextIsCutAndAnUnreadableFileIsDropped() throws {
    let inbox = try folder()
    defer { try? FileManager.default.removeItem(at: inbox) }
    try ShareInbox.add(
      SharedItem(text: String(repeating: "a", count: ShareInbox.textMax + 10)), in: inbox)
    try Data("not json".utf8).write(to: inbox.appending(path: "broken.json"))
    let items = ShareInbox.takeAll(from: inbox)
    #expect(items.count == 1)
    #expect(items.first?.text?.count == ShareInbox.textMax)
    #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.path()).isEmpty)
  }

  @Test func withoutAnInboxNothingIsWritten() {
    #expect(throws: (any Error).self) { try ShareInbox.add(SharedItem(text: "x"), in: nil) }
    #expect(ShareInbox.takeAll(from: nil).isEmpty)
  }
}
