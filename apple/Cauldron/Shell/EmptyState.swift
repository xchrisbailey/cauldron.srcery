import CauldronKit
import SwiftUI

/// What a section shows before it has anything in it: an icon and one line of copy that says
/// what to do first. The section's name is the navigation title around it.
struct EmptyState: View {
  let systemImage: String
  let message: CopyString

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(Brand.Colors.magic)
        .accessibilityHidden(true)
      Text(verbatim: message.text)
        .brandText(.body)
        .foregroundStyle(Brand.Colors.subtext)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Brand.Colors.base)
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  EmptyState(
    systemImage: AppDestination.recipes.systemImage, message: Copy.recipes.empty)
}
