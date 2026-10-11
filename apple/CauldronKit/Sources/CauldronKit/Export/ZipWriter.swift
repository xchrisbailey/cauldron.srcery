import Foundation

public enum ZipError: Error, Hashable {
  /// An entry was added after `finish()`.
  case finished
  case duplicateName(String)
  /// The archive would need Zip64: more than 65,535 entries, or 4 GiB. A recipe box doesn't.
  case tooLarge
}

/// Writes a zip archive one entry at a time, so a few hundred photos never sit in memory
/// together. Entries are stored, not deflated: the photos are JPEG or HEIC already, and
/// storing keeps the writer short enough to read in one sitting. It needs only Foundation,
/// so it runs on Linux and in the CauldronKit tests.
///
/// The format is PKWARE APPNOTE 6.3.x: a local header and the bytes for each entry, then a
/// central directory and an end record. File names are UTF-8.
public final class ZipWriter {
  private struct Entry {
    var name: [UInt8]
    var crc32: UInt32
    var size: UInt32
    var offset: UInt32
  }

  private let handle: FileHandle
  private let dosTime: UInt16
  private let dosDate: UInt16
  private var entries: [Entry] = []
  private var names: Set<String> = []
  private var offset = 0
  private var isFinished = false

  /// Creates (or replaces) the archive at `url`. `modified` is the time every entry shows.
  public init(writingTo url: URL, modified: Date = .now) throws {
    guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
    else { throw CocoaError(.fileWriteUnknown) }
    handle = try FileHandle(forWritingTo: url)
    (dosTime, dosDate) = Self.dosStamp(modified)
  }

  /// Adds an entry. `name` is the path inside the archive, with `/` between folders.
  public func add(_ name: String, contents: Data) throws {
    guard !isFinished else { throw ZipError.finished }
    guard names.insert(name).inserted else { throw ZipError.duplicateName(name) }
    let nameBytes = Array(name.utf8)
    guard entries.count < Int(UInt16.max), nameBytes.count <= Int(UInt16.max),
      contents.count <= Int(UInt32.max), offset <= Int(UInt32.max)
    else { throw ZipError.tooLarge }

    let entry = Entry(
      name: nameBytes, crc32: Self.crc32(contents), size: UInt32(contents.count),
      offset: UInt32(offset))
    var header = Bytes()
    header.u32(0x0403_4b50)
    header.u16(20)  // version needed
    header.u16(Self.utf8NameFlag)
    header.u16(0)  // stored
    header.u16(dosTime)
    header.u16(dosDate)
    header.u32(entry.crc32)
    header.u32(entry.size)  // compressed size
    header.u32(entry.size)
    header.u16(UInt16(nameBytes.count))
    header.u16(0)  // extra field length
    header.bytes.append(contentsOf: nameBytes)
    try write(header.bytes)
    try write(contents)
    entries.append(entry)
  }

  /// Writes the central directory and closes the file. Call it once; the archive isn't
  /// readable until then.
  public func finish() throws {
    guard !isFinished else { return }
    isFinished = true
    let directoryStart = offset
    var directory = Bytes()
    for entry in entries {
      directory.u32(0x0201_4b50)
      directory.u16(Self.unixMadeBy)
      directory.u16(20)  // version needed
      directory.u16(Self.utf8NameFlag)
      directory.u16(0)  // stored
      directory.u16(dosTime)
      directory.u16(dosDate)
      directory.u32(entry.crc32)
      directory.u32(entry.size)
      directory.u32(entry.size)
      directory.u16(UInt16(entry.name.count))
      directory.u16(0)  // extra field length
      directory.u16(0)  // comment length
      directory.u16(0)  // disk number
      directory.u16(0)  // internal attributes
      directory.u32(Self.regularFile)
      directory.u32(entry.offset)
      directory.bytes.append(contentsOf: entry.name)
    }
    let directorySize = directory.bytes.count
    guard directoryStart + directorySize <= Int(UInt32.max) else { throw ZipError.tooLarge }
    directory.u32(0x0605_4b50)
    directory.u16(0)  // this disk
    directory.u16(0)  // disk with the central directory
    directory.u16(UInt16(entries.count))
    directory.u16(UInt16(entries.count))
    directory.u32(UInt32(directorySize))
    directory.u32(UInt32(directoryStart))
    directory.u16(0)  // comment length
    try write(directory.bytes)
    try handle.close()
  }

  // MARK: Pieces

  private static let utf8NameFlag: UInt16 = 0x0800
  /// Made on Unix (3), by zip 2.0 (20), so the next field's permissions are honoured.
  private static let unixMadeBy: UInt16 = 3 << 8 | 20
  /// `-rw-r--r--` in the high half of the external attributes.
  private static let regularFile: UInt32 = 0o100644 << 16

  private func write(_ bytes: some DataProtocol) throws {
    try handle.write(contentsOf: bytes)
    offset += bytes.count
  }

  private struct Bytes {
    var bytes: [UInt8] = []

    mutating func u16(_ value: UInt16) {
      bytes.append(UInt8(truncatingIfNeeded: value))
      bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func u32(_ value: UInt32) {
      u16(UInt16(truncatingIfNeeded: value))
      u16(UInt16(truncatingIfNeeded: value >> 16))
    }
  }

  /// MS-DOS time and date, in UTC. DOS dates run 1980 to 2107 and have two-second steps.
  private static func dosStamp(_ date: Date) -> (time: UInt16, date: UInt16) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let year = min(max((parts.year ?? 1980) - 1980, 0), 127)
    let time = (parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2
    let day = year << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1)
    return (UInt16(time), UInt16(day))
  }

  // MARK: CRC-32

  private static let crcTable: [UInt32] = (0..<256).map { index in
    (0..<8).reduce(UInt32(index)) { value, _ in
      value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
    }
  }

  /// The CRC-32 zip uses (IEEE 802.3, reflected).
  public static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
      crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }
    return ~crc
  }
}
