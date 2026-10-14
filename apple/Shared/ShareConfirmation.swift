import CoreText
import SwiftUI

#if os(iOS)
  import UIKit
#else
  import AppKit
#endif

/// The colours and type of the share extension's confirmation.
///
/// The extension has no asset catalogue and no fonts of its own: they are in the app that
/// contains it, so they are read from there. Wherever that can't be done (the app bundle isn't
/// found, or a colour or font isn't in it) each falls back to the closest system equivalent, so
/// the confirmation is never blank. Run inside the app, as the tests do, the app is the bundle.
struct ShareTheme {
  var base: Color
  var ink: Color
  var subtext: Color
  var magic: Color
  var heat: Color
  /// Whether Geist is in use; false means the system font.
  var usesBrandFont: Bool

  /// The theme found in the containing app.
  static let live: ShareTheme = {
    let app = containingApp(of: Bundle.main.bundleURL).flatMap { Bundle(url: $0) }
    func color(_ name: String, _ fallback: Color) -> Color {
      guard let app, hasColor(name, in: app) else { return fallback }
      return Color(name, bundle: app)
    }
    return ShareTheme(
      base: color("base", fallbackBase),
      ink: color("ink", .primary),
      subtext: color("subtext", .secondary),
      magic: color("magic", .accentColor),
      heat: color("heat", .red),
      usesBrandFont: app.map(registerFonts) ?? false)
  }()

  /// The app's bundle folder: `url` itself when it is an app, otherwise the nearest folder above
  /// it that is (`Cauldron.app/PlugIns/X.appex` on iPhone, `Cauldron.app/Contents/PlugIns/X.appex`
  /// on the Mac).
  static func containingApp(of url: URL) -> URL? {
    var current = url
    for _ in 0..<6 {
      if current.pathExtension == "app" { return current }
      let parent = current.deletingLastPathComponent()
      if parent == current { return nil }
      current = parent
    }
    return nil
  }

  /// A font in the brand's two families, at a weight from 100 to 900.
  func font(size: CGFloat, weight: CGFloat) -> Font {
    guard usesBrandFont else { return .system(size: size, weight: Self.systemWeight(weight)) }
    let attributes: [CFString: Any] = [
      kCTFontNameAttribute: "Geist-Regular",
      // The `wght` axis, as in the app's brand fonts.
      kCTFontVariationAttribute: [NSNumber(value: 0x7767_6874): NSNumber(value: Double(weight))],
    ]
    return Font(
      CTFontCreateWithFontDescriptor(
        CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil))
  }

  private static func systemWeight(_ weight: CGFloat) -> Font.Weight {
    weight >= 650 ? .semibold : weight >= 500 ? .medium : .regular
  }

  private static var fallbackBase: Color {
    #if os(iOS)
      Color(UIColor.systemBackground)
    #else
      Color(NSColor.windowBackgroundColor)
    #endif
  }

  private static func hasColor(_ name: String, in bundle: Bundle) -> Bool {
    #if os(iOS)
      UIColor(named: name, in: bundle, compatibleWith: nil) != nil
    #else
      NSColor(named: NSColor.Name(name), bundle: bundle) != nil
    #endif
  }

  /// Registers Geist for this process from the app's bundle; whether it can be used.
  private static func registerFonts(from app: Bundle) -> Bool {
    guard let url = app.url(forResource: "Geist-Variable", withExtension: "ttf") else {
      return false
    }
    var error: Unmanaged<CFError>?
    // Registered already (the app itself) reports an error and still works, so judge by the
    // family resolving.
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    let descriptor = CTFontDescriptorCreateWithAttributes(
      [kCTFontFamilyNameAttribute: "Geist"] as CFDictionary)
    return CTFontCopyFamilyName(CTFontCreateWithFontDescriptor(descriptor, 12, nil)) as String
      == "Geist"
  }
}

/// What the share extension shows before it closes: the result of leaving the item for the app.
struct ShareConfirmation: View {
  enum Outcome: Equatable {
    case sent(title: String, detail: String)
    case failed(String)
  }

  let outcome: Outcome
  var theme = ShareTheme.live
  @ScaledMetric private var titleSize = 22
  @ScaledMetric private var bodySize = 15

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(accent)
        .accessibilityHidden(true)
      switch outcome {
      case .sent(let title, let detail):
        Text(verbatim: title)
          .font(theme.font(size: titleSize, weight: 650))
          .foregroundStyle(theme.ink)
        Text(verbatim: detail)
          .font(theme.font(size: bodySize, weight: 400))
          .foregroundStyle(theme.subtext)
      case .failed(let message):
        Text(verbatim: message)
          .font(theme.font(size: bodySize, weight: 400))
          .foregroundStyle(theme.heat)
      }
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: 360)
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.base.ignoresSafeArea())
    .accessibilityElement(children: .combine)
  }

  private var symbol: String {
    switch outcome {
    case .sent: "flame"
    case .failed: "exclamationmark.circle"
    }
  }

  private var accent: Color {
    switch outcome {
    case .sent: theme.magic
    case .failed: theme.heat
    }
  }
}
