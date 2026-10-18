import Foundation
import Testing

@testable import CauldronKit

// Links shared from Apple News. `no-publisher.html` is the stub apple.news served for an article
// with no publisher link (fetched October 2026). `publisher.html` is the same stub with the
// redirect and `og:url` that a publisher's article carries.

@Suite("Apple News links")
struct AppleNewsTests {
  static let stub = "https://apple.news/AQYVt2XxgSXaRTQ7v3ZsZbg"

  static let lemonPasta = """
    <script type="application/ld+json">
    {"@context":"https://schema.org","@type":"Recipe","name":"Lemon pasta",
    "recipeIngredient":["200g spaghetti","1 lemon, zested and juiced","40g parmesan"],
    "recipeInstructions":[{"@type":"HowToStep","text":"Cook the pasta."},
    {"@type":"HowToStep","text":"Toss it with the lemon and parmesan."}]}
    </script>
    """

  private static func fixture(_ name: String) throws -> FakeFetcher.Response {
    .page(
      FetchedPage(
        bytes: Data(try Fixtures.text("apple-news/\(name).html").utf8),
        contentType: "text/html; charset=utf-8", url: ""))
  }

  @Test func findsThePublishersLinkInTheStub() throws {
    let html = try Fixtures.text("apple-news/publisher.html")
    #expect(
      AppleNews.publisherLink(html: html, base: Self.stub)
        == "https://cook.example/recipes/lemon-pasta?utm_source=applenews")
  }

  @Test func importsThePublishersPage() async throws {
    let fetcher = FakeFetcher([
      Self.stub: try Self.fixture("publisher"),
      "https://cook.example/recipes/lemon-pasta?utm_source=applenews": .html(
        "<h1>Lemon pasta</h1>", head: Self.lemonPasta),
    ])
    let got = try await Distill.url(Self.stub, fetcher: fetcher, extractor: nil)
    #expect(got.draft.title == "Lemon pasta")
    #expect(got.draft.ingredients.count == 3)
    #expect(got.draft.sourceUrl == "https://cook.example/recipes/lemon-pasta")
    #expect(got.draft.siteName == "cook.example")
    #expect(await fetcher.requests.count == 2)
  }

  @Test func failsAsNoRecipeWhenTheStubHasNoPublisherLink() async throws {
    let fetcher = FakeFetcher([Self.stub: try Self.fixture("no-publisher")])
    await #expect(throws: DistillError.failed(.noRecipe)) {
      try await Distill.url(Self.stub, fetcher: fetcher, extractor: nil)
    }
    #expect(await fetcher.requests.count == 1)
  }

  @Test func fallsBackToTheCanonicalOrOpenGraphLink() {
    let canonical = #"<link rel="canonical" href="https://cook.example/a">"#
    let graph = #"<meta property="og:url" content="https://cook.example/b">"#
    #expect(AppleNews.publisherLink(html: canonical, base: Self.stub) == "https://cook.example/a")
    #expect(AppleNews.publisherLink(html: graph, base: Self.stub) == "https://cook.example/b")
  }

  @Test func ignoresLinksBackToAppleNewsAndOtherSchemes() {
    let html = """
      <script>redirectToUrlAfterTimeout("applenews:///AQYV", 0);</script>
      <link rel="canonical" href="https://apple.news/AQYV">
      <meta property="og:url" content="/AQYV">
      """
    #expect(AppleNews.publisherLink(html: html, base: Self.stub) == nil)
  }

  @Test func onlyReadsStubsOnAppleNews() {
    #expect(AppleNews.isStub("https://apple.news/AQYV"))
    #expect(!AppleNews.isStub("https://news.apple.com/AQYV"))
    #expect(!AppleNews.isStub("https://notapple.news/AQYV"))
  }
}
