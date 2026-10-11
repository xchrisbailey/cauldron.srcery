import SwiftUI

/// The first screen. The app shell replaces it; until then debug builds show the brand preview.
struct RootView: View {
  var body: some View {
    #if DEBUG
      BrandPreview()
    #else
      Brand.Colors.base.ignoresSafeArea()
    #endif
  }
}

#Preview {
  RootView()
}
