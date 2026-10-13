import Foundation
import SwiftSoup

// The one place that imports SwiftSoup. The reference read pages with linkedom's DOM; this is
// the small part of it the importers use: a parsed document, its elements in document order,
// their attributes and text. Selectors aren't used: each importer walks the tree and tests
// elements itself, so a match means what the reference's CSS meant (case-sensitive attribute
// values, `~=` as a word list) and a hostile page can't nest deeper than a stack allows,
// because every walk here is iterative.
//
// These types wrap SwiftSoup's reference-type tree, so they are not `Sendable`. They live
// inside one synchronous call and never cross an actor; what the callers pass on are plain
// value types.

struct HTMLDocument {
  fileprivate let document: SwiftSoup.Document

  init(_ html: String) {
    let parsed = (try? SwiftSoup.parse(html)) ?? SwiftSoup.Document("")
    // `innerHTML` is read back as written, not indented.
    parsed.outputSettings().prettyPrint(pretty: false)
    document = parsed
  }

  /// The `<body>`.
  var body: HTMLElement? { document.body().map(HTMLElement.init) }

  /// Every element, in document order.
  var elements: [HTMLElement] { HTMLElement(document).descendants }
}

enum HTMLNode {
  case element(HTMLElement)
  case text(String)
}

struct HTMLElement: Equatable {
  fileprivate let element: SwiftSoup.Element

  fileprivate init(_ element: SwiftSoup.Element) { self.element = element }

  static func == (lhs: HTMLElement, rhs: HTMLElement) -> Bool { lhs.element === rhs.element }

  /// Lower-case, as the parser normalises it.
  var tagName: String { element.tagName() }

  /// `getAttribute(name)`: nil when the element doesn't have it.
  func attribute(_ name: String) -> String? {
    guard element.hasAttr(name) else { return nil }
    return try? element.attr(name)
  }

  func hasAttribute(_ name: String) -> Bool { element.hasAttr(name) }

  /// The class names, split on whitespace.
  var classNames: [String] {
    (attribute("class") ?? "").split(whereSeparator: { " \t\n\r\u{0C}".contains($0) }).map(
      String.init)
  }

  var parent: HTMLElement? {
    guard let parent = element.parent(), !(parent is SwiftSoup.Document) else { return nil }
    return HTMLElement(parent)
  }

  /// This element, then its parents up to the root.
  var inclusiveAncestors: [HTMLElement] {
    var out: [HTMLElement] = []
    var current: HTMLElement? = self
    while let here = current {
      out.append(here)
      current = here.parent
    }
    return out
  }

  var children: [HTMLNode] {
    element.getChildNodes().compactMap { node in
      if let child = node as? SwiftSoup.Element { return .element(HTMLElement(child)) }
      if let text = node as? TextNode { return .text(text.getWholeText()) }
      if let data = node as? DataNode { return .text(data.getWholeData()) }
      return nil
    }
  }

  /// Descendant elements in document order, not including this one.
  var descendants: [HTMLElement] {
    var out: [HTMLElement] = []
    var stack = Array(childElements.reversed())
    while let next = stack.popLast() {
      out.append(next)
      stack.append(contentsOf: next.childElements.reversed())
    }
    return out
  }

  /// Descendant elements in document order, visiting at most `budget` of them and charging
  /// each one to it, so work over a hostile page's nesting stays bounded.
  func descendants(budget: inout Int) -> [HTMLElement] {
    var out: [HTMLElement] = []
    var stack = Array(childElements.reversed())
    while budget > 0, let next = stack.popLast() {
      budget -= 1
      out.append(next)
      stack.append(contentsOf: next.childElements.reversed())
    }
    return out
  }

  /// `textContent`, visiting at most `budget` nodes and charging each one to it.
  func textContent(budget: inout Int) -> String {
    var out = ""
    var stack: [Node] = Array(element.getChildNodes().reversed())
    while budget > 0, let node = stack.popLast() {
      budget -= 1
      if let text = node as? TextNode {
        out += text.getWholeText()
      } else if let data = node as? DataNode {
        out += data.getWholeData()
      } else if node is SwiftSoup.Element {
        stack.append(contentsOf: node.getChildNodes().reversed())
      }
    }
    return out
  }

  var childElements: [HTMLElement] {
    element.getChildNodes().compactMap { ($0 as? SwiftSoup.Element).map(HTMLElement.init) }
  }

  /// `textContent`: every descendant text node, scripts and styles included, with no
  /// whitespace changes.
  var textContent: String {
    var out = ""
    var stack: [Node] = Array(element.getChildNodes().reversed())
    while let node = stack.popLast() {
      if let text = node as? TextNode {
        out += text.getWholeText()
      } else if let data = node as? DataNode {
        out += data.getWholeData()
      } else if node is SwiftSoup.Element {
        stack.append(contentsOf: node.getChildNodes().reversed())
      }
    }
    return out
  }

  /// `innerHTML`.
  var innerHTML: String { (try? element.html()) ?? "" }
}
