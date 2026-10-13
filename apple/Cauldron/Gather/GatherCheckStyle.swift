import SwiftUI

/// A square tick box with its label beside it, the whole row a target. The tick is `magic`, as
/// checked things are across the app.
struct GatherCheckStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
          .font(.system(size: 20))
          .foregroundStyle(configuration.isOn ? Brand.Colors.magic : Brand.Colors.overlay1)
          .accessibilityHidden(true)
        configuration.label
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(.isToggle)
  }
}
