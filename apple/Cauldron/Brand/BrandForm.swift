import SwiftUI

extension View {
  /// A form or list that sits on `base` instead of the system's grouped grey. Pair it with
  /// `brandFormRows()` on each of its sections: SwiftUI reads a row's fill from the row or its
  /// `Section`, never from the container, so the form alone leaves the rows system grey.
  func brandForm() -> some View {
    self
      .scrollContentBackground(.hidden)
      .background(Brand.Colors.base)
  }

  /// The `mantle` row fill the brand's forms use. Put it on a `Section`, or on a row that sits
  /// outside one.
  func brandFormRows() -> some View {
    listRowBackground(Brand.Colors.mantle)
  }
}

extension View {
  /// One gap between a grouped form's sections. iOS leaves about three times as much room after
  /// a section with no footer as after one with a footer, so a form that mixes them reads
  /// uneven; any explicit value brings the two within a few points of each other. The Mac
  /// already spaces them alike and has no such setting.
  func brandSectionSpacing() -> some View {
    #if os(iOS)
      listSectionSpacing(.custom(12))
    #else
      self
    #endif
  }
}
