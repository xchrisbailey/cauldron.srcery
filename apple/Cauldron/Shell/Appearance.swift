import CauldronKit
import SwiftUI

/// Which palette the app wears. Latte is the light appearance and Mocha the dark one; System
/// follows the device. It is a per-device setting kept in `UserDefaults`, not in
/// `PreferencesRecord`, because a phone and a Mac shouldn't have to agree.
enum AppearanceChoice: String, CaseIterable, Identifiable, Sendable {
  case system
  case latte
  case mocha

  /// The `UserDefaults` key `@AppStorage` reads.
  static let storageKey = "appearance"

  var id: Self { self }

  /// What to force on the window, or nil to follow the device.
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .latte: .light
    case .mocha: .dark
    }
  }

  var label: CopyString {
    switch self {
    case .system: Copy.settings.appearance.system
    case .latte: Copy.settings.appearance.latte
    case .mocha: Copy.settings.appearance.mocha
    }
  }
}

private struct AppearanceModifier: ViewModifier {
  @AppStorage(AppearanceChoice.storageKey) private var choice = AppearanceChoice.system

  func body(content: Content) -> some View {
    content
      .preferredColorScheme(choice.colorScheme)
      .tint(Brand.Colors.magic)
  }
}

extension View {
  /// Applies the chosen appearance and the brand's tint. Put it on the root of every window.
  func cauldronAppearance() -> some View {
    modifier(AppearanceModifier())
  }
}
