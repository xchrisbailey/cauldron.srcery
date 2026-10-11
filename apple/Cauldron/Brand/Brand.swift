import Foundation

/// Cauldron's brand: colours, fonts and text styles. Follows the brand book.
enum Brand {
  private final class BundleAnchor {}

  /// The bundle that holds the asset catalogue and the fonts.
  static let bundle = Bundle(for: BundleAnchor.self)
}
