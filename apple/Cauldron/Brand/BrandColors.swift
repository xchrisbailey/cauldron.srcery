import SwiftUI

extension Brand {
  /// The brand's colours by kitchen role. The values live in the asset catalogue, where Latte
  /// is the light appearance and Mocha the dark one. `bun run brand` writes them from the
  /// web app's `tokens.css`.
  enum Colors {
    /// Page background.
    static let base = color("base")
    /// Cards and navigation.
    static let mantle = color("mantle")
    static let crust = color("crust")
    static let surface0 = color("surface0")
    static let surface1 = color("surface1")
    static let overlay0 = color("overlay0")
    /// Units next to quantities, and quiet labels.
    static let overlay1 = color("overlay1")
    static let subtext = color("subtext")
    /// Text.
    static let ink = color("ink")
    /// Primary buttons, selected navigation, step numbers, checked ingredients and focus.
    static let magic = color("magic")
    /// Timers, today in the week, the unsaved dot and the cursor.
    static let heat = color("heat")
    /// Cook's tips, import fields to confirm and the breakfast tag.
    static let tips = color("tips")
    /// Diet tags and items already in the pantry.
    static let fresh = color("fresh")
    static let sparklePink = color("sparklePink")
    static let sparkleLavender = color("sparkleLavender")
    /// Held for the tracker. Don't use it elsewhere.
    static let trackerBlue = color("trackerBlue")
    /// Held for the tracker. Don't use it elsewhere.
    static let trackerTeal = color("trackerTeal")
    /// Held for the tracker. Don't use it elsewhere.
    static let trackerRed = color("trackerRed")

    /// Every role's name in the asset catalogue, in the brand book's order.
    static let roles = [
      "base", "mantle", "crust", "surface0", "surface1", "overlay0", "overlay1", "subtext", "ink",
      "magic", "heat", "tips", "fresh", "sparklePink", "sparkleLavender", "trackerBlue",
      "trackerTeal", "trackerRed",
    ]

    /// The catalogue name of a role's colour set.
    static func assetName(_ role: String) -> String {
      "Brand/\(role)"
    }

    static func color(_ role: String) -> Color {
      Color(assetName(role), bundle: .main)
    }
  }
}
