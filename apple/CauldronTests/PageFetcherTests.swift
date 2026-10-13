import CauldronKit
import Foundation
import Synchronization
import Testing

@testable import Cauldron

/// Answers `URLSession` requests from a table instead of the network. Each test uses its own
/// host, so the suite can run in parallel.
final class StubNetwork: URLProtocol {
  enum Behaviour: Sendable {
    case respond(status: Int = 200, headers: [String: String] = [:], chunks: [Data])
    case redirect(status: Int = 302, to: String)
    case fail(URLError.Code)
    /// Never answers; waits to be cancelled.
    case hang
  }

  private static let table = Mutex<[String: Behaviour]>([:])
  private static let seenRequests = Mutex<[URLRequest]>([])
  private static let loading = Mutex<[String: Int]>([:])

  static func set(_ url: String, _ behaviour: Behaviour) {
    table.withLock { $0[url] = behaviour }
  }

  static func requests(to host: String) -> [URLRequest] {
    seenRequests.withLock { $0.filter { $0.url?.host == host } }
  }

  static func started(_ url: String) -> Int { loading.withLock { $0[url] ?? 0 } }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url, let client else { return }
    Self.seenRequests.withLock { $0.append(request) }
    Self.loading.withLock { $0[url.absoluteString, default: 0] += 1 }
    switch Self.table.withLock({ $0[url.absoluteString] }) {
    case .respond(let status, let headers, let chunks)?:
      let response = HTTPURLResponse(
        url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
      client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      for chunk in chunks { client.urlProtocol(self, didLoad: chunk) }
      client.urlProtocolDidFinishLoading(self)
    case .redirect(let status, let target)?:
      let response = HTTPURLResponse(
        url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Location": target])!
      let next = URLRequest(url: URL(string: target)!)
      client.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
      // If the session doesn't follow it, this is the answer.
      client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client.urlProtocolDidFinishLoading(self)
    case .fail(let code)?:
      client.urlProtocol(self, didFailWithError: URLError(code))
    case .hang?:
      break
    case nil:
      client.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
    }
  }

  override func stopLoading() {}
}

@Suite("Page fetcher")
struct PageFetcherTests {
  private let fetcher = URLSessionPageFetcher(protocolClasses: [StubNetwork.self])
  private let html = Data("<html>hello</html>".utf8)

  private func request(_ url: String, max: Int = 1_000_000) -> FetchRequest {
    FetchRequest(url: url, maxBytes: max, accept: "text/html")
  }

  private func failure(_ url: String, max: Int = 1_000_000) async -> FetchError? {
    do {
      _ = try await fetcher.fetch(request(url, max: max))
      return nil
    } catch {
      return error
    }
  }

  // MARK: Getting a page

  @Test func readsTheBodyTheTypeAndTheFinalLink() async throws {
    StubNetwork.set(
      "https://ok.test/a",
      .respond(headers: ["Content-Type": "text/html; charset=utf-8"], chunks: [html]))
    let page = try await fetcher.fetch(request("https://ok.test/a"))
    #expect(page.bytes == html)
    #expect(page.contentType == "text/html; charset=utf-8")
    #expect(page.url == "https://ok.test/a")
  }

  @Test func sendsTheAcceptHeaderAndTheReferencesUserAgentAndKeepsNothing() async throws {
    StubNetwork.set("https://headers.test/a", .respond(chunks: [html]))
    _ = try await fetcher.fetch(request("https://headers.test/a"))
    let sent = try #require(StubNetwork.requests(to: "headers.test").first)
    #expect(sent.value(forHTTPHeaderField: "Accept") == "text/html")
    #expect(
      sent.value(forHTTPHeaderField: "User-Agent") == "Cauldron/1.0 (+https://srcery.computer)")
    #expect(sent.value(forHTTPHeaderField: "Cookie") == nil)
  }

  @Test func followsRedirectsAndReportsWhereItEnded() async throws {
    StubNetwork.set("https://redirect.test/short", .redirect(to: "https://redirect.test/long"))
    StubNetwork.set(
      "https://redirect.test/long",
      .respond(headers: ["Content-Type": "text/html"], chunks: [html]))
    let page = try await fetcher.fetch(request("https://redirect.test/short"))
    #expect(page.url == "https://redirect.test/long")
    #expect(page.bytes == html)
  }

  @Test func aRedirectLoopEndsAsTheRedirectsOwnStatus() async {
    StubNetwork.set("https://loop.test/a", .redirect(to: "https://loop.test/b"))
    StubNetwork.set("https://loop.test/b", .redirect(status: 301, to: "https://loop.test/a"))
    #expect(await failure("https://loop.test/a") == .status(301))
    // The first request and three redirects, no more.
    #expect(StubNetwork.requests(to: "loop.test").count == 4)
  }

  @Test func aRedirectToSomewhereThatIsntAWebLinkIsBlocked() async {
    StubNetwork.set("https://away.test/a", .redirect(to: "file:///etc/passwd"))
    #expect(await failure("https://away.test/a") == .blocked(detail: "redirect"))
    StubNetwork.set("https://away.test/b", .redirect(to: "https://user:pass@away.test/c"))
    #expect(await failure("https://away.test/b") == .blocked(detail: "redirect"))
  }

  // MARK: Limits

  @Test func stopsAtTheSizeCapWhileReading() async {
    let chunk = Data(repeating: 65, count: 400)
    StubNetwork.set("https://big.test/a", .respond(chunks: [chunk, chunk, chunk]))
    #expect(await failure("https://big.test/a", max: 1000) == .tooLarge)
  }

  @Test func aBodyExactlyAtTheCapIsFine() async throws {
    StubNetwork.set("https://exact.test/a", .respond(chunks: [Data(repeating: 65, count: 1000)]))
    let page = try await fetcher.fetch(request("https://exact.test/a", max: 1000))
    #expect(page.bytes.count == 1000)
  }

  @Test func aDeclaredSizeOverTheCapFailsWithoutReadingTheBody() async {
    StubNetwork.set(
      "https://declared.test/a",
      .respond(headers: ["Content-Length": "5000"], chunks: [Data(repeating: 65, count: 5000)]))
    #expect(await failure("https://declared.test/a", max: 1000) == .tooLarge)
  }

  // MARK: Failures

  @Test func anErrorStatusIsReportedWithItsCode() async {
    for status in [403, 404, 429, 500, 503] {
      let url = "https://status.test/\(status)"
      StubNetwork.set(url, .respond(status: status, chunks: [html]))
      #expect(await failure(url) == .status(status))
    }
  }

  @Test func networkFailuresMapToTheDocumentedErrors() async {
    let cases: [(URLError.Code, FetchError)] = [
      (.timedOut, .timeout),
      (.cannotFindHost, .unreachable(detail: "dns")),
      (.notConnectedToInternet, .unreachable()),
      (.cannotConnectToHost, .unreachable()),
    ]
    for (code, expected) in cases {
      let url = "https://fails.test/\(code.rawValue)"
      StubNetwork.set(url, .fail(code))
      #expect(await failure(url) == expected, "\(code)")
    }
  }

  @Test func linksThatAreNotWebLinksAreBlockedBeforeAnyRequest() async {
    for link in [
      "ftp://nope.test/a", "file:///etc/hosts", "javascript:alert(1)", "https://u:p@nope.test/a",
      "https:///nohost", "not a url", "",
    ] {
      #expect(await failure(link) != nil, "\(link)")
      guard case .blocked? = await failure(link) else {
        Issue.record("\(link) should be blocked")
        continue
      }
    }
    #expect(StubNetwork.requests(to: "nope.test").isEmpty)
  }

  // MARK: Cancelling

  @Test func cancellingEndsAFetchThatIsWaitingOnTheServer() async {
    StubNetwork.set("https://hang.test/a", .hang)
    let fetcher = fetcher
    let task = Task { () -> FetchError? in
      do {
        _ = try await fetcher.fetch(
          FetchRequest(url: "https://hang.test/a", maxBytes: 1000, accept: "*/*"))
        return nil
      } catch {
        return error as? FetchError
      }
    }
    while StubNetwork.started("https://hang.test/a") == 0 { await Task.yield() }
    task.cancel()
    #expect(await task.value == .cancelled)
  }

  // MARK: The mapping

  @Test func everyKindOfFailureMapsToOneOfTheSeamsErrors() {
    func mapped(_ code: URLError.Code) -> FetchError {
      URLSessionPageFetcher.fetchError(from: URLError(code))
    }
    #expect(mapped(.cancelled) == .cancelled)
    #expect(mapped(.timedOut) == .timeout)
    #expect(mapped(.dnsLookupFailed) == .unreachable(detail: "dns"))
    #expect(mapped(.cannotFindHost) == .unreachable(detail: "dns"))
    #expect(mapped(.networkConnectionLost) == .unreachable())
    #expect(mapped(.dataLengthExceedsMaximum) == .tooLarge)
    #expect(mapped(.unsupportedURL) == .blocked(detail: "scheme"))
    #expect(mapped(.badURL) == .blocked(detail: "scheme"))
    #expect(mapped(.appTransportSecurityRequiresSecureConnection) == .blocked(detail: "insecure"))
    #expect(mapped(.serverCertificateUntrusted) == .blocked(detail: "tls"))
    #expect(mapped(.secureConnectionFailed) == .blocked(detail: "tls"))
    #expect(mapped(.httpTooManyRedirects) == .blocked(detail: "redirect"))
    #expect(URLSessionPageFetcher.fetchError(from: CancellationError()) == .cancelled)
    #expect(URLSessionPageFetcher.fetchError(from: FetchError.tooLarge) == .tooLarge)
    #expect(
      URLSessionPageFetcher.fetchError(from: NSError(domain: "x", code: 1))
        == .unreachable(detail: "read"))
  }
}
