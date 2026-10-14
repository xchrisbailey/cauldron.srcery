import SwiftUI

/// The filled button for a screen's main action: `base` text on `magic`, in both appearances.
///
/// Use it instead of the system's prominent bordered style. Inside a `Form` or `List` that draws its
/// label in the tint, which is also its fill, so the text vanishes.
struct BrandProminentButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .brandText(.control)
      .lineLimit(1)
      .padding(.horizontal, 16)
      .frame(minHeight: 44)
      .foregroundStyle(Brand.Colors.base)
      .background(Brand.Colors.magic, in: Capsule())
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
      .contentShape(Capsule())
  }
}

extension ButtonStyle where Self == BrandProminentButtonStyle {
  /// The filled button for a screen's main action.
  static var brandProminent: BrandProminentButtonStyle { BrandProminentButtonStyle() }
}
