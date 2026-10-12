import CoreText
import Foundation
import SwiftUI

extension Brand {
  /// Geist for text and Geist Mono for every quantity, unit, time and date. Both ship as
  /// variable fonts and are registered at runtime, so no Info.plist key is needed.
  enum Fonts {
    enum Family: String, Sendable {
      case ui = "Geist"
      case mono = "Geist Mono"

      /// The variable font's default instance. Variations only apply when it is picked by this
      /// name; a family-name lookup resolves to a fixed instance that ignores them.
      fileprivate var postScriptName: String {
        switch self {
        case .ui: "Geist-Regular"
        case .mono: "GeistMono-Regular"
        }
      }

      fileprivate var file: String {
        switch self {
        case .ui: "Geist-Variable"
        case .mono: "GeistMono-Variable"
        }
      }
    }

    /// The `wght` variation axis, as the four-character tag `wght`.
    static let weightAxis: UInt32 = 0x7767_6874

    private static let registration: Bool = {
      let results = [Family.ui, .mono].map { family -> Bool in
        guard let url = Brand.bundle.url(forResource: family.file, withExtension: "ttf") else {
          return false
        }
        var error: Unmanaged<CFError>?
        // Registering twice (a previous launch in the same process) reports an error that
        // still leaves the font usable, so judge by whether the family resolves instead.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        return isInstalled(family)
      }
      return !results.contains(false)
    }()

    /// Registers the bundled fonts for this process. Safe to call more than once. Returns
    /// whether both families are available.
    @discardableResult
    static func register() -> Bool { registration }

    private static func isInstalled(_ family: Family) -> Bool {
      let descriptor = CTFontDescriptorCreateWithAttributes(
        [kCTFontFamilyNameAttribute: family.rawValue] as CFDictionary)
      let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
      return CTFontCopyFamilyName(font) as String == family.rawValue
    }

    /// A font of `family` at `size` with the given weight (100 to 900, so 650 is real).
    static func ctFont(_ family: Family, size: CGFloat, weight: CGFloat) -> CTFont {
      // Until the bundled file is registered, the name can resolve to a copy of Geist installed
      // on the Mac, which is a fixed instance and ignores the weight.
      register()
      let attributes: [CFString: Any] = [
        kCTFontNameAttribute: family.postScriptName,
        kCTFontVariationAttribute: [NSNumber(value: weightAxis): NSNumber(value: Double(weight))],
      ]
      return CTFontCreateWithFontDescriptor(
        CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil)
    }
  }
}
