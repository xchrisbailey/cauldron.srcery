import CauldronKit
import Foundation
import Testing

@Suite("Image file type")
struct ImageFileTypeTests {
  private static func bytes(_ values: [UInt8], padding: Int = 12) -> Data {
    Data(values + [UInt8](repeating: 0, count: padding))
  }

  private static func ascii(_ text: String) -> [UInt8] { Array(text.utf8) }

  static let cases: [(name: String, data: Data, ext: String)] = [
    ("JPEG", bytes([0xFF, 0xD8, 0xFF, 0xE0]), "jpg"),
    ("PNG", bytes([0x89] + ascii("PNG") + [0x0D, 0x0A, 0x1A, 0x0A]), "png"),
    ("GIF", bytes(ascii("GIF89a")), "gif"),
    ("WebP", bytes(ascii("RIFF") + [0, 0, 0, 0] + ascii("WEBP")), "webp"),
    ("HEIC", bytes([0, 0, 0, 0x18] + ascii("ftypheic")), "heic"),
    ("HEIF with a generic brand", bytes([0, 0, 0, 0x18] + ascii("ftypmif1")), "heic"),
    ("AVIF", bytes([0, 0, 0, 0x18] + ascii("ftypavif")), "avif"),
    ("something else", bytes(ascii("not an image")), "bin"),
    ("nothing", Data(), "bin"),
    ("two bytes", Data([0xFF, 0xD8]), "bin"),
  ]

  @Test("names the file extension from the first bytes", arguments: cases)
  func sniffs(_ example: (name: String, data: Data, ext: String)) {
    #expect(ImageFileType.fileExtension(of: example.data) == example.ext, "\(example.name)")
  }
}
