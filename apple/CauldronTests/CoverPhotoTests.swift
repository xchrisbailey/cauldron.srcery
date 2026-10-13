import CauldronKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Cauldron

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
}
