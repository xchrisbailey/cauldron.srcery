import SwiftUI

/// A line across the top of the app when iCloud needs the cook's attention (signed out, or
/// full). It says the data is safe; Settings has the same line for the rest of the time.
struct SyncBanner: View {
  let status: ICloudStatus

  var body: some View {
    if status.needsAttention {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: status.systemImage)
          .foregroundStyle(Brand.Colors.heat)
          .accessibilityHidden(true)
        Text(verbatim: status.message.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.ink)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(Brand.Colors.mantle)
      .overlay(alignment: .bottom) { Brand.Colors.surface0.frame(height: 1) }
      .accessibilityElement(children: .combine)
    }
  }
}

#Preview("Signed out") { SyncBanner(status: .signedOut) }
#Preview("Full") { SyncBanner(status: .full) }
