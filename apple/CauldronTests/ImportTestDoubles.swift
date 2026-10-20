import CauldronKit
import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

@testable import Cauldron
@testable import CauldronImports

/// A `PageFetcher` that answers from a list of links and keeps what it was asked. A link it has
/// no answer for is a 404. Nothing here touches the network.
final class ScriptedFetcher: PageFetcher {
  enum Reply: Sendable {
    case page(FetchedPage)
    case fail(FetchError)
    /// Waits until the request is cancelled.
    case hold
  }

  private let replies: Mutex<[String: Reply]>
  private let seen = Mutex<[FetchRequest]>([])
  private let started = Mutex<Int>(0)

  init(_ replies: [String: Reply] = [:]) {
    self.replies = Mutex(replies)
  }

  var requests: [FetchRequest] { seen.withLock { $0 } }
  var startedCount: Int { started.withLock { $0 } }

  func set(_ link: String, _ reply: Reply) {
    replies.withLock { $0[link] = reply }
  }

  func fetch(_ request: FetchRequest) async throws(FetchError) -> FetchedPage {
    seen.withLock { $0.append(request) }
    started.withLock { $0 += 1 }
    switch replies.withLock({ $0[request.url] }) {
    case .page(var page):
      // Like the network, which says where it ended up.
      if page.url.isEmpty { page.url = request.url }
      return page
    case .fail(let error): throw error
    case .hold:
      do { try await Task.sleep(for: .seconds(60)) } catch { throw .cancelled }
      throw .timeout
    case nil: throw .status(404)
    }
  }
}

/// Returns an image only after the cook has made an edit while its request was in flight.
struct EditingCoverFetcher: PageFetcher {
  let editing: @MainActor @Sendable () -> Void
  let bytes: Data

  func fetch(_ request: FetchRequest) async throws(FetchError) -> FetchedPage {
    await editing()
    return FetchedPage(bytes: bytes, contentType: "image/png", url: request.url)
  }
}

extension ScriptedFetcher.Reply {
  static func html(_ body: String, head: String = "", url: String? = nil) -> Self {
    .page(
      FetchedPage(
        bytes: Data("<html><head>\(head)</head><body>\(body)</body></html>".utf8),
        contentType: "text/html; charset=utf-8", url: url ?? ""))
  }

  static func image(_ data: Data, type: String? = "image/png") -> Self {
    .page(FetchedPage(bytes: data, contentType: type, url: ""))
  }
}

/// A model that reads one recipe, or fails, and keeps what it was asked.
final class ScriptedExtractor: RecipeExtracting {
  private let answer: Mutex<Result<Extraction, RecipeAIError>>
  private let seen = Mutex<[ExtractInput]>([])

  init(recipe: ExtractedRecipe, rough: Bool = false) {
    answer = Mutex(.success(Extraction(outcome: .found, recipe: recipe, usage: nil, rough: rough)))
  }

  init(failing error: RecipeAIError) {
    answer = Mutex(.failure(error))
  }

  var inputs: [ExtractInput] { seen.withLock { $0 } }

  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    seen.withLock { $0.append(input) }
    return try answer.withLock { $0 }.get()
  }
}

/// A recipe as a model would read it.
func readRecipe(
  title: String = "Grandma's soup", ingredients: [String] = ["1 onion", "2 carrots"],
  steps: [String] = ["Chop.", "Simmer for 20 minutes."]
) -> ExtractedRecipe {
  ExtractedRecipe(
    title: title,
    ingredients: ingredients.map { ExtractedLine(line: $0, section: nil, unsure: false) },
    steps: steps.map { ExtractedStep(text: $0, section: nil, unsure: false) })
}

enum ImportFixtures {
  /// A page that publishes its recipe as JSON-LD, so no model is needed.
  static let tacosLink = "https://cook.example/tacos"
  static let tacosImage = "https://cook.example/img/tacos.png"

  static func tacos(nutrition: Bool = false, image: Bool = true) -> ScriptedFetcher.Reply {
    let json = """
      {"@context":"https://schema.org","@type":"Recipe","name":"Smoky black bean tacos",
      "author":{"@type":"Person","name":"Ada Cook"},\(image ? #""image":["\#(tacosImage)"],"# : "")
      "recipeYield":"4 servings","prepTime":"PT15M","cookTime":"PT20M","recipeCuisine":"Mexican",
      \(nutrition ? #""nutrition":{"@type":"NutritionInformation","calories":"350 kcal","proteinContent":"20 g","carbohydrateContent":"30 g","fatContent":"10 g"},"# : "")
      "recipeIngredient":["2 cans black beans, drained","1 tsp smoked paprika","8 corn tortillas"],
      "recipeInstructions":[{"@type":"HowToStep","text":"Warm the beans with the paprika."},
      {"@type":"HowToStep","text":"Fill the tortillas."}]}
      """
    return .html(
      "<article><h1>Tacos</h1></article>",
      head: """
        <script type="application/ld+json">\(json)</script>
        <meta property="og:site_name" content="Cook Example">
        """)
  }

  /// A page with the recipe only in its text, which needs a model to be read.
  static let soupLink = "https://blog.example/soup"
  static let soup: ScriptedFetcher.Reply = .html(
    """
    <nav>Home Recipes Shop</nav><article><h1>Grandma's soup</h1><p>My grandma made this.</p>
    <ul><li>1 onion</li><li>2 carrots</li></ul><p>Chop. Simmer for 20 minutes.</p></article>
    """)

  /// A real image, as `type` encodes it.
  static func imageData(_ width: Int = 64, _ height: Int = 48, as type: UTType = .png) -> Data {
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return Data() }
    context.setFillColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
    else { return Data() }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
  }

  /// Quick options for tests: no waiting before a retry.
  static let quick = DistillOptions(timeout: .seconds(20), retryDelay: .milliseconds(1))
}

/// A text reader that answers page by page, in the order it is asked, and keeps what it was
/// given. Nothing here runs Vision.
final class ScriptedReader: RecipeTextReader {
  enum Reply: Sendable {
    case text(String)
    case fail(PageReadError)
    /// Waits until the read is cancelled.
    case hold
  }

  private let replies: Mutex<[Reply]>
  private let seen = Mutex<[Data]>([])

  /// The replies are used in order; asked for more, the reader finds no text.
  init(_ replies: [Reply]) {
    self.replies = Mutex(replies)
  }

  convenience init(pages: String...) {
    self.init(pages.map { .text($0) })
  }

  /// The images it was asked to read, in order.
  var images: [Data] { seen.withLock { $0 } }
  var startedCount: Int { seen.withLock { $0.count } }

  func read(_ image: Data) async throws(PageReadError) -> String {
    seen.withLock { $0.append(image) }
    let reply = replies.withLock { $0.isEmpty ? Reply.text("") : $0.removeFirst() }
    switch reply {
    case .text(let text): return text
    case .fail(let error): throw error
    case .hold:
      do { try await Task.sleep(for: .seconds(60)) } catch { throw .cancelled }
      throw .failed
    }
  }
}

extension ImportFixtures {
  /// A page of a cookbook that reads without a model: it has Ingredients and Method headings.
  static let soupPage = """
    Tomato soup
    Serves 4

    Ingredients
    2 onions
    400 g tomatoes

    Method
    1. Chop the onions.
    2. Simmer for 20 minutes.
    """

  /// The same recipe over two pages, the break falling between the lists.
  static let soupPageOne = "Tomato soup\nServes 4\n\nIngredients\n2 onions\n400 g tomatoes"
  static let soupPageTwo = "Method\n1. Chop the onions.\n2. Simmer for 20 minutes."
}
