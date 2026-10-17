import CoreText
import SwiftUI

extension Brand {
  /// The brand book's type scale, mirroring `type` and `quantity` in the web tokens.
  enum TextStyle: CaseIterable, Sendable {
    case title
    case section
    case body
    case control
    /// A number: Geist Mono. The unit that follows it is `unit`.
    case quantity
    /// The unit next to a quantity: Geist Mono, regular, in `overlay1`.
    case unit

    var family: Fonts.Family {
      switch self {
      case .quantity, .unit: .mono
      case .title, .section, .body, .control: .ui
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

    /// Tracking as a fraction of the size.
    var tracking: CGFloat {
      switch self {
      case .title: -0.025
      default: 0
      }
    }

    /// Line height as a multiple of the size, where the brand sets one.
    var lineHeight: CGFloat? {
      switch self {
      case .body: 1.6
      default: nil
      }
    }

    /// The system style this one scales with under Dynamic Type.
    var textStyle: Font.TextStyle {
      switch self {
      case .title: .largeTitle
      case .section: .title3
      case .body: .body
      case .control: .subheadline
      case .quantity, .unit: .footnote
      }
    }

    /// The colour the style sets itself, if any.
    var color: Color? {
      switch self {
      case .unit: Brand.Colors.overlay1
      default: nil
      }
    }
  }
}

extension Font {
  /// A brand font at `size` (the style's own size by default).
  static func brand(_ style: Brand.TextStyle, size: CGFloat? = nil) -> Font {
    Brand.Fonts.register()
    return Font(
      Brand.Fonts.ctFont(style.family, size: size ?? style.size, weight: style.weight))
  }
}

private struct BrandTextModifier: ViewModifier {
  let style: Brand.TextStyle
  @ScaledMetric private var size: CGFloat

  init(style: Brand.TextStyle) {
    self.style = style
    _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
  }

  @ViewBuilder
  func body(content: Content) -> some View {
    let styled =
      content
      .font(.brand(style, size: size))
      .tracking(style.tracking * size)
      .lineSpacing(lineSpacing)
    if let color = style.color {
      styled.foregroundStyle(color)
    } else {
      styled
    }
  }

  /// The gap that brings the font's natural line height up to the brand's multiple.
  private var lineSpacing: CGFloat {
    guard let multiple = style.lineHeight else { return 0 }
    let font = Brand.Fonts.ctFont(style.family, size: size, weight: style.weight)
    let natural = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    return max(0, size * multiple - natural)
  }
}

extension View {
  /// Sets text in a brand style: font, tracking and line height, scaling with Dynamic Type.
  /// Only `unit` sets a colour; every other style inherits it, so screens set `Brand.Colors.ink`
  /// once at their root.
  func brandText(_ style: Brand.TextStyle) -> some View {
    modifier(BrandTextModifier(style: style))
  }
}

/// A quantity and its unit: the value in Geist Mono, the unit in Geist Mono and `overlay1`.
struct QuantityText: View {
  let value: String
  let unit: String?

  init(_ value: String, unit: String? = nil) {
    self.value = value
    self.unit = unit
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
      Text(verbatim: value).brandText(.quantity)
      if let unit {
        Text(verbatim: unit).brandText(.unit)
      }
    }
  }
}
