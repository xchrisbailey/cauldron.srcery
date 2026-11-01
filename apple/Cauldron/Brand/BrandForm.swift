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
