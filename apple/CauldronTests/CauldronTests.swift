import CauldronKit
import Testing

@testable import Cauldron

@MainActor
@Test func appLinksCauldronKit() {
  _ = RootView()
  #expect(Copy.ui.appName.text == "Cauldron")
}
