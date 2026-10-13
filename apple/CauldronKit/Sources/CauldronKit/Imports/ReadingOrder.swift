import Foundation

// Puts the text recognised on a photographed page into reading order. Text recognition returns
// pieces of text with boxes, in no order a person would read them. A cookbook page is often two
// columns (the ingredients beside the method), so reading it top to bottom across the page would
// weave the two together.
//
// The rules, kept deliberately small (this is not layout analysis):
//
// 1. A gutter is a vertical gap that splits the page into a left and a right side. It needs at
//    least three pieces of text on each side, each side at least 12% of the page wide (so a column
//    of quantities beside their ingredients is not a column), and a gap of at least 3% of the
//    page between the two. Among the gaps that qualify, the widest wins.
// 2. A piece of text that crosses the gutter is a heading or a footer spanning both columns. It
//    may be at most 30% of the page's pieces; more than that and the page is a single column.
// 3. Spanning text splits the page into bands, read from the top. In each band the left column is
//    read in full, then the right one. Each column is read by the same rules again, so a sidebar
//    or a third column falls out of it.
// 4. Without a gutter, or inside a column, pieces on the same baseline are joined left to right
//    and the lines are read top to bottom. Two pieces are on one baseline when their heights
//    overlap by at least half the smaller one's, which forgives a page photographed slightly
//    askew.
//
// What it won't do: tell a table from columns when its gaps are wide, or read text set at an
// angle. The pages are then simply less tidy, and the model that reads the result copes.

/// Where a piece of text sits on its page. All four numbers are fractions of the page, 0 to 1,
/// measured from its top-left corner (the opposite way up from Vision's boxes, which the app
/// flips once at the edge).
public struct TextBox: Sendable, Hashable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  var maxX: Double { x + width }
  var maxY: Double { y + height }
  var midY: Double { y + height / 2 }

  var isUsable: Bool {
    [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
  }
}

/// A piece of recognised text, usually one printed line, and its box.
public struct TextFragment: Sendable, Hashable {
  public var text: String
  public var box: TextBox

  public init(text: String, box: TextBox) {
    self.text = text
    self.box = box
  }
}

public enum ReadingOrder {
  /// The smallest gap between two columns, as a fraction of the page.
  static let minGutter = 0.03
  /// Each side of a gutter needs at least this many pieces of text...
  static let minColumnFragments = 3
  /// ...and at least this much of the page's width.
  static let minColumnWidth = 0.12
  /// Spanning text above this share of the pieces means there is no gutter.
  static let maxSpanningShare = 0.3
  /// The gutter must sit inside this central part of the text, on each side's share of its
  /// width; it can't be a margin.
  static let centralMargin = 0.2
  /// Columns inside columns stop here.
  static let maxDepth = 3

  /// A page's text, one string per line, in reading order. Empty text and unusable boxes are
  /// dropped.
  public static func lines(_ fragments: [TextFragment]) -> [String] {
    let usable = fragments.filter {
      $0.box.isUsable && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return read(usable, depth: 0)
  }

  /// A page's text as one string.
  public static func text(_ fragments: [TextFragment]) -> String {
    lines(fragments).joined(separator: "\n")
  }

  /// Pages, in the order they were captured, with a blank line between. A page with no text is
  /// left out.
  public static func join(pages: [String]) -> String {
    pages.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n\n")
  }

  // MARK: Columns

  private struct Split {
    var left: [TextFragment]
    var right: [TextFragment]
    var spanning: [TextFragment]
    var gap: Double
  }

  private static func read(_ fragments: [TextFragment], depth: Int) -> [String] {
    guard depth < maxDepth, let split = bestSplit(of: fragments) else { return rows(fragments) }
    var output: [String] = []
    var left = split.left
    var right = split.right
    // Each piece of spanning text closes the band above it.
    for span in split.spanning.sorted(by: { $0.box.midY < $1.box.midY }) {
      let aboveLeft = left.filter { $0.box.midY < span.box.midY }
      let aboveRight = right.filter { $0.box.midY < span.box.midY }
      output += read(aboveLeft, depth: depth + 1) + read(aboveRight, depth: depth + 1)
      output += rows([span])
      left.removeAll { $0.box.midY < span.box.midY }
      right.removeAll { $0.box.midY < span.box.midY }
    }
    return output + read(left, depth: depth + 1) + read(right, depth: depth + 1)
  }

  private static func bestSplit(of fragments: [TextFragment]) -> Split? {
    guard fragments.count >= 2 * minColumnFragments else { return nil }
    let lowest = fragments.map(\.box.x).min() ?? 0
    let highest = fragments.map(\.box.maxX).max() ?? 0
    let reach = highest - lowest
    guard reach > 0 else { return nil }
    let low = lowest + reach * centralMargin
    let high = highest - reach * centralMargin

    let edges = Set(fragments.flatMap { [$0.box.x, $0.box.maxX] }).sorted()
    var best: Split?
    for (a, b) in zip(edges, edges.dropFirst()) {
      let candidate = (a + b) / 2
      guard candidate >= low, candidate <= high,
        let split = split(fragments, at: candidate)
      else { continue }
      if split.gap > (best?.gap ?? 0) { best = split }
    }
    return best
  }

  private static func split(_ fragments: [TextFragment], at line: Double)
    -> Split?
  {
    var left: [TextFragment] = []
    var right: [TextFragment] = []
    var spanning: [TextFragment] = []
    for fragment in fragments {
      let box = fragment.box
      if box.maxX <= line {
        left.append(fragment)
      } else if box.x >= line {
        right.append(fragment)
      } else {
        spanning.append(fragment)
      }
    }
    guard left.count >= minColumnFragments, right.count >= minColumnFragments,
      Double(spanning.count) <= maxSpanningShare * Double(fragments.count)
    else { return nil }
    guard let leftEdge = left.map(\.box.maxX).max(), let rightEdge = right.map(\.box.x).min()
    else { return nil }
    let gap = rightEdge - leftEdge
    guard gap >= minGutter else { return nil }
    guard width(of: left) >= minColumnWidth,
      width(of: right) >= minColumnWidth
    else { return nil }
    return Split(left: left, right: right, spanning: spanning, gap: gap)
  }

  private static func width(of fragments: [TextFragment]) -> Double {
    let lowest = fragments.map(\.box.x).min() ?? 0
    let highest = fragments.map(\.box.maxX).max() ?? 0
    return highest - lowest
  }

  // MARK: Lines

  private struct Row {
    var top: Double
    var bottom: Double
    var members: [TextFragment]
  }

  /// Joins pieces on one baseline and reads the lines top to bottom.
  private static func rows(_ fragments: [TextFragment]) -> [String] {
    let ordered = fragments.sorted {
      $0.box.midY != $1.box.midY ? $0.box.midY < $1.box.midY : $0.box.x < $1.box.x
    }
    var rows: [Row] = []
    for fragment in ordered {
      let box = fragment.box
      if var last = rows.last {
        let overlap = min(last.bottom, box.maxY) - max(last.top, box.y)
        if overlap >= 0.5 * min(box.height, last.bottom - last.top) {
          last.top = min(last.top, box.y)
          last.bottom = max(last.bottom, box.maxY)
          last.members.append(fragment)
          rows[rows.count - 1] = last
          continue
        }
      }
      rows.append(Row(top: box.y, bottom: box.maxY, members: [fragment]))
    }
    return rows.map { row in
      row.members.sorted { $0.box.x < $1.box.x }
        .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined(separator: " ")
    }
  }
}
