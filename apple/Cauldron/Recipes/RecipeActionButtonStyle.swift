import SwiftUI

/// The look of a button in a recipe's action bar: `primary` is the one filled in `magic`,
/// `secondary` sits on a `surface0` plate, and `quiet` is bare text for the actions that should
/// stay reachable without competing.
struct RecipeActionButtonStyle: ButtonStyle {
  enum Kind { case primary, secondary, quiet }

  let kind: Kind
  @Environment(\.isEnabled) private var isEnabled

  init(_ kind: Kind = .secondary) {
    self.kind = kind
  }

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .brandText(.control)
      .lineLimit(1)
      // Asks for the whole label, so a row of buttons that can't fit stacks instead.
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, kind == .quiet ? 8 : 14)
      .frame(minHeight: 44)
      // Plates share a row's width; quiet text keeps its own and wraps on to the next line.
      .frame(maxWidth: kind == .quiet ? nil : .infinity)
      .foregroundStyle(foreground)
      .background(fill, in: RoundedRectangle(cornerRadius: 10))
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
      .contentShape(RoundedRectangle(cornerRadius: 10))
  }

  private var foreground: Color {
    switch kind {
    case .primary: Brand.Colors.base
    case .secondary, .quiet: Brand.Colors.ink
    }
  }

  private var fill: Color {
    switch kind {
    case .primary: Brand.Colors.magic
    case .secondary: Brand.Colors.surface0
    case .quiet: Color.clear
    }
  }
}
