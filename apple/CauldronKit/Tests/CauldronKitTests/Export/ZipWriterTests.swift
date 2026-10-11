import CauldronKit
import Foundation
import Testing

/// What a zip reader finds, read straight from the central directory so the test doesn't
/// depend on the writer's own bookkeeping.
private struct ZipFile {
  struct Entry {
    var name: String
    var method: Int
    var crc32: UInt32
    var size: Int
    var data: Data
  }

  var entries: [Entry] = []

  init(_ bytes: Data) throws {
    let bytes = [UInt8](bytes)
    func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
    func u32(_ at: Int) -> UInt32 { UInt32(u16(at)) | UInt32(u16(at + 2)) << 16 }

    let end = bytes.count - 22
    try #require(end >= 0 && u32(end) == 0x0605_4b50, "no end of central directory")
    let count = u16(end + 10)
    #expect(u16(end + 8) == count)
    var cursor = Int(u32(end + 16))
    for _ in 0..<count {
      try #require(u32(cursor) == 0x0201_4b50, "bad central directory entry")
      let method = u16(cursor + 10)
      let crc = u32(cursor + 16)
      let size = Int(u32(cursor + 24))
      let nameLength = u16(cursor + 28)
      let extraLength = u16(cursor + 30)
      let commentLength = u16(cursor + 32)
      let offset = Int(u32(cursor + 42))
      let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
      cursor += 46 + nameLength + extraLength + commentLength

      try #require(u32(offset) == 0x0403_4b50, "bad local header for \(name)")
      let start = offset + 30 + u16(offset + 26) + u16(offset + 28)
      entries.append(
        Entry(
          name: name, method: method, crc32: crc, size: size,
          data: Data(bytes[start..<(start + size)])))
    }
    #expect(cursor == end, "the central directory should end where the end record starts")
  }
}

@Suite("Zip writer")
struct ZipWriterTests {
  private func scratch() throws -> URL {
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "ZipWriterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  @Test func crc32MatchesTheStandardCheckValue() {
    // The CRC-32 check value from the PNG and zip specs.
    #expect(ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    #expect(ZipWriter.crc32(Data()) == 0)
  }

  @Test func storesEveryEntryWithItsNameAndBytes() throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "photos.zip")
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
    let big = Data((0..<70_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })

    let writer = try ZipWriter(writingTo: url, modified: Date(timeIntervalSince1970: 1_760_000_000))
    try writer.add("photos/one.jpg", contents: jpeg)
    try writer.add("photos/crème brûlée.png", contents: big)
    try writer.add("empty.bin", contents: Data())
    try writer.finish()

    let zip = try ZipFile(Data(contentsOf: url))
    #expect(zip.entries.map(\.name) == ["photos/one.jpg", "photos/crème brûlée.png", "empty.bin"])
    #expect(zip.entries.map(\.data) == [jpeg, big, Data()])
    #expect(zip.entries.map(\.method) == [0, 0, 0])
    #expect(zip.entries.map(\.size) == [10, 70_000, 0])
    #expect(zip.entries.map(\.crc32) == [ZipWriter.crc32(jpeg), ZipWriter.crc32(big), 0])
  }

  @Test func anEmptyArchiveIsStillAValidZip() throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "empty.zip")
    let writer = try ZipWriter(writingTo: url)
    try writer.finish()
    #expect(try ZipFile(Data(contentsOf: url)).entries.isEmpty)
  }

  @Test func refusesAnEntryAfterFinishing() throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let writer = try ZipWriter(writingTo: folder.appending(path: "done.zip"))
    try writer.finish()
    #expect(throws: ZipError.finished) { try writer.add("late.txt", contents: Data([1])) }
  }

  @Test func refusesTwoEntriesWithOneName() throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let writer = try ZipWriter(writingTo: folder.appending(path: "dupe.zip"))
    try writer.add("a.txt", contents: Data([1]))
    #expect(throws: ZipError.duplicateName("a.txt")) {
      try writer.add("a.txt", contents: Data([2]))
    }
  }
}
