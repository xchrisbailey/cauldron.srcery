import CauldronKit
import CoreGraphics
import CoreText
import Foundation
import SwiftUI

/// Draws a `RecipePrintout` as a PDF on white paper, in the brand's type and Latte colours,
/// onto as many pages as it takes. It uses CoreText rather than a SwiftUI view so the text
/// breaks between lines at the page edge, and so the same code prints on both platforms.
enum RecipePDF {
  /// US Letter where the cook measures in US units, else A4.
  static func pageSize(locale: Locale = .current) -> CGSize {
    locale.measurementSystem == .us
      ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842)
  }

  /// At most this many pages, so a runaway layout can't fill memory.
  private static let pageLimit = 60

  static func render(_ printout: RecipePrintout, pageSize: CGSize = pageSize()) -> Data {
    let text = attributedText(for: printout)
    let data = NSMutableData()
    var box = CGRect(origin: .zero, size: pageSize)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &box, nil)
    else { return Data() }
    let margin: CGFloat = 54
    let content = box.insetBy(dx: margin, dy: margin)
    let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
    var location = 0
    var pages = 0
    repeat {
      context.beginPDFPage(nil)
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(box)
      let frame = CTFramesetterCreateFrame(
        framesetter, CFRange(location: location, length: 0), CGPath(rect: content, transform: nil),
        nil)
      CTFrameDraw(frame, context)
      context.endPDFPage()
      let shown = CTFrameGetVisibleStringRange(frame).length
      if shown == 0 { break }
      location += shown
      pages += 1
    } while location < text.length && pages < pageLimit
    context.closePDF()
    return data as Data
  }

  // MARK: Text

  private struct Palette {
    let ink: CGColor
    let subtext: CGColor
    let magic: CGColor
    let heat: CGColor

    /// The brand's Latte colours, whatever the appearance the app is in: paper is always light.
    init() {
      var environment = EnvironmentValues()
      environment.colorScheme = .light
      func resolve(_ color: Color) -> CGColor {
        let resolved = color.resolve(in: environment)
        return CGColor(
          srgbRed: CGFloat(resolved.red), green: CGFloat(resolved.green),
          blue: CGFloat(resolved.blue), alpha: 1)
      }
      ink = resolve(Brand.Colors.ink)
      subtext = resolve(Brand.Colors.subtext)
      magic = resolve(Brand.Colors.magic)
      heat = resolve(Brand.Colors.heat)
    }
  }

  /// The printout as one attributed string. Exposed for tests, which read its text.
  static func attributedText(for printout: RecipePrintout) -> NSAttributedString {
    let palette = Palette()
    let result = NSMutableAttributedString()

    func font(_ family: Brand.Fonts.Family, _ size: CGFloat, _ weight: CGFloat = 400) -> CTFont {
      Brand.Fonts.ctFont(family, size: size, weight: weight)
    }

    func add(
      _ string: String, _ font: CTFont, _ color: CGColor, _ style: CTParagraphStyle? = nil
    ) {
      var attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
      ]
      if let style {
        attributes[NSAttributedString.Key(kCTParagraphStyleAttributeName as String)] = style
      }
      result.append(NSAttributedString(string: string, attributes: attributes))
    }

    // Paragraph styles are per paragraph, so each paragraph's pieces share one.
    func label(_ string: String) {
      add(
        string.uppercased() + "\n", font(.mono, 10, 500), palette.subtext,
        paragraph(before: 22, after: 6))
    }

    add(printout.title + "\n", font(.ui, 26, 650), palette.ink, paragraph(after: 6))
    if let summary = printout.summary {
      add(summary + "\n", font(.ui, 12, 400), palette.subtext, paragraph(after: 6))
    }
    if !printout.facts.isEmpty {
      add(
        printout.facts.joined(separator: "   ") + "\n", font(.mono, 11, 400), palette.ink,
        paragraph(after: 4))
    }
    if let source = printout.source {
      add(source + "\n", font(.ui, 11, 400), palette.subtext, paragraph(after: 4))
    }

    if !printout.ingredients.isEmpty {
      label(Copy.recipeView.ingredients.text)
      let line = paragraph(head: 84, tabs: [84], after: 3)
      for row in printout.ingredients {
        switch row {
        case .heading(let name):
          add(name + "\n", font(.ui, 12, 650), palette.ink, paragraph(before: 8, after: 3))
        case .line(let item):
          let amount = [item.amount, item.unit].compactMap { $0 }.joined(separator: " ")
          add(amount, font(.mono, 11, 500), palette.ink, line)
          add("\t", font(.ui, 12), palette.ink, line)
          add(item.text, font(.ui, 12), palette.ink, line)
          if item.optional {
            add(" (\(Copy.recipeView.optional.text))", font(.ui, 12), palette.subtext, line)
          }
          add("\n", font(.ui, 12), palette.ink, line)
        }
      }
    }

    if !printout.steps.isEmpty {
      label(Copy.recipeView.method.text)
      let line = paragraph(head: 24, tabs: [24], after: 8)
      for row in printout.steps {
        switch row {
        case .heading(let name):
          add(name + "\n", font(.ui, 12, 650), palette.ink, paragraph(before: 6, after: 4))
        case .step(let number, let step, let timer):
          add("\(number)", font(.mono, 11, 600), palette.magic, line)
          add("\t", font(.ui, 12), palette.ink, line)
          add(step, font(.ui, 12), palette.ink, line)
          if let timer {
            add("  \(timer)", font(.mono, 11, 500), palette.heat, line)
          }
          add("\n", font(.ui, 12), palette.ink, line)
        }
      }
    }

    if let notes = printout.notes {
      add(notes + "\n", font(.ui, 11.5, 400), palette.subtext, paragraph(before: 14))
    }
    return result
  }

  // MARK: Paragraphs

  /// A paragraph style: the hanging indent and tab stops that line an ingredient's text up
  /// under itself when it wraps, and the space around it.
  private static func paragraph(
    head: CGFloat = 0, tabs: [CGFloat] = [], before: CGFloat = 0, after: CGFloat = 0
  ) -> CTParagraphStyle {
    let values: [(CTParagraphStyleSpecifier, CGFloat)] = [
      (.headIndent, head), (.paragraphSpacingBefore, before), (.paragraphSpacing, after),
      (.lineHeightMultiple, 1.25),
    ]
    let storage = UnsafeMutablePointer<CGFloat>.allocate(capacity: values.count)
    defer { storage.deallocate() }
    var settings: [CTParagraphStyleSetting] = []
    for (index, entry) in values.enumerated() {
      storage[index] = entry.1
      settings.append(
        CTParagraphStyleSetting(
          spec: entry.0, valueSize: MemoryLayout<CGFloat>.size, value: storage + index))
    }
    let stops = tabs.map { CTTextTabCreate(.left, Double($0), nil) } as CFArray
    return withUnsafePointer(to: stops) { pointer in
      var all = settings
      all.append(
        CTParagraphStyleSetting(
          spec: .tabStops, valueSize: MemoryLayout<CFArray>.size, value: pointer))
      return CTParagraphStyleCreate(all, all.count)
    }
  }
}
