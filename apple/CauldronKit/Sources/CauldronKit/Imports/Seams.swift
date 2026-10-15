import Foundation

// The two things the app supplies to the import pipeline. Everything else in `Imports/` is pure.
//
// - A fetch: a link in, the bytes and the response's facts out, or why not. The live one is
//   `URLSession`. It follows redirects (the reference allowed three), reports the final link,
//   stops reading at `maxBytes`, and fails a request that takes too long.
// - An extractor: text in, a model's reading out. The live one is `FallbackExtractor` (Gemini,
//   then the on-device model, whose result comes back marked `rough`).
//
// Tests drive the pipeline with fakes of both.

/// A request for one page or one small API response.
public struct FetchRequest: Sendable, Hashable {
  public var url: String
  /// The most bytes to read. More than this is `FetchError.tooLarge`.
  public var maxBytes: Int
  /// Sent as `Accept`.
  public var accept: String

  public init(url: String, maxBytes: Int, accept: String) {
    self.url = url
    self.maxBytes = maxBytes
    self.accept = accept
  }
}

/// What came back: the body, its content type, and the link it finally came from after
/// redirects.
public struct FetchedPage: Sendable, Hashable {
  public var bytes: Data
  public var contentType: String?
  public var url: String

  public init(bytes: Data, contentType: String?, url: String) {
    self.bytes = bytes
    self.contentType = contentType
    self.url = url
  }
}

/// Why a fetch failed (`FetchError` in the reference's `RemoteFetch`).
public enum FetchError: Error, Sendable, Hashable {
  /// The link, or somewhere it redirected to, isn't one to open.
  case blocked(detail: String? = nil)
  /// No connection, or the server couldn't be reached. `detail` is "dns" when the name doesn't
  /// resolve, which a retry won't fix.
  case unreachable(detail: String? = nil)
  /// The server answered with this HTTP status.
  case status(Int)
  /// The body is bigger than `maxBytes`.
  case tooLarge
  case timeout
  /// The request was cancelled.
  case cancelled

  /// Worth trying again: the failure may pass (not a name that doesn't resolve).
  var isTransient: Bool {
    switch self {
    case .unreachable(let detail): detail != "dns"
    case .timeout: true
    case .status(let code): (500...599).contains(code) || code == 429
    case .blocked, .tooLarge, .cancelled: false
    }
  }
}

public protocol PageFetcher: Sendable {
  func fetch(_ request: FetchRequest) async throws(FetchError) -> FetchedPage
}

/// Reads a recipe out of text with a model. Throwing `RecipeAIError.missingKey` means there is
/// no model to ask, and is treated as having none. `FallbackExtractor` is the app's.
public protocol RecipeExtracting: Sendable {
  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction
}

extension FallbackExtractor: RecipeExtracting {}

/// Why a distill failed, or that it was cancelled.
public enum DistillError: Error, Sendable, Hashable {
  /// The plain reason, with whatever was read before it failed (a caption with no recipe).
  case failed(ImportFailureCode, raw: String? = nil)
  /// The work was cancelled, such as by closing the sheet. Not a failure to show.
  case cancelled

  /// The failure code, or nil for a cancellation.
  public var code: ImportFailureCode? {
    if case .failed(let code, _) = self { return code }
    return nil
  }

  public var raw: String? {
    if case .failed(_, let raw) = self { return raw }
    return nil
  }
}

/// Limits and timings a distill runs with.
public struct DistillOptions: Sendable, Hashable {
  /// A distill gets this long; past it, it fails as timed out. This bounds waiting on the
  /// fetcher and the extractor, not parsing: reading a page or text is linear in its size and
  /// does not watch the clock.
  public var timeout: Duration
  /// The wait before the first retry of a transient fetch failure; it doubles for the second.
  public var retryDelay: Duration
  /// Recipe pages are rarely over 1 MB; some carry a lot of inline script.
  public var maxPageBytes: Int
  /// How long the app waits for the macro estimate asked for during an import (`MACRO_TIMEOUT`
  /// in the reference). One that isn't back by then is left for after the recipe is saved.
  public var macroTimeout: Duration

  public init(
    timeout: Duration = .seconds(120), retryDelay: Duration = .milliseconds(400),
    maxPageBytes: Int = 5 * 1024 * 1024, macroTimeout: Duration = .seconds(30)
  ) {
    self.timeout = timeout
    self.retryDelay = retryDelay
    self.maxPageBytes = maxPageBytes
    self.macroTimeout = macroTimeout
  }
}
