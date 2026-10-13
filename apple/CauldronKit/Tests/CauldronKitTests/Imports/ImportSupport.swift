import Foundation
import Testing

@testable import CauldronKit

// Shared by the import tests: the reference's saved fixtures, values pinned by running the
// TypeScript under Bun, and fakes for the two seams.

enum Fixtures {
  /// A file under `Imports/Fixtures/`, as UTF-8 text.
  static func text(_ path: String) throws -> String {
    try String(contentsOf: url(path), encoding: .utf8)
  }

  static func url(_ path: String) -> URL {
    Bundle.module.resourceURL!.appendingPathComponent("Fixtures").appendingPathComponent(path)
  }

  /// The names (without extension) of the files with `ext` in a fixture folder, sorted.
  static func names(in folder: String, ext: String) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: url(folder).path)
      .filter { $0.hasSuffix("." + ext) }.map { String($0.dropLast(ext.count + 1)) }.sorted()
  }

  /// A JSON file the reference's tests keep next to a fixture, or one produced by running the
  /// reference (`pinned/`).
  static func json(_ path: String) throws -> JSONValue {
    let value = JSONValue.parse(try text(path))
    return try #require(value, "\(path) isn't JSON")
  }
}

extension JSONValue {
  subscript(key: String) -> JSONValue {
    if case .object(let object) = self { return object[key] ?? .null }
    return .null
  }

  var items: [JSONValue] {
    if case .array(let items) = self { return items }
    return []
  }

  var text: String? { string }

  var number: Double? {
    if case .number(let number) = self { return number }
    return nil
  }

  var strings: [String] { items.compactMap(\.string) }

  /// Every object member that is null dropped, as the Swift types leave out a nil.
  var strippingNulls: JSONValue {
    switch self {
    case .object(let object):
      .object(object.compactMapValues { $0 == .null ? nil : $0.strippingNulls })
    case .array(let items):
      .array(items.map(\.strippingNulls))
    default:
      self
    }
  }

  /// A Swift value as the JSON the reference would have written for it.
  static func of<T: Encodable>(_ value: T) -> JSONValue {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(value),
      let text = String(data: data, encoding: .utf8), let json = JSONValue.parse(text)
    else { return .null }
    return json.strippingNulls
  }

  /// A JSON value for an optional string.
  init(_ string: String?) { self = string.map(JSONValue.string) ?? .null }
}

/// Collects what a fake was asked.
actor Calls<Element: Sendable> {
  private(set) var all: [Element] = []

  func add(_ element: Element) { all.append(element) }
  var count: Int { all.count }
  var last: Element? { all.last }
}

/// A model that answers from a closure and remembers what it was sent.
struct FakeExtractor: RecipeExtracting {
  let calls = Calls<ExtractInput>()
  let answer: @Sendable (ExtractInput) async throws(RecipeAIError) -> Extraction

  init(answer: @escaping @Sendable (ExtractInput) async throws(RecipeAIError) -> Extraction) {
    self.answer = answer
  }

  /// A model that always reads this recipe.
  init(recipe: ExtractedRecipe, rough: Bool = false) {
    self.init { input throws(RecipeAIError) in
      Extraction(
        outcome: .found, recipe: recipe,
        usage: AIUsage(model: "fake", inputTokens: input.text.jsLength, outputTokens: 100),
        rough: rough)
    }
  }

  /// A model that gives this outcome with no recipe.
  init(outcome: ExtractOutcome) {
    self.init { _ throws(RecipeAIError) in
      Extraction(outcome: outcome, recipe: .empty, usage: nil)
    }
  }

  /// A model that always fails.
  init(failing error: RecipeAIError) {
    self.init { _ throws(RecipeAIError) in throw error }
  }

  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    await calls.add(input)
    return try await answer(input)
  }
}

/// A fetcher with canned responses by link, which remembers what it was asked for.
struct FakeFetcher: PageFetcher {
  enum Response: Sendable {
    case page(FetchedPage)
    case failure(FetchError)
  }

  let responses: [String: Response]
  let requests = Calls<FetchRequest>()

  init(_ responses: [String: Response]) { self.responses = responses }

  func fetch(_ request: FetchRequest) async throws(FetchError) -> FetchedPage {
    await requests.add(request)
    switch responses[request.url] {
    case .page(var page):
      if page.url.isEmpty { page.url = request.url }
      return page
    case .failure(let error): throw error
    case nil: throw .status(404)
    }
  }
}

extension FakeFetcher.Response {
  /// An HTML page.
  static func html(
    _ body: String, head: String = "", url: String = "", type: String = "text/html; charset=utf-8"
  ) -> Self {
    .page(
      FetchedPage(
        bytes: Data(
          "<!doctype html><html><head>\(head)</head><body>\(body)</body></html>".utf8),
        contentType: type, url: url))
  }

  static func json(_ text: String) -> Self {
    .page(FetchedPage(bytes: Data(text.utf8), contentType: "application/json", url: ""))
  }
}

/// Compares a Swift value with what the reference gave, with a readable message.
func expectSame(
  _ actual: JSONValue, _ expected: JSONValue, _ label: @autoclosure () -> String,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  let want = expected.strippingNulls
  if actual != want {
    Issue.record(
      "\(label()) differs.\n  got:  \(actual)\n  want: \(want)", sourceLocation: sourceLocation)
  }
}
