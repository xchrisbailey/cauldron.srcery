import Testing

@testable import Cauldron

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Guards the Resources build phase in `project.yml`: a synced folder alone is not bundled.
struct BundleResourcesTests {
  @Test func assetCatalogueIsBundled() {
    #if canImport(UIKit)
      let colour = UIColor(named: "base", in: Brand.bundle, compatibleWith: nil)
    #else
      let colour = NSColor(named: "base", bundle: Brand.bundle)
    #endif
    #expect(colour != nil)
  }

  @Test(arguments: ["Geist-Variable", "GeistMono-Variable"])
  func fontsAreBundled(_ name: String) {
    #expect(Brand.bundle.url(forResource: name, withExtension: "ttf") != nil)
  }

  @Test func fontLicenceIsBundled() {
    #expect(Brand.bundle.url(forResource: "OFL", withExtension: "txt") != nil)
  }
}
