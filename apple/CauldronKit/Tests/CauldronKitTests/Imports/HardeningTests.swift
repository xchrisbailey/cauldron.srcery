import Foundation
import Testing

@testable import CauldronKit

// What hostile pages and responses must not be able to do on a phone: run the reader for
// seconds, make it quadratic, or hand the app a link or a character it shouldn't trust.

private func seconds(_ work: () throws -> Void) rethrows -> Double {
  let clock = ContinuousClock()
  let start = clock.now
  try work()
  let elapsed = start.duration(to: clock.now)
  return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
}

// MARK: The final link

/// A fetcher that reports whatever final link it is told to.
private struct ReportsURL: PageFetcher {
  let finalURL: String
  func fetch(_ request: FetchRequest) async throws(FetchError) -> FetchedPage {
    FetchedPage(
      bytes: Data("<html><body><p>hi</p></body></html>".utf8), contentType: "text/html",
      url: finalURL)
  }
}

@Suite("The link a response reports")
struct FinalURLTests {
  @Test(arguments: [
    "javascript:alert(1)", "file:///etc/hosts", "ftp://cook.example/x", "garbage", "",
    "data:text/html,hi", "//cook.example/x", "https://u:p@cook.example/x",
    "https://cook.example:99999/x", "https:///",
  ])
  func refusesAFinalLinkThatIsNotAnHTTPLinkWithoutCredentials(finalURL: String) async {
    await #expect(throws: DistillError.failed(.blocked)) {
      try await Distill.url(
        "https://cook.example/p", fetcher: ReportsURL(finalURL: finalURL), extractor: nil)
    }
  }

  @Test func refusesItForASharedPostToo() async {
    await #expect(throws: DistillError.failed(.blocked)) {
      try await Distill.url(
        "https://vm.tiktok.com/ZMabc123/", fetcher: ReportsURL(finalURL: "javascript:alert(1)"),
        extractor: nil)
    }
  }
}

// MARK: Backtracking

@Suite("Durations")
struct DurationTests {
  /// The reference's `DURATION`, as it was ported at first: kept here to compare the scanner
  /// that replaced it on short inputs. It is exponential on a long failing line.
  private static let oracle = JSRegex(
    "^(?:about\(JS.s)+|approx\\.?\(JS.s)+)?[0-9½¼¾.,\(JS.space)\\-–]+"
      + "(?:\(JS.s)*(?:hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|and|to)\(JS.endWord)"
      + "[0-9½¼¾.,\(JS.space)\\-–]*)*\\z", ignoreCase: true)

  @Test func agreesWithTheReferencePatternOnGeneratedLines() {
    let pieces = [
      "10", "1½", "2.5", " ", "  ", "-", "–", "min", "mins", "minutes", "h", "hr", "hours", "m",
      "s", "sec", "and", "to", "about", "approx", "approx.", "x", "_", ",", ".", "½", "\u{00A0}",
      "MIN", "Hours", "ms", "10m", "30",
    ]
    var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    func next() -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int(seed >> 33)
    }
    var disagreements: [String] = []
    for _ in 0..<30_000 {
      let line = (0..<(1 + next() % 7)).map { _ in pieces[next() % pieces.count] }.joined()
      if TextRecipe.isDuration(line) != Self.oracle.test(line) { disagreements.append(line) }
    }
    #expect(disagreements.isEmpty, "\(disagreements.prefix(10))")
  }

  static let pinned: [JSONValue] = (try? Fixtures.json("pinned/durations.json").items) ?? []

  @Test(arguments: pinned)
  func readsTimeLinesLikeTheReference(entry: JSONValue) throws {
    let duration = try #require(entry["duration"].string)
    let text =
      "Prep: \(duration)\nCook: \(duration)\nBake: \(duration)\nIngredients\n1 egg\nMethod\nCook it."
    let got: JSONValue =
      TextRecipe.read(text).map {
        .object([
          "clarity": .string($0.clarity == .clear ? "clear" : "rough"), "recipe": .of($0.recipe),
        ])
      } ?? .null
    expectSame(got, entry["reading"], "duration \(duration.debugDescription)")
  }

  @Test(arguments: [16, 200, 5000])
  func aLineOfShortUnitWordsThatFailsTheEndIsLinear(tokens: Int) async {
    let line = "Prep: 1 " + String(repeating: "m ", count: tokens) + "x"
    let text = "\(line)\n\nIngredients\n1 egg\n\nMethod\nCook it."
    let took = await seconds {
      _ = TextRecipe.read(text)
    }
    #expect(took < 0.5, "\(tokens) tokens took \(took)s")
    var finished = false
    let viaDistill = ContinuousClock()
    let start = viaDistill.now
    _ = try? await Distill.text(text, extractor: nil)
    finished = start.duration(to: viaDistill.now) < .milliseconds(500)
    #expect(finished)
  }

  @Test func theScannerItselfIsLinear() {
    let line = String(repeating: "1 m ", count: 250_000) + "x"
    #expect(seconds { _ = TextRecipe.isDuration(line) } < 1)
  }
}

@Suite("Pathological text")
struct PathologicalTextTests {
  private func check(_ label: String, _ text: String, limit: Double = 5) async {
    let took = await seconds {
      for kind in [ExtractKind.text, .caption, .page] { _ = Distill.planText(text, kind: kind) }
    }
    #expect(took < limit, "\(label) took \(took)s")
  }

  @Test func decorationRunsThatDontReachTheEnd() async {
    await check("dashes", String(repeating: "- ", count: 24_000) + "x")
    await check("spaces", "Ingredients\n" + String(repeating: " ", count: 40_000) + "x")
    await check("stars", String(repeating: "*", count: 45_000) + "x")
    await check("emoji", String(repeating: "✨", count: 20_000) + "x")
  }

  @Test func separatorsAndUnitsInOneLine() async {
    await check("pipes", "Serves " + String(repeating: "| ", count: 20_000) + "x")
    await check("commas", "Prep " + String(repeating: ",", count: 40_000) + "x")
    await check("spaces", "Prep: 5 min" + String(repeating: " ", count: 40_000) + "x")
  }

  @Test func manyLinesOfEveryKind() async {
    await check(
      "blank lines", "Ingredients\n" + String(repeating: "\n", count: 40_000) + "Method\nx")
    await check(
      "steps", "Ingredients\n1 egg\nMethod\n1. a\n" + String(repeating: "b\n", count: 20_000))
    await check(
      "numbered",
      "Ingredients\n1 egg\nMethod\n" + (1...9000).map { "\($0 % 90). step" }.joined(separator: "\n")
    )
    await check(
      "ingredients", "Ingredients\n" + String(repeating: "1 egg\n", count: 3000) + "Method\nx")
    await check("loose", String(repeating: "2 eggs\n\n", count: 6000) + "stir")
    await check("colons", String(repeating: "a: ", count: 16_000))
  }

  @Test func anInstagramDescriptionOfWhiteSpaceAndNumbers() {
    let spaces = "1" + String(repeating: " ", count: 7000) + "likes"
    let numbers = String(repeating: "1 ", count: 3500)
    let quotes = String(repeating: ": \"", count: 2600) + "x"
    for body in [spaces, numbers, quotes] {
      let html = "<meta property=\"og:description\" content=\"\(body)\">"
      #expect(
        seconds { _ = Social.fromOpenGraph(html, source: .instagram) } < 1.5,
        "\(body.prefix(12))")
    }
  }

  @Test func aLinkThatAlmostMatches() {
    let link = "https://" + String(repeating: "a", count: 2030) + " "
    #expect(seconds { _ = Distill.isAcceptedLink(link) } < 0.5)
  }
}

// MARK: Microdata

@Suite("Microdata scanning")
struct MicrodataScanTests {
  private func page(nesting: Int, prop: String, tag: String = "div") -> String {
    "<html><body><div itemscope itemtype=\"https://schema.org/Recipe\">"
      + (0..<nesting).map { _ in "<\(tag) itemprop=\"\(prop)\">" }.joined() + "x"
      + (0..<nesting).map { _ in "</\(tag)>" }.joined() + "</div></body></html>"
  }

  /// The reading of the item, not the HTML parse before it (SwiftSoup takes about 10 µs per
  /// element, linear, and is not under this code's control).
  @Test(arguments: [5_000, 50_000])
  func nestedPropertiesAreReadInOnePass(nesting: Int) {
    for prop in [
      "name", "recipeIngredient", "recipeInstructions", "author", "image", "recipeYield",
    ] {
      let document = HTMLDocument(page(nesting: nesting, prop: prop))
      let took = seconds {
        _ = SchemaOrg.microdataRecipe(document, base: "https://cook.example/x")
      }
      // 1 s alone; the margin is for the rest of the suite running beside it. The quadratic
      // version took 10 s at 4,000.
      #expect(took < 2.5, "\(nesting) nested \(prop) took \(took)s")
    }
  }

  @Test func nestedListsOfSteps() {
    let html = page(nesting: 5_000, prop: "recipeInstructions", tag: "ol")
    #expect(seconds { _ = Distill.readPage(html: html, url: "https://cook.example/x") } < 1.5)
  }

  @Test func aNestedItemsPropertiesDontBelongToTheOuterOne() {
    let document = HTMLDocument(
      """
      <div itemscope itemtype="https://schema.org/Recipe">
        <span itemprop="name">Soup</span>
        <div itemprop="author" itemscope itemtype="https://schema.org/Person">
          <span itemprop="name">Ada</span>
          <span itemprop="recipeIngredient">not mine</span>
        </div>
        <span itemprop="recipeIngredient">1 onion</span>
      </div>
      """)
    let recipe = SchemaOrg.microdataRecipe(document, base: "https://cook.example/")
    #expect(recipe?.title == "Soup")
    #expect(recipe?.author == "Ada")
    #expect(recipe?.ingredients.map(\.line) == ["1 onion"])
  }
}

// MARK: Image links

@Suite("Image links")
struct ImageLinkTests {
  private func distill(head: String = "", body: String = "", ld: String? = nil) async throws
    -> Distilled
  {
    let recipe =
      ld ?? """
        {"@type":"Recipe","name":"Dal","recipeIngredient":["1 cup lentils"],"recipeInstructions":["Simmer."]}
        """
    let fetcher = FakeFetcher([
      "https://cook.example/p": .html(
        body, head: head + "<script type=\"application/ld+json\">\(recipe)</script>")
    ])
    return try await Distill.url("https://cook.example/p", fetcher: fetcher, extractor: nil)
  }

  @Test(arguments: [
    "javascript:alert(1)", "file:///etc/passwd", "data:image/png;base64,AAAA",
    "ftp://x.example/i.png",
    "https://u:p@cdn.example/i.png", "https://user@cdn.example/i.png", "  ", "http://",
  ])
  func aPagesOpenGraphImageIsHttpOrNothing(link: String) async throws {
    let got = try await distill(head: "<meta property=\"og:image\" content=\"\(link)\">")
    #expect(got.imageUrl == nil)
  }

  @Test(arguments: [
    "javascript:alert(1)", "file:///etc/passwd", "https://u:p@cdn.example/i.png",
  ])
  func aJSONLDImageIsHttpOrNothing(link: String) async throws {
    let got = try await distill(
      ld: """
        {"@type":"Recipe","name":"Dal","image":"\(link)","recipeIngredient":["1 cup lentils"],"recipeInstructions":["Simmer."]}
        """)
    #expect(got.imageUrl == nil)
    let object = try await distill(
      ld: """
        {"@type":"Recipe","name":"Dal","image":{"@type":"ImageObject","url":"\(link)"},"recipeIngredient":["1 cup lentils"],"recipeInstructions":["Simmer."]}
        """)
    #expect(object.imageUrl == nil)
  }

  @Test func aMicrodataImageIsHttpOrNothing() async throws {
    for link in ["javascript:alert(1)", "https://u:p@cdn.example/i.png"] {
      let fetcher = FakeFetcher([
        "https://cook.example/p": .html(
          """
          <div itemscope itemtype="https://schema.org/Recipe"><h1 itemprop="name">Dal</h1>
          <img itemprop="image" src="\(link)"><li itemprop="recipeIngredient">1 cup lentils</li>
          <div itemprop="recipeInstructions"><p>Simmer.</p></div></div>
          """)
      ])
      let got = try await Distill.url("https://cook.example/p", fetcher: fetcher, extractor: nil)
      #expect(got.extractor == .microdata)
      #expect(got.imageUrl == nil, "\(link)")
    }
  }

  @Test func aGoodImageStillComesThroughAndRelativeOnesAreResolved() async throws {
    let good = try await distill(head: "<meta property=\"og:image\" content=\"/img/a.png\">")
    #expect(good.imageUrl == "https://cook.example/img/a.png")
  }

  private let tiktok = "https://www.tiktok.com/@a/video/7300000000000000001"
  private let caption = "Rice\n\nIngredients\n- 1 cup rice\n\nMethod\n1. Cook it."

  @Test(arguments: ["file:///etc/passwd", "javascript:alert(1)", "https://u:p@t.example/c.jpg"])
  func anOEmbedThumbnailIsHttpOrNothing(link: String) async throws {
    let fetcher = FakeFetcher([
      oEmbedLink(tiktok): .json(
        #"{"title":"\#(caption.replacingOccurrences(of: "\n", with: "\\n"))","thumbnail_url":"\#(link)"}"#
      )
    ])
    let got = try await Distill.url(tiktok, fetcher: fetcher, extractor: nil)
    #expect(got.draft.title == "Rice")
    #expect(got.imageUrl == nil)
  }

  @Test(arguments: ["file:///etc/passwd", "javascript:alert(1)", "https://u:p@t.example/c.jpg"])
  func aPostPagesOpenGraphImageIsHttpOrNothing(link: String) async throws {
    let fetcher = FakeFetcher([
      "https://www.instagram.com/reel/Cxyz123/": .html(
        "",
        head: """
          <meta property="og:description" content="1 likes, 2 comments - ada on May 2, 2026: &quot;Rice&#10;&#10;Ingredients&#10;- 1 cup rice&#10;&#10;Method&#10;1. Cook it.&quot;.">\
          <meta property="og:image" content="\(link)">
          """)
    ])
    let got = try await Distill.url(
      "https://www.instagram.com/reel/Cxyz123/", fetcher: fetcher, extractor: nil)
    #expect(got.draft.title == "Rice")
    #expect(got.imageUrl == nil)
  }

  @Test func theReadersTakeAnOptionalBase() {
    let html =
      #"<meta property="og:description" content="Rice"><meta property="og:image" content="/rel.jpg">"#
    #expect(
      Distill.readOpenGraph(html: html, source: .tiktok, base: "https://t.example/a")?.imageUrl
        == "https://t.example/rel.jpg")
    #expect(Distill.readOpenGraph(html: html, source: .tiktok)?.imageUrl == nil)
  }
}

private func oEmbedLink(_ url: String) -> String {
  var allowed = CharacterSet.alphanumerics
  allowed.insert(charactersIn: "-_.!~*'()")
  return
    "https://www.tiktok.com/oembed?url=\(url.addingPercentEncoding(withAllowedCharacters: allowed) ?? url)"
}

// MARK: Characters

@Suite("Control and bidirectional characters")
struct UnsafeCharacterTests {
  @Test func dropsThemFromEveryTextOfADraft() {
    let recipe = ExtractedRecipe(
      title: "Cake\u{202E}\u{0} X", description: "De\u{2066}sc\u{7}ription",
      author: "Ad\u{202A}a", siteName: "Si\u{85}te", tags: ["#ta\u{202D}g", "\u{202E}"],
      notes: "Line\u{202B} one\n\nline\u{9F} two",
      ingredients: [
        ExtractedLine(
          line: "2 cu\u{202E}ps flour\u{0}", section: "For\u{2069} dough", unsure: false)
      ],
      steps: [ExtractedStep(text: "Mix\u{1B}\u{202C} well.", section: "S\u{86}tep", unsure: false)])
    let draft = ImportDraft(
      reading: recipe,
      from: DraftSource(source: .web, sourceUrl: "https://cook.example/\u{202E}x\u{0}"))
    #expect(draft.title == "Cake X")
    #expect(draft.description == "Description")
    #expect(draft.sourceAuthor == "Ada")
    #expect(draft.siteName == "Site")
    #expect(draft.tags == ["tag"])
    #expect(draft.notes == "Line one\n\nline two")
    #expect(draft.ingredients.map(\.line) == ["2 cups flour"])
    #expect(draft.ingredients.map(\.section) == ["For dough"])
    #expect(draft.steps.map(\.text) == ["Mix well."])
    #expect(draft.steps.map(\.section) == ["Step"])
    #expect(draft.sourceUrl == "https://cook.example/x")
  }

  @Test func leavesOrdinaryRightToLeftTextAndEmojiAlone() {
    let hebrew = "עוגת שוקולד"
    let arabic = "كعكة الشوكولاتة"
    let family = "Family 👨‍👩‍👧 dinner"
    let combined = "Cre\u{0300}me bru\u{0302}le\u{0301}e"
    for title in [hebrew, arabic, family, combined] {
      let draft = ImportDraft(
        reading: ExtractedRecipe(title: title), from: DraftSource(source: .text, sourceUrl: nil))
      #expect(draft.title == title)
    }
  }

  @Test func keepsTheWhiteSpaceItAlreadyCollapses() {
    let draft = ImportDraft(
      reading: ExtractedRecipe(title: "A\tB\u{A0}C\u{B}D", notes: "x\ty\n\n\n\nz"),
      from: DraftSource(source: .text, sourceUrl: nil))
    #expect(draft.title == "A B C D")
    #expect(draft.notes == "x y\n\nz")
  }

  @Test func aTitleOfNothingButControlsIsMissing() {
    let draft = ImportDraft(
      reading: ExtractedRecipe(title: "\u{202E}\u{0}"),
      from: DraftSource(source: .text, sourceUrl: nil))
    #expect(draft.title.isEmpty)
    #expect(draft.unsure.contains(.title))
  }

  @Test func appliesToPastedAndFetchedTextAlike() async throws {
    let pasted = try await Distill.text(
      "Cake\u{202E}\u{0}\n\nIngredients\n1 cup fl\u{202E}our\n\nMethod\nMix\u{0} it.",
      extractor: nil)
    #expect(pasted.draft.title == "Cake")
    #expect(pasted.draft.ingredients.map(\.line) == ["1 cup flour"])
    #expect(pasted.draft.steps.map(\.text) == ["Mix it."])

    let name = "Cake\u{202E}\\u0000 X"
    let json = """
      {"@type":"Recipe","name":"\(name)","recipeIngredient":["1 cup fl\\u202Eour"],"recipeInstructions":["Mi\\u0007x."]}
      """
    let fetcher = FakeFetcher([
      "https://cook.example/p": .html(
        "", head: "<script type=\"application/ld+json\">\(json)</script>")
    ])
    let page = try await Distill.url("https://cook.example/p", fetcher: fetcher, extractor: nil)
    #expect(page.draft.title == "Cake X")
    #expect(page.draft.ingredients.map(\.line) == ["1 cup flour"])
    #expect(page.draft.steps.map(\.text) == ["Mix."])
  }
}
