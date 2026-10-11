import CauldronKit
import Testing

@testable import Cauldron

@MainActor
@Test func appLinksCauldronKit() {
  _ = AppDestinationView(destination: .recipes)
  #expect(Copy.ui.appName.text == "Cauldron")
}
