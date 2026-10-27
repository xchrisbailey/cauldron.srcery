import SwiftUI

extension EnvironmentValues {
  /// What writes search keywords after a save. Nil in a preview or a test that doesn't care, and
  /// then a save writes none.
  @Entry var searchKeywords: SearchKeywordRunner?
}
