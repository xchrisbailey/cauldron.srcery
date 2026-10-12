import CoreText
import Foundation
import SwiftUI

extension Brand {
  /// The bundled typefaces. Both are variable fonts with one weight axis, from 100 to 900.
  enum Typeface: String, CaseIterable, Sendable {
    /// The interface and recipes.
    case ui = "Geist"
    /// Every quantity, unit, time, serving count and date.
    case mono = "Geist Mono"

    var fileName: String {
      switch self {
      case .ui: "Geist-Variable"
      case .mono: "GeistMono-Variable"
      }
    }
  }

  /// On the main actor because CoreText's descriptors are not `Sendable`, and only views use them.
  @MainActor
  enum Fonts {
    /// The OpenType tag `wght`, which names the weight axis of a variable font.
    private static let weightAxis = 0x7767_6874

    /// Registers the bundled fonts with the system, once. The app does this as it launches.
    static func register() {
      _ = descriptors
    }

    /// Each typeface's descriptor, read from its bundled file. Fonts are built from these and
    /// not looked up by name, so a copy of Geist installed on the Mac can't stand in for ours.
    private static let descriptors: [Typeface: CTFontDescriptor] = {
      var found: [Typeface: CTFontDescriptor] = [:]
      for typeface in Typeface.allCases {
        guard
          let url = Bundle.main.url(forResource: typeface.fileName, withExtension: "ttf"),
          let all = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
          let first = all.first
        else {
          assertionFailure("\(typeface.fileName).ttf is missing from the bundle")
          continue
        }
        // Registering twice fails harmlessly, as it does in previews that reuse a process.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        found[typeface] = first
      }
      return found
    }()

    /// A typeface at an exact weight, such as the 650 the brand book gives section headings.
    static func ctFont(_ typeface: Typeface, size: CGFloat, weight: CGFloat) -> CTFont {
      guard let base = descriptors[typeface] else {
        return CTFontCreateUIFontForLanguage(.system, size, nil)
          ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
      }
      let descriptor = CTFontDescriptorCreateCopyWithVariation(
        base,
        weightAxis as CFNumber,
        weight
      )
      return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    static func font(_ typeface: Typeface, size: CGFloat, weight: CGFloat) -> Font {
      Font(ctFont(typeface, size: size, weight: weight))
    }
  }
}
