import CauldronKit
import SwiftUI

struct ContentView: View {
  var body: some View {
    ContentUnavailableView(CauldronKit.appName, systemImage: "flame")
  }
}

#Preview {
  ContentView()
}
