import SwiftUI

extension Brand {
  /// The brand palette: Catppuccin Latte in the light appearance, Mocha in the dark one.
  /// The asset catalogue is the only place with raw values; Swift reads them through here.
  enum Colors {
    /// One colour set in the asset catalogue, named for its kitchen role.
    enum Token: String, CaseIterable, Sendable {
      /// Page background.
      case base
      /// Cards, nav.
      case mantle
      case crust
      case surface0
      case surface1
      case overlay0
      /// Units next to quantities, quiet labels.
      case overlay1
      case subtext
      /// Text.
      case ink
      /// Primary buttons, selected nav, step numbers, checked ingredients, focus.
      case magic
      /// Timers, today in the week, the unsaved dot, the cursor.
      case heat
      /// Cook's tips, import fields to confirm, the breakfast tag.
      case tips
      /// Diet tags, items already in the pantry.
      case fresh
      case sparklePink
      case sparkleLavender
      /// Held for the tracker; don't use elsewhere.
      case trackerBlue
      /// Held for the tracker; don't use elsewhere.
      case trackerTeal
      /// Held for the tracker; don't use elsewhere.
      case trackerRed

      var color: Color { Color(rawValue, bundle: Brand.bundle) }
    }

    static let base = Token.base.color
    static let mantle = Token.mantle.color
    static let crust = Token.crust.color
    static let surface0 = Token.surface0.color
    static let surface1 = Token.surface1.color
    static let overlay0 = Token.overlay0.color
    static let overlay1 = Token.overlay1.color
    static let subtext = Token.subtext.color
    static let ink = Token.ink.color
    static let magic = Token.magic.color
    static let heat = Token.heat.color
    static let tips = Token.tips.color
    static let fresh = Token.fresh.color
    static let sparklePink = Token.sparklePink.color
    static let sparkleLavender = Token.sparkleLavender.color
    static let trackerBlue = Token.trackerBlue.color
    static let trackerTeal = Token.trackerTeal.color
    static let trackerRed = Token.trackerRed.color
  }
}
