import CauldronKit
import Foundation

/// What opens a brew window on the Mac: the recipe and the scale the cook chose. A plain value
/// so a window can be opened with it and restored by it.
struct BrewRequest: Codable, Hashable {
  var recipeID: UUID
  /// Set when the cook scaled by servings.
  var servings: Int?
  /// Set when the recipe has no servings and the cook scaled by a multiplier.
  var multiplier: Double?

  init(recipeID: UUID, scale: Scale) {
    self.recipeID = recipeID
    switch scale {
    case .servings(let servings): self.servings = servings
    case .multiplier(let multiplier): self.multiplier = multiplier
    }
  }

  var scale: Scale {
    if let servings { .servings(servings) } else { .multiplier(multiplier ?? 1) }
  }
}
