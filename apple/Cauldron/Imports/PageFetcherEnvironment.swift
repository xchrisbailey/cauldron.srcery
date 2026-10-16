import CauldronImports
import CauldronKit
import SwiftUI

extension EnvironmentValues {
  /// What fetches a page for Distill: the shared live one unless a preview or a test says
  /// otherwise. The `@Entry` default is evaluated on every read, so it must not make a session.
  @Entry var pageFetcher: any PageFetcher = URLSessionPageFetcher.live
}

extension EnvironmentValues {
  /// What reads text off a photographed page for Distill: Vision unless a preview or a test says
  /// otherwise.
  @Entry var recipeTextReader: any RecipeTextReader = VisionTextReader()
}
