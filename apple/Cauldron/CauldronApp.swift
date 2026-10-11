import SwiftData
import SwiftUI

@main
struct CauldronApp: App {
  private let container: ModelContainer

  init() {
    Brand.Fonts.register()
    do {
      container = try CauldronStore.container(CauldronStore.launchMode)
    } catch {
      // Without its store the app can do nothing useful, and carrying on in memory would
      // quietly lose whatever was entered.
      fatalError("Cauldron couldn't open its data store: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
    }
    .modelContainer(container)
  }
}
