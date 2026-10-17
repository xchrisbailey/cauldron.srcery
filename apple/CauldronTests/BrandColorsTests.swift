import SwiftUI
import Testing

@testable import Cauldron

/// Expected values are written out here on purpose: they are the brand's source of truth
/// (Catppuccin Latte for light, Mocha for dark, with Latte's darker `subtext`), and the
/// asset catalogue must agree with them.
private struct Expected {
  let token: Brand.Colors.Token
  let light: UInt32
  let dark: UInt32
}

private let expected: [Expected] = [
  Expected(token: .base, light: 0xEFF1F5, dark: 0x1E1E2E),
  Expected(token: .mantle, light: 0xE6E9EF, dark: 0x181825),
  Expected(token: .crust, light: 0xDCE0E8, dark: 0x11111B),
  Expected(token: .surface0, light: 0xCCD0DA, dark: 0x313244),
  Expected(token: .surface1, light: 0xBCC0CC, dark: 0x45475A),
  Expected(token: .overlay0, light: 0x9CA0B0, dark: 0x6C7086),
  Expected(token: .overlay1, light: 0x8C8FA1, dark: 0x7F849C),
  Expected(token: .subtext, light: 0x5C5F77, dark: 0xA6ADC8),
  Expected(token: .ink, light: 0x4C4F69, dark: 0xCDD6F4),
  Expected(token: .magic, light: 0x8839EF, dark: 0xCBA6F7),
  Expected(token: .heat, light: 0xFE640B, dark: 0xFAB387),
  Expected(token: .tips, light: 0xDF8E1D, dark: 0xF9E2AF),
  Expected(token: .fresh, light: 0x40A02B, dark: 0xA6E3A1),
  Expected(token: .sparklePink, light: 0xEA76CB, dark: 0xF5C2E7),
  Expected(token: .sparkleLavender, light: 0x7287FD, dark: 0xB4BEFE),
  Expected(token: .trackerBlue, light: 0x1E66F5, dark: 0x89B4FA),
  Expected(token: .trackerTeal, light: 0x179299, dark: 0x94E2D5),
  Expected(token: .trackerRed, light: 0xD20F39, dark: 0xF38BA8),
]

/// The 8-bit sRGB components the colour resolves to in an appearance.
private func resolve(_ color: Color, _ scheme: ColorScheme) -> UInt32 {
  var environment = EnvironmentValues()
  environment.colorScheme = scheme
  let resolved = color.resolve(in: environment)
  func byte(_ component: Float) -> UInt32 { UInt32((component * 255).rounded()) }
  return byte(resolved.red) << 16 | byte(resolved.green) << 8 | byte(resolved.blue)
}

@MainActor
struct BrandColorsTests {
  @Test func everyTokenHasExpectedValues() {
    #expect(Set(expected.map(\.token)) == Set(Brand.Colors.Token.allCases))
  }

  @Test(arguments: expected)
  fileprivate func lightMatchesLatte(_ row: Expected) {
    #expect(resolve(row.token.color, .light) == row.light)
  }

  @Test(arguments: expected)
  fileprivate func darkMatchesMocha(_ row: Expected) {
    #expect(resolve(row.token.color, .dark) == row.dark)
  }

  @Test func namedAccessorsReadTheSameSets() {
    #expect(resolve(Brand.Colors.magic, .dark) == 0xCBA6F7)
    #expect(resolve(Brand.Colors.ink, .light) == 0x4C4F69)
  }
}
