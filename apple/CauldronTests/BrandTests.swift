import CoreText
import SwiftUI
import Testing

@testable import Cauldron

#if canImport(UIKit)
  import UIKit
  private typealias PlatformColor = UIColor
#else
  import AppKit
  private typealias PlatformColor = NSColor
#endif

@MainActor @Suite struct BrandTests {
  @Test(arguments: Brand.Colors.roles)
  func everyRoleHasAColourSet(role: String) {
    #expect(PlatformColor(named: Brand.Colors.assetName(role)) != nil)
  }

  @Test func rolesAreDistinct() {
    #expect(Set(Brand.Colors.roles).count == Brand.Colors.roles.count)
    #expect(Brand.Colors.roles.count == 18)
  }

  @Test(arguments: Brand.Typeface.allCases)
  func bundledFontsLoad(typeface: Brand.Typeface) {
    #expect(Bundle.main.url(forResource: typeface.fileName, withExtension: "ttf") != nil)
    let font = Brand.Fonts.ctFont(typeface, size: 20, weight: 650)
    #expect(CTFontCopyFamilyName(font) as String == typeface.rawValue)
  }

  @Test func exactWeightsReachTheVariableAxis() throws {
    let font = Brand.Fonts.ctFont(.ui, size: 20, weight: 650)
    let variation = try #require(CTFontCopyVariation(font) as? [NSNumber: NSNumber])
    #expect(variation.values.map(\.doubleValue) == [650])
  }

  @Test func quantitiesAreSetInGeistMono() {
    #expect(Brand.TextStyle.quantity.typeface == .mono)
    #expect(Brand.TextStyle.unit.typeface == .mono)
  }
}
