import CoreText
import SwiftUI
import Testing

@testable import Cauldron

struct BrandFontsTests {
  @Test func bundledFontsRegister() {
    #expect(Brand.Fonts.register())
  }

  @Test func bothFamiliesResolve() {
    Brand.Fonts.register()
    #expect(
      CTFontCopyFamilyName(Brand.Fonts.ctFont(.ui, size: 15, weight: 400)) as String == "Geist")
    #expect(
      CTFontCopyFamilyName(Brand.Fonts.ctFont(.mono, size: 13, weight: 500)) as String
        == "Geist Mono")
  }

  @Test func weightsAreVariationValues() {
    Brand.Fonts.register()
    let section = Brand.Fonts.ctFont(.ui, size: 20, weight: 650)
    let variation = CTFontCopyVariation(section) as? [NSNumber: NSNumber]
    #expect(variation?[NSNumber(value: Brand.Fonts.weightAxis)] == 650)
  }

  @Test func quantitiesAndUnitsAreMono() {
    #expect(Brand.TextStyle.quantity.family == .mono)
    #expect(Brand.TextStyle.unit.family == .mono)
    #expect(Brand.TextStyle.body.family == .ui)
  }

  @Test func scaleMatchesTheBrandBook() {
    #expect(Brand.TextStyle.title.size == 34)
    #expect(Brand.TextStyle.title.weight == 700)
    #expect(Brand.TextStyle.section.size == 20)
    #expect(Brand.TextStyle.section.weight == 650)
    #expect(Brand.TextStyle.body.size == 15)
    #expect(Brand.TextStyle.body.lineHeight == 1.6)
    #expect(Brand.TextStyle.control.size == 14)
    #expect(Brand.TextStyle.control.weight == 500)
    #expect(Brand.TextStyle.quantity.size == 13)
    #expect(Brand.TextStyle.quantity.weight == 500)
    #expect(Brand.TextStyle.title.tracking == -0.025)
  }
}
