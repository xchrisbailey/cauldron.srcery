import Foundation
import Testing

@testable import CauldronKit

// Distilling a link or pasted text end to end, with saved responses standing in for the
// network and a fake model. Ported from `imports-web.test.ts`, `imports-text.test.ts` and
// `imports-social.test.ts`, minus the transport the reference tested through (the job queue,
// the photo store, the HTTP routes), then the failure paths the device adds.

private func recipe(
  title: String? = nil, _ ingredients: [String] = ["1 onion"], _ steps: [String] = ["Simmer it."],
  servings: Int? = nil, unsure: [DraftField] = []
) -> ExtractedRecipe {
  ExtractedRecipe(
    title: title, servings: servings,
    ingredients: ingredients.map { ExtractedLine(line: $0, section: nil, unsure: false) },
    steps: steps.map { ExtractedStep(text: $0, section: nil, unsure: false) }, unsure: unsure)
}

private func jsonLD(_ json: String) -> String {
  "<script type=\"application/ld+json\">\(json)</script>"
}

// MARK: Websites

@Suite("Distilling a website")
struct DistillWebTests {
  static let tacos = """
    {"@context":"https://schema.org","@type":"Recipe","name":"Smoky black bean tacos",
    "author":{"@type":"Person","name":"Ada Cook"},"image":["/img/tacos.png"],
    "recipeYield":"4 servings","prepTime":"PT15M","cookTime":"PT20M","recipeCuisine":"Mexican",
    "recipeIngredient":["2 cans black beans, drained","1 tsp smoked paprika","8 corn tortillas"],
    "recipeInstructions":[{"@type":"HowToStep","text":"Warm the beans with the paprika."},
    {"@type":"HowToStep","text":"Fill the tortillas."}]}
    """

  static let fetcher = FakeFetcher([
    "https://cook.example/tacos?utm_source=x": .html(
      "<article><h1>Tacos</h1></article>",
      head: """
        \(jsonLD(tacos))
        <link rel="canonical" href="https://cook.example/tacos/">
        <meta property="og:site_name" content="Cook Example">
        """),
    "https://blog.example/soup": .html(
      """
      <nav>Home Recipes Shop</nav><article><h1>Grandma's soup</h1><p>My grandma made this.</p>
      <ul><li>1 onion</li></ul><p>Simmer it.</p></article><footer>© Blog</footer>
      """,
      head: #"<meta property="og:image" content="https://blog.example/missing.jpg">"#),
    "https://blog.example/soup#top": .html(
      "<article><h1>Soup</h1><ul><li>1 onion</li></ul><p>Simmer it.</p></article>"),
    "https://cook.example/menu.pdf": .page(
      FetchedPage(bytes: Data([37, 80, 68, 70]), contentType: "application/pdf", url: "")),
  ])

  @Test func readsJSONLDWithoutTheModelAndKeepsTheCanonicalLink() async throws {
    let model = FakeExtractor(recipe: recipe())
    let got = try await Distill.url(
      "https://cook.example/tacos?utm_source=x", fetcher: Self.fetcher, extractor: model)
    let draft = got.draft
    #expect(draft.title == "Smoky black bean tacos")
    #expect(draft.servings == 4)
    #expect(draft.prepMinutes == 15)
    #expect(draft.cookMinutes == 20)
    #expect(draft.sourcePlatform == .web)
    #expect(draft.sourceUrl == "https://cook.example/tacos")
    #expect(draft.sourceAuthor == "Ada Cook")
    #expect(draft.siteName == "Cook Example")
    #expect(draft.tags == ["Mexican"])
    #expect(
      draft.ingredients.map(\.line) == [
        "2 cans black beans, drained", "1 tsp smoked paprika", "8 corn tortillas",
      ])
    #expect(
      draft.steps.map(\.text) == ["Warm the beans with the paprika.", "Fill the tortillas."])
    #expect(got.extractor == .jsonLD)
    #expect(got.usage == nil)
    #expect(got.rough == false)
    // The photo is the app's to fetch: the link comes back, the key stays empty.
    #expect(got.imageUrl == "https://cook.example/img/tacos.png")
    #expect(draft.photoKey == nil)
    #expect(await model.calls.count == 0)
  }

  @Test func sendsAPageWithoutRecipeDataToTheModelAsReadableText() async throws {
    let model = FakeExtractor(recipe: recipe(title: "Grandma's soup"))
    let got = try await Distill.url(
      "https://blog.example/soup", fetcher: Self.fetcher, extractor: model)
    let sent = try #require(await model.calls.last)
    #expect(sent.kind == .page)
    #expect(sent.text.contains("1 onion"))
    #expect(!sent.text.contains("Home Recipes Shop"))
    #expect(got.extractor == .model)
    // The page's text is kept.
    #expect(got.raw?.contains("1 onion") == true)
    #expect(got.draft.title == "Grandma's soup")
    #expect(got.draft.siteName == "blog.example")
    #expect(got.imageUrl == "https://blog.example/missing.jpg")
    #expect(got.usage == AIUsage(model: "fake", inputTokens: sent.text.jsLength, outputTokens: 100))
  }

  @Test func failsWithAPlainReasonWhenTheLinkIsNotAPageItCanRead() async {
    let model = FakeExtractor(recipe: recipe())
    await #expect(throws: DistillError.failed(.couldntRead)) {
      try await Distill.url(
        "https://cook.example/menu.pdf", fetcher: Self.fetcher, extractor: model)
    }
    await #expect(throws: DistillError.failed(.couldntRead)) {
      try await Distill.url(
        "https://cook.example/missing", fetcher: Self.fetcher, extractor: model)
    }
  }

  @Test func flagsAReadingFromTheOnDeviceModelAsRough() async throws {
    let model = FakeExtractor(recipe: recipe(title: "Soup"), rough: true)
    let got = try await Distill.url(
      "https://blog.example/soup", fetcher: Self.fetcher, extractor: model)
    #expect(got.rough)
    #expect(got.extractor == .model)
  }

  @Test func sourceLinkIsTheCanonicalLinkWhenThePageGivesOneOnItsOwnSite() async throws {
    let got = try await Distill.url(
      "https://cook.example/tacos?utm_source=x", fetcher: Self.fetcher, extractor: nil)
    #expect(got.draft.sourceUrl == "https://cook.example/tacos")
  }

  @Test func theLinkIsKeptWhenThePageHasNoCanonicalOne() async throws {
    let got = try await Distill.url(
      "https://blog.example/soup#top", fetcher: Self.fetcher,
      extractor: FakeExtractor(recipe: recipe(title: "Soup")))
    #expect(got.draft.sourceUrl == "https://blog.example/soup")
  }
}

// MARK: Pasted text

private let pasted = """
  Weeknight dal

  A quick red lentil dal.

  Serves 4
  Prep: 10 mins | Cook: 30 mins

  Ingredients
  - 1 cup red lentils, rinsed
  - 1 onion, finely chopped
  - 2 tsp ground cumin

  Method
  1. Fry the onion until soft.
  2. Add the lentils, cumin and 3 cups water.
  3. Simmer for 25 minutes.
  """

// A paste with no headings, which the text reader can't lay out by itself.
private let messy = "made this dal last night, lentils + onion + cumin, simmer it all, so good"

/// The fake model for pasted text: a recipe for the messy paste, nothing for "no recipe here",
/// a failure for "flaky", and a reading that never finishes for "hang".
private func textModel() -> FakeExtractor {
  FakeExtractor { input async throws(RecipeAIError) in
    if input.text.contains("hang") {
      try? await Task.sleep(for: .seconds(60))
      throw .cancelled
    }
    if input.text.contains("flaky") { throw .failed(detail: "bad output") }
    if input.text.contains("no recipe here") {
      return Extraction(outcome: .missing, recipe: .empty, usage: nil)
    }
    return Extraction(
      outcome: .found,
      recipe: ExtractedRecipe(
        title: "Last night's dal", servings: 2,
        ingredients: [
          ExtractedLine(line: "1 cup red lentils", section: nil, unsure: false),
          ExtractedLine(line: "some cumin", section: nil, unsure: true),
        ],
        steps: [ExtractedStep(text: "Simmer it all.", section: nil, unsure: false)],
        unsure: [.servings]),
      usage: AIUsage(model: "fake", inputTokens: input.text.jsLength, outputTokens: 100))
  }
}

@Suite("Distilling pasted text")
struct DistillTextTests {
  @Test func readsALaidOutPasteWithoutTheModel() async throws {
    let model = textModel()
    let got = try await Distill.text(pasted, extractor: model)
    let draft = got.draft
    #expect(draft.title == "Weeknight dal")
    #expect(draft.description == "A quick red lentil dal.")
    #expect(draft.servings == 4)
    #expect(draft.prepMinutes == 10)
    #expect(draft.cookMinutes == 30)
    #expect(draft.sourcePlatform == .text)
    #expect(draft.sourceUrl == nil)
    #expect(draft.photoKey == nil)
    #expect(draft.unsure.isEmpty)
    #expect(
      draft.ingredients.map(\.line) == [
        "1 cup red lentils, rinsed", "1 onion, finely chopped", "2 tsp ground cumin",
      ])
    #expect(
      draft.steps.map(\.text) == [
        "Fry the onion until soft.", "Add the lentils, cumin and 3 cups water.",
        "Simmer for 25 minutes.",
      ])
    #expect(got.extractor == .text)
    #expect(got.raw == nil)
    #expect(got.usage == nil)
    #expect(await model.calls.count == 0)
  }

  @Test func sendsMessyTextToTheModelAndReportsItsCost() async throws {
    let model = textModel()
    let got = try await Distill.text(messy, extractor: model)
    #expect(await model.calls.last == ExtractInput(text: messy, kind: .text))
    let draft = got.draft
    #expect(draft.title == "Last night's dal")
    #expect(draft.servings == 2)
    #expect(draft.unsure == [.servings])
    #expect(draft.ingredients.map(\.line) == ["1 cup red lentils", "some cumin"])
    #expect(draft.ingredients.map(\.unsure) == [false, true])
    #expect(got.extractor == .model)
    #expect(got.usage == AIUsage(model: "fake", inputTokens: messy.jsLength, outputTokens: 100))
  }

  @Test func failsAsNoRecipeWhenThereIsntOne() async {
    await #expect(throws: DistillError.failed(.noRecipe)) {
      try await Distill.text("no recipe here, just chat", extractor: textModel())
    }
  }

  @Test func fallsBackToTheRoughReadingWhenTheModelFails() async throws {
    let got = try await Distill.text(
      "flaky dal\n1 cup red lentils\n2 tsp cumin\nSimmer the lentils with the cumin until soft.",
      extractor: textModel())
    #expect(got.draft.ingredients.map(\.line) == ["1 cup red lentils", "2 tsp cumin"])
    #expect(got.draft.unsure.contains(.title))
    #expect(got.extractor == .text)
  }

  @Test func timesOutADistillThatRunsTooLong() async {
    await #expect(throws: DistillError.failed(.timeout)) {
      try await Distill.text(
        "hang on, this takes a while", extractor: textModel(),
        options: DistillOptions(timeout: .milliseconds(50)))
    }
  }

  @Test func readsMessyTextWithoutAModelAsTheRoughReadingOrNotAtAll() async throws {
    let rough = try await Distill.text(
      "dal\n1 cup red lentils\n2 tsp cumin\nSimmer the lentils with the cumin until soft.",
      extractor: nil)
    #expect(rough.extractor == .text)
    await #expect(throws: DistillError.failed(.noRecipe)) {
      try await Distill.text(messy, extractor: nil)
    }
  }

  @Test func treatsAMissingKeyAsNoModel() async throws {
    let noKey = FakeExtractor(failing: .missingKey)
    await #expect(throws: DistillError.failed(.noRecipe)) {
      try await Distill.text(messy, extractor: noKey)
    }
    #expect(await noKey.calls.count == 1)
  }

  @Test(arguments: [
    RecipeAIError.rateLimited, .invalidKey, .invalidModel, .unreachable, .failed(detail: "x"),
  ])
  func failsAsUnavailableWhenTheModelFailsAndThereIsNoRoughReading(error: RecipeAIError)
    async
  {
    await #expect(throws: DistillError.failed(.unavailable)) {
      try await Distill.text(messy, extractor: FakeExtractor(failing: error))
    }
  }

  @Test func stopsWhenTheModelRequestIsCancelled() async {
    await #expect(throws: DistillError.cancelled) {
      try await Distill.text(messy, extractor: FakeExtractor(failing: .cancelled))
    }
  }

  @Test func failsAsSpokenOnlyWhenTheModelSaysItIsInTheVideo() async {
    await #expect(throws: DistillError.failed(.spokenOnly)) {
      try await Distill.text(messy, extractor: FakeExtractor(outcome: .inVideo))
    }
  }

  @Test func flagsARoughModelReading() async throws {
    let got = try await Distill.text(
      messy, extractor: FakeExtractor(recipe: recipe(title: "Dal"), rough: true))
    #expect(got.rough)
  }

  @Test func refusesEmptyAndOversizedText() async {
    await #expect(throws: DistillError.failed(.noRecipe)) {
      try await Distill.text("  \n ", extractor: nil)
    }
    await #expect(throws: DistillError.failed(.tooLarge)) {
      try await Distill.text(String(repeating: "x", count: Distill.textMax + 1), extractor: nil)
    }
  }

  @Test func queuesAMacroEstimateForARecipeWithNoNutrition() async throws {
    let got = try await Distill.text(pasted, extractor: nil)
    #expect(got.draft.macros == nil)
    #expect(
      got.macroEstimate
        == MacroEstimateInput(
          title: "Weeknight dal", servings: 4,
          ingredients: [
            "1 cup red lentils, rinsed", "1 onion, finely chopped", "2 tsp ground cumin",
          ]))
  }
}

@Suite("Sources")
struct SourceTests {
  @Test func tellsALinksKindFromItsHost() {
    #expect(Distill.classify("https://www.instagram.com/reel/abc123/") == .instagram)
    #expect(Distill.classify("https://instagr.am/p/abc123/") == .instagram)
    #expect(Distill.classify("https://vm.tiktok.com/ZM123/") == .tiktok)
    #expect(Distill.classify("https://example.com/dal") == .web)
    #expect(Distill.classify("https://notinstagram.com/dal") == .web)
  }

  @Test func dropsWhatDoesntChangeThePageFromALink() {
    #expect(
      Distill.normalizeURL("https://Example.com/recipes/dal/?utm_source=share&id=2#jump")
        == "https://example.com/recipes/dal?id=2")
  }

  @Test func acceptsHTTPLinksAndRefusesTheRest() {
    #expect(Distill.isAcceptedLink("https://example.com/dal"))
    #expect(Distill.isAcceptedLink("  http://example.com  "))
    #expect(!Distill.isAcceptedLink("example.com/dal"))
    #expect(!Distill.isAcceptedLink("ftp://example.com/dal"))
    #expect(!Distill.isAcceptedLink("javascript:alert(1)"))
    #expect(!Distill.isAcceptedLink("https://user:pw@example.com/dal"))
    #expect(!Distill.isAcceptedLink("https://example.com/" + String(repeating: "a", count: 2100)))
    #expect(!Distill.isAcceptedLink("https://exa mple.com"))
    #expect(!Distill.isAcceptedLink(""))
  }
}

// MARK: Fetching

@Suite("Fetching a page")
struct FetchTests {
  private func distill(
    _ fetcher: FakeFetcher, link: String = "https://cook.example/p",
    model: FakeExtractor? = nil
  ) async throws -> Distilled {
    try await Distill.url(
      link, fetcher: fetcher, extractor: model,
      options: DistillOptions(retryDelay: .milliseconds(1)))
  }

  private static let tacos = FakeFetcher.Response.html(
    "<h1>Tacos</h1>", head: jsonLD(DistillWebTests.tacos))

  @Test(arguments: [
    (FetchError.blocked(), ImportFailureCode.blocked), (.tooLarge, .tooLarge),
    (.timeout, .timeout), (.unreachable(detail: "dns"), .couldntRead),
    (.unreachable(), .couldntRead), (.status(404), .couldntRead), (.status(503), .couldntRead),
  ])
  func mapsFetchFailuresToTheirCodes(error: FetchError, code: ImportFailureCode) async {
    let fetcher = FakeFetcher(["https://cook.example/p": .failure(error)])
    await #expect(throws: DistillError.failed(code)) { try await distill(fetcher) }
  }

  @Test func stopsWhenTheFetchIsCancelled() async {
    let fetcher = FakeFetcher(["https://cook.example/p": .failure(.cancelled)])
    await #expect(throws: DistillError.cancelled) { try await distill(fetcher) }
  }

  @Test(arguments: [
    FetchError.timeout, .unreachable(), .status(500), .status(503), .status(429),
  ])
  func triesATransientFailureThreeTimesInAll(error: FetchError) async {
    let fetcher = FakeFetcher(["https://cook.example/p": .failure(error)])
    _ = try? await distill(fetcher)
    #expect(await fetcher.requests.count == 3)
  }

  @Test(arguments: [
    FetchError.unreachable(detail: "dns"), .status(404), .status(403), .blocked(), .tooLarge,
  ])
  func doesntRetryAFailureThatWontPass(error: FetchError) async {
    let fetcher = FakeFetcher(["https://cook.example/p": .failure(error)])
    _ = try? await distill(fetcher)
    #expect(await fetcher.requests.count == 1)
  }

  @Test func succeedsWhenARetryDoes() async throws {
    // Answers 503 twice, then the page.
    let counter = Calls<Int>()
    struct Flaky: PageFetcher {
      let counter: Calls<Int>
      func fetch(_ request: FetchRequest) async throws(FetchError) -> FetchedPage {
        await counter.add(1)
        if await counter.count < 3 { throw .status(503) }
        return FetchedPage(
          bytes: Data(
            "<html><head>\(jsonLD(DistillWebTests.tacos))</head><body></body></html>".utf8),
          contentType: "text/html", url: request.url)
      }
    }
    let got = try await Distill.url(
      "https://cook.example/p", fetcher: Flaky(counter: counter), extractor: nil,
      options: DistillOptions(retryDelay: .milliseconds(1)))
    #expect(got.draft.title == "Smoky black bean tacos")
    #expect(await counter.count == 3)
  }

  @Test func asksForAPageWithinTheSizeCap() async throws {
    let fetcher = FakeFetcher(["https://cook.example/p": Self.tacos])
    _ = try await distill(fetcher)
    let request = try #require(await fetcher.requests.last)
    #expect(request.maxBytes == 5 * 1024 * 1024)
    #expect(request.accept.hasPrefix("text/html"))
  }

  @Test func refusesABodyBiggerThanTheCapEvenIfTheFetcherLetItThrough() async {
    let big = FetchedPage(
      bytes: Data(count: 2000), contentType: "text/html", url: "https://cook.example/p")
    let fetcher = FakeFetcher(["https://cook.example/p": .page(big)])
    await #expect(throws: DistillError.failed(.tooLarge)) {
      try await Distill.url(
        "https://cook.example/p", fetcher: fetcher, extractor: nil,
        options: DistillOptions(maxPageBytes: 1000))
    }
  }

  @Test(arguments: ["application/pdf", "image/png", "application/json", "text/css", "video/mp4"])
  func refusesAResponseThatIsNotAPage(type: String) async {
    let page = FetchedPage(bytes: Data("x".utf8), contentType: type, url: "https://cook.example/p")
    await #expect(throws: DistillError.failed(.couldntRead)) {
      try await distill(FakeFetcher(["https://cook.example/p": .page(page)]))
    }
  }

  @Test(arguments: [
    "text/html", "TEXT/HTML; charset=utf-8", "application/xhtml+xml", "text/plain",
    "application/xml", "text/xml; charset=utf-8",
  ])
  func readsAnyPageLikeContentType(type: String) async throws {
    let body = "<html><head>\(jsonLD(DistillWebTests.tacos))</head><body></body></html>"
    let page = FetchedPage(bytes: Data(body.utf8), contentType: type, url: "https://cook.example/p")
    let got = try await distill(FakeFetcher(["https://cook.example/p": .page(page)]))
    #expect(got.draft.title == "Smoky black bean tacos")
  }

  @Test func readsAPageWithNoContentType() async throws {
    let body = "<html><head>\(jsonLD(DistillWebTests.tacos))</head><body></body></html>"
    let page = FetchedPage(bytes: Data(body.utf8), contentType: nil, url: "https://cook.example/p")
    let got = try await distill(FakeFetcher(["https://cook.example/p": .page(page)]))
    #expect(got.draft.title == "Smoky black bean tacos")
  }

  @Test func refusesARedirectThatLandedOnALinkWithCredentials() async {
    let page = FetchedPage(
      bytes: Data("<html></html>".utf8), contentType: "text/html",
      url: "https://user:pw@evil.example/x")
    await #expect(throws: DistillError.failed(.blocked)) {
      try await distill(FakeFetcher(["https://cook.example/p": .page(page)]))
    }
  }

  @Test(arguments: ["not a link", "ftp://cook.example/p", "https://u:p@cook.example/p", ""])
  func refusesALinkItWontOpenWithoutFetching(link: String) async {
    let fetcher = FakeFetcher([:])
    await #expect(throws: DistillError.failed(.blocked)) { try await distill(fetcher, link: link) }
    #expect(await fetcher.requests.count == 0)
  }

  @Test func timesOutAFetchThatNeverReturns() async {
    struct Stuck: PageFetcher {
      func fetch(_ request: FetchRequest) async throws(FetchError) -> FetchedPage {
        try? await Task.sleep(for: .seconds(60))
        throw .cancelled
      }
    }
    await #expect(throws: DistillError.failed(.timeout)) {
      try await Distill.url(
        "https://cook.example/p", fetcher: Stuck(), extractor: nil,
        options: DistillOptions(timeout: .milliseconds(50)))
    }
  }

  @Test func readsAPageWhoseModelCallIsNotNeeded() async throws {
    let model = FakeExtractor(failing: .rateLimited)
    let fetcher = FakeFetcher(["https://cook.example/p": Self.tacos])
    let got = try await distill(fetcher, model: model)
    #expect(got.extractor == .jsonLD)
    #expect(await model.calls.count == 0)
  }

  @Test func failsAThinPageAsUnavailableWhenTheModelCantBeReached() async {
    let fetcher = FakeFetcher([
      "https://cook.example/p": .html("<article><p>Just a story.</p></article>")
    ])
    await #expect(throws: DistillError.failed(.unavailable)) {
      try await distill(fetcher, model: FakeExtractor(failing: .unreachable))
    }
  }

  @Test func keepsIngredientsWithoutAMethodWhenTheModelFailsButNotAfterATimeout() async throws {
    let thin = """
      {"@type":"Recipe","name":"Pico","recipeIngredient":["4 tomatoes","1 lime"]}
      """
    let fetcher = FakeFetcher([
      "https://cook.example/p": .html("<article><p>Just a story.</p></article>", head: jsonLD(thin))
    ])
    let got = try await distill(fetcher, model: FakeExtractor(failing: .unreachable))
    #expect(got.extractor == .jsonLD)
    #expect(got.draft.ingredients.map(\.line) == ["4 tomatoes", "1 lime"])
    #expect(got.draft.steps.isEmpty)
    #expect(got.draft.unsure == [.title])
    // The text was read, so it is kept.
    #expect(got.raw?.contains("Just a story.") == true)
  }

  @Test func macrosFromThePageAreKeptAndNeedNoEstimate() async throws {
    let withNutrition = """
      {"@type":"Recipe","name":"Pico","recipeIngredient":["4 tomatoes"],"recipeInstructions":["Dice."],
      "nutrition":{"calories":"310 kcal","proteinContent":"12.34 g","carbohydrateContent":"40 g","fatContent":"9 g"}}
      """
    let fetcher = FakeFetcher([
      "https://cook.example/p": .html("<h1>x</h1>", head: jsonLD(withNutrition))
    ])
    let got = try await distill(fetcher)
    #expect(got.draft.macros == Macros(calories: 310, protein: 12.3, carbs: 40, fat: 9))
    #expect(got.macroEstimate == nil)
  }
}

// MARK: Posts

private let caption = """
  Crispy chilli oil noodles 🌶️ my go-to when I'm tired

  Ingredients:
  - 200g wheat noodles
  - 2 tbsp chilli oil
  - 1 tbsp soy sauce
  - 1 spring onion, sliced

  Method:
  1. Cook the noodles and drain.
  2. Toss with the chilli oil and soy.
  3. Top with spring onion.

  #noodles #easyrecipes #dinnerideas
  """

private let tiktok = "https://www.tiktok.com/@noodlecook/video/7301234567890123456"

private func oEmbed(_ url: String) -> String {
  var allowed = CharacterSet.alphanumerics
  allowed.insert(charactersIn: "-_.!~*'()")
  return
    "https://www.tiktok.com/oembed?url=\(url.addingPercentEncoding(withAllowedCharacters: allowed) ?? url)"
}

private func jsonObject(_ pairs: KeyValuePairs<String, String>) -> FakeFetcher.Response {
  var parts: [String] = []
  for (key, value) in pairs {
    let data = (try? JSONEncoder().encode([value])) ?? Data()
    let text = String(data: data, encoding: .utf8) ?? "[\"\"]"
    parts.append("\"\(key)\":\(text.dropFirst().dropLast())")
  }
  return .json("{" + parts.joined(separator: ",") + "}")
}

@Suite("Distilling a social post")
struct DistillSocialTests {
  static let fetcher = FakeFetcher([
    oEmbed(tiktok): jsonObject([
      "title": caption, "author_name": "Noodle Cook", "author_unique_id": "noodlecook",
      "thumbnail_url": "https://p16.tiktokcdn.example/cover.jpg",
    ]),
    // A share link that redirects to the post.
    "https://vm.tiktok.com/ZMabc123/": .html("", url: "\(tiktok)?_r=1&u_code=xyz"),
    oEmbed("https://www.tiktok.com/@ricecook/video/7300000000000000001"): jsonObject([
      "title": "garlic butter rice, so good, rice + butter + garlic then cook it all",
      "author_unique_id": "ricecook",
    ]),
    oEmbed("https://www.tiktok.com/@spoken/video/7300000000000000002"): jsonObject([
      "title": "full recipe in the video 👀 #fyp", "author_unique_id": "spoken",
    ]),
    // No oEmbed caption: the page's Open Graph tags have it.
    "https://www.tiktok.com/@ogonly/video/7300000000000000003": .html(
      "",
      head: """
        <meta property="og:description" content="\(caption.replacingOccurrences(of: "\n", with: "&#10;"))">\
        <meta property="og:image" content="https://p16.tiktokcdn.example/og.jpg">
        """),
    "https://www.instagram.com/share/reel/BAGshare1/": .html(
      "", url: "https://www.instagram.com/accounts/login/?next=%2Freel%2FCxyz123%2F"),
    "https://www.instagram.com/reel/Cxyz123/": .html(
      "",
      head: """
        <meta property="og:description" content="1,204 likes, 33 comments - sunsetcook on May 2, 2026: &quot;golden hour on the terrace 🌅&quot;.">
        """),
  ])

  static func model() -> FakeExtractor {
    FakeExtractor { input async throws(RecipeAIError) in
      if input.text.contains("full recipe in the video") {
        return Extraction(outcome: .inVideo, recipe: .empty, usage: nil)
      }
      if input.text.contains("golden hour") {
        return Extraction(outcome: .missing, recipe: .empty, usage: nil)
      }
      return Extraction(
        outcome: .found,
        recipe: recipe(title: "Garlic butter rice", ["1 cup rice"], ["Cook the rice in butter."]),
        usage: AIUsage(model: "fake", inputTokens: 1, outputTokens: 1))
    }
  }

  @Test func readsALaidOutCaptionFromOEmbedWithoutTheModelCreditingTheCreator() async throws {
    let model = Self.model()
    let got = try await Distill.url(
      "\(tiktok)?is_from_webapp=1", fetcher: Self.fetcher, extractor: model)
    let draft = got.draft
    #expect(draft.title == "Crispy chilli oil noodles 🌶️ my go-to when I'm tired")
    #expect(draft.sourcePlatform == .tiktok)
    #expect(draft.sourceUrl == tiktok)
    #expect(draft.sourceAuthor == "@noodlecook")
    #expect(draft.siteName == "TikTok")
    #expect(
      draft.ingredients.map(\.line) == [
        "200g wheat noodles", "2 tbsp chilli oil", "1 tbsp soy sauce", "1 spring onion, sliced",
      ])
    #expect(draft.steps.count == 3)
    #expect(draft.tags.isEmpty)
    #expect(got.extractor == .text)
    #expect(got.raw == caption)
    #expect(got.imageUrl == "https://p16.tiktokcdn.example/cover.jpg")
    #expect(await model.calls.count == 0)
  }

  @Test func followsAShareLinkToThePost() async throws {
    let got = try await Distill.url(
      "https://vm.tiktok.com/ZMabc123/", fetcher: Self.fetcher, extractor: nil)
    #expect(got.draft.sourceUrl == tiktok)
  }

  @Test func sendsAMessyCaptionToTheModelTunedForCaptions() async throws {
    let model = Self.model()
    let got = try await Distill.url(
      "https://www.tiktok.com/@ricecook/video/7300000000000000001", fetcher: Self.fetcher,
      extractor: model)
    #expect(await model.calls.last?.kind == .caption)
    #expect(got.draft.title == "Garlic butter rice")
    #expect(got.draft.sourceAuthor == "@ricecook")
    #expect(got.usage?.model == "fake")
  }

  @Test func fallsBackToThePagesOpenGraphCaption() async throws {
    let got = try await Distill.url(
      "https://www.tiktok.com/@ogonly/video/7300000000000000003", fetcher: Self.fetcher,
      extractor: Self.model())
    #expect(got.draft.ingredients.count == 4)
    #expect(got.imageUrl == "https://p16.tiktokcdn.example/og.jpg")
  }

  @Test func failsWithThePasteSuggestionWhenTheRecipeIsOnlyInTheVideoAndKeepsTheCaption() async {
    await #expect(
      throws: DistillError.failed(.spokenOnly, raw: "full recipe in the video 👀 #fyp")
    ) {
      try await Distill.url(
        "https://www.tiktok.com/@spoken/video/7300000000000000002", fetcher: Self.fetcher,
        extractor: Self.model())
    }
    await #expect(
      throws: DistillError.failed(
        .spokenOnly, raw: "golden hour on the terrace 🌅")
    ) {
      try await Distill.url(
        "https://www.instagram.com/reel/Cxyz123/?igsh=abc", fetcher: Self.fetcher,
        extractor: Self.model())
    }
  }

  @Test func withoutAModelACaptionWithNoRecipeIsNoRecipeNotSpokenOnly() async {
    await #expect(
      throws: DistillError.failed(.noRecipe, raw: "golden hour on the terrace 🌅")
    ) {
      try await Distill.url(
        "https://www.instagram.com/reel/Cxyz123/", fetcher: Self.fetcher, extractor: nil)
    }
  }

  @Test func followsAnInstagramShareLinkEvenToALoginPage() async {
    // The share code isn't the post's; the redirect says where the post is. The caption is then
    // read from the page the link landed on, as the reference does, which here is the login
    // page and has none.
    await #expect(throws: DistillError.failed(.spokenOnly)) {
      try await Distill.url(
        "https://www.instagram.com/share/reel/BAGshare1/", fetcher: Self.fetcher,
        extractor: Self.model())
    }
  }

  @Test func cantReadAPostItCantReach() async {
    await #expect(throws: DistillError.failed(.couldntRead)) {
      try await Distill.url(
        "https://www.tiktok.com/@gone/video/7300000000000000009", fetcher: Self.fetcher,
        extractor: nil)
    }
  }

  @Test func failsAPostWithNoCaptionAtAllAsSpokenOnly() async {
    let fetcher = FakeFetcher([
      "https://www.instagram.com/reel/Cempty1/": .html("", head: "<title>Instagram</title>")
    ])
    await #expect(throws: DistillError.failed(.spokenOnly)) {
      try await Distill.url(
        "https://www.instagram.com/reel/Cempty1/", fetcher: fetcher, extractor: Self.model())
    }
  }

  @Test func stopsWhenAnOEmbedLookupIsBlocked() async {
    let fetcher = FakeFetcher([oEmbed(tiktok): .failure(.blocked())])
    await #expect(throws: DistillError.failed(.blocked)) {
      try await Distill.url(tiktok, fetcher: fetcher, extractor: nil)
    }
  }

  @Test func asksTikTokForTheCaptionOnlyOnceAndNeverAsksInstagramForAToken() async throws {
    let fetcher = FakeFetcher([
      oEmbed(tiktok): jsonObject(["title": caption, "author_unique_id": "noodlecook"]),
      "https://www.instagram.com/reel/Cxyz123/": Self.fetcher.responses[
        "https://www.instagram.com/reel/Cxyz123/"]!,
    ])
    _ = try await Distill.url(tiktok, fetcher: fetcher, extractor: nil)
    #expect(await fetcher.requests.all.map(\.url) == [oEmbed(tiktok)])
    #expect(await fetcher.requests.last?.accept == "application/json")
    #expect(await fetcher.requests.last?.maxBytes == 512 * 1024)

    _ = try? await Distill.url(
      "https://www.instagram.com/reel/Cxyz123/", fetcher: fetcher, extractor: nil)
    let urls = await fetcher.requests.all.map(\.url)
    #expect(urls.dropFirst() == ["https://www.instagram.com/reel/Cxyz123/"])
  }
}

@Suite("Post links")
struct PostLinkTests {
  @Test func findsThePostBehindEachLinkShape() {
    #expect(
      Distill.canonicalPost(.instagram, url: "https://instagram.com/p/AbC_12-3/?igsh=xyz")
        == "https://www.instagram.com/p/AbC_12-3/")
    #expect(
      Distill.canonicalPost(.instagram, url: "https://www.instagram.com/reels/AbC123/")
        == "https://www.instagram.com/reel/AbC123/")
    #expect(
      Distill.canonicalPost(.instagram, url: "https://www.instagram.com/sunsetcook/reel/AbC123/")
        == "https://www.instagram.com/reel/AbC123/")
    #expect(
      Distill.canonicalPost(.tiktok, url: "\(tiktok)?is_from_webapp=1&sender_device=pc") == tiktok)
    #expect(Distill.canonicalPost(.tiktok, url: "https://vm.tiktok.com/ZMabc123/") == nil)
    // Share links carry their own code: they're followed, not read as posts.
    #expect(
      Distill.canonicalPost(.instagram, url: "https://www.instagram.com/share/reel/BAGxyz123/")
        == nil)
    #expect(
      Distill.canonicalPost(.instagram, url: "https://www.instagram.com/share/p/BAGxyz123/")
        == nil)
    #expect(Distill.canonicalPost(.instagram, url: "https://www.instagram.com/sunsetcook/") == nil)
  }

  @Test func readsInstagramsOpenGraphCaptionAndHandle() {
    let got = Distill.readOpenGraph(
      html:
        #"<meta property="og:description" content="12K likes, 80 comments - ada.cooks on March 1, 2026: &quot;Lemon pasta. Ingredients: pasta, lemon&quot;.">"#,
      source: .instagram)
    #expect(
      got
        == SocialCapture(
          caption: "Lemon pasta. Ingredients: pasta, lemon", author: "@ada.cooks", imageUrl: nil))
  }

  @Test func keepsATikTokCaptionsOwnQuotes() {
    let got = Distill.readOpenGraph(
      html:
        #"<meta property="og:description" content="Pasta night. Top tip: &quot;salt the water&quot;">"#,
      source: .tiktok)
    #expect(got?.caption == #"Pasta night. Top tip: "salt the water""#)
  }
}
