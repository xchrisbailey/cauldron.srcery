import CauldronKit
import Foundation

/// How a request reaches the network. The app uses `URLSession`; tests answer from memory.
protocol AITransport: Sendable {
  /// The response's status and body. Throws when there was no response at all.
  func send(_ request: URLRequest) async throws -> (status: Int, body: Data)
}

struct URLSessionTransport: AITransport {
  /// Refuses every redirect. A request carries the key in a header, and following a redirect
  /// would hand that header to wherever it pointed.
  private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
      _ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
      nil
    }
  }

  /// No cache and no cookies: nothing about a request is left on disk.
  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 90
    configuration.waitsForConnectivity = false
    return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
  }()

  func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
    let (data, response) = try await Self.session.data(for: request)
    return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
  }
}

/// A transport with no network behind it.
struct NoTransport: AITransport {
  func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
    throw URLError(.notConnectedToInternet)
  }
}

/// Gemini, OpenAI or Claude, called straight from the device with the cook's own key. The Kit
/// builds the request and reads the response for the provider; this sends it and maps a failed
/// send to the typed errors.
struct CloudRecipeAI: RecipeAI {
  let provider: AIProvider
  /// This provider's key.
  let keys: any AIKeyStore
  let transport: any AITransport
  /// The model to ask, read at each call so a change in Settings takes effect at once.
  let model: @Sendable () -> String

  private func ask(_ task: AITask) async throws(RecipeAIError) -> (AIAnswer, String) {
    guard let key = keys.key() else { throw .missingKey }
    let model = model()
    let built = try provider.request(for: task, model: model, key: key)
    var request = URLRequest(url: built.url)
    request.httpMethod = "POST"
    for (name, value) in built.headers { request.setValue(value, forHTTPHeaderField: name) }
    request.httpBody = built.body
    let response: (status: Int, body: Data)
    do {
      response = try await transport.send(request)
    } catch {
      // Cancelled by whoever asked, or else offline or timed out: no answer either way.
      throw Task.isCancelled ? .cancelled : .unreachable
    }
    return (try provider.answer(status: response.status, body: response.body), model)
  }

  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    let (answer, model) = try await ask(.extract(input))
    return try answer.extraction(model: model)
  }

  func estimateMacros(_ input: MacroEstimateInput) async throws(RecipeAIError) -> Macros {
    try await ask(.macros(input)).0.macros()
  }

  func estimateMeal(_ text: String) async throws(RecipeAIError) -> [DescribedItem] {
    try await ask(.meal(text)).0.meal()
  }
}
