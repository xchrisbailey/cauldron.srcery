import Foundation

// Reading saved or fetched HTML: text with entities decoded, the page's own metadata, and its
// readable text for the model (`html.ts` in the API).

/// A page's own description of itself: Open Graph, Twitter and plain meta tags, and the
/// canonical link.
public struct PageMeta: Sendable, Hashable, Codable {
  public var title: String?
  public var description: String?
  public var siteName: String?
  public var author: String?
  public var imageUrl: String?
  public var canonicalUrl: String?

  public init(
    title: String? = nil, description: String? = nil, siteName: String? = nil,
    author: String? = nil, imageUrl: String? = nil, canonicalUrl: String? = nil
  ) {
    self.title = title
    self.description = description
    self.siteName = siteName
    self.author = author
    self.imageUrl = imageUrl
    self.canonicalUrl = canonicalUrl
  }
}

enum PageText {
  private static let angleOrAmpersand = JSRegex("[<&]")
  private static let lineBreakTag = JSRegex("<br\(JS.s)*/?>", ignoreCase: true)

  /// Text with HTML entities and tags removed, whitespace collapsed (`plainText`).
  static func plain(_ value: String) -> String {
    guard angleOrAmpersand.test(value) else { return value.jsSpacesCollapsed().jsTrimmed() }
    let document = HTMLDocument(
      "<div>\(lineBreakTag.replacing(in: value, with: " "))</div>")
    let text = document.elements.first { $0.tagName == "div" }?.textContent ?? value
    return text.jsSpacesCollapsed().jsTrimmed()
  }

  /// A link resolved against the page, http(s) only (`absolute`).
  static func absolute(_ href: String?, base: String) -> String? {
    guard let href, !href.isEmpty, let baseURL = WebURL.parse(base) else { return nil }
    return WebURL.parse(href.jsTrimmed(), base: baseURL)?.string
  }

  private static func isTrackingName(_ name: String) -> Bool {
    let lowered = name.lowercased()
    if lowered.hasPrefix("utm_") {
      return !name.unicodeScalars.dropFirst(4).contains { JS.lineBreakScalars.contains($0) }
    }
    return ["fbclid", "gclid", "msclkid", "mc_cid", "mc_eid", "igshid", "ref", "_ga", "_gl"]
      .contains(lowered)
  }

  /// A link without tracking parameters (utm_*, fbclid and the like).
  static func withoutTracking(_ href: String?) -> String? {
    guard let href, !href.isEmpty else { return nil }
    guard let url = WebURL.parse(href) else { return href }
    return url.removingParams(where: isTrackingName).string
  }

  private static func attribute(_ element: HTMLElement?, _ name: String) -> String? {
    guard let value = element?.attribute(name)?.jsTrimmed(), !value.isEmpty else { return nil }
    return value
  }

  private static func meta(_ elements: [HTMLElement], _ keys: [String]) -> String? {
    let metas = elements.filter { $0.tagName == "meta" }
    for key in keys {
      let element =
        metas.first { $0.attribute("property") == key }
        ?? metas.first { $0.attribute("name") == key }
      if let content = attribute(element, "content") { return plain(content) }
    }
    return nil
  }

  /// Open Graph, Twitter and plain meta tags, and the canonical link (`pageMeta`).
  static func pageMeta(_ document: HTMLDocument, base: String) -> PageMeta {
    let elements = document.elements
    let titleText = elements.first { $0.tagName == "title" }?.textContent.jsTrimmed()
    let canonical = elements.first {
      $0.tagName == "link" && $0.attribute("rel") == "canonical"
    }
    return PageMeta(
      title: meta(elements, ["og:title", "twitter:title"])
        ?? (titleText.flatMap { $0.isEmpty ? nil : $0 }),
      description: meta(elements, ["og:description", "description", "twitter:description"]),
      siteName: meta(elements, ["og:site_name", "application-name"]),
      author: meta(elements, ["author", "article:author"]),
      imageUrl: absolute(
        meta(elements, ["og:image", "og:image:url", "twitter:image"]), base: base),
      canonicalUrl: withoutTracking(
        absolute(
          attribute(canonical, "href") ?? meta(elements, ["og:url"]), base: base)))
  }

  private static let blockTags: Set<String> = [
    "p", "div", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "section", "article", "tr",
    "br", "blockquote", "header", "figcaption", "dt", "dd",
  ]
  private static let noiseTags: Set<String> = [
    "script", "style", "noscript", "template", "svg", "iframe", "nav", "footer", "aside", "form",
    "button",
  ]

  /// What the reference's NOISE selector matched: scripts and navigation, anything hidden from
  /// assistive technology, comments, ads, and anything whose class mentions a newsletter or
  /// related posts.
  private static func isNoise(_ element: HTMLElement) -> Bool {
    if noiseTags.contains(element.tagName) { return true }
    if element.attribute("aria-hidden") == "true" { return true }
    if element.attribute("id") == "comments" { return true }
    let classes = element.classNames
    if classes.contains(where: {
      $0 == "comments" || $0 == "comment" || $0 == "advertisement" || $0 == "ad"
    }) {
      return true
    }
    if let value = element.attribute("class"),
      value.contains("newsletter") || value.contains("related")
    {
      return true
    }
    return false
  }

  private enum Step {
    case node(HTMLNode)
    case close
  }

  /// The page's readable text, one block per line: the article (or main) when there is one,
  /// without scripts, navigation, footers and comments. Fed to the model when a page has no
  /// structured recipe (`readableText`).
  static func readable(_ document: HTMLDocument, max: Int) -> String {
    let elements = document.elements
    guard
      let root =
        elements.first(where: { $0.tagName == "article" })
        ?? elements.first(where: { $0.tagName == "main" })
        ?? elements.first(where: { $0.attribute("role") == "main" })
        ?? document.body
    else { return "" }
    var out: [String] = []
    var line = ""
    func flush() {
      let text = line.jsSpacesCollapsed().jsTrimmed()
      if !text.isEmpty { out.append(text) }
      line = ""
    }
    // Walked with a stack, not recursion: a hostile page can nest far deeper than the call
    // stack goes. The root is never noise, however it is marked.
    var stack: [Step] = [.node(.element(root))]
    var isRoot = true
    while let step = stack.popLast() {
      guard case .node(let node) = step else {
        flush()
        continue
      }
      switch node {
      case .text(let text):
        line += text
      case .element(let element):
        if !isRoot && isNoise(element) { continue }
        isRoot = false
        if blockTags.contains(element.tagName) {
          flush()
          stack.append(.close)
        }
        if element.tagName == "li" { line += "- " }
        for child in element.children.reversed() { stack.append(.node(child)) }
      }
    }
    flush()
    return out.joined(separator: "\n").jsPrefix(max)
  }
}
