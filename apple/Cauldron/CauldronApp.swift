import SwiftUI

@main
struct CauldronApp: App {
  init() {
    Brand.Fonts.register()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
    }
  }
}
