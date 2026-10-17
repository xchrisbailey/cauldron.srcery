import CauldronKit
import Compression
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Cauldron
@testable import CauldronImports

@Suite("Import cover photo")
struct CoverPhotoTests {
  private let link = "https://cook.example/img/cover.png"

  @Test func aPhotoIsFetchedWithTheImageLimitAndComesBackDownscaled() async throws {
    let fetcher = ScriptedFetcher([link: .image(ImportFixtures.imageData(4000, 1000))])
    let photo = try #require(await CoverPhoto.fetch(link, using: fetcher))
    #expect(photo.width == PhotoProcessing.maxPixel && photo.height == 512)
    let request = try #require(fetcher.requests.first)
    #expect(request.maxBytes == 15 * 1024 * 1024)
    #expect(request.accept == "image/*")
  }

  @Test func aServerThatDoesntSayWhatItSentIsGivenTheBenefitOfTheDoubt() async {
    for type in [nil, "application/octet-stream", "IMAGE/JPEG; q=1"] {
      let fetcher = ScriptedFetcher([link: .image(ImportFixtures.imageData(), type: type)])
      #expect(await CoverPhoto.fetch(link, using: fetcher) != nil, "\(String(describing: type))")
    }
  }

  @Test func theWrongTypeIsDroppedWithoutAnError() async {
    let fetcher = ScriptedFetcher([link: .image(ImportFixtures.imageData(), type: "text/html")])
    #expect(await CoverPhoto.fetch(link, using: fetcher) == nil)
  }

  @Test func bytesThatAreNotAnImageAreDropped() async {
    let fetcher = ScriptedFetcher([link: .image(Data("<html></html>".utf8))])
    #expect(await CoverPhoto.fetch(link, using: fetcher) == nil)
  }

  @Test func aPhotoOverTheLimitIsDropped() async {
    let big = Data(repeating: 0, count: PhotoProcessing.maxBytes + 1)
    #expect(await CoverPhoto.fetch(link, using: ScriptedFetcher([link: .image(big)])) == nil)
    #expect(await CoverPhoto.fetch(link, using: ScriptedFetcher([link: .fail(.tooLarge)])) == nil)
  }

  @Test func everyFetchFailureIsDroppedQuietly() async {
    for error in [
      FetchError.blocked(), .unreachable(detail: "dns"), .status(404), .timeout, .cancelled,
    ] {
      #expect(await CoverPhoto.fetch(link, using: ScriptedFetcher([link: .fail(error)])) == nil)
    }
  }

  @Test func aLinkThatIsNotOneToOpenIsNeverFetched() async {
    let fetcher = ScriptedFetcher()
    for bad in ["file:///etc/passwd", "ftp://x.example/a.png", "", "data:image/png;base64,AAAA"] {
      #expect(await CoverPhoto.fetch(bad, using: fetcher) == nil)
    }
    #expect(fetcher.requests.isEmpty)
  }

  @Test func aPhotoThatTakesTooLongIsGivenUpOn() async {
    let fetcher = ScriptedFetcher([link: .hold])
    let photo = await CoverPhoto.fetch(link, using: fetcher, timeout: .milliseconds(50))
    #expect(photo == nil)
  }

  // MARK: Bounds

  /// A single-colour 1-bit PNG declaring `width` x `height`: a few KB for ten thousand pixels
  /// a side, which decoded would be about 400 MB.
  private func png(declaring width: UInt32, _ height: UInt32) -> Data {
    func be(_ value: UInt32) -> [UInt8] {
      (0..<4).map { UInt8(truncatingIfNeeded: value >> (24 - 8 * UInt32($0))) }
    }
    func crc32(_ bytes: [UInt8]) -> UInt32 {
      var crc: UInt32 = 0xFFFF_FFFF
      for byte in bytes {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
      }
      return ~crc
    }
    func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
      let typed = Array(type.utf8) + body
      return be(UInt32(body.count)) + typed + be(crc32(typed))
    }
    // Every row is a filter byte and the pixels, all zero.
    let rowBytes = 1 + (Int(width) + 7) / 8
    let raw = [UInt8](repeating: 0, count: rowBytes * Int(height))
    var deflated = [UInt8](repeating: 0, count: raw.count / 100 + 1024)
    let size = compression_encode_buffer(
      &deflated, deflated.count, raw, raw.count, nil, COMPRESSION_ZLIB)
    var a: UInt32 = 1
    var b: UInt32 = 0
    for byte in raw {
      a = (a + UInt32(byte)) % 65521
      b = (b + a) % 65521
    }
    let zlib = [0x78, 0x9C] + deflated.prefix(size) + be((b << 16) | a)
    let header = be(width) + be(height) + [1, 0, 0, 0, 0]
    return Data(
      [137, 80, 78, 71, 13, 10, 26, 10] + chunk("IHDR", header) + chunk("IDAT", zlib)
        + chunk("IEND", []))
  }

  @Test func aTinyFileThatDeclaresAHugeImageIsRefusedBeforeItIsDecoded() async throws {
    let bomb = png(declaring: 10_000, 10_000)
    #expect(bomb.count < 100_000, "\(bomb.count) bytes")
    // Refused for its declared size, read from the header: nothing was decoded, or the
    // process would be holding 400 MB.
    #expect(PhotoProcessing.process(bomb, maxPixels: CoverPhoto.maxPixels) == .failure(.tooBig))
    #expect(CoverPhoto.maxPixels == 24_000_000)
    let fetcher = ScriptedFetcher([link: .image(bomb)])
    #expect(await CoverPhoto.fetch(link, using: fetcher) == nil)
  }

  @Test func thePixelLimitIsHonouredAtItsEdgeAndThePickerKeepsItsOwn() throws {
    let square = ImportFixtures.imageData(100, 100)
    let over = PhotoProcessing.process(square, maxPixels: 9_999)
    let exact = PhotoProcessing.process(square, maxPixels: 10_000)
    #expect(over == .failure(.tooBig))
    _ = try exact.get()
    #expect(PhotoProcessing.maxPixels == 100_000_000)
    // The picker's default allows what a page may not.
    #expect(CoverPhoto.maxPixels < PhotoProcessing.maxPixels)
  }

  @Test func aSlowDecodeCantHoldTheImportPastTheLimit() async {
    let fetcher = ScriptedFetcher([link: .image(ImportFixtures.imageData())])
    let clock = ContinuousClock()
    let started = clock.now
    let photo = await CoverPhoto.fetch(link, using: fetcher, timeout: .milliseconds(100)) { _ in
      Thread.sleep(forTimeInterval: 2)
      return ProcessedPhoto(data: Data([1]), width: 1, height: 1)
    }
    #expect(photo == nil, "the late result is dropped")
    #expect(clock.now - started < .seconds(1))
  }

  @Test func aDecodeThatFinishesInTimeIsUsed() async {
    let fetcher = ScriptedFetcher([link: .image(ImportFixtures.imageData())])
    let expected = ProcessedPhoto(data: Data([9]), width: 1, height: 1)
    let photo = await CoverPhoto.fetch(link, using: fetcher) { _ in expected }
    #expect(photo == expected)
  }

  @Test func cancellingTheImportEndsTheStepAtOnce() async {
    let fetcher = ScriptedFetcher([link: .hold])
    let task = Task { await CoverPhoto.fetch(link, using: fetcher) }
    while fetcher.startedCount == 0 { await Task.yield() }
    task.cancel()
    #expect(await task.value == nil)
  }

  @Test func aCoverPhotoAtAPrivateAddressIsNeverRequested() async {
    let live = URLSessionPageFetcher(protocolClasses: [StubNetwork.self])
    for address in ["http://192.168.1.1/cover.png", "http://localhost/cover.png"] {
      StubNetwork.set(address, .respond(chunks: [ImportFixtures.imageData()]))
      #expect(await CoverPhoto.fetch(address, using: live) == nil)
      #expect(StubNetwork.started(address) == 0)
    }
  }
}
