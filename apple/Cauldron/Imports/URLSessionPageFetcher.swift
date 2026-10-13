import CauldronKit
import Foundation
import Synchronization

/// The live `PageFetcher`: `URLSession`, as `RemoteFetch.ts` did with `fetch` (minus the
/// address checks, which guard a server and mean nothing on the cook's own device).
///
/// - An ephemeral session, so no cookie, cache or credential is kept.
/// - Only links `AddressRules` allows (http and https, no credentials, the default port, no
///   local or private address) for the first request and every redirect. At most `maxRedirects` redirects are followed; a fourth is the answer itself.
/// - The body is read as it arrives and stops at `maxBytes`.
/// - Failures end as the `FetchError` that `Seams.swift` documents.
struct URLSessionPageFetcher: PageFetcher {
  /// What the reference sent.
  static let userAgent = "Cauldron/1.0 (+https://srcery.computer)"
  /// The reference followed three.
  static let maxRedirects = 3

  private let session: URLSession

  /// - Parameters:
  ///   - idleTimeout: how long the server may stay silent (the reference allowed 10 seconds).
  ///   - totalTimeout: how long a whole fetch may take, redirects and body included.
  ///   - protocolClasses: what answers the requests in place of the network, for tests.
  init(
    idleTimeout: TimeInterval = 10, totalTimeout: TimeInterval = 30,
    protocolClasses: [AnyClass]? = nil
  ) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.waitsForConnectivity = false
    configuration.timeoutIntervalForRequest = idleTimeout
    configuration.timeoutIntervalForResource = totalTimeout
    if let protocolClasses { configuration.protocolClasses = protocolClasses }
    session = URLSession(configuration: configuration)
  }

  /// The one fetcher the app uses, so a session isn't made for every screen that wants one.
  static let live: URLSessionPageFetcher = {
    liveCreations.withLock { $0 += 1 }
    return URLSessionPageFetcher()
  }()

  /// How many times `live` was made, for a test to check it is once.
  static let liveCreations = Mutex(0)

  func fetch(_ request: FetchRequest) async throws(FetchError) -> FetchedPage {
    let url = try Self.checked(request.url)
    var urlRequest = URLRequest(url: url)
    urlRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    urlRequest.setValue(request.accept, forHTTPHeaderField: "Accept")
    let redirects = RedirectGuard(limit: Self.maxRedirects)
    do {
      return try await load(urlRequest, maxBytes: request.maxBytes, redirects: redirects)
    } catch {
      throw Self.fetchError(from: error)
    }
  }

  private func load(_ request: URLRequest, maxBytes: Int, redirects: RedirectGuard) async throws
    -> FetchedPage
  {
    let (bytes, response) = try await session.bytes(for: request, delegate: redirects)
    if let refusal = redirects.refusal { throw refusal }
    guard let http = response as? HTTPURLResponse else {
      throw FetchError.unreachable(detail: "response")
    }
    // Includes a redirect that was refused for being one too many: it is the answer.
    guard (200...299).contains(http.statusCode) else { throw FetchError.status(http.statusCode) }
    if http.expectedContentLength > Int64(maxBytes) { throw FetchError.tooLarge }

    var body: [UInt8] = []
    body.reserveCapacity(
      http.expectedContentLength > 0 ? Int(http.expectedContentLength) : 64 * 1024)
    for try await byte in bytes {
      body.append(byte)
      if body.count > maxBytes { throw FetchError.tooLarge }
    }
    return FetchedPage(
      bytes: Data(body), contentType: http.value(forHTTPHeaderField: "Content-Type"),
      url: http.url?.absoluteString ?? request.url?.absoluteString ?? "")
  }

  // MARK: Rules

  /// The link as a URL, or why it isn't one to open (`AddressRules`). `URL(string:)` writes an
  /// internationalised host in punycode, so a link the pipeline accepts as typed
  /// (`https://пример.рф/x`) is fetched under its ASCII name.
  static func checked(_ link: String) throws(FetchError) -> URL {
    guard let url = URL(string: link) else { throw .blocked(detail: "scheme") }
    if let reason = AddressRules.refusal(for: url) { throw .blocked(detail: reason) }
    return url
  }

  /// Where a failure ends up. A pure function of the error, so the mapping can be tested for
  /// every code without a network.
  static func fetchError(from error: any Error) -> FetchError {
    if let error = error as? FetchError { return error }
    if error is CancellationError { return .cancelled }
    guard let error = error as? URLError else { return .unreachable(detail: "read") }
    switch error.code {
    case .cancelled:
      return .cancelled
    case .timedOut:
      return .timeout
    case .cannotFindHost, .dnsLookupFailed:
      return .unreachable(detail: "dns")
    case .dataLengthExceedsMaximum:
      return .tooLarge
    case .badURL, .unsupportedURL:
      return .blocked(detail: "scheme")
    case .appTransportSecurityRequiresSecureConnection:
      // A plain http link on a device that only opens https ones.
      return .blocked(detail: "insecure")
    case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
      .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
      .clientCertificateRequired:
      return .blocked(detail: "tls")
    case .httpTooManyRedirects, .redirectToNonExistentLocation:
      return .blocked(detail: "redirect")
    default:
      return .unreachable()
    }
  }
}

/// Decides each redirect of one fetch: followed up to the limit, and only to an http(s) link
/// without credentials. A redirect it refuses becomes the response, so a loop ends as the
/// redirect's own status and a redirect to somewhere else entirely as `blocked`.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
  private struct State {
    var followed = 0
    var refusal: FetchError?
  }

  private let limit: Int
  private let state = Mutex(State())

  init(limit: Int) {
    self.limit = limit
  }

  /// Set when a redirect went somewhere that isn't one to open.
  var refusal: FetchError? { state.withLock { $0.refusal } }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
  ) async -> URLRequest? {
    guard let target = request.url,
      (try? URLSessionPageFetcher.checked(target.absoluteString)) != nil
    else {
      state.withLock { $0.refusal = .blocked(detail: "redirect") }
      return nil
    }
    let follow = state.withLock { state in
      state.followed += 1
      return state.followed <= limit
    }
    return follow ? request : nil
  }
}
