import SwiftUI

extension Brand {
  /// The brand book's type scale. Sizes are in points at the default text size, and grow with
  /// Dynamic Type.
  enum TextStyle: CaseIterable, Sendable {
    case title
    case section
    case body
    case control
    /// Quantities, units, times, serving counts and dates. Always Geist Mono.
    case quantity
    /// The unit beside a quantity: lighter, and coloured `Brand.Colors.overlay1`.
    case unit

    var typeface: Typeface {
      switch self {
      case .title, .section, .body, .control: .ui
      case .quantity, .unit: .mono
      }
    }

    var size: CGFloat {
      switch self {
      case .title: 34
      case .section: 20
      case .body: 15
      case .control: 14
      case .quantity, .unit: 13
      }
    }

    var weight: CGFloat {
      switch self {
      case .title: 700
      case .section: 650
      case .body, .unit: 400
      case .control, .quantity: 500
      }
    }

    /// Letter spacing, as a fraction of the size.
    var tracking: CGFloat {
      switch self {
      case .title: -0.025
      case .section, .body, .control, .quantity, .unit: 0
      }
    }

    /// Line height, as a multiple of the size. Nil keeps the font's own.
    var leading: CGFloat? {
      switch self {
      case .body: 1.6
      case .title, .section, .control, .quantity, .unit: nil
      }
    }

    /// The system style whose Dynamic Type curve this one follows.
    var scalesWith: Font.TextStyle {
      switch self {
      case .title: .largeTitle
      case .section: .title3
      case .body: .subheadline
      case .control: .footnote
      case .quantity, .unit: .footnote
      }
    }
  }
}

private struct BrandTextStyleModifier: ViewModifier {
  let style: Brand.TextStyle
  @ScaledMetric private var size: CGFloat

  init(style: Brand.TextStyle) {
    self.style = style
    _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.scalesWith)
  }

  func body(content: Content) -> some View {
    let font = Brand.Fonts.ctFont(style.typeface, size: size, weight: style.weight)
    let natural = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    let extra = style.leading.map { max(0, $0 * size - natural) } ?? 0
    content
      .font(Font(font))
      .tracking(style.tracking * size)
      .lineSpacing(extra)
      .monospacedDigit()
  }
}

extension View {
  /// Sets text in one of the brand's type styles.
  func brandStyle(_ style: Brand.TextStyle) -> some View {
    modifier(BrandTextStyleModifier(style: style))
  }
}

/// A quantity with its unit, such as "250 g": both in Geist Mono, the unit quieter.
struct QuantityText: View {
  let value: String
  let unit: String?

  init(_ value: String, unit: String? = nil) {
    self.value = value
    self.unit = unit
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Text(value)
        .brandStyle(.quantity)
        .foregroundStyle(Brand.Colors.ink)
      if let unit {
        Text(unit)
          .brandStyle(.unit)
          .foregroundStyle(Brand.Colors.overlay1)
      }
    }
  }
}
