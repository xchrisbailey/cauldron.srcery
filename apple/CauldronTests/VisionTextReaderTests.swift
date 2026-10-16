import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Cauldron
@testable import CauldronImports

/// The live reader, against a picture drawn here: a recipe page set in two columns under a
/// title. This runs Vision for real (on the device or the simulator the tests run on), so it
/// checks the whole chain: decoding, recognition, the flip from Vision's boxes to the page's, and
/// the reading order.
@Suite("Vision text reader")
struct VisionTextReaderTests {
  private struct Line {
    var text: String
    var x: Double
    /// Down from the top of the page.
    var y: Double
  }

  /// A white page of black text, as PNG bytes.
  private func page(_ lines: [Line], width: Int = 1400, height: Int = 1800, size: Double = 52)
    -> Data
  {
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return Data() }
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    for line in lines {
      let text = NSAttributedString(
        string: line.text,
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): font,
          NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
      context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
      // Core Graphics counts up from the bottom; the page counts down from the top.
      context.textPosition = CGPoint(x: line.x, y: Double(height) - line.y)
      CTLineDraw(CTLineCreateWithAttributedString(text), context)
    }
    let data = NSMutableData()
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else { return Data() }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
  }

  private func words(in text: String) -> [String] {
    text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
  }

  @Test func readsALaidOutPageInReadingOrder() async throws {
    let picture = page([
      Line(text: "Tomato soup", x: 480, y: 200),
      Line(text: "2 white onions", x: 100, y: 450),
      Line(text: "3 large carrots", x: 100, y: 560),
      Line(text: "50 g butter", x: 100, y: 670),
      Line(text: "Simmer gently", x: 760, y: 450),
      Line(text: "Season well", x: 760, y: 560),
      Line(text: "Serve hot", x: 760, y: 670),
    ])
    let text = try await VisionTextReader().read(picture)
    let found = words(in: text)
    for word in ["tomato", "onions", "carrots", "butter", "simmer", "season", "serve"] {
      #expect(found.contains(word), "'\(word)' should have been read: \(text)")
    }
    // The title, then the left column in full, then the right, not read across.
    let order = ["tomato", "onions", "carrots", "butter", "simmer", "season", "serve"]
      .compactMap { found.firstIndex(of: $0) }
    #expect(order == order.sorted(), "wrong order: \(text)")
  }

  @Test func aPictureWithNoTextReadsAsEmpty() async throws {
    let text = try await VisionTextReader().read(page([]))
    #expect(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  @Test func aLargePictureIsShrunkBeforeItIsRead() async throws {
    let reader = VisionTextReader.self
    let big = try #require(
      reader.page(from: ImportFixtures.imageData(9000, 6000, as: .jpeg), longSide: 4096))
    #expect(max(big.width, big.height) == 4096)
    let small = try #require(reader.page(from: ImportFixtures.imageData(300, 200), longSide: 4096))
    #expect(max(small.width, small.height) == 300, "never enlarged")
  }

  @Test func bytesThatArentAPictureAreUnreadable() async {
    await #expect(throws: PageReadError.unreadable) {
      _ = try await VisionTextReader().read(Data("not a picture".utf8))
    }
  }
}
