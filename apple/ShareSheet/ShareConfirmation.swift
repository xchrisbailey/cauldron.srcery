import CoreText
import SwiftUI

/// Geist for the share extension's confirmation.
///
/// The colours come from the brand catalogue, which the extension carries as a resource of its
/// own (`Brand.Colors`). The fonts are too big to carry twice, so they are read from the app
/// that contains the extension. Where that can't be done (the app bundle isn't found, or the
/// font isn't in it) the system font stands in, so the confirmation is never blank. Run inside
/// the app, as the tests do, the app is the bundle.
enum ShareFonts {
  /// Whether Geist could be loaded from the containing app.
  static let isAvailable: Bool = register(file: "Geist-Variable", family: "Geist")

  /// Whether Geist Mono could be, for quantities, times and counts.
  static let isMonoAvailable: Bool = register(file: "GeistMono-Variable", family: "Geist Mono")

  private static func register(file: String, family: String) -> Bool {
    guard let app = containingApp(of: Bundle.main.bundleURL).flatMap({ Bundle(url: $0) }),
      let url = app.url(forResource: file, withExtension: "ttf")
    else { return false }
    var error: Unmanaged<CFError>?
    // Registered already (the app itself) reports an error and still works, so judge by the
    // family resolving.
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    let descriptor = CTFontDescriptorCreateWithAttributes(
      [kCTFontFamilyNameAttribute: family] as CFDictionary)
    return CTFontCopyFamilyName(CTFontCreateWithFontDescriptor(descriptor, 12, nil)) as String
      == family
  }

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

  /// Geist at `size` and a weight from 100 to 900, or the system font.
  static func font(size: CGFloat, weight: CGFloat) -> Font {
    guard isAvailable else { return .system(size: size, weight: systemWeight(weight)) }
    return variable("Geist-Regular", size: size, weight: weight)
  }

  /// Geist Mono at `size`, for every quantity, unit, time and count; or the system's monospaced
  /// font.
  static func mono(size: CGFloat, weight: CGFloat = 400) -> Font {
    guard isMonoAvailable else {
      return .system(size: size, weight: systemWeight(weight), design: .monospaced)
    }
    return variable("GeistMono-Regular", size: size, weight: weight)
  }

  private static func systemWeight(_ weight: CGFloat) -> Font.Weight {
    weight >= 650 ? .semibold : weight >= 500 ? .medium : .regular
  }

  private static func variable(_ name: String, size: CGFloat, weight: CGFloat) -> Font {
    let attributes: [CFString: Any] = [
      kCTFontNameAttribute: name,
      // The `wght` axis, as in the app's brand fonts.
      kCTFontVariationAttribute: [NSNumber(value: 0x7767_6874): NSNumber(value: Double(weight))],
    ]
    return Font(
      CTFontCreateWithFontDescriptor(
        CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil))
  }
}

/// What the share extension shows before it closes: the result of leaving the item for the app.
struct ShareConfirmation: View {
  enum Outcome: Equatable {
    case sent(title: String, detail: String)
    case failed(String)
  }

  let outcome: Outcome
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
          .font(ShareFonts.font(size: titleSize, weight: 650))
          .foregroundStyle(Brand.Colors.ink)
        Text(verbatim: detail)
          .font(ShareFonts.font(size: bodySize, weight: 400))
          .foregroundStyle(Brand.Colors.subtext)
      case .failed(let message):
        Text(verbatim: message)
          .font(ShareFonts.font(size: bodySize, weight: 400))
          .foregroundStyle(Brand.Colors.heat)
      }
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: 360)
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Brand.Colors.base.ignoresSafeArea())
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
    case .sent: Brand.Colors.magic
    case .failed: Brand.Colors.heat
    }
  }
}
