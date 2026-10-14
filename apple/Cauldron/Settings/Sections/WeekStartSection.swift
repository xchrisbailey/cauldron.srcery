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
      .listRowBackground(Brand.Colors.mantle)
    } footer: {
      Text(verbatim: Copy.settings.weekStart.hint.text)
    }
  }
}
