import SwiftUI

/// A square tick box with its label beside it, the whole row a target. The tick is `magic`, as
/// checked things are across the app.
///
/// By default the box sits on the label's first baseline. A label of several lines passes the
/// height of its first line, and the box is then centred on that line instead, so it never
/// drifts away from the text it ticks.
struct GatherCheckStyle: ToggleStyle {
  var firstLineHeight: CGFloat?

  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(alignment: firstLineHeight == nil ? .firstTextBaseline : .top, spacing: 10) {
        Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
          .font(.system(size: 20))
          .foregroundStyle(configuration.isOn ? Brand.Colors.magic : Brand.Colors.overlay1)
          .frame(height: firstLineHeight)
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
