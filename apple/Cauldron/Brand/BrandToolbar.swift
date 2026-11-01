import SwiftUI

extension View {
  /// Keeps the Mac window's title bar the colour of the page under it. A screen whose content
  /// scrolls beneath the bar otherwise gets the system's own band there: neutral grey in Mocha,
  /// and over a narrow column only as wide as the column. Does nothing on iPhone and iPad.
  func brandWindowToolbar() -> some View {
    #if os(macOS)
      toolbarBackground(Brand.Colors.base, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
    #else
      self
    #endif
  }
}
