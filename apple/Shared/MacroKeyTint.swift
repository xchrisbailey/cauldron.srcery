import CauldronKit
import SwiftUI

extension MacroKey {
  /// The colour the tracker gives the number: protein, carbs and fat have their own, and
  /// calories take the brand's.
  var tint: Color {
    switch self {
    case .calories: Brand.Colors.magic
    case .protein: Brand.Colors.trackerBlue
    case .carbs: Brand.Colors.trackerTeal
    case .fat: Brand.Colors.trackerRed
    }
  }
}
