import SwiftUI

extension View {
  /// Keeps a list or a form to the width a page of reading needs and centres it, so a wide Mac
  /// window doesn't stretch a row or a field across the whole screen. A narrower window is
  /// unaffected. Put the background after it, so the margins keep the page's colour.
  func readingColumn(maxWidth: CGFloat = ReadingColumn.list) -> some View {
    frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
  }
}

/// The widths the screens cap at. `GatherScreen` uses `list`.
enum ReadingColumn {
  /// A list of rows: the diary, the weigh-ins, the Gather list.
  static let list: CGFloat = 760
  /// A form of labelled fields: targets, the check-in, Settings.
  static let form: CGFloat = 640
}
