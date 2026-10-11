import SwiftUI

/// The look of a button in a recipe's action bar: `primary` is the one filled in `magic`.
struct RecipeActionButtonStyle: ButtonStyle {
  enum Kind { case primary, secondary }

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
      .padding(.horizontal, 14)
      .frame(minHeight: 44)
      .frame(maxWidth: .infinity)
      .foregroundStyle(kind == .primary ? Brand.Colors.base : Brand.Colors.ink)
      .background(
        kind == .primary ? Brand.Colors.magic : Brand.Colors.surface0,
        in: RoundedRectangle(cornerRadius: 10)
      )
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
      .contentShape(RoundedRectangle(cornerRadius: 10))
  }
}
