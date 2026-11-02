import CauldronKit
import SwiftData
import SwiftUI

/// The day the week starts on. It is the same preference the Week page's picker writes, through
/// the same code, so changing it here is what the Week and Gather sections show.
struct WeekStartSection: View {
  @Environment(\.modelContext) private var context
  @Query private var preferences: [PreferencesRecord]

  var body: some View {
    Section {
      WeekStartPicker(
        startsOn: WeekStartPreference.current(preferences),
        onChange: { WeekStartPreference.set($0, preferences: preferences, in: context) }
      )
      .labelsHidden()
      .listRowBackground(Brand.Colors.mantle)
    } header: {
      // Every other Settings section has a header; without one this section sat tight under
      // Appearance's footer. The header carries the name, so the picker's own label is hidden.
      Text(verbatim: Copy.settings.weekStart.title.text)
    } footer: {
      Text(verbatim: Copy.settings.weekStart.hint.text)
    }
  }
}
