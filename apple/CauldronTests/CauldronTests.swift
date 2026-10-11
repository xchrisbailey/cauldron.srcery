import CauldronKit
import Testing

@testable import Cauldron

@MainActor
@Test func appLinksCauldronKit() {
  _ = RootView()
  #expect(CauldronKit.name == "Cauldron")
}
