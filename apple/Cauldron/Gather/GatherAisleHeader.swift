import SwiftUI

/// The heading over one aisle: the brand's mono eyebrow, set in capitals by the text case, so
/// the string itself, and what VoiceOver reads, stays in normal case. Every aisle header on
/// every platform comes from here.
///
/// It is the first row of its aisle, not a pinned `Section` header. The system draws a filled
/// band behind a pinned header on the Mac and a material on iPhone, and the brand wants neither:
/// the eyebrow sits straight on the page.
struct GatherAisleHeader: View {
  let title: String

  var body: some View {
    Text(verbatim: title)
      .brandText(.quantity)
      .foregroundStyle(Brand.Colors.subtext)
      .textCase(.uppercase)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, GatherLayout.gutter)
      .padding(.top, 16)
      .padding(.bottom, 4)
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .accessibilityAddTraits(.isHeader)
  }
}
