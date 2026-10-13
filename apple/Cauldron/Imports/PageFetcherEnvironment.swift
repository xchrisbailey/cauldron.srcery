import CauldronKit
import SwiftUI

extension EnvironmentValues {
  /// What fetches a page for Distill. The live one unless a preview or a test says otherwise.
  @Entry var pageFetcher: any PageFetcher = URLSessionPageFetcher()
}
