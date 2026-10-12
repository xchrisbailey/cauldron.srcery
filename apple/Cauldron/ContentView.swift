import CauldronKit
import SwiftUI

struct ContentView: View {
  #if DEBUG
    /// `-brandPreview YES` opens the brand preview at launch.
    @State private var showsBrandPreview = UserDefaults.standard.bool(forKey: "brandPreview")
  #endif

  var body: some View {
    #if DEBUG
      NavigationStack {
        placeholder
          .toolbar {
            Button("Brand") { showsBrandPreview = true }
          }
          .navigationDestination(isPresented: $showsBrandPreview) { BrandPreview() }
      }
    #else
      placeholder
    #endif
  }

  private var placeholder: some View {
    ContentUnavailableView(CauldronKit.appName, systemImage: "flame")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Brand.Colors.base)
  }
}

#Preview {
  ContentView()
}
