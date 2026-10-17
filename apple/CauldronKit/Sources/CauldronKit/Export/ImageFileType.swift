import Foundation

/// Names a photo's file in the export by what its bytes are, since the store keeps the image
/// without a name or a type.
public enum ImageFileType {
  /// The extension for `data`, or `bin` when it isn't an image format the app writes or can
  /// import from a camera roll.
  public static func fileExtension(of data: Data) -> String {
    let head = [UInt8](data.prefix(12))
    func has(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
      head.count >= offset + prefix.count && Array(head[offset..<(offset + prefix.count)]) == prefix
    }
    if has([0xFF, 0xD8, 0xFF]) { return "jpg" }
    if has([0x89, 0x50, 0x4E, 0x47]) { return "png" }
    if has(Array("GIF8".utf8)) { return "gif" }
    if has(Array("RIFF".utf8)) && has(Array("WEBP".utf8), at: 8) { return "webp" }
    if has(Array("ftyp".utf8), at: 4) {
      return has(Array("avif".utf8), at: 8) ? "avif" : "heic"
    }
    return "bin"
  }
}
