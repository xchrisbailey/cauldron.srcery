import Foundation

// Links shared from Apple News. "apple.news/A…" serves a stub page that opens the News app on an
// Apple device and otherwise sends the browser on to the publisher's article with a script
// (`redirectToUrlAfterTimeout("https://…", 0)`). The stub itself has no recipe, so the importer
// reads the publisher's link out of it and imports that page instead. An article that only
// lives in News (News+ and some partner stories) has no publisher link, and stays "no recipe".

enum AppleNews {
  /// Whether a link is on apple.news.
  static func isStub(_ url: String) -> Bool {
    guard let host = WebURL.parse(url)?.host else { return false }
    return host == "apple.news" || host.hasSuffix(".apple.news")
  }

  private static let redirect = JSRegex(
    "redirectToUrlAfterTimeout\\(\(JS.s)*[\"']([^\"'\(JS.space)]+)[\"']")

  /// The publisher's link in a stub page: its redirect, then a canonical or `og:url` link.
  /// Nil when there is none, or when it is not an http(s) link off apple.news.
  static func publisherLink(html: String, base: String) -> String? {
    let elements = HTMLDocument(html).elements
    let scripted = elements.lazy.filter { $0.tagName == "script" }
      .compactMap { redirect.firstMatch(in: $0.textContent)?.group(1) }
      .map { $0.replacingOccurrences(of: "\\/", with: "/") }
    let canonical = elements.first {
      $0.tagName == "link" && $0.attribute("rel")?.lowercased() == "canonical"
    }?.attribute("href")
    let graph = elements.first {
      $0.tagName == "meta" && $0.attribute("property") == "og:url"
    }?.attribute("content")
    let candidates = Array(scripted) + [canonical, graph].compactMap { $0 }
    let baseURL = WebURL.parse(base)
    for candidate in candidates {
      let trimmed = candidate.jsTrimmed()
      guard !trimmed.isEmpty, let url = WebURL.parse(trimmed, base: baseURL),
        url.username.isEmpty,
        url.password.isEmpty, !isStub(url.string)
      else { continue }
      return url.string
    }
    return nil
  }
}
